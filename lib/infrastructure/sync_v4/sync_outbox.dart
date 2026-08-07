import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:serenutos/infrastructure/database/database_executor.dart';
import 'package:sqflite/sqflite.dart';

/// The only write-ahead journal used by Sync v4. Call inside the same SQLite
/// transaction as the domain write; a committed entity can never lack an event.
class SyncOutboxV4 {
  static const _uuid = Uuid();
  static final Map<int, Future<void>> _schemaReady = {};

  static Future<void> enqueue(
    Object db, {
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    final executor = _asExecutor(db);
    await _ensureSchema(executor);
    final cursorRow = await executor.query('sync_cursor_v4',
        columns: const ['cursor'],
        where: 'key = ?',
        whereArgs: const ['global'],
        limit: 1);
    final baseRevision =
        cursorRow.isEmpty ? 0 : (cursorRow.first['cursor'] as num).toInt();
    final pendingForEntity = await executor.query(
      'sync_outbox_v4',
      columns: const ['id'],
      where: "entity_type = ? AND entity_id = ? AND state = 'PENDING'",
      whereArgs: [entityType, entityId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (pendingForEntity.isNotEmpty) {
      await executor.update(
        'sync_outbox_v4',
        {
          'operation': operation,
          'payload': jsonEncode(payload),
          'attempts': 0,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [pendingForEntity.first['id']],
      );
      return;
    }
    await executor.insert('sync_outbox_v4', {
      'mutation_id': _uuid.v4(),
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation,
      'payload': jsonEncode(payload),
      'base_revision': baseRevision,
      'state': 'PENDING',
      'attempts': 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static DbExecutor _asExecutor(Object db) {
    if (db is DbExecutor) return db;
    if (db is DatabaseExecutor) return _SqfliteExecutor(db);
    throw ArgumentError.value(db, 'db', 'Unsupported database executor');
  }

  static Future<void> _ensureSchema(DbExecutor db) {
    // Test harnesses and recovered databases can bypass the normal migration
    // chain. The one-time per-executor guard prevents DDL from serializing
    // every POS mutation during a large offline batch.
    return _schemaReady.putIfAbsent(db.hashCode, () async {
      await db.execute('''CREATE TABLE IF NOT EXISTS sync_outbox_v4 (
      id INTEGER PRIMARY KEY AUTOINCREMENT, mutation_id TEXT NOT NULL UNIQUE,
      entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, operation TEXT NOT NULL,
      payload TEXT NOT NULL, base_revision INTEGER NOT NULL DEFAULT 0,
      state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL)''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sync_outbox_v4_state ON sync_outbox_v4(state, id)');
      await db.execute(
          'CREATE TABLE IF NOT EXISTS sync_cursor_v4 (key TEXT PRIMARY KEY, cursor INTEGER NOT NULL DEFAULT 0)');
      try {
        await db.execute(
            'ALTER TABLE sync_outbox_v4 ADD COLUMN base_revision INTEGER NOT NULL DEFAULT 0');
      } catch (_) {
        // Existing databases already migrated; the column is intentionally idempotent.
      }
    });
  }
}

final class _SqfliteExecutor implements DbExecutor {
  const _SqfliteExecutor(this._delegate);

  final DatabaseExecutor _delegate;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SqfliteExecutor &&
          runtimeType == other.runtimeType &&
          _delegate == other._delegate;

  @override
  int get hashCode => _delegate.hashCode;

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _delegate.delete(table, where: where, whereArgs: whereArgs);
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      _delegate.execute(sql, arguments);
  @override
  Future<int> insert(String table, Map<String, Object?> values,
          {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) =>
      _delegate.insert(table, values,
          nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);
  @override
  Future<List<Map<String, Object?>>> query(String table,
          {bool? distinct,
          List<String>? columns,
          String? where,
          List<Object?>? whereArgs,
          String? groupBy,
          String? having,
          String? orderBy,
          int? limit,
          int? offset}) =>
      _delegate.query(table,
          distinct: distinct,
          columns: columns,
          where: where,
          whereArgs: whereArgs,
          groupBy: groupBy,
          having: having,
          orderBy: orderBy,
          limit: limit,
          offset: offset);
  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
      _delegate.rawDelete(sql, arguments);
  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) =>
      _delegate.rawInsert(sql, arguments);
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
          [List<Object?>? arguments]) =>
      _delegate.rawQuery(sql, arguments);
  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      _delegate.rawUpdate(sql, arguments);
  @override
  Future<int> update(String table, Map<String, Object?> values,
          {String? where,
          List<Object?>? whereArgs,
          ConflictAlgorithm? conflictAlgorithm}) =>
      _delegate.update(table, values,
          where: where,
          whereArgs: whereArgs,
          conflictAlgorithm: conflictAlgorithm);
}
