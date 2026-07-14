// lib/domain/services/sync_chaos_injector.dart
// Sync Conflict Simulation Framework — Injectable Fault Layer
//
// PRODUCTION SAFETY: This class is never referenced by production code paths.
// The `OfflineSyncService` accepts an optional injector; in production it is
// always null, resulting in zero-overhead no-ops on every check.
//
// USAGE (test only):
//   final injector = SyncChaosInjector()
//     ..add(NetworkCutFault())
//     ..add(DelayFault(milliseconds: 200));
//   final service = OfflineSyncService(
//     ..., chaosInjector: injector,
//   );

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kReleaseMode;

// ── Fault hook points ────────────────────────────────────────────────────────

/// Points in the sync pipeline where faults can be injected.
enum FaultHook {
  /// Before the HTTP POST is sent.
  beforePush,

  /// After a successful HTTP 200/201 response, before marking `is_synced = 1`.
  afterPushBeforeCommit,

  /// During the pull phase (before `_pullUpdates` processing).
  beforePull,
}

// ── Base fault ───────────────────────────────────────────────────────────────

/// Base class for all injectable faults.
abstract class SyncFault {
  /// The hook point where this fault is triggered.
  final FaultHook hook;

  const SyncFault(this.hook);

  /// Apply the fault. May throw, delay, or mutate shared state.
  Future<void> apply({String? saleId});
}

// ── Concrete fault implementations ───────────────────────────────────────────

/// Simulates a network connection drop by throwing [SocketException].
class NetworkCutFault extends SyncFault {
  final String message;

  const NetworkCutFault({
    this.message = 'Simulated network cut by SyncChaosInjector',
    FaultHook hook = FaultHook.beforePush,
  }) : super(hook);

  @override
  Future<void> apply({String? saleId}) async {
    throw SocketException(message);
  }
}

/// Injects an artificial delay to create timing-sensitive race conditions.
class DelayFault extends SyncFault {
  final int milliseconds;

  const DelayFault({
    required this.milliseconds,
    FaultHook hook = FaultHook.beforePush,
  }) : super(hook);

  @override
  Future<void> apply({String? saleId}) async {
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
  }
}

/// Simulates the server returning a 409 Conflict (duplicate idempotency key).
/// The client's idempotency logic should treat this as success.
class DuplicatePushFault extends SyncFault {
  const DuplicatePushFault({FaultHook hook = FaultHook.beforePush})
      : super(hook);

  @override
  Future<void> apply({String? saleId}) async {
    // Signal to the injector that the HTTP response should be 409.
    // The OfflineSyncService checks `injector.overrideStatusCode` before POST.
  }

  int get statusCodeOverride => 409;
}

/// Simulates a device clock being skewed ahead by [minutes] minutes.
/// Used to test idempotency key uniqueness under time drift conditions.
class ClockSkewFault extends SyncFault {
  final int minutes;

  const ClockSkewFault({
    required this.minutes,
    FaultHook hook = FaultHook.beforePush,
  }) : super(hook);

  @override
  Future<void> apply({String? saleId}) async {
    // Clock skew is applied via SyncChaosInjector.now() override below.
  }

  Duration get skew => Duration(minutes: minutes);
}

/// Forces a crash (StateError) mid-transaction, after push but before DB commit.
/// Used to verify full transaction rollback on partial writes.
class PartialWriteFault extends SyncFault {
  const PartialWriteFault() : super(FaultHook.afterPushBeforeCommit);

  @override
  Future<void> apply({String? saleId}) async {
    throw StateError(
      'PartialWriteFault: simulated crash after push, before DB commit'
      '${saleId != null ? " (saleId: $saleId)" : ""}',
    );
  }
}

/// Simulated DatabaseException subclass for Disk Full conditions
class DiskFullDatabaseException implements Exception {
  final String? message;
  DiskFullDatabaseException(
      [this.message = 'SQLITE_FULL: database or disk is full']);

  @override
  String toString() => 'DatabaseException($message)';
}

/// Simulates a disk full write failure by throwing a [DiskFullDatabaseException].
class DiskFullFault extends SyncFault {
  const DiskFullFault({FaultHook hook = FaultHook.afterPushBeforeCommit})
      : super(hook);

  @override
  Future<void> apply({String? saleId}) async {
    throw DiskFullDatabaseException();
  }
}

// ── Injector orchestrator ────────────────────────────────────────────────────

/// Orchestrates multiple faults across sync hook points.
///
/// Usage:
/// ```dart
/// final injector = SyncChaosInjector()
///   ..addFault(DelayFault(milliseconds: 300))
///   ..addFault(NetworkCutFault());
/// ```
class SyncChaosInjector {
  final List<SyncFault> _faults = [];

  /// Clock override — set by [ClockSkewFault] consumers.
  Duration _clockSkew = Duration.zero;

  /// Optional HTTP status code override — set by [DuplicatePushFault].
  int? _statusCodeOverride;

  /// Returns the current time with any injected clock skew applied.
  DateTime get now => DateTime.now().add(_clockSkew);

  /// Returns the HTTP status code override if a [DuplicatePushFault] is active.
  int? get statusCodeOverride => _statusCodeOverride;

  /// Register a fault to be applied at its designated hook point.
  SyncChaosInjector addFault(SyncFault fault) {
    _faults.add(fault);
    if (fault is ClockSkewFault) {
      _clockSkew = fault.skew;
    }
    if (fault is DuplicatePushFault) {
      _statusCodeOverride = fault.statusCodeOverride;
    }
    return this;
  }

  /// Apply all faults registered for [hook]. Throws on first throwing fault.
  ///
  /// **Production guard:** This method is a guaranteed no-op in release builds
  /// (`kReleaseMode == true`). Faults can only fire in debug/profile mode.
  /// This prevents accidental chaos injection from corrupting production data.
  Future<void> trigger(FaultHook hook, {String? saleId}) async {
    // Hard compile-time guard — never fire in production
    if (kReleaseMode) return;
    for (final fault in _faults.where((f) => f.hook == hook)) {
      await fault.apply(saleId: saleId);
    }
  }

  /// Returns true if any fault is registered for [hook].
  bool hasFaultAt(FaultHook hook) => _faults.any((f) => f.hook == hook);

  /// Clears all registered faults (useful for test tearDown).
  void reset() {
    _faults.clear();
    _clockSkew = Duration.zero;
    _statusCodeOverride = null;
  }
}
