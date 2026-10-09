part of 'sync_v4_service.dart';

bool _isProductImageReset(Map<String, dynamic> change) {
  if (change['entity_type'] != 'system_reset') return false;
  final payload = change['payload'];
  if (payload is! Map) return false;
  return payload['scope'] == 'operational' || payload['scope'] == 'catalog';
}

bool _isCatalogReset(Map<String, dynamic> change) {
  if (change['entity_type'] != 'system_reset') return false;
  final payload = change['payload'];
  if (payload is! Map) return false;
  return payload['scope'] == 'catalog';
}

/// Local order numbers historically came from a device-local sequence, so
/// two devices can legitimately create different orders with (for example)
/// `SP-000001`. The cloud keeps both records, while the legacy SQLite schema
/// has a UNIQUE constraint on [order_number]. Keep both orders locally by
/// assigning a stable display suffix to the incoming record.

extension SyncV4Recovery on SyncV4Service {
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

  /// Retries previously rejected outbox mutations across all entity types
  /// (e.g. sales rejected due to discount/stock calculation bugs) and enqueues
  /// any unsynced local rows so both PC and mobile devices converge completely.
  Future<void> _recoverUnsyncedAndRejectedEntities(Database db) async {
    await DatabaseManager.retryOnLock(() async {
      await db.rawUpdate('''
        UPDATE sync_outbox_v4
           SET state = 'DEAD_LETTER'
         WHERE state = 'REJECTED'
           AND attempts >= 5
      ''');

      await db.rawUpdate('''
        UPDATE sync_outbox_v4
           SET state = 'PENDING'
         WHERE state = 'REJECTED'
           AND attempts < 5
      ''');

      await db.transaction((txn) async {
        const entityTables = <String, String>{
          'product': 'products',
          'customer': 'customers',
          'sale': 'sales',
          'order': 'orders',
          'financial_transaction': 'financial_transactions',
        };

        for (final entry in entityTables.entries) {
          final entityType = entry.key;
          final tableName = entry.value;

          final unsynced = await txn.rawQuery('''
            SELECT t.* FROM $tableName t
            WHERE COALESCE(t.is_synced, 0) = 0
              AND NOT EXISTS (
                SELECT 1 FROM sync_outbox_v4 o
                WHERE o.entity_type = '$entityType'
                  AND o.entity_id = t.id
              )
            LIMIT 100
          ''');

          for (final row in unsynced) {
            final id = row['id']?.toString();
            if (id == null || id.isEmpty) continue;
            final payload = Map<String, dynamic>.from(row);
            if (entityType == 'sale' || entityType == 'order') {
              final itemTable =
                  entityType == 'sale' ? 'sale_items' : 'order_items';
              final parentCol = entityType == 'sale' ? 'sale_id' : 'order_id';
              payload['items'] = await txn.query(
                itemTable,
                where: '$parentCol = ?',
                whereArgs: [id],
              );
            }
            await SyncOutboxV4.enqueue(
              txn,
              entityType: entityType,
              entityId: id,
              operation: row['is_deleted'] == 1 ? 'DELETE' : 'UPSERT',
              payload: payload,
            );
          }
        }
      });
    });
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
}
