// lib/infrastructure/repositories/sms_log_repository.dart
// Serenut POS — SMS Log Repository
// Persists SMS send attempts to SQLite sms_logs table.
// Created: 01 Jul 2026

import 'package:flutter/foundation.dart';
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
      debugPrint('⚠️ SmsLogRepository.insertLog error: $e');
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
      debugPrint('⚠️ SmsLogRepository.updateStatus error: $e');
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
      debugPrint('⚠️ SmsLogRepository.incrementRetry error: $e');
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
      debugPrint('⚠️ SmsLogRepository.getRecentLogs error: $e');
      return [];
    }
  }

  /// Fetch pending entries with retry_count < [maxRetries].
  Future<List<SmsLogEntry>> getPendingLogs({int maxRetries = 3}) async {
    if (kIsWeb) {
      return _inMemoryLogs
          .where((e) =>
              e.status == SmsLogStatus.pending && e.retryCount < maxRetries)
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
      debugPrint('⚠️ SmsLogRepository.getPendingLogs error: $e');
      return [];
    }
  }

  /// Count pending entries.
  Future<int> getPendingCount() async {
    if (kIsWeb) {
      return _inMemoryLogs
          .where((e) => e.status == SmsLogStatus.pending)
          .length;
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

  /// Fetch all active campaign logs (status: pending or sending) for bulk_debt_reminder.
  Future<List<SmsLogEntry>> getActiveCampaignLogs() async {
    if (kIsWeb) {
      return _inMemoryLogs
          .where((e) =>
              (e.status == SmsLogStatus.pending ||
                  e.status == SmsLogStatus.sending) &&
              e.eventType == 'bulk_debt_reminder')
          .toList();
    }
    try {
      final database = await _db.getDatabase();
      final rows = await database.query(
        'sms_logs',
        where:
            "(status = 'pending' OR status = 'sending') AND event_type = 'bulk_debt_reminder'",
        orderBy: 'created_at ASC',
      );
      return rows.map(SmsLogEntry.fromMap).toList();
    } catch (e) {
      debugPrint('⚠️ SmsLogRepository.getActiveCampaignLogs error: $e');
      return [];
    }
  }

  /// Mark all active campaign logs as cancelled.
  Future<void> cancelActiveCampaignLogs() async {
    if (kIsWeb) {
      for (var i = 0; i < _inMemoryLogs.length; i++) {
        if ((_inMemoryLogs[i].status == SmsLogStatus.pending ||
                _inMemoryLogs[i].status == SmsLogStatus.sending) &&
            _inMemoryLogs[i].eventType == 'bulk_debt_reminder') {
          _inMemoryLogs[i] =
              _inMemoryLogs[i].copyWith(status: SmsLogStatus.cancelled);
        }
      }
      return;
    }
    try {
      final database = await _db.getDatabase();
      await database.update(
        'sms_logs',
        {'status': 'cancelled'},
        where:
            "(status = 'pending' OR status = 'sending') AND event_type = 'bulk_debt_reminder'",
      );
    } catch (e) {
      debugPrint('⚠️ SmsLogRepository.cancelActiveCampaignLogs error: $e');
    }
  }

  /// Delete log entries older than [days] days.
  Future<void> pruneOldLogs({int days = 90}) async {
    if (kIsWeb) {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      _inMemoryLogs.removeWhere((e) =>
          e.createdAt.isBefore(cutoff) && e.status != SmsLogStatus.pending);
      return;
    }
    try {
      final database = await _db.getDatabase();
      final cutoff =
          DateTime.now().subtract(Duration(days: days)).toIso8601String();
      await database.delete(
        'sms_logs',
        where: "created_at < ? AND status != 'pending'",
        whereArgs: [cutoff],
      );
    } catch (e) {
      debugPrint('⚠️ SmsLogRepository.pruneOldLogs error: $e');
    }
  }

  /// Reset stuck SMS logs (status: sending) to interrupted status.
  Future<void> resetStuckJobs() async {
    if (kIsWeb) {
      for (var i = 0; i < _inMemoryLogs.length; i++) {
        if (_inMemoryLogs[i].status == SmsLogStatus.sending) {
          _inMemoryLogs[i] =
              _inMemoryLogs[i].copyWith(status: SmsLogStatus.interrupted);
        }
      }
      return;
    }
    try {
      final database = await _db.getDatabase();
      await database.update(
        'sms_logs',
        {'status': SmsLogStatus.interrupted.value},
        where: 'status = ?',
        whereArgs: ['sending'],
      );
    } catch (e) {
      debugPrint('⚠️ SmsLogRepository.resetStuckJobs error: $e');
    }
  }

  /// Fetch entries with status 'interrupted'.
  Future<List<SmsLogEntry>> getUnknownLogs() async {
    if (kIsWeb) {
      return _inMemoryLogs
          .where((e) => e.status == SmsLogStatus.interrupted)
          .toList();
    }
    try {
      final database = await _db.getDatabase();
      final rows = await database.query(
        'sms_logs',
        where: 'status = ?',
        whereArgs: [SmsLogStatus.interrupted.value],
        orderBy: 'created_at ASC',
      );
      return rows.map(SmsLogEntry.fromMap).toList();
    } catch (e) {
      debugPrint('⚠️ SmsLogRepository.getUnknownLogs error: $e');
      return [];
    }
  }
}
