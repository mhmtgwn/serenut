// lib/infrastructure/repositories/sqlite_audit_repository.dart
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/models/audit_event.dart';
import 'package:serenutos/domain/repositories/audit_repository.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class SqliteAuditRepository implements IAuditRepository {
  final DatabaseManager _dbManager;

  SqliteAuditRepository(this._dbManager);

  @override
  Future<AuditEvent> logEvent(AuditEvent event) async {
    final db = await _dbManager.getDatabase();
    return db.transaction((txn) async {
      final previous = await txn.query(
        'audit_events',
        columns: ['record_hash'],
        orderBy: 'timestamp DESC, id DESC',
        limit: 1,
      );
      final previousHash =
          previous.isEmpty ? null : previous.first['record_hash']?.toString();
      final payload = <String, dynamic>{
        'id': event.id,
        'event_type': event.eventType,
        'entity_type': event.entityType,
        'entity_id': event.entityId,
        'user_id': event.userId,
        'user_name': event.userName,
        'old_value': event.oldValue,
        'new_value': event.newValue,
        'timestamp': event.timestamp.toUtc().toIso8601String(),
        'device_id': event.deviceId,
        'notes': event.notes,
        'previous_hash': previousHash,
      };
      final recordHash =
          sha256.convert(utf8.encode(jsonEncode(payload))).toString();
      final chained = event.copyWithHashes(
        previousHash: previousHash,
        recordHash: recordHash,
      );
      await txn.insert(
        'audit_events',
        chained.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return chained;
    });
  }

  @override
  Future<List<AuditEvent>> getEvents({
    String? eventType,
    String? entityType,
    String? userId,
    DateTime? fromDate,
    DateTime? toDate,
    int? limit,
    int? offset,
  }) async {
    final db = await _dbManager.getDatabase();
    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (eventType != null && eventType.isNotEmpty) {
      whereClauses.add('event_type = ?');
      whereArgs.add(eventType);
    }

    if (entityType != null && entityType.isNotEmpty) {
      whereClauses.add('entity_type = ?');
      whereArgs.add(entityType);
    }

    if (userId != null && userId.isNotEmpty) {
      whereClauses.add('user_id = ?');
      whereArgs.add(userId);
    }

    if (fromDate != null) {
      whereClauses.add('timestamp >= ?');
      whereArgs.add(fromDate.toIso8601String());
    }

    if (toDate != null) {
      whereClauses.add('timestamp <= ?');
      whereArgs.add(toDate.toIso8601String());
    }

    final whereString =
        whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final results = await db.query(
      'audit_events',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );

    return results.map((r) => AuditEvent.fromMap(r)).toList();
  }

  @override
  Future<List<AuditEvent>> search(String query) async {
    final db = await _dbManager.getDatabase();
    final likeQuery = '%$query%';

    final results = await db.query(
      'audit_events',
      where:
          'user_name LIKE ? OR notes LIKE ? OR entity_id LIKE ? OR event_type LIKE ? OR entity_type LIKE ?',
      whereArgs: [likeQuery, likeQuery, likeQuery, likeQuery, likeQuery],
      orderBy: 'timestamp DESC',
    );

    return results.map((r) => AuditEvent.fromMap(r)).toList();
  }
}
