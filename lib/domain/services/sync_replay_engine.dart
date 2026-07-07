// lib/domain/services/sync_replay_engine.dart
// Incident Replay Engine — Reconstructs and classifies root cause of sync incidents.

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/services/sync_trace_service.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

/// Categories of roots causes classified by the heuristic analyzer.
enum RootCauseCategory {
  networkTimeout,       // Simulated / real SocketException, timeouts
  duplicatePush,        // 409 Conflict duplicate uploads
  databaseLock,         // SQLite lock or contention issues
  dataCorruption,       // Balance drift alarms
  licenseFailure,       // Bulut senkronizasyon lisanslama sorunları
  unhandledException,   // Any other critical/error trace
  unknown,
}

extension RootCauseCategoryLabel on RootCauseCategory {
  String get label {
    switch (this) {
      case RootCauseCategory.networkTimeout:     return 'Network Timeout/Connection Drop';
      case RootCauseCategory.duplicatePush:      return 'Duplicate Push (Idempotency Key Conflict)';
      case RootCauseCategory.databaseLock:        return 'Database Lock/Contention';
      case RootCauseCategory.dataCorruption:      return 'Silent Data Corruption';
      case RootCauseCategory.licenseFailure:      return 'License Failure';
      case RootCauseCategory.unhandledException:  return 'Unhandled System Exception';
      case RootCauseCategory.unknown:             return 'Unknown Root Cause';
    }
  }

  String get description {
    switch (this) {
      case RootCauseCategory.networkTimeout:
        return 'The connection was lost or timed out during data transfer. POS queue will auto-retry.';
      case RootCauseCategory.duplicatePush:
        return 'Server returned 409 Conflict. Handled gracefully using idempotency keys without data loss.';
      case RootCauseCategory.databaseLock:
        return 'Local SQLite file was locked by another process or concurrent write. Transaction rolled back safely.';
      case RootCauseCategory.dataCorruption:
        return 'Critical balance mismatch detected between customer balance and transaction ledger. Auto-corrected.';
      case RootCauseCategory.licenseFailure:
        return 'Cloud synchronization feature is disabled or license token is invalid.';
      case RootCauseCategory.unhandledException:
        return 'An unexpected runtime error occurred. Check stack trace details for resolution.';
      case RootCauseCategory.unknown:
        return 'Insufficient trace telemetry to classify root cause. Check raw logs.';
    }
  }
}

/// A unified chronological step in the execution trace.
class ReplayStep {
  final DateTime timestamp;
  final String type; // 'log' | 'transition'
  final String title;
  final String description;
  final Map<String, dynamic> metadata;

  const ReplayStep({
    required this.timestamp,
    required this.type,
    required this.title,
    required this.description,
    required this.metadata,
  });
}

/// The final diagnostic report for an incident.
class ReplayReport {
  final String correlationId;
  final RootCauseCategory rootCause;
  final String diagnosis;
  final List<ReplayStep> steps;

  const ReplayReport({
    required this.correlationId,
    required this.rootCause,
    required this.diagnosis,
    required this.steps,
  });
}

/// Motore that reconstructs the unified timeline and classifies the root cause.
class SyncReplayEngine {
  final SyncTraceService _tracer;

  SyncReplayEngine({Database? db, SyncTraceService? tracer})
      : _tracer = tracer ?? SyncTraceService(db: db);

  /// Generates a comprehensive [ReplayReport] for the given [correlationId].
  Future<ReplayReport> generateReport(String correlationId) async {
    final steps = <ReplayStep>[];

    // 1. Gather Telemetry Log events
    final logEvents = await _tracer.getTrace(correlationId);
    for (final log in logEvents) {
      steps.add(ReplayStep(
        timestamp: log.timestamp,
        type: 'log',
        title: '${log.level.emoji} ${log.event}',
        description: log.metadata['error_message']?.toString() ??
            log.metadata['context']?.toString() ??
            'Telemetry event logged',
        metadata: log.metadata,
      ));
    }

    // 2. Gather State Machine Transitions (correlationId is mapped directly to sessionId)
    final transitions = await _tracer.getSessionTransitions(correlationId);
    for (final row in transitions) {
      final occurredAt = DateTime.tryParse(row['occurred_at'] as String? ?? '') ?? DateTime.now();
      final meta = row['metadata'] != null
          ? jsonDecode(row['metadata'] as String) as Map<String, dynamic>
          : <String, dynamic>{};

      steps.add(ReplayStep(
        timestamp: occurredAt,
        type: 'transition',
        title: '🔁 State Transition',
        description: '${row['from_state']} ➔ ${row['to_state']} (${row['trigger_event']})',
        metadata: {
          ...meta,
          if (row['sale_id'] != null) 'sale_id': row['sale_id'],
          if (row['device_id'] != null) 'device_id': row['device_id'],
        },
      ));
    }

    // 3. Sort chronologically
    steps.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // 4. Heuristic Analyzer for root cause classification
    var category = RootCauseCategory.unknown;
    var diagnosis = 'Trace sequence is healthy or contains insufficient error details.';

    // Check for specific markers in the unified step list
    final hasDrift = steps.any((s) =>
        s.title.contains('silent_data_corruption_alarm') ||
        s.metadata.containsKey('drift'));

    final hasNetworkError = steps.any((s) =>
        s.description.contains('SocketException') ||
        s.description.contains('TimeoutException') ||
        s.description.contains('NetworkCutFault'));

    final hasDuplicate = steps.any((s) =>
        s.description.contains('409') ||
        s.description.contains('pushConflict') ||
        s.description.contains('Duplicate push conflict'));

    final hasDbLock = steps.any((s) =>
        s.description.contains('DatabaseLockedException') ||
        s.description.toLowerCase().contains('database is locked'));

    final hasLicenseFail = steps.any((s) =>
        s.title.contains('sync_license_invalid') ||
        s.description.contains('lisans bulunamadı'));

    final hasCriticalOrError = steps.any((s) =>
        s.title.contains('🚨') ||
        s.title.contains('❌') ||
        s.title.contains('unhandled_exception'));

    if (hasDrift) {
      category = RootCauseCategory.dataCorruption;
      diagnosis = 'Automatic balance drift check failed due to a discrepancy in customer balance. Invariant corrected.';
    } else if (hasNetworkError) {
      category = RootCauseCategory.networkTimeout;
      diagnosis = 'Connection was lost or timed out mid-flight. POS sync engine remains safe and scheduled for automatic retry.';
    } else if (hasDuplicate) {
      category = RootCauseCategory.duplicatePush;
      diagnosis = 'Server returned a 409 Conflict. Handled gracefully by the system idempotency logic. Zero action required.';
    } else if (hasDbLock) {
      category = RootCauseCategory.databaseLock;
      diagnosis = 'Concurrent write or read operations locked the local SQLite database file. Transaction aborted safely.';
    } else if (hasLicenseFail) {
      category = RootCauseCategory.licenseFailure;
      diagnosis = 'Licensing verification failed. Features such as cloud synchronization are locked.';
    } else if (hasCriticalOrError) {
      category = RootCauseCategory.unhandledException;
      diagnosis = 'An unhandled exception was captured during sync. Please inspect the stack trace details.';
    }

    return ReplayReport(
      correlationId: correlationId,
      rootCause: category,
      diagnosis: diagnosis,
      steps: steps,
    );
  }
}
