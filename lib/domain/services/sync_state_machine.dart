// lib/domain/services/sync_state_machine.dart
// Sync State Machine — Deterministic conflict model with SQLite audit trail.
//
// Every state transition is persisted to `sync_state_log` table so that:
//   - Post-incident replay is possible via correlationId / session_id
//   - Crash recovery can restore the last known state
//   - The SyncTraceService can reconstruct full sync event chains

import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

// ── States ────────────────────────────────────────────────────────────────────

/// All valid states in the sync pipeline.
enum SyncState {
  /// No sync in progress.
  idle,

  /// Actively pushing/pulling with the server.
  syncing,

  /// Server returned a conflict (409) or clock skew detected.
  conflictDetected,

  /// Applying server-authoritative merge policy.
  resolving,

  /// All pending sales successfully synced.
  synced,

  /// Max retries exceeded or unrecoverable error.
  failed,
}

extension SyncStateLabel on SyncState {
  String get label => name;
}

// ── Trigger events ────────────────────────────────────────────────────────────

/// Events that drive state transitions.
enum SyncTrigger {
  startSync,
  pushSuccess,
  pushConflict,     // 409 from server
  pushNetworkError, // SocketException / timeout
  mergeComplete,    // server-auth resolution applied
  maxRetriesExceeded,
  noSalesFound,
  pullComplete,
}

// ── Transition table ──────────────────────────────────────────────────────────

/// Legal state transitions:  [from][trigger] → to
/// Any unlisted combination is rejected with [InvalidSyncTransitionError].
const Map<SyncState, Map<SyncTrigger, SyncState>> _transitions = {
  SyncState.idle: {
    SyncTrigger.startSync:   SyncState.syncing,
    SyncTrigger.noSalesFound: SyncState.synced,
  },
  SyncState.syncing: {
    SyncTrigger.pushSuccess:       SyncState.syncing,   // more sales pending
    SyncTrigger.pullComplete:      SyncState.synced,    // all done
    SyncTrigger.pushConflict:      SyncState.conflictDetected,
    SyncTrigger.pushNetworkError:  SyncState.syncing,   // retry in-flight
    SyncTrigger.maxRetriesExceeded: SyncState.failed,
    SyncTrigger.noSalesFound:      SyncState.synced,
  },
  SyncState.conflictDetected: {
    SyncTrigger.startSync:   SyncState.resolving,
    SyncTrigger.maxRetriesExceeded: SyncState.failed,
  },
  SyncState.resolving: {
    SyncTrigger.mergeComplete:      SyncState.syncing,  // resume after merge
    SyncTrigger.maxRetriesExceeded: SyncState.failed,
  },
  SyncState.synced: {
    SyncTrigger.startSync: SyncState.syncing,           // next cycle
  },
  SyncState.failed: {
    SyncTrigger.startSync: SyncState.syncing,           // manual retry
  },
};

// ── Errors ────────────────────────────────────────────────────────────────────

class InvalidSyncTransitionError implements Exception {
  final SyncState from;
  final SyncTrigger trigger;
  InvalidSyncTransitionError(this.from, this.trigger);

  @override
  String toString() =>
      'InvalidSyncTransition: no rule for $from + ${trigger.name}';
}

// ── State Machine ─────────────────────────────────────────────────────────────

/// Deterministic sync state machine with SQLite-persisted audit trail.
///
/// Design principles:
///   1. All transitions are explicit — unlisted combos throw immediately.
///   2. Every transition is written to `sync_state_log` (crash-recoverable).
///   3. `sessionId` groups all transitions in one sync cycle for trace queries.
class SyncStateMachine {
  final Database? _db;

  SyncState _current = SyncState.idle;
  final String _sessionId;
  final String? _deviceId;

  SyncStateMachine({
    Database? db,
    String? deviceId,
    String? sessionId,
  })  : _db = db,
        _deviceId = deviceId,
        _sessionId = sessionId ?? const Uuid().v4();

  /// Current state.
  SyncState get currentState => _current;

  /// Session ID for this sync cycle (groups all transitions for trace queries).
  String get sessionId => _sessionId;

  /// Apply [trigger] and transition to the next state.
  ///
  /// Returns the new [SyncState].
  /// Throws [InvalidSyncTransitionError] for illegal transitions.
  Future<SyncState> transition(
    SyncTrigger trigger, {
    String? saleId,
    Map<String, dynamic>? metadata,
  }) async {
    final allowed = _transitions[_current];
    if (allowed == null || !allowed.containsKey(trigger)) {
      throw InvalidSyncTransitionError(_current, trigger);
    }

    final from = _current;
    final to = allowed[trigger]!;
    _current = to;

    // Persist the transition for post-incident replay
    if (_db != null) {
      await _db!.insert('sync_state_log', {
        'session_id':    _sessionId,
        'from_state':    from.label,
        'to_state':      to.label,
        'trigger_event': trigger.name,
        'sale_id':       saleId,
        'device_id':     _deviceId,
        'metadata':      metadata != null ? jsonEncode(metadata) : null,
        'occurred_at':   DateTime.now().toIso8601String(),
      });
    }

    return to;
  }

  /// Returns all transitions for [sessionId] in chronological order.
  /// Used by [SyncTraceService] for incident replay.
  Future<List<Map<String, dynamic>>> getSessionTransitions(
      [String? sessionId]) async {
    if (_db == null) return [];
    return _db!.query(
      'sync_state_log',
      where: 'session_id = ?',
      whereArgs: [sessionId ?? _sessionId],
      orderBy: 'occurred_at ASC',
    );
  }

  /// Restores the last known state from the DB after a crash.
  ///
  /// If no prior session found, stays at [SyncState.idle].
  Future<void> restoreFromCrash() async {
    if (_db == null) return;
    final rows = await _db!.query(
      'sync_state_log',
      where: 'session_id = ?',
      whereArgs: [_sessionId],
      orderBy: 'occurred_at DESC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final lastState = rows.first['to_state'] as String?;
      if (lastState != null) {
        _current = SyncState.values.firstWhere(
          (s) => s.label == lastState,
          orElse: () => SyncState.idle,
        );
      }
    }
  }

  /// Deletes all `sync_state_log` rows older than [retentionDays] days.
  static Future<int> purgeOldTransitions(
    Database db, {
    int retentionDays = 30,
  }) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .toIso8601String();
    return db.delete(
      'sync_state_log',
      where: 'occurred_at < ?',
      whereArgs: [cutoff],
    );
  }
}
