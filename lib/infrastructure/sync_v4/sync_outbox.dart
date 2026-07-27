import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:serenutos/infrastructure/database/database_executor.dart';

/// The only write-ahead journal used by Sync v4. Call inside the same SQLite
/// transaction as the domain write; a committed entity can never lack an event.
class SyncOutboxV4 {
  static const _uuid = Uuid();
  static final Map<int, Future<void>> _schemaReady = {};

  static Future<void> enqueue(
    DbExecutor db, {
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    await _ensureSchema(db);
    await db.insert('sync_outbox_v4', {
      'mutation_id': _uuid.v4(),
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation,
      'payload': jsonEncode(payload),
      'state': 'PENDING',
      'attempts': 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<void> _ensureSchema(DbExecutor db) {
    // Test harnesses and recovered databases can bypass the normal migration
    // chain. The one-time per-executor guard prevents DDL from serializing
    // every POS mutation during a large offline batch.
    return _schemaReady.putIfAbsent(db.hashCode, () async {
      await db.execute('''CREATE TABLE IF NOT EXISTS sync_outbox_v4 (
      id INTEGER PRIMARY KEY AUTOINCREMENT, mutation_id TEXT NOT NULL UNIQUE,
      entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, operation TEXT NOT NULL,
      payload TEXT NOT NULL, state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL)''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sync_outbox_v4_state ON sync_outbox_v4(state, id)');
    });
  }
}
