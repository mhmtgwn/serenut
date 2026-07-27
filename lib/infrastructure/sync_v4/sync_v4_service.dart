import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

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
  SyncV4Service(this._api);
  final ApiClient _api;
  static const _deviceKey = 'sync_v4_device_id';
  static const _legacySnapshotKey = 'sync_v4_legacy_snapshot_v1';

  Future<SyncV4Result> sync() async {
    final db = await DatabaseManager().getDatabase();
    final deviceId = await _deviceId();
    await _snapshotPreV4DataOnce(db);
    await db.rawUpdate(
        "UPDATE sync_outbox_v4 SET state = 'PENDING' WHERE state = 'SENDING'");
    final pending = await db.query('sync_outbox_v4',
        where: "state = 'PENDING'", orderBy: 'id ASC', limit: 100);
    final orderedPending = _dependencyOrder(pending);
    var pushed = 0;
    if (orderedPending.isNotEmpty) {
      await db.update('sync_outbox_v4', {'state': 'SENDING'},
          where: 'id IN (${List.filled(orderedPending.length, '?').join(',')})',
          whereArgs: orderedPending.map((r) => r['id']).toList());
      try {
        final response = await _api.send('POST', '/api/v4/sync/push',
            body: {
              'device_id': deviceId,
              'mutations': orderedPending
                  .map((r) => {
                        'mutation_id': r['mutation_id'],
                        'entity_type': r['entity_type'],
                        'entity_id': r['entity_id'],
                        'operation': r['operation'],
                        'payload': jsonDecode(r['payload'] as String),
                      })
                  .toList(),
            },
            idempotencyKey: 'sync-v4-${orderedPending.first['mutation_id']}');
        final body = Map<String, dynamic>.from(response.json as Map);
        final acknowledged = ((body['results'] as List?) ?? [])
            .map((r) => (r as Map)['mutation_id'])
            .toList();
        await db.transaction((txn) async {
          if (acknowledged.isNotEmpty) {
            await txn.delete('sync_outbox_v4',
                where:
                    'mutation_id IN (${List.filled(acknowledged.length, '?').join(',')})',
                whereArgs: acknowledged);
          }
        });
        pushed = acknowledged.length;
      } catch (_) {
        await db.rawUpdate(
            "UPDATE sync_outbox_v4 SET state = 'PENDING', attempts = attempts + 1 WHERE state = 'SENDING'");
        rethrow;
      }
    }
    final state = await db.query('sync_cursor_v4',
        where: 'key = ?', whereArgs: ['global'], limit: 1);
    final cursor = state.isEmpty ? 0 : (state.first['cursor'] as num).toInt();
    final response =
        await _api.get('/api/v4/sync/pull?cursor=$cursor&limit=200');
    final pullBody = Map<String, dynamic>.from(response.json as Map);
    final changes = _dependencyOrder(
      ((pullBody['changes'] as List?) ?? const [])
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList(),
    );
    await db.transaction((txn) async {
      for (final raw in changes.cast<Map>()) {
        await _apply(txn, Map<String, dynamic>.from(raw));
      }
      final next = (pullBody['next_cursor'] as num?)?.toInt() ?? cursor;
      await txn.insert('sync_cursor_v4', {'key': 'global', 'cursor': next},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
    return SyncV4Result(pushed: pushed, pulled: changes.length);
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
            'state': 'PENDING',
            'attempts': 0,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      }
    });
    await prefs.setBool(_legacySnapshotKey, true);
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
    final row = {...payload, 'id': id, 'is_synced': 1};
    if (type == 'financial_transaction') {
      await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.ignore);
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
        final quantity = (source['quantity'] as num?)?.toDouble() ?? 0;
        final unitPrice = (source['unit_price'] as num?)?.toDouble() ?? 0;
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

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceKey) ?? await _createDeviceId(prefs);
  }

  Future<String> _createDeviceId(SharedPreferences prefs) async {
    final id = const Uuid().v4();
    await prefs.setString(_deviceKey, id);
    return id;
  }
}
