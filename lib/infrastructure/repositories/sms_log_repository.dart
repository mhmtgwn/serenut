// lib/infrastructure/repositories/sms_log_repository.dart
// Serenut POS — SMS Log Repository
// Persists SMS send attempts to SQLite sms_logs table.
// Created: 01 Jul 2026

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:serenutos/domain/models/sms_log_entry.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';

class SmsLogRepository {
  final DatabaseManager _db;
  final List<SmsLogEntry> _inMemoryLogs = [];

  SmsLogRepository(this._db);

  // ── Write ──────────────────────────────────────────────────────────────────

  /// Insert a new SMS log entry (status: pending).
  Future<void> insertLog(SmsLogEntry entry) async {
    if (kIsWeb) {
      _inMemoryLogs.add(entry);
      return;
    }
    try {
      final database = await _db.getDatabase();
      await database.insert('sms_logs', entry.toMap());
    } catch (e) {
      // Non-fatal: logging failures must not crash the app
      print('⚠️ SmsLogRepository.insertLog error: $e');
    }
  }

  /// Update the status of an existing log entry.
  Future<void> updateStatus(
    String id,
    SmsLogStatus status, {
    DateTime? sentAt,
    String? errorMessage,
  }) async {
    if (kIsWeb) {
      final index = _inMemoryLogs.indexWhere((e) => e.id == id);
      if (index != -1) {
        _inMemoryLogs[index] = _inMemoryLogs[index].copyWith(
          status: status,
          sentAt: sentAt,
          errorMessage: errorMessage,
        );
      }
      return;
    }
    try {
      final database = await _db.getDatabase();
      final updates = <String, dynamic>{
        'status': status.value,
        if (sentAt != null) 'sent_at': sentAt.toIso8601String(),
        if (errorMessage != null) 'error_message': errorMessage,
      };
      await database.update(
        'sms_logs',
        updates,
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      print('⚠️ SmsLogRepository.updateStatus error: $e');
    }
  }

  /// Increment retry count for a failed entry.
  Future<void> incrementRetry(String id) async {
    if (kIsWeb) {
      final index = _inMemoryLogs.indexWhere((e) => e.id == id);
      if (index != -1) {
        _inMemoryLogs[index] = _inMemoryLogs[index].copyWith(
          retryCount: _inMemoryLogs[index].retryCount + 1,
        );
      }
      return;
    }
    try {
      final database = await _db.getDatabase();
      await database.rawUpdate(
        'UPDATE sms_logs SET retry_count = retry_count + 1 WHERE id = ?',
        [id],
      );
    } catch (e) {
      print('⚠️ SmsLogRepository.incrementRetry error: $e');
    }
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  /// Fetch the most recent [limit] log entries (newest first).
  Future<List<SmsLogEntry>> getRecentLogs({int limit = 50}) async {
    if (kIsWeb) {
      final sorted = List<SmsLogEntry>.from(_inMemoryLogs)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sorted.take(limit).toList();
    }
    try {
      final database = await _db.getDatabase();
      final rows = await database.query(
        'sms_logs',
        orderBy: 'created_at DESC',
        limit: limit,
      );
      return rows.map(SmsLogEntry.fromMap).toList();
    } catch (e) {
      print('⚠️ SmsLogRepository.getRecentLogs error: $e');
      return [];
    }
  }

  /// Fetch pending entries with retry_count < [maxRetries].
  Future<List<SmsLogEntry>> getPendingLogs({int maxRetries = 3}) async {
    if (kIsWeb) {
      return _inMemoryLogs
          .where((e) => e.status == SmsLogStatus.pending && e.retryCount < maxRetries)
          .toList();
    }
    try {
      final database = await _db.getDatabase();
      final rows = await database.query(
        'sms_logs',
        where: 'status = ? AND retry_count < ?',
        whereArgs: ['pending', maxRetries],
        orderBy: 'created_at ASC',
      );
      return rows.map(SmsLogEntry.fromMap).toList();
    } catch (e) {
      print('⚠️ SmsLogRepository.getPendingLogs error: $e');
      return [];
    }
  }

  /// Count pending entries.
  Future<int> getPendingCount() async {
    if (kIsWeb) {
      return _inMemoryLogs.where((e) => e.status == SmsLogStatus.pending).length;
    }
    try {
      final database = await _db.getDatabase();
      final result = await database.rawQuery(
        "SELECT COUNT(*) as cnt FROM sms_logs WHERE status = 'pending'",
      );
      return (result.first['cnt'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Delete log entries older than [days] days.
  Future<void> pruneOldLogs({int days = 90}) async {
    if (kIsWeb) {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      _inMemoryLogs.removeWhere((e) => e.createdAt.isBefore(cutoff) && e.status != SmsLogStatus.pending);
      return;
    }
    try {
      final database = await _db.getDatabase();
      final cutoff = DateTime.now().subtract(Duration(days: days)).toIso8601String();
      await database.delete(
        'sms_logs',
        where: "created_at < ? AND status != 'pending'",
        whereArgs: [cutoff],
      );
    } catch (e) {
      print('⚠️ SmsLogRepository.pruneOldLogs error: $e');
    }
  }
}
