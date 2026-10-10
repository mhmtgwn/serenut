part of 'sync_v4_service.dart';

extension SyncV4Orchestration on SyncV4Service {
  Future<SyncV4Result> sync() async {
    await DatabaseManager.waitForWriteLock();
    final db = await DatabaseManager().getDatabase();
    var companyChanged = false;
    try {
      companyChanged = await this._syncCompanyProfile(db);
    } catch (_) {
      // Company profile synchronization is retried on the next cycle and must
      // not prevent transactional sales/inventory replication.
    }
    final deviceActivationId = await _deviceActivationId();
    final deviceId = await _deviceId();
    if (!kIsWeb) {
      try {
        final scope = _licenseService?.getLicenseInfo()?.merchantId ?? '';
        await _productImagePeerService.start(scope);
        await _productImagePeerService.prepareLocalImages(db);
      } catch (_) {
        // Product images are best-effort and never block business-data sync.
      }
    }
    await this._snapshotPreV4DataOnce(db);
    await this._recoverUnsyncedImportedProductsOnce(db);
    await this._recoverUnsyncedAndRejectedEntities(db);
    await DatabaseManager.retryOnLock(() async {
      await db.rawUpdate(
          "UPDATE sync_outbox_v4 SET state = 'PENDING' WHERE state = 'SENDING'");
    });
    var pending = await DatabaseManager.retryOnLock(() async {
      return await db.query('sync_outbox_v4',
          where: "state = 'PENDING'", orderBy: 'id ASC', limit: 100);
    });
    var pushed = 0;
    var failed = 0;
    final errors = <String>[];
    while (pending.isNotEmpty) {
      final orderedPending = this._dependencyOrder(pending);
      await DatabaseManager.retryOnLock(() async {
        await db.update('sync_outbox_v4', {'state': 'SENDING'},
            where:
                'id IN (${List.filled(orderedPending.length, '?').join(',')})',
            whereArgs: orderedPending.map((r) => r['id']).toList());
      });
      try {
        final response = await _api.send('POST', '/api/v4/sync/push',
            body: {
              'device_activation_id': deviceActivationId,
              'device_id': deviceId,
              'mutations': orderedPending
                  .map((r) => {
                        'mutation_id': r['mutation_id'],
                        'entity_type': r['entity_type'],
                        'entity_id': r['entity_id'],
                        'operation': r['operation'],
                        'base_revision': r['base_revision'] ?? 0,
                        'payload': jsonDecode(r['payload'] as String),
                      })
                  .toList(),
            });
        final pushDto = SyncPushResponseDto.fromJson(
            Map<String, dynamic>.from(response.json as Map));
        final acknowledged = pushDto.results
            .map((r) => r.mutationId)
            .where((id) => id.isNotEmpty)
            .toList();
        final conflicts = pushDto.conflicts;
        final conflicted = conflicts
            .map((r) => r.mutationId)
            .where((id) => id.isNotEmpty)
            .toList();
        final rejected = pushDto.rejected;
        final rejectedIds = rejected
            .map((r) => r.mutationId)
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toList();
        await DatabaseManager.retryOnLock(() async {
          await db.transaction((txn) async {
            if (acknowledged.isNotEmpty) {
              final ackSet = acknowledged.toSet();
              for (final row in orderedPending) {
                final mutId = row['mutation_id']?.toString();
                if (mutId != null && ackSet.contains(mutId)) {
                  final entityType = row['entity_type']?.toString();
                  final entityId = row['entity_id']?.toString();
                  if (entityId != null && entityId.isNotEmpty) {
                    final domainTable = switch (entityType) {
                      'financial_transaction' => 'financial_transactions',
                      'product' => 'products',
                      'customer' => 'customers',
                      'order' => 'orders',
                      'sale' => 'sales',
                      _ => null,
                    };
                    if (domainTable != null) {
                      await txn.update(
                        domainTable,
                        {'is_synced': 1},
                        where: 'id = ?',
                        whereArgs: [entityId],
                      );
                    }
                  }
                }
              }
              await txn.delete('sync_outbox_v4',
                  where:
                      'mutation_id IN (${List.filled(acknowledged.length, '?').join(',')})',
                  whereArgs: acknowledged);
            }
            if (conflicted.isNotEmpty) {
              await txn.update('sync_outbox_v4', {'state': 'CONFLICT'},
                  where:
                      'mutation_id IN (${List.filled(conflicted.length, '?').join(',')})',
                  whereArgs: conflicted);
              for (final conflict in conflicts) {
                await txn.insert('sync_conflicts_v4', conflict.toDbRow(),
                    conflictAlgorithm: ConflictAlgorithm.replace);
              }
              failed += conflicted.length;
              errors.add(
                  '${conflicted.length} kayıt başka bir aygıttaki daha yeni değişiklikle çakıştı.');
            }
            if (rejectedIds.isNotEmpty) {
              await txn.rawUpdate('''
                UPDATE sync_outbox_v4
                   SET state = CASE WHEN attempts >= 4 THEN 'DEAD_LETTER' ELSE 'REJECTED' END,
                       attempts = attempts + 1
                 WHERE mutation_id IN (${List.filled(rejectedIds.length, '?').join(',')})
              ''', rejectedIds);
              failed += rejectedIds.length;
              for (final rejection in rejected) {
                errors.add(
                    '${rejection.mutationId ?? "bilinmeyen"}: ${rejection.error}');
              }
            }
          });
        });
        pushed += acknowledged.length;
      } catch (_) {
        await DatabaseManager.retryOnLock(() async {
          await db.rawUpdate(
              "UPDATE sync_outbox_v4 SET state = 'PENDING', attempts = attempts + 1 WHERE state = 'SENDING'");
        });
        rethrow;
      }
      pending = await DatabaseManager.retryOnLock(() async {
        return await db.query('sync_outbox_v4',
            where: "state = 'PENDING'", orderBy: 'id ASC', limit: 100);
      });
    }
    final state = await db.query('sync_cursor_v4',
        where: 'key = ?', whereArgs: ['global'], limit: 1);
    var cursor = state.isEmpty ? 0 : _syncInt(state.first['cursor']);
    var pulled = companyChanged ? 1 : 0;
    final pulledEntityTypes = <String>{};
    if (companyChanged) pulledEntityTypes.add('settings');
    var reconciled = 0;
    var productImagesNeedCleanup = false;
    var catalogSourceNeedsReset = false;

    // A fresh installation cannot reconstruct a tenant from a change log that
    // started after the tenant's original records were created. Hydrate from
    // the server's canonical domain snapshot once, then continue cursor pulls.
    if (state.isEmpty) {
      final bootstrap = await _api.get(
        '/api/v4/sync/bootstrap?device_activation_id=$deviceActivationId&device_id=$deviceId',
      );
      final bootstrapDto = SyncBootstrapResponseDto.fromJson(
        Map<String, dynamic>.from(bootstrap.json as Map),
      );
      final snapshot = this._dependencyOrder(
        bootstrapDto.changes.map((change) => change.toMap()).toList(),
      );
      productImagesNeedCleanup = snapshot.any(_isProductImageReset);
      catalogSourceNeedsReset = snapshot.any(_isCatalogReset);
      await DatabaseManager.retryOnLock(() async {
        await db.transaction((txn) async {
          for (final raw in snapshot) {
            final entityType = raw['entity_type']?.toString();
            if (entityType != null && entityType.isNotEmpty) {
              pulledEntityTypes.add(entityType);
            }
            await this._apply(txn, raw);
          }
          reconciled += await this._reconcileCustomerBalances(txn);
          cursor = bootstrapDto.nextCursor;
          await txn.insert(
              'sync_cursor_v4', {'key': 'global', 'cursor': cursor},
              conflictAlgorithm: ConflictAlgorithm.replace);
        });
      });
      // Bootstrap rows are remote changes too. Counting them ensures consumers
      // invalidate their in-memory lists immediately after first hydration.
      pulled += snapshot.length;
    }
    while (true) {
      final response = await _api.get(
        '/api/v4/sync/pull?cursor=$cursor&limit=200&device_activation_id=$deviceActivationId&device_id=$deviceId',
      );
      final pullDto = SyncPullResponseDto.fromJson(
        Map<String, dynamic>.from(response.json as Map),
        cursor,
      );
      final changes = this._dependencyOrder(
        pullDto.changes.map((c) => c.toMap()).toList(),
      );
      productImagesNeedCleanup =
          productImagesNeedCleanup || changes.any(_isProductImageReset);
      catalogSourceNeedsReset =
          catalogSourceNeedsReset || changes.any(_isCatalogReset);
      final next = pullDto.nextCursor;
      await DatabaseManager.retryOnLock(() async {
        await db.transaction((txn) async {
          for (final raw in changes.cast<Map>()) {
            final rowMap = Map<String, dynamic>.from(raw);
            final entityType = rowMap['entity_type']?.toString();
            if (entityType != null && entityType.isNotEmpty) {
              pulledEntityTypes.add(entityType);
            }
            await this._apply(txn, rowMap);
          }
          if (changes.isNotEmpty) {
            reconciled += await this._reconcileCustomerBalances(txn);
          }
          await txn.insert('sync_cursor_v4', {'key': 'global', 'cursor': next},
              conflictAlgorithm: ConflictAlgorithm.replace);
        });
      });
      pulled += changes.length;
      if (changes.length < 200 || next <= cursor) break;
      cursor = next;
    }
    await DatabaseManager.retryOnLock(() async {
      await db.transaction((txn) async {
        reconciled += await this._reconcileCustomerBalances(txn);
      });
    });
    if (productImagesNeedCleanup && !kIsWeb) {
      await _productImageCleaner();
    }
    if (catalogSourceNeedsReset && !kIsWeb) {
      await _catalogSourceResetter();
    }
    if (!kIsWeb) {
      try {
        pulled += await _productImagePeerService.syncMissingImages(db);
      } catch (_) {
        // An offline peer is expected; the periodic sync pass retries later.
      }
    }
    return SyncV4Result(
      pushed: pushed,
      pulled: pulled,
      reconciled: reconciled,
      failed: failed,
      errors: errors,
      pulledEntityTypes: pulledEntityTypes,
    );
  }

  Future<bool> _syncCompanyProfile(Database db) async {
    final rows = await db.query('settings', limit: 1);
    if (rows.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final isDirty = prefs.getBool('sync_v4_company_dirty') ?? false;

    // 1. If local is dirty, we MUST push local changes to the server.
    // Local user edits take absolute priority over server snapshot.
    if (isDirty) {
      try {
        final response = await _api.get('/api/v1/company');
        if (!response.isSuccess || response.json == null) {
          debugPrint(
              '[SyncV4] Server unreachable for company sync. Preserving local dirty state.');
          return false;
        }
        final remote = Map<String, dynamic>.from(response.json as Map);
        final remoteVersion = _syncInt(remote['version']);

        final local = rows.first;
        final logo =
            await this._portableLogo(local['business_logo']?.toString());
        final localName = local['business_name']?.toString().trim();
        final localTax = local['business_tax_id']?.toString().trim();
        final patchBody = <String, dynamic>{
          'expected_version': remoteVersion,
          'force': true,
          if (localName != null && localName.isNotEmpty) 'name': localName,
          if (local['business_address'] != null)
            'address': local['business_address'],
          if (local['business_phone'] != null)
            'phone': local['business_phone'],
          if (local['business_email'] != null)
            'email': local['business_email'],
          if (localTax != null && localTax.isNotEmpty)
            'tax_number': localTax,
          if (local['owner_name'] != null)
            'owner_name': local['owner_name'],
          if (local['business_type'] != null)
            'type': local['business_type'],
          if (local['business_city'] != null)
            'city': local['business_city'],
          if (local['business_district'] != null)
            'district': local['business_district'],
          if (local['currency'] != null)
            'currency': local['currency'],
          if (logo != null && logo.isNotEmpty)
            'logo_url': logo,
        };
        ApiResponse? patch;
        try {
          patch = await _api.send('PATCH', '/api/v1/company', body: patchBody);
        } on ApiException catch (e) {
          if (e.statusCode == 409) {
            final freshRes = await _api.get('/api/v1/company');
            if (freshRes.isSuccess && freshRes.json != null) {
              final freshRemote = Map<String, dynamic>.from(freshRes.json as Map);
              final freshVer = _syncInt(freshRemote['version']);
              patchBody['expected_version'] = freshVer;
              final isTaxConflict = e.responseBody.contains('TAX_NUMBER_CONFLICT');
              if (isTaxConflict) {
                patchBody.remove('tax_number');
                if (freshRemote['tax_number'] != null) {
                  await prefs.setString(
                      'settings_tax_number', freshRemote['tax_number'].toString());
                }
              }
              try {
                patch = await _api.send('PATCH', '/api/v1/company', body: patchBody);
              } catch (retryErr) {
                debugPrint('[SyncV4] Retry company PATCH failed: $retryErr');
              }
            }
          } else {
            debugPrint('[SyncV4] Company PATCH failed with status ${e.statusCode}: ${e.message}');
          }
        }
        if (patch != null && patch.isSuccess && patch.json != null) {
          final canonical = Map<String, dynamic>.from(patch.json as Map);
          final newVer = _syncInt(canonical['version']);
          await prefs.setInt(SyncV4Service._companyVersionKey, newVer);
          await prefs.setString(
              SyncV4Service._companySyncedAtKey,
              canonical['updated_at']?.toString() ??
                  DateTime.now().toUtc().toIso8601String());
          await prefs.setBool('sync_v4_company_dirty', false);
          return true;
        } else {
          // If remote patch failed, do NOT overwrite local settings!
          return false;
        }
      } catch (e) {
        debugPrint('[SyncV4] Error pushing dirty company profile: $e');
        // Offline or server error: preserve local settings and dirty state!
        return false;
      }
    }

    // 2. If NOT dirty, check if remote has updates
    final response = await _api.get('/api/v1/company');
    if (!response.isSuccess || response.json == null) return false;
    final remote = Map<String, dynamic>.from(response.json as Map);
    final remoteVersion = _syncInt(remote['version']);
    final knownVersion = prefs.getInt(SyncV4Service._companyVersionKey);

    final localName = rows.first['business_name']?.toString() ?? '';
    final localIsDefault = (localName.isEmpty || localName == 'Serenut OS');

    // Only pull from remote if remote version is strictly newer than known version,
    // OR if local is default/unconfigured
    if (!localIsDefault) {
      if (knownVersion != null && remoteVersion <= knownVersion) {
        return false;
      }
      if (knownVersion == null) {
        // Record remote version so we track future changes without clobbering existing local customization
        if (remoteVersion > 0) {
          await prefs.setInt(SyncV4Service._companyVersionKey, remoteVersion);
        }
        return false;
      }
    }

    // Remote has newer changes or local was unconfigured default
    final canonicalName = remote['name']?.toString() ?? '';
    final resolvedName =
        (canonicalName.isEmpty || canonicalName == 'Serenut OS') &&
                !localIsDefault
            ? localName
            : (canonicalName.isNotEmpty ? canonicalName : localName);

    String pick(dynamic remoteVal, dynamic localVal, [String fallback = '']) {
      final r = remoteVal?.toString().trim();
      if (r != null && r.isNotEmpty) return r;
      final l = localVal?.toString().trim();
      if (l != null && l.isNotEmpty) return l;
      return fallback;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'settings',
      {
        'business_name': resolvedName,
        'business_phone': pick(remote['phone'], rows.first['business_phone']),
        'business_address':
            pick(remote['address'], rows.first['business_address']),
        'business_tax_id':
            pick(remote['tax_number'], rows.first['business_tax_id']),
        'business_logo': pick(remote['logo_url'], rows.first['business_logo']),
        'owner_name': pick(remote['owner_name'], rows.first['owner_name']),
        'business_email': pick(remote['email'], rows.first['business_email']),
        'business_city': pick(remote['city'], rows.first['business_city']),
        'business_district':
            pick(remote['district'], rows.first['business_district']),
        'business_type': pick(remote['type'], rows.first['business_type']),
        'currency': pick(remote['currency'], rows.first['currency'], '₺'),
        'updated_at': remote['updated_at']?.toString() ?? now,
      },
      where: 'id = ?',
      whereArgs: [rows.first['id']],
    );
    await prefs.setInt(SyncV4Service._companyVersionKey, remoteVersion);
    await prefs.setString(
        SyncV4Service._companySyncedAtKey,
        remote['updated_at']?.toString() ?? now);
    await prefs.setBool('sync_v4_company_dirty', false);
    return true;
  }

  Future<String?> _portableLogo(String? value) async {
    if (value == null || value.trim().isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    late final Uint8List bytes;
    if (value.startsWith('data:image/')) {
      final comma = value.indexOf(',');
      if (comma < 0) return null;
      bytes = base64Decode(value.substring(comma + 1));
    } else {
      final file = File(value);
      if (!await file.exists()) return null;
      bytes = await file.readAsBytes();
    }
    if (bytes.length > 3 * 1024 * 1024 || img.decodeImage(bytes) == null) {
      return null;
    }
    final upload = await _api.uploadImage(
      '/api/v1/company/logo',
      bytes: bytes,
      filename: 'company-logo.png',
      mimeType: 'image/png',
    );
    final json = Map<String, dynamic>.from(upload.json as Map);
    return json['display_url']?.toString();
  }

  /// A customer balance is a ledger projection, not replicated business data.
  /// Rebuilding it makes bootstrap, retries and out-of-order snapshots converge.
  Future<int> _reconcileCustomerBalances(Transaction db) async {
    return db.rawUpdate('''
      UPDATE customers
         SET balance = COALESCE((
           SELECT SUM(CASE
             WHEN ft.type IN ('sale', 'manual_debt') THEN -(CASE WHEN ft.debt_amount > 0 THEN ft.debt_amount ELSE (ft.amount - ft.paid_amount) END)
             WHEN ft.type IN ('payment', 'collection') THEN ft.paid_amount
             WHEN ft.type = 'cancellation' THEN (CASE WHEN ft.debt_amount > 0 THEN ft.debt_amount ELSE (ft.amount - ft.paid_amount) END)
             WHEN ft.type = 'refund' AND ft.paid_amount = 0 THEN ft.amount
             ELSE 0
           END)
             FROM financial_transactions ft
            WHERE ft.customer_id = customers.id
              AND COALESCE(ft.is_deleted, 0) = 0
         ), 0)
       WHERE ABS(balance - COALESCE((
           SELECT SUM(CASE
             WHEN ft.type IN ('sale', 'manual_debt') THEN -(CASE WHEN ft.debt_amount > 0 THEN ft.debt_amount ELSE (ft.amount - ft.paid_amount) END)
             WHEN ft.type IN ('payment', 'collection') THEN ft.paid_amount
             WHEN ft.type = 'cancellation' THEN (CASE WHEN ft.debt_amount > 0 THEN ft.debt_amount ELSE (ft.amount - ft.paid_amount) END)
             WHEN ft.type = 'refund' AND ft.paid_amount = 0 THEN ft.amount
             ELSE 0
           END)
             FROM financial_transactions ft
            WHERE ft.customer_id = customers.id
              AND COALESCE(ft.is_deleted, 0) = 0
         ), 0)) > 0.000001
    ''');
  }

  /// V4 was introduced after customers had already been using offline data.
  /// Seed that durable local state exactly once so a newly installed device can
  /// receive the complete tenant dataset, not merely edits made after V4.
}
