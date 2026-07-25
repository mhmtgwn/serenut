import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'outbox_dao.dart';
import 'sync_v2_schema.dart';

class SyncLocalTransactionService {
  final Database db;
  final OutboxDao outboxDao;

  SyncLocalTransactionService({required this.db, required this.outboxDao});

  /**
   * Atomically executes local entity mutation and inserts outbox item inside a SINGLE SQLite ACID transaction.
   */
  Future<void> executeLocalTransaction({
    required String tenantId,
    required String deviceId,
    required String domain,
    required String entityType,
    required String entityId,
    required String opType,
    required Map<String, dynamic> payload,
    required String clientMutationId,
    required int baseRevision,
    int priority = 1,
    required Future<void> Function(Transaction txn) entityOperation,
  }) async {
    await db.transaction((txn) async {
      // 1. Perform Entity SQL Operation (INSERT / UPDATE / DELETE)
      await entityOperation(txn);

      // 2. Insert Outbox Mutation
      final mutation = LocalMutation(
        clientMutationId: clientMutationId,
        tenantId: tenantId,
        deviceId: deviceId,
        domain: domain,
        entityType: entityType,
        entityId: entityId,
        opType: opType,
        payload: jsonEncode(payload),
        clientTimestamp: DateTime.now().millisecondsSinceEpoch,
        baseRevision: baseRevision,
        priority: priority,
        status: 'PENDING',
      );
      await outboxDao.insert(mutation, txn: txn);

      // 3. Update Sync Metadata
      await txn.insert(
        SyncV2Schema.tableMetadata,
        {
          'entity_type': entityType,
          'entity_id': entityId,
          'domain': domain,
          'local_version': 1,
          'sync_status': 'PENDING_PUSH',
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }
}
