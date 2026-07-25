import 'package:sqflite/sqflite.dart';
import 'sync_v2_schema.dart';

class LocalMutation {
  final int? id;
  final String clientMutationId;
  final String tenantId;
  final String deviceId;
  final String domain;
  final String entityType;
  final String entityId;
  final String opType;
  final String payload;
  final int clientTimestamp;
  final int baseRevision;
  final int priority;
  final String status;
  final int attempts;
  final String? lastError;

  LocalMutation({
    this.id,
    required this.clientMutationId,
    required this.tenantId,
    required this.deviceId,
    required this.domain,
    required this.entityType,
    required this.entityId,
    required this.opType,
    required this.payload,
    required this.clientTimestamp,
    required this.baseRevision,
    this.priority = 1,
    this.status = 'PENDING',
    this.attempts = 0,
    this.lastError,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'client_mutation_id': clientMutationId,
      'tenant_id': tenantId,
      'device_id': deviceId,
      'domain': domain,
      'entity_type': entityType,
      'entity_id': entityId,
      'op_type': opType,
      'payload': payload,
      'client_timestamp': clientTimestamp,
      'base_revision': baseRevision,
      'priority': priority,
      'status': status,
      'attempts': attempts,
      'last_error': lastError,
    };
  }

  factory LocalMutation.fromMap(Map<String, dynamic> map) {
    return LocalMutation(
      id: map['id'] as int?,
      clientMutationId: map['client_mutation_id'] as String,
      tenantId: map['tenant_id'] as String,
      deviceId: map['device_id'] as String,
      domain: map['domain'] as String,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String,
      opType: map['op_type'] as String,
      payload: map['payload'] as String,
      clientTimestamp: map['client_timestamp'] as int,
      baseRevision: map['base_revision'] as int,
      priority: map['priority'] as int? ?? 1,
      status: map['status'] as String? ?? 'PENDING',
      attempts: map['attempts'] as int? ?? 0,
      lastError: map['last_error'] as String?,
    );
  }
}

class OutboxDao {
  final Database db;

  OutboxDao(this.db);

  Future<int> insert(LocalMutation mutation, {Transaction? txn}) async {
    final executor = txn ?? db;
    return await executor.insert(
      SyncV2Schema.tableOutbox,
      mutation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<LocalMutation>> getPendingBatch(int limit) async {
    final maps = await db.query(
      SyncV2Schema.tableOutbox,
      where: 'status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'priority ASC, id ASC',
      limit: limit,
    );
    return maps.map((m) => LocalMutation.fromMap(m)).toList();
  }

  Future<void> markSending(List<int> ids) async {
    if (ids.isEmpty) return;
    final inClause = ids.join(',');
    await db.rawUpdate(
      'UPDATE ${SyncV2Schema.tableOutbox} SET status = ? WHERE id IN ($inClause)',
      ['SENDING'],
    );
  }

  Future<void> deleteByIds(List<int> ids, {Transaction? txn}) async {
    if (ids.isEmpty) return;
    final executor = txn ?? db;
    final inClause = ids.join(',');
    await executor.rawDelete(
      'DELETE FROM ${SyncV2Schema.tableOutbox} WHERE id IN ($inClause)',
    );
  }

  Future<void> markFailed(int id, String error) async {
    await db.rawUpdate(
      'UPDATE ${SyncV2Schema.tableOutbox} SET status = ?, attempts = attempts + 1, last_error = ? WHERE id = ?',
      ['PENDING', error, id],
    );
  }

  Future<int> getPendingCount() async {
    final res = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${SyncV2Schema.tableOutbox} WHERE status = ?',
      ['PENDING'],
    );
    return Sqflite.firstIntValue(res) ?? 0;
  }
}
