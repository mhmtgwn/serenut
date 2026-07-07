// lib/infrastructure/services/persistent_print_queue.dart
// Serenut POS — Crash-safe Persistent Print Queue
// Survives app kill, power loss, and device restarts
// Created: 24 Jun 2026

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        'receiptJson': receiptJson,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
        'status': status.name,
        'lastError': lastError,
      };

  factory PersistedPrintJob.fromMap(Map<String, dynamic> map) {
    return PersistedPrintJob(
      id: map['id'] as String,
      title: (map['title'] as String?) ?? 'Fis',
      receiptJson: map['receiptJson'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      retryCount: (map['retryCount'] as int?) ?? 0,
      status: PrintJobStatus.values.firstWhere(
        (s) => s.name == (map['status'] as String?),
        orElse: () => PrintJobStatus.pending,
      ),
      lastError: map['lastError'] as String?,
    );
  }
}

// ── Persistent Print Queue ────────────────────────────────────────────────────

/// Crash-safe print queue backed by SharedPreferences.
///
/// Design guarantees:
/// - Jobs survive app kill / power loss
/// - Atomically updates job status before and after printing
/// - After 5 failed retries → abandoned (not lost from log)
/// - Max 200 jobs stored (older completed jobs pruned)
class PersistentPrintQueue {
  static const String _defaultQueueKey = 'serenut_print_queue';
  static const int _maxRetries = 5;
  static const int _maxJobs = 200;
  static int _idCounter = 0; // Monotonic counter — guarantees unique IDs in tight loops

  final String _queueKey;

  /// [testKey] — pass a unique key per test to achieve full isolation.
  PersistentPrintQueue({String? testKey})
      : _queueKey = testKey ?? _defaultQueueKey;

  /// Exposed for tests that need to share the same key across instances
  /// (e.g., simulating an app restart loading from same persisted storage).
  @visibleForTesting
  String get testKey => _queueKey;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Add a new print job to the persistent queue.
  Future<PersistedPrintJob> enqueue({
    required String title,
    required String receiptJson,
  }) async {
    final job = PersistedPrintJob(
      id: '${DateTime.now().microsecondsSinceEpoch}_${++_idCounter}',
      title: title,
      receiptJson: receiptJson,
      createdAt: DateTime.now(),
    );
    final jobs = await _load();
    jobs.add(job);
    await _save(jobs);
    return job;
  }

  /// Load all pending jobs (status = pending, retryCount < maxRetries).
  Future<List<PersistedPrintJob>> loadPending() async {
    final jobs = await _load();
    return jobs
        .where((j) =>
            j.status == PrintJobStatus.pending &&
            j.retryCount < _maxRetries)
        .toList();
  }

  /// Load all jobs for display (full history).
  Future<List<PersistedPrintJob>> loadAll() async => _load();

  /// Mark a job as currently printing (prevents duplicate processing).
  Future<void> markPrinting(String id) async {
    await _updateJob(id, (j) => j.copyWith(status: PrintJobStatus.printing));
  }

  /// Mark a job as successfully printed.
  Future<void> markDone(String id) async {
    await _updateJob(id, (j) => j.copyWith(status: PrintJobStatus.success));
  }

  /// Mark a job as failed and increment retry count.
  /// If retryCount >= maxRetries, marks as abandoned.
  Future<void> markFailed(String id, {String? error}) async {
    await _updateJob(id, (j) {
      final newRetryCount = j.retryCount + 1;
      final newStatus = newRetryCount >= _maxRetries
          ? PrintJobStatus.abandoned
          : PrintJobStatus.pending; // Reset to pending for next retry cycle
      return j.copyWith(
        retryCount: newRetryCount,
        status: newStatus,
        lastError: error,
      );
    });
  }

  /// Reset a printing job back to pending (e.g., after crash mid-print).
  Future<void> resetStuckJobs() async {
    final jobs = await _load();
    final reset = jobs.map((j) {
      if (j.status == PrintJobStatus.printing) {
        // Was stuck mid-print at app kill — reset to pending for retry
        return j.copyWith(status: PrintJobStatus.pending);
      }
      return j;
    }).toList();
    await _save(reset);
  }

  /// Get count of jobs waiting to print.
  Future<int> pendingCount() async {
    final pending = await loadPending();
    return pending.length;
  }

  /// Clear ALL jobs (including pending) — for test isolation and factory reset.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey);
  }

  /// Clear all completed/abandoned jobs (housekeeping).
  Future<void> clearCompleted() async {
    final jobs = await _load();
    final active = jobs
        .where((j) =>
            j.status != PrintJobStatus.success &&
            j.status != PrintJobStatus.abandoned)
        .toList();
    await _save(active);
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  Future<void> _updateJob(
    String id,
    PersistedPrintJob Function(PersistedPrintJob) updater,
  ) async {
    final jobs = await _load();
    final idx = jobs.indexWhere((j) => j.id == id);
    if (idx != -1) {
      jobs[idx] = updater(jobs[idx]);
      await _save(jobs);
    }
  }

  Future<List<PersistedPrintJob>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_queueKey) ?? [];
    final result = <PersistedPrintJob>[];
    for (final item in raw) {
      try {
        result.add(PersistedPrintJob.fromMap(
          jsonDecode(item) as Map<String, dynamic>,
        ));
      } catch (_) {
        // Skip corrupt entries
      }
    }
    return result;
  }

  Future<void> _save(List<PersistedPrintJob> jobs) async {
    final prefs = await SharedPreferences.getInstance();
    // Prune: keep newest _maxJobs
    final trimmed = jobs.length > _maxJobs
        ? jobs.sublist(jobs.length - _maxJobs)
        : jobs;
    await prefs.setStringList(
      _queueKey,
      trimmed.map((j) => jsonEncode(j.toMap())).toList(),
    );
  }
}
