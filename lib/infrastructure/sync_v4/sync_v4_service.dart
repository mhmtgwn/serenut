import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/domain/services/device_manager.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_outbox.dart';

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
      this.failed = 0,
      this.errors = const []});
  final int pushed;
  final int pulled;
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
    LicenseService? licenseService,
  })  : _deviceActivationIdResolver = deviceActivationIdResolver,
        _deviceIdResolver = deviceIdResolver,
        _licenseService = licenseService;
  final ApiClient _api;
  final Future<String> Function()? _deviceActivationIdResolver;
  final Future<String> Function()? _deviceIdResolver;
  final LicenseService? _licenseService;
  static const _legacySnapshotKey = 'sync_v4_legacy_snapshot_v1';
  static const _unsyncedProductRecoveryKey =
      'sync_v4_unsynced_product_recovery_v1';

  Future<SyncV4Result> sync() async {
    final db = await DatabaseManager().getDatabase();
    final deviceActivationId = await _deviceActivationId();
    final deviceId = await _deviceId();
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
      await db.transaction((txn) async {
        for (final raw in snapshot) {
          await _apply(txn, raw);
        }
        cursor = _syncInt(bootstrapBody['next_cursor']);
        await txn.insert('sync_cursor_v4', {'key': 'global', 'cursor': cursor},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });
    }
    var pulled = 0;
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
      final next = _syncInt(pullBody['next_cursor'], cursor);
      await db.transaction((txn) async {
        for (final raw in changes.cast<Map>()) {
          await _apply(txn, Map<String, dynamic>.from(raw));
        }
        await txn.insert('sync_cursor_v4', {'key': 'global', 'cursor': next},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });
      pulled += changes.length;
      if (changes.length < 200 || next <= cursor) break;
      cursor = next;
    }
    return SyncV4Result(
      pushed: pushed,
      pulled: pulled,
      failed: failed,
      errors: errors,
    );
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
      'financial_transaction': 4,
    };
    final ordered = List<Map<String, dynamic>>.from(records);
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

  Future<void> _apply(Transaction db, Map<String, dynamic> change) async {
    final type = change['entity_type'] as String;
    final payload = Map<String, dynamic>.from(change['payload'] as Map);
    final id = change['entity_id'] as String;
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
    final items = payload.remove('items');
    final row = await _normalizeRowForLocalSchema(
      db,
      table,
      {...payload, 'id': id, 'is_synced': 1},
    );
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
