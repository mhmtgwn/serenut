// lib/infrastructure/services/persistent_print_queue.dart
// Serenut POS — Crash-safe Persistent Print Queue (SQLite-backed)
// Survives app kill, power loss, and device restarts
// Created: 12 Jul 2026 (Migrated to SQLite)

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/services/financial_integrity_service.dart';
import 'package:sqflite/sqflite.dart';

// ── Print Job Status ──────────────────────────────────────────────────────────

enum PrintJobStatus { pending, printing, success, failed, abandoned }

// ── Persisted Print Job ───────────────────────────────────────────────────────

class PersistedPrintJob {
  final String id;
  final String title;
  final String receiptJson; // Serialized receipt data
  final DateTime createdAt;
  final int retryCount;
  final PrintJobStatus status;
  final String? lastError;

  const PersistedPrintJob({
    required this.id,
    required this.title,
    required this.receiptJson,
    required this.createdAt,
    this.retryCount = 0,
    this.status = PrintJobStatus.pending,
    this.lastError,
  });

  PersistedPrintJob copyWith({
    int? retryCount,
    PrintJobStatus? status,
    String? lastError,
  }) {
    return PersistedPrintJob(
      id: id,
      title: title,
      receiptJson: receiptJson,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      status: status ?? this.status,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'receipt_json': receiptJson,
        'created_at': createdAt.toIso8601String(),
        'retry_count': retryCount,
        'status': status.name,
        'last_error': lastError,
      };

  factory PersistedPrintJob.fromMap(Map<String, dynamic> map) {
    return PersistedPrintJob(
      id: map['id'] as String,
      title: (map['title'] as String?) ?? 'Fis',
      receiptJson: (map['receipt_json'] ?? map['receiptJson']) as String,
      createdAt:
          DateTime.parse((map['created_at'] ?? map['createdAt']) as String),
      retryCount: (map['retry_count'] ?? map['retryCount'] ?? 0) as int,
      status: PrintJobStatus.values.firstWhere(
        (s) => s.name == (map['status'] as String?),
        orElse: () => PrintJobStatus.pending,
      ),
      lastError: (map['last_error'] ?? map['lastError']) as String?,
    );
  }
}

// ── Persistent Print Queue ────────────────────────────────────────────────────

/// Crash-safe print queue backed by SQLite database.
class PersistentPrintQueue {
  static const int _maxRetries = 5;
  static const int _maxJobs = 200;
  static int _idCounter =
      0; // Monotonic counter — guarantees unique IDs in tight loops
  static final _lock = AsyncLock();

  final String? testKey;
  final String? _testTableName;

  PersistentPrintQueue({this.testKey})
      : _testTableName = testKey != null ? 'print_queue_$testKey' : null;

  String get _tableName => _testTableName ?? 'print_queue';

  Future<Database> _getDb() => DatabaseManager().getDatabase();

  /// Helper to ensure custom test tables exist (mostly for tests using unique keys)
  Future<void> _ensureTable(Database db) async {
    if (_testTableName != null) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableName (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          receipt_json TEXT NOT NULL,
          created_at TEXT NOT NULL,
          retry_count INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL,
          last_error TEXT
        )
      ''');
    }
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Add a new print job to the persistent queue.
  Future<PersistedPrintJob> enqueue({
    required String title,
    required String receiptJson,
  }) {
    return _lock.run(() async {
      final job = PersistedPrintJob(
        id: '${DateTime.now().microsecondsSinceEpoch}_${++_idCounter}',
        title: title,
        receiptJson: receiptJson,
        createdAt: DateTime.now(),
      );

      final db = await _getDb();
      await _ensureTable(db);

      await db.insert(_tableName, {
        'id': job.id,
        'title': job.title,
        'receipt_json': job.receiptJson,
        'created_at': job.createdAt.toIso8601String(),
        'retry_count': job.retryCount,
        'status': job.status.name,
        'last_error': job.lastError,
      });

      // Prune: keep newest _maxJobs
      final count = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM $_tableName')) ??
          0;

      if (count > _maxJobs) {
        final deleteCount = count - _maxJobs;
        await db.execute('''
          DELETE FROM $_tableName WHERE id IN (
            SELECT id FROM $_tableName ORDER BY created_at ASC LIMIT $deleteCount
          )
        ''');
      }

      return job;
    });
  }

  /// Load all pending jobs (status = pending, retryCount < maxRetries).
  Future<List<PersistedPrintJob>> loadPending() async {
    final db = await _getDb();
    await _ensureTable(db);
    final rows = await db.query(
      _tableName,
      where: 'status = ? AND retry_count < ?',
      whereArgs: [PrintJobStatus.pending.name, _maxRetries],
      orderBy: 'created_at ASC',
    );
    return rows.map((r) => PersistedPrintJob.fromMap(r)).toList();
  }

  /// Load all jobs for display (full history).
  Future<List<PersistedPrintJob>> loadAll() async {
    final db = await _getDb();
    await _ensureTable(db);
    final rows = await db.query(_tableName, orderBy: 'created_at ASC');
    return rows.map((r) => PersistedPrintJob.fromMap(r)).toList();
  }

  /// Mark a job as currently printing (prevents duplicate processing).
  Future<void> markPrinting(String id) async {
    final db = await _getDb();
    await _ensureTable(db);
    await db.update(
      _tableName,
      {'status': PrintJobStatus.printing.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark a job as successfully printed.
  Future<void> markDone(String id) async {
    final db = await _getDb();
    await _ensureTable(db);
    await db.update(
      _tableName,
      {'status': PrintJobStatus.success.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark a job as failed and increment retry count.
  /// If retryCount >= maxRetries, marks as abandoned.
  Future<void> markFailed(String id, {String? error}) async {
    final db = await _getDb();
    await _ensureTable(db);

    final rows = await db.query(
      _tableName,
      columns: ['retry_count'],
      where: 'id = ?',
      whereArgs: [id],
    );

    if (rows.isNotEmpty) {
      final currentRetryCount = rows.first['retry_count'] as int;
      final newRetryCount = currentRetryCount + 1;
      final newStatus = newRetryCount >= _maxRetries
          ? PrintJobStatus.abandoned.name
          : PrintJobStatus.pending.name;

      await db.update(
        _tableName,
        {
          'retry_count': newRetryCount,
          'status': newStatus,
          'last_error': error,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// Reset a printing job back to pending (e.g., after crash mid-print).
  Future<void> resetStuckJobs() async {
    final db = await _getDb();
    await _ensureTable(db);
    await db.update(
      _tableName,
      {'status': PrintJobStatus.pending.name},
      where: 'status = ?',
      whereArgs: [PrintJobStatus.printing.name],
    );
  }

  /// Reset a specific job to pending so it can be retried.
  Future<void> resetJob(String id) async {
    final db = await _getDb();
    await _ensureTable(db);
    await db.update(
      _tableName,
      {
        'status': PrintJobStatus.pending.name,
        'retry_count': 0,
        'last_error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get count of jobs waiting to print.
  Future<int> pendingCount() async {
    final db = await _getDb();
    await _ensureTable(db);
    final result = await db.rawQuery(
      'SELECT COUNT(*) FROM $_tableName WHERE status = ? AND retry_count < ?',
      [PrintJobStatus.pending.name, _maxRetries],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Clear ALL jobs (including pending) — for test isolation and factory reset.
  Future<void> clearAll() async {
    final db = await _getDb();
    await _ensureTable(db);
    await db.delete(_tableName);
  }

  /// Clear all completed/abandoned jobs (housekeeping).
  Future<void> clearCompleted() async {
    final db = await _getDb();
    await _ensureTable(db);
    await db.delete(
      _tableName,
      where: 'status = ? OR status = ?',
      whereArgs: [PrintJobStatus.success.name, PrintJobStatus.abandoned.name],
    );
  }
}
