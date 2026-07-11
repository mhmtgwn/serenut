// lib/providers/sync_provider.dart
// Serenut POS — Offline Sync Riverpod Provider + AppLifecycle Trigger
// Created: 24 Jun 2026

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:serenutos/domain/services/offline_sync_service.dart';
import 'package:serenutos/domain/services/sync_state_machine.dart';
import 'package:serenutos/domain/services/sync_trace_service.dart';
import 'package:serenutos/domain/services/incident_repository.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/domain/services/sync_replay_engine.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';

import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/service_providers.dart';


// ── Sync Status ───────────────────────────────────────────────────────────────
enum SyncStatus { idle, syncing, success, error }

class SyncState {
  final SyncStatus status;
  final int? lastSyncedCount;
  final String? lastError;
  final DateTime? lastSyncAt;

  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSyncedCount,
    this.lastError,
    this.lastSyncAt,
  });

  SyncState copyWith({
    SyncStatus? status,
    int? lastSyncedCount,
    String? lastError,
    DateTime? lastSyncAt,
  }) {
    return SyncState(
      status:           status ?? this.status,
      lastSyncedCount:  lastSyncedCount ?? this.lastSyncedCount,
      lastError:        lastError ?? this.lastError,
      lastSyncAt:       lastSyncAt ?? this.lastSyncAt,
    );
  }
}

// ── Sync Notifier ─────────────────────────────────────────────────────────────
class SyncNotifier extends StateNotifier<SyncState> with WidgetsBindingObserver {
  final Ref _ref;
  OfflineSyncService? _syncService;

  /// Active state machine for the current sync session.
  /// Updated on every triggerSync() call with a fresh session.
  SyncStateMachine? _machine;
  SyncStateMachine? get stateMachine => _machine;

  SyncNotifier(this._ref) : super(const SyncState()) {
    WidgetsBinding.instance.addObserver(this);
    _initAndSync();
  }

  Future<void> _initAndSync() async {
    try {
      final saleRepo   = await _ref.read(saleRepositoryProvider.future);
      final transactionRepo = await _ref.read(financialTransactionRepositoryProvider.future);
      final licenseService = _ref.read(licenseServiceProvider);
      final trialManager   = _ref.read(trialManagerProvider);
      _syncService     = OfflineSyncService(
        saleRepository: saleRepo,
        transactionRepository: transactionRepo,
        licenseService: licenseService,
        trialManager: trialManager,
      );
      await triggerSync();
    } catch (_) {
      // Silent — sync will be retried on next foreground
    }
  }

  /// Trigger sync manually (e.g., after a sale is created).
  Future<void> triggerSync() async {
    final service = _syncService;
    if (service == null) return;
    if (state.status == SyncStatus.syncing) return;

    state = state.copyWith(status: SyncStatus.syncing);

    try {
      final db = kIsWeb ? null : await DatabaseManager().getDatabase();
      final machine = SyncStateMachine(db: db);
      _machine = machine;

      final result = await service.syncPendingSales(stateMachine: machine);

      if (result.synced > 0 || result.failed == 0) {
        state = state.copyWith(
          status:          SyncStatus.success,
          lastSyncedCount: result.synced,
          lastSyncAt:      DateTime.now(),
          lastError:       null,
        );
      } else {
        // Log the partial sync failure event
        await TelemetryService().logStructured(
          event: 'sync_partial_failure',
          level: LogLevel.error,
          correlationId: machine.sessionId,
          metadata: {
            'errors': result.errors,
            'synced': result.synced,
            'failed': result.failed,
          },
        );
        state = state.copyWith(
          status:    SyncStatus.error,
          lastError: result.errors.isNotEmpty ? result.errors.first : 'Sync failed',
        );
      }
    } catch (e, st) {
      await TelemetryService().logError(
        e,
        st,
        context: 'SyncNotifier.triggerSync',
        correlationId: _machine?.sessionId,
      );
      state = state.copyWith(
        status:    SyncStatus.error,
        lastError: e.toString(),
      );
    }
  }

  // ── AppLifecycle — Trigger sync when app comes to foreground ──────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Fire-and-forget — non-blocking
      triggerSync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncService?.dispose();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Global sync state provider.
/// 
/// Usage:
/// ```dart
/// // Trigger sync manually
/// ref.read(syncProvider.notifier).triggerSync();
/// 
/// // Watch sync status
/// final syncState = ref.watch(syncProvider);
/// if (syncState.status == SyncStatus.syncing) { ... }
/// ```
final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>(
  (ref) => SyncNotifier(ref),
);

/// Quick accessor — true if any sales are being synced right now.
final isSyncingProvider = Provider<bool>(
  (ref) => ref.watch(syncProvider).status == SyncStatus.syncing,
);

/// Provides the current [SyncStateMachine] state for Debug Console UI.
/// Updates reactively when [syncProvider] changes.
final syncMachineStateProvider = Provider<SyncState?>((ref) {
  // Expose the current SyncState for UI consumption
  return ref.watch(syncProvider);
});

/// Provides recent deduplicated incidents for the Debug Console.
/// Auto-refreshes on each sync cycle.
final recentIncidentsProvider = FutureProvider.autoDispose(
  (ref) async {
    // Invalidate when sync state changes to pick up new incidents
    ref.watch(syncProvider);
    final repo = IncidentRepository(
      tracer: SyncTraceService(),
    );
    return repo.getDeduplicatedIncidents(hours: 48);
  },
);

/// Provides recent sync sessions for the Debug Console timeline viewer.
final recentSessionsProvider = FutureProvider.autoDispose(
  (ref) async {
    ref.watch(syncProvider);
    final tracer = SyncTraceService();
    return tracer.getRecentSessions(count: 20);
  },
);

/// Provides a family provider to generate a ReplayReport for a given correlationId.
final incidentReplayProvider = FutureProvider.family.autoDispose<ReplayReport, String>(
  (ref, correlationId) async {
    ref.watch(syncProvider);
    final db = kIsWeb ? null : await DatabaseManager().getDatabase();
    final engine = SyncReplayEngine(db: db);
    return engine.generateReport(correlationId);
  },
);
