import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:serenutos/domain/services/device_manager.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/services/barcode_standard.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_outbox.dart';
import 'package:serenutos/infrastructure/services/data_reset_service.dart';
import 'package:serenutos/infrastructure/services/product_image_peer_service.dart';

int _syncInt(Object? value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _syncDouble(Object? value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

class SyncV4Result {
  const SyncV4Result(
      {required this.pushed,
      required this.pulled,
      this.reconciled = 0,
      this.failed = 0,
      this.errors = const []});
  final int pushed;
  final int pulled;
  final int reconciled;
  final int failed;
  final List<String> errors;
  int get synced => pushed;
  bool get success => failed == 0 && errors.isEmpty;
}

/// Crash-safe, cursor based replication. WebSocket is deliberately optional:
/// correctness comes from this pull loop, not from a live connection.
class SyncV4Service {
  SyncV4Service(
    this._api, {
    Future<String> Function()? deviceActivationIdResolver,
    Future<String> Function()? deviceIdResolver,
    Future<void> Function()? productImageCleaner,
    ProductImagePeerService? productImagePeerService,
    LicenseService? licenseService,
  })  : _deviceActivationIdResolver = deviceActivationIdResolver,
        _deviceIdResolver = deviceIdResolver,
        _productImageCleaner =
            productImageCleaner ?? DataResetService.clearProductImages,
        _productImagePeerService =
            productImagePeerService ?? ProductImagePeerService.instance,
        _licenseService = licenseService;
  final ApiClient _api;
  final Future<String> Function()? _deviceActivationIdResolver;
  final Future<String> Function()? _deviceIdResolver;
  final Future<void> Function() _productImageCleaner;
  final ProductImagePeerService _productImagePeerService;
  final LicenseService? _licenseService;
  static const _legacySnapshotKey = 'sync_v4_legacy_snapshot_v1';
  static const _unsyncedProductRecoveryKey =
      'sync_v4_unsynced_product_recovery_v1';
  static const _companyVersionKey = 'sync_v4_company_version';
  static const _companySyncedAtKey = 'sync_v4_company_synced_at';

  /// Permanently resets the tenant's operational data on the server, then
  /// applies the returned reset barrier locally. The server revision prevents
  /// stale offline mutations from resurrecting pre-reset data.
  Future<int> resetOperationalData() async {
    final deviceActivationId = await _deviceActivationId();
    final deviceId = await _deviceId();
    final response = await _api.post('/api/v4/sync/operational-reset', {
      'device_activation_id': deviceActivationId,
      'device_id': deviceId,
    });
    final body = Map<String, dynamic>.from(response.json as Map);
    final revision = _syncInt(body['reset_revision']);
    if (revision <= 0) throw StateError('invalid_operational_reset_revision');

    if (!kIsWeb) {
      final db = await DatabaseManager().getDatabase();
      await db.transaction((txn) async {
        await DataResetService.clearOperationalTables(txn);
        await txn.insert(
          'sync_cursor_v4',
          {'key': 'global', 'cursor': revision},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      await _productImageCleaner();
    }
    return revision;
  }

  /// Resets only the tenant product catalogue on the server and applies the
  /// returned barrier locally. Sales, customers and financial history remain.
  Future<int> resetProductCatalog() async {
    final deviceActivationId = await _deviceActivationId();
    final deviceId = await _deviceId();
    final response = await _api.post('/api/v4/sync/catalog-reset', {
      'device_activation_id': deviceActivationId,
      'device_id': deviceId,
    });
    final body = Map<String, dynamic>.from(response.json as Map);
    final revision = _syncInt(body['reset_revision']);
    if (revision <= 0) throw StateError('invalid_catalog_reset_revision');

    if (!kIsWeb) {
      final db = await DatabaseManager().getDatabase();
      await db.transaction((txn) async {
        await DataResetService.clearProductCatalog(txn);
        await txn.insert(
          'sync_cursor_v4',
          {'key': 'global', 'cursor': revision},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      await _productImageCleaner();
    }
    return revision;
  }

  Future<SyncV4Result> sync() async {
    final db = await DatabaseManager().getDatabase();
    var companyChanged = false;
    try {
      companyChanged = await _syncCompanyProfile(db);
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
    await _snapshotPreV4DataOnce(db);
    await _recoverUnsyncedImportedProductsOnce(db);
    await db.rawUpdate(
        "UPDATE sync_outbox_v4 SET state = 'PENDING' WHERE state = 'SENDING'");
    var pending = await db.query('sync_outbox_v4',
        where: "state = 'PENDING'", orderBy: 'id ASC', limit: 100);
    var pushed = 0;
    var failed = 0;
    final errors = <String>[];
    while (pending.isNotEmpty) {
      final orderedPending = _dependencyOrder(pending);
      await db.update('sync_outbox_v4', {'state': 'SENDING'},
          where: 'id IN (${List.filled(orderedPending.length, '?').join(',')})',
          whereArgs: orderedPending.map((r) => r['id']).toList());
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
            },
            idempotencyKey: 'sync-v4-${orderedPending.first['mutation_id']}');
        final body = Map<String, dynamic>.from(response.json as Map);
        final acknowledged = ((body['results'] as List?) ?? [])
            .map((r) => (r as Map)['mutation_id'])
            .toList();
        final conflicts = ((body['conflicts'] as List?) ?? [])
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        final conflicted =
            conflicts.map((r) => r['mutation_id']).whereType<String>().toList();
        final rejected = ((body['rejected'] as List?) ?? [])
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        final rejectedIds =
            rejected.map((r) => r['mutation_id']).whereType<String>().toList();
        await db.transaction((txn) async {
          if (acknowledged.isNotEmpty) {
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
              await txn.insert(
                  'sync_conflicts_v4',
                  {
                    'mutation_id': conflict['mutation_id'],
                    'entity_type': conflict['entity_type'],
                    'entity_id': conflict['entity_id'],
                    'server_revision': conflict['server_revision'],
                    'detected_at': DateTime.now().toUtc().toIso8601String(),
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace);
            }
            failed += conflicted.length;
            errors.add(
                '${conflicted.length} kayıt başka bir aygıttaki daha yeni değişiklikle çakıştı.');
          }
          if (rejectedIds.isNotEmpty) {
            await txn.update('sync_outbox_v4', {'state': 'REJECTED'},
                where:
                    'mutation_id IN (${List.filled(rejectedIds.length, '?').join(',')})',
                whereArgs: rejectedIds);
            failed += rejectedIds.length;
            for (final rejection in rejected) {
              errors.add(
                  '${rejection['mutation_id']}: ${rejection['error'] ?? 'mutation_failed'}');
            }
          }
        });
        pushed += acknowledged.length;
      } catch (_) {
        await db.rawUpdate(
            "UPDATE sync_outbox_v4 SET state = 'PENDING', attempts = attempts + 1 WHERE state = 'SENDING'");
        rethrow;
      }
      pending = await db.query('sync_outbox_v4',
          where: "state = 'PENDING'", orderBy: 'id ASC', limit: 100);
    }
    final state = await db.query('sync_cursor_v4',
        where: 'key = ?', whereArgs: ['global'], limit: 1);
    var cursor = state.isEmpty ? 0 : _syncInt(state.first['cursor']);
    var pulled = companyChanged ? 1 : 0;
    var reconciled = 0;
    var productImagesNeedCleanup = false;

    // A fresh installation cannot reconstruct a tenant from a change log that
    // started after the tenant's original records were created. Hydrate from
    // the server's canonical domain snapshot once, then continue cursor pulls.
    if (state.isEmpty) {
      final bootstrap = await _api.get(
        '/api/v4/sync/bootstrap?device_activation_id=$deviceActivationId&device_id=$deviceId',
      );
      final bootstrapBody = Map<String, dynamic>.from(bootstrap.json as Map);
      final snapshot = _dependencyOrder(
        ((bootstrapBody['changes'] as List?) ?? const [])
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList(),
      );
      productImagesNeedCleanup = snapshot.any(_isProductImageReset);
      await db.transaction((txn) async {
        for (final raw in snapshot) {
          await _apply(txn, raw);
        }
        cursor = _syncInt(bootstrapBody['next_cursor']);
        await txn.insert('sync_cursor_v4', {'key': 'global', 'cursor': cursor},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });
      // Bootstrap rows are remote changes too. Counting them ensures consumers
      // invalidate their in-memory lists immediately after first hydration.
      pulled += snapshot.length;
    }
    while (true) {
      final response = await _api.get(
        '/api/v4/sync/pull?cursor=$cursor&limit=200&device_activation_id=$deviceActivationId&device_id=$deviceId',
      );
      final pullBody = Map<String, dynamic>.from(response.json as Map);
      final changes = _dependencyOrder(
        ((pullBody['changes'] as List?) ?? const [])
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList(),
      );
      productImagesNeedCleanup =
          productImagesNeedCleanup || changes.any(_isProductImageReset);
      final next = _syncInt(pullBody['next_cursor'], cursor);
      await db.transaction((txn) async {
        for (final raw in changes.cast<Map>()) {
          await _apply(txn, Map<String, dynamic>.from(raw));
        }
        reconciled += await _reconcileCustomerBalances(txn);
        await txn.insert('sync_cursor_v4', {'key': 'global', 'cursor': next},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });
      pulled += changes.length;
      if (changes.length < 200 || next <= cursor) break;
      cursor = next;
    }
    if (productImagesNeedCleanup && !kIsWeb) {
      await _productImageCleaner();
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
    );
  }

  Future<bool> _syncCompanyProfile(Database db) async {
    final response = await _api.get('/api/v1/company');
    final remote = Map<String, dynamic>.from(response.json as Map);
    final rows = await db.query('settings', limit: 1);
    if (rows.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final knownVersion = prefs.getInt(_companyVersionKey);
    final lastSyncedAt =
        DateTime.tryParse(prefs.getString(_companySyncedAtKey) ?? '');
    final localUpdatedAt =
        DateTime.tryParse(rows.first['updated_at']?.toString() ?? '');
    final remoteUpdatedAt =
        DateTime.tryParse(remote['updated_at']?.toString() ?? '');
    final remoteVersion = _syncInt(remote['version']);

    final localChanged = knownVersion != null &&
        localUpdatedAt != null &&
        lastSyncedAt != null &&
        localUpdatedAt.isAfter(lastSyncedAt);
    final remoteChanged = knownVersion != null && remoteVersion > knownVersion;

    Map<String, dynamic> canonical = remote;
    if (localChanged &&
        (!remoteChanged ||
            remoteUpdatedAt == null ||
            localUpdatedAt.isAfter(remoteUpdatedAt))) {
      final local = rows.first;
      final logo = await _portableLogo(local['business_logo']?.toString());
      final patch = await _api.send('PATCH', '/api/v1/company', body: {
        'expected_version': remoteVersion,
        'name': local['business_name'],
        'address': local['business_address'],
        'phone': local['business_phone'],
        'email': local['business_email'],
        'tax_number': local['business_tax_id'],
        'owner_name': local['owner_name'],
        'type': local['business_type'],
        'city': local['business_city'],
        'district': local['business_district'],
        'currency': local['currency'],
        'logo_url': logo,
      });
      canonical = Map<String, dynamic>.from(patch.json as Map);
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'settings',
      {
        'business_name': canonical['name'] ?? '',
        'business_phone': canonical['phone'] ?? '',
        'business_address': canonical['address'] ?? '',
        'business_tax_id': canonical['tax_number'],
        'business_logo': canonical['logo_url'],
        'owner_name': canonical['owner_name'] ?? '',
        'business_email': canonical['email'],
        'business_city': canonical['city'] ?? '',
        'business_district': canonical['district'] ?? '',
        'business_type': canonical['type'] ?? '',
        'currency': canonical['currency'] ?? '₺',
        'updated_at': canonical['updated_at']?.toString() ?? now,
      },
      where: 'id = ?',
      whereArgs: [rows.first['id']],
    );
    await prefs.setInt(_companyVersionKey, _syncInt(canonical['version']));
    await prefs.setString(
        _companySyncedAtKey, canonical['updated_at']?.toString() ?? now);
    return localChanged || remoteChanged || knownVersion == null;
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
             WHEN ft.type IN ('sale', 'manual_debt') THEN -ft.debt_amount
             WHEN ft.type IN ('payment', 'collection') THEN ft.paid_amount
             WHEN ft.type = 'cancellation' THEN ft.debt_amount
             WHEN ft.type = 'refund' AND ft.paid_amount = 0 THEN ft.amount
             ELSE 0
           END)
             FROM financial_transactions ft
            WHERE ft.customer_id = customers.id
              AND COALESCE(ft.is_deleted, 0) = 0
         ), 0)
       WHERE ABS(balance - COALESCE((
           SELECT SUM(CASE
             WHEN ft.type IN ('sale', 'manual_debt') THEN -ft.debt_amount
             WHEN ft.type IN ('payment', 'collection') THEN ft.paid_amount
             WHEN ft.type = 'cancellation' THEN ft.debt_amount
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
  Future<void> _snapshotPreV4DataOnce(Database db) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_legacySnapshotKey) == true) return;

    await db.transaction((txn) async {
      const entityTables = <String, String>{
        'product': 'products',
        'customer': 'customers',
        'order': 'orders',
        'sale': 'sales',
        'financial_transaction': 'financial_transactions',
      };
      for (final entry in entityTables.entries) {
        final rows = await txn.query(entry.value);
        for (final source in rows) {
          final id = source['id']?.toString();
          if (id == null || id.isEmpty) continue;
          final existing = await txn.query('sync_outbox_v4',
              columns: ['id'],
              where: 'entity_type = ? AND entity_id = ?',
              whereArgs: [entry.key, id],
              limit: 1);
          if (existing.isNotEmpty) continue;

          final payload = Map<String, dynamic>.from(source);
          if (entry.key == 'order' || entry.key == 'sale') {
            final itemTable =
                entry.key == 'order' ? 'order_items' : 'sale_items';
            final parentColumn = entry.key == 'order' ? 'order_id' : 'sale_id';
            payload['items'] = await txn
                .query(itemTable, where: '$parentColumn = ?', whereArgs: [id]);
          }
          await txn.insert('sync_outbox_v4', {
            'mutation_id': const Uuid().v4(),
            'entity_type': entry.key,
            'entity_id': id,
            'operation': source['is_deleted'] == 1 ? 'DELETE' : 'UPSERT',
            'payload': jsonEncode(payload),
            'base_revision': 0,
            'state': 'PENDING',
            'attempts': 0,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      }
    });
    await prefs.setBool(_legacySnapshotKey, true);
  }

  /// Catalog imports in releases before 1.2.0+42 wrote products with
  /// `is_synced = 0` but did not create outbox mutations. Recover those rows
  /// exactly once; the normal import path now enqueues mutations atomically.
  Future<void> _recoverUnsyncedImportedProductsOnce(Database db) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_unsyncedProductRecoveryKey) == true) return;

    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT p.* FROM products p
        WHERE COALESCE(p.is_synced, 0) = 0
          AND NOT EXISTS (
            SELECT 1 FROM sync_outbox_v4 o
            WHERE o.entity_type = 'product' AND o.entity_id = p.id
          )
        ORDER BY p.id
      ''');
      for (final row in rows) {
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        await SyncOutboxV4.enqueue(
          txn,
          entityType: 'product',
          entityId: id,
          operation: row['is_deleted'] == 1 ? 'DELETE' : 'UPSERT',
          payload: Map<String, dynamic>.from(row),
        );
      }
    });
    await prefs.setBool(_unsyncedProductRecoveryKey, true);
  }

  /// Parents must exist before child aggregate rows and line items are applied.
  /// Deletions run in reverse order so their tombstones cannot violate FKs.
  List<Map<String, dynamic>> _dependencyOrder(
      List<Map<String, dynamic>> records) {
    const parentsFirst = <String, int>{
      'product': 0,
      'customer': 1,
      'order': 2,
      'sale': 3,
      'refund': 4,
      'financial_transaction': 5,
    };
    List<Map<String, dynamic>> orderSegment(
        List<Map<String, dynamic>> segment) {
      final ordered = List<Map<String, dynamic>>.from(segment);
      ordered.sort((a, b) {
        final aDelete = a['operation'] == 'DELETE';
        final bDelete = b['operation'] == 'DELETE';
        if (aDelete != bDelete) return aDelete ? 1 : -1;
        final aRank = parentsFirst[a['entity_type']] ?? 99;
        final bRank = parentsFirst[b['entity_type']] ?? 99;
        return aDelete ? bRank.compareTo(aRank) : aRank.compareTo(bRank);
      });
      return ordered;
    }

    // A server-issued reset is a causal barrier. Preserve its journal position
    // while still dependency-sorting ordinary changes on either side.
    final result = <Map<String, dynamic>>[];
    final segment = <Map<String, dynamic>>[];
    for (final record in records) {
      if (record['entity_type'] == 'system_reset') {
        result.addAll(orderSegment(segment));
        segment.clear();
        result.add(record);
      } else {
        segment.add(record);
      }
    }
    result.addAll(orderSegment(segment));
    return result;
  }

  Future<void> _apply(Transaction db, Map<String, dynamic> change) async {
    final type = change['entity_type'] as String;
    final payload = Map<String, dynamic>.from(change['payload'] as Map);
    var id = change['entity_id'] as String;
    if (type == 'system_reset') {
      switch (payload['scope']) {
        case 'operational':
          await DataResetService.clearOperationalTables(db);
          break;
        case 'catalog':
          await DataResetService.clearProductCatalog(db);
          break;
        default:
          throw StateError('unsupported_system_reset_scope');
      }
      return;
    }
    if (type == 'refund') {
      if (change['operation'] == 'DELETE') throw StateError('immutable_refund');
      await _applyRefund(db, id, payload);
      return;
    }
    final table = switch (type) {
      'product' => 'products',
      'customer' => 'customers',
      'order' => 'orders',
      'sale' => 'sales',
      'financial_transaction' => 'financial_transactions',
      _ => null,
    };
    if (table == null) return;
    if (change['operation'] == 'DELETE') {
      final tombstone = <String, Object?>{
        'is_deleted': 1,
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'is_synced': 1,
      };
      if (table == 'products' || table == 'customers') {
        tombstone['is_active'] = 0;
      }
      await db.update(table, tombstone, where: 'id = ?', whereArgs: [id]);
      return;
    }
    if (type == 'product') {
      final repairedId = BarcodeStandard.normalizeReadyCatalog(id);
      if (repairedId != id) {
        final existing = await db.query(
          'products',
          columns: const ['id', 'name', 'price', 'image_url'],
          where: 'id = ?',
          whereArgs: [repairedId],
          limit: 1,
        );
        final incomingName = payload['name']?.toString().trim().toLowerCase();
        final incomingPrice = _syncDouble(payload['price']);
        if (existing.isNotEmpty &&
            existing.first['name']?.toString().trim().toLowerCase() ==
                incomingName &&
            ((_syncDouble(existing.first['price']) - incomingPrice).abs() <=
                0.01)) {
          final retainedImage = existing.first['image_url']?.toString() ?? '';
          if ((payload['image_url']?.toString().trim().isEmpty ?? true) &&
              retainedImage.isNotEmpty) {
            payload['image_url'] = retainedImage;
          }
          if (payload['sku']?.toString() == id) payload['sku'] = repairedId;
          id = repairedId;
        }
      }
    }
    final items = payload.remove('items');
    if (type == 'order' &&
        (payload['order_number'] == null ||
            payload['order_number'].toString().trim().isEmpty)) {
      // Cloud orders created before schema v80 have no order number. SQLite
      // requires one, so use a deterministic value that is stable on replay.
      payload['order_number'] = 'SYNC-$id';
    }
    final row = await _normalizeRowForLocalSchema(
      db,
      table,
      {...payload, 'id': id, 'is_synced': 1},
    );
    if (type == 'order') {
      await _disambiguateOrderNumber(db, row, id);
    }
    if (type == 'customer') {
      // Server balance is a cache and uses the opposite sign convention.
      // The immutable local ledger is the sole source for this projection.
      row.remove('balance');
    }
    if (type == 'financial_transaction') {
      // Ledger rows are immutable. Replaying the same globally unique ID is
      // an idempotent no-op; a new ID is inserted exactly once.
      final existing = await db.query(
        table,
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existing.isNotEmpty) return;
      await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.abort);
      return;
    }
    final updated =
        await db.update(table, row, where: 'id = ?', whereArgs: [id]);
    if (updated == 0) {
      await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.abort);
    }
    if (items is List && (type == 'sale' || type == 'order')) {
      final itemTable = type == 'sale' ? 'sale_items' : 'order_items';
      final parentColumn = type == 'sale' ? 'sale_id' : 'order_id';
      await db.delete(itemTable, where: '$parentColumn = ?', whereArgs: [id]);
      for (var index = 0; index < items.length; index++) {
        final source = Map<String, dynamic>.from(items[index] as Map);
        final productId = source['product_id']?.toString();
        if (productId == null || productId.isEmpty) continue;
        final quantity = _syncDouble(source['quantity']);
        final unitPrice = _syncDouble(source['unit_price']);
        await db.insert(
            itemTable,
            {
              'id': source['id'] ?? 'sync-$id-$productId-$index',
              parentColumn: id,
              'product_id': productId,
              'product_name': source['product_name'],
              'quantity': quantity,
              'unit_price': unitPrice,
              if (type == 'sale') 'subtotal': quantity * unitPrice,
              'created_at': source['created_at'] ??
                  DateTime.now().toUtc().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  static bool _isProductImageReset(Map<String, dynamic> change) {
    if (change['entity_type'] != 'system_reset') return false;
    final payload = change['payload'];
    if (payload is! Map) return false;
    return payload['scope'] == 'operational' || payload['scope'] == 'catalog';
  }

  /// Local order numbers historically came from a device-local sequence, so
  /// two devices can legitimately create different orders with (for example)
  /// `SP-000001`. The cloud keeps both records, while the legacy SQLite schema
  /// has a UNIQUE constraint on [order_number]. Keep both orders locally by
  /// assigning a stable display suffix to the incoming record.
  Future<void> _disambiguateOrderNumber(
    Transaction db,
    Map<String, Object?> row,
    String id,
  ) async {
    final orderNumber = row['order_number']?.toString().trim() ?? '';
    if (orderNumber.isEmpty) return;

    final collision = await db.query(
      'orders',
      columns: const ['id'],
      where: 'order_number = ? AND id <> ?',
      whereArgs: [orderNumber, id],
      limit: 1,
    );
    if (collision.isEmpty) return;

    // Including the globally unique entity ID makes the value deterministic
    // across retries and avoids silently merging two unrelated orders.
    row['order_number'] = '$orderNumber-$id';
  }

  Future<void> _applyRefund(
      Transaction db, String id, Map<String, dynamic> payload) async {
    final existing = await db.query('refunds',
        columns: const ['id'], where: 'id=?', whereArgs: [id], limit: 1);
    if (existing.isNotEmpty) return;
    final saleId = payload['sale_id']?.toString() ?? '';
    final sales =
        await db.query('sales', where: 'id=?', whereArgs: [saleId], limit: 1);
    if (sales.isEmpty) throw StateError('refund_sale_missing');
    final sale = sales.first;
    final snapshotProjection = payload['_snapshot_projection'] == true;
    final rawItems = payload['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      throw StateError('refund_items_missing');
    }
    final normalized = <Map<String, Object?>>[];
    var amount = 0.0;
    for (final value in rawItems) {
      final item = Map<String, dynamic>.from(value as Map);
      final saleItemId = item['sale_item_id']?.toString() ?? '';
      final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
      final rows = await db.rawQuery(
          '''SELECT si.*,COALESCE((SELECT SUM(ri.quantity)
        FROM refund_items ri WHERE ri.sale_item_id=si.id),0) refunded_quantity
        FROM sale_items si WHERE si.id=? AND si.sale_id=?''',
          [saleItemId, saleId]);
      if (rows.isEmpty || quantity <= 0) {
        throw StateError('invalid_refund_item');
      }
      final row = rows.first;
      final sold = (row['quantity'] as num).toDouble();
      final refunded = (row['refunded_quantity'] as num).toDouble();
      if (quantity > sold - refunded) {
        throw StateError('invalid_refund_quantity');
      }
      final unit = (row['subtotal'] as num).toDouble() / sold;
      final subtotal = double.parse((unit * quantity).toStringAsFixed(2));
      amount += subtotal;
      normalized.add({
        'sale_item_id': saleItemId,
        'product_id': row['product_id'],
        'quantity': quantity,
        'unit_refund_amount': unit,
        'subtotal': subtotal
      });
    }
    amount = double.parse(amount.toStringAsFixed(2));
    final now = DateTime.now().toUtc().toIso8601String();
    final method = payload['refund_method']?.toString() ?? 'balance';
    final reason = payload['reason']?.toString() ?? '';
    await db.insert('refunds', {
      'id': id,
      'sale_id': saleId,
      'amount': amount,
      'refund_method': method,
      'external_reference': payload['external_reference'],
      'reason': reason,
      'status': 'completed',
      'created_at': now
    });
    for (final row in normalized) {
      await db.insert('refund_items',
          {'id': 'sync-$id-${row['sale_item_id']}', 'refund_id': id, ...row});
      if (!snapshotProjection) {
        await db.rawUpdate(
            'UPDATE products SET quantity=quantity+?,updated_at=? WHERE id=?',
            [row['quantity'], now, row['product_id']]);
      }
    }
    final previous = (sale['refunded_amount'] as num?)?.toDouble() ?? 0;
    final total = (sale['total_amount'] as num).toDouble();
    final newRefunded = double.parse((previous + amount).toStringAsFixed(2));
    await db.update(
        'sales',
        {
          'refunded_amount': newRefunded,
          'fsm_state':
              newRefunded >= total - 0.01 ? 'refunded' : 'partially_refunded',
          'updated_at': now
        },
        where: 'id=?',
        whereArgs: [saleId]);
    final customerId = sale['customer_id']?.toString();
    if (!snapshotProjection && customerId != null && customerId.isNotEmpty) {
      await db.insert(
          'financial_transactions',
          {
            'id': 'refund-$id',
            'type': 'refund',
            'customer_id': customerId,
            'amount': amount,
            'paid_amount': method == 'balance' ? 0.0 : amount,
            'debt_amount': 0.0,
            'reference_id': id,
            'description': reason,
            'payment_method': method,
            'created_at': now,
            'is_synced': 1
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Sync payloads outlive individual client schema versions. Only write
  /// columns present in the receiving SQLite table and fill mandatory audit
  /// timestamps when an older producer omitted them.
  Future<Map<String, Object?>> _normalizeRowForLocalSchema(
    Transaction db,
    String table,
    Map<String, dynamic> source,
  ) async {
    final schema = await db.rawQuery('PRAGMA table_info($table)');
    final columns = schema
        .map((column) => column['name']?.toString())
        .whereType<String>()
        .toSet();
    final row = <String, Object?>{
      for (final entry in source.entries)
        if (columns.contains(entry.key)) entry.key: entry.value,
    };
    final now = DateTime.now().toUtc().toIso8601String();
    if (columns.contains('created_at') && row['created_at'] == null) {
      row['created_at'] = now;
    }
    if (columns.contains('updated_at') && row['updated_at'] == null) {
      row['updated_at'] = row['created_at'] ?? now;
    }
    return row;
  }

  Future<String> _deviceId() async {
    final resolver = _deviceIdResolver;
    if (resolver != null) return resolver();
    final prefs = await SharedPreferences.getInstance();
    return DeviceManager.resolveDeviceId(prefs);
  }

  Future<String> _deviceActivationId() async {
    final resolver = _deviceActivationIdResolver;
    if (resolver != null) return resolver();
    final licenseService = _licenseService;
    if (licenseService != null) {
      final activationId = licenseService.getLicenseInfo()?.activationId;
      if (activationId != null && activationId.isNotEmpty) {
        return activationId;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final activationId = LicenseService(prefs).getLicenseInfo()?.activationId;
    if (activationId == null || activationId.isEmpty) {
      throw StateError('active_device_activation_required');
    }
    return activationId;
  }
}
