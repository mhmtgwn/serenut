// lib/providers/sync_provider.dart
// Serenut OS — Offline Sync Riverpod Provider + AppLifecycle Trigger
// Created: 24 Jun 2026

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:serenutos/infrastructure/sync_v4/sync_v4_service.dart';
import 'package:serenutos/domain/services/sync_state_machine.dart';
import 'package:serenutos/domain/services/sync_trace_service.dart';
import 'package:serenutos/domain/services/incident_repository.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/domain/services/sync_replay_engine.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/infrastructure/sync_v4/sms_cloud_outbox.dart';

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
      status: status ?? this.status,
      lastSyncedCount: lastSyncedCount ?? this.lastSyncedCount,
      lastError: lastError ?? this.lastError,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }
}

// ── Sync Notifier ─────────────────────────────────────────────────────────────
class SyncNotifier extends StateNotifier<SyncState>
    with WidgetsBindingObserver {
  final Ref _ref;
  SyncV4Service? _syncService;

  /// Active state machine for the current sync session.
  /// Updated on every triggerSync() call with a fresh session.
  SyncStateMachine? _machine;
  Timer? _periodicSyncTimer;
  bool _syncRequestedWhileRunning = false;
  SyncStateMachine? get stateMachine => _machine;

  SyncNotifier(this._ref) : super(const SyncState()) {
    WidgetsBinding.instance.addObserver(this);
    _initAndSync();
  }

  Future<void> _initAndSync() async {
    try {
      _syncService = SyncV4Service(
        _ref.read(apiClientProvider),
        licenseService: _ref.read(licenseServiceProvider),
      );
      await triggerSync();
      _periodicSyncTimer ??= Timer.periodic(
        const Duration(seconds: 30),
        (_) => triggerSync(),
      );
    } catch (e, st) {
      // Silent — sync will be retried on next foreground
      TelemetryService().logError(e, st, context: 'SyncNotifier.initSync', level: LogLevel.warning);
    }
  }

  /// Force a full re-sync from server by clearing the last sync timestamp cursor.
  Future<void> forceFullSync() async {
    try {
      final db = kIsWeb ? null : await DatabaseManager().getDatabase();
      await db
          ?.delete('sync_cursor_v4', where: 'key = ?', whereArgs: ['global']);
    } catch (e, st) {
      TelemetryService().logError(e, st, context: 'SyncNotifier.forceFullSync', level: LogLevel.warning);
    }

    state = const SyncState();
    await triggerSync();
  }

  /// Trigger sync manually (e.g., after a sale is created).
  Future<void> triggerSync() async {
    final service = _syncService;
    if (service == null) return;
    if (state.status == SyncStatus.syncing) {
      // Never lose a mutation/event that arrives during an active pass. One
      // trailing pass is sufficient because the outbox coalesces entity edits.
      _syncRequestedWhileRunning = true;
      return;
    }

    // Check device activation and license status before initiating network sync.
    // Preserves local outbox while setting classified error state.
    var activationId =
        _ref.read(licenseServiceProvider).getLicenseInfo()?.activationId;
    if (activationId == null || activationId.isEmpty) {
      // A successful server activation may not yet be present in the local
      // cache after reinstall/update. Recover the entitlement and signed
      // device token before classifying sync as blocked.
      try {
        await _ref.read(authServiceProvider).refreshEntitlement();
        activationId =
            _ref.read(licenseServiceProvider).getLicenseInfo()?.activationId;
      } catch (_) {
        // The classified error below is retained for the recovery UI.
      }
    }
    if (activationId == null || activationId.isEmpty) {
      final hasAccessToken = _ref.read(apiClientProvider).jwtToken?.isNotEmpty ?? false;
      final hasRefreshToken = _ref.read(authServiceProvider).getRefreshToken()?.isNotEmpty ?? false;

      // Only log structured error if the user is authenticated but missing device activation
      if (hasAccessToken || hasRefreshToken) {
        await TelemetryService().logStructured(
          event: 'sync_activation_recovery_failed',
          level: LogLevel.error,
          metadata: {
            'has_access_token': hasAccessToken,
            'has_refresh_token': hasRefreshToken,
          },
        );
      }

      state = state.copyWith(
        status: SyncStatus.error,
        lastError:
            'active_device_activation_required: Cihaz aktivasyonu veya lisansı gerekli.',
      );
      return;
    }

    state = state.copyWith(status: SyncStatus.syncing);
    try {
      final db = kIsWeb ? null : await DatabaseManager().getDatabase();
      final machine = SyncStateMachine(db: db);
      _machine = machine;

      final result = await service.sync();
      await SmsCloudOutbox(_ref.read(apiClientProvider)).flush();

      // Repository consumers keep their own AsyncNotifier caches. Rebuild them
      // after either a local push or a remote pull so open screens immediately
      // show changes made on another device.
      // FIX: also invalidate when pull-only data arrives (no local push pending)
      if (result.synced > 0 || result.pulled > 0 || result.reconciled > 0) {
        _ref.invalidate(settingsProvider);
        _ref.invalidate(settingsNotifierProvider);
        _ref.invalidate(productRepositoryProvider);
        _ref.invalidate(customerRepositoryProvider);
        _ref.invalidate(saleRepositoryProvider);
        _ref.invalidate(financialTransactionRepositoryProvider);
        _ref.invalidate(orderRepositoryProvider);
        _ref.invalidate(ordersControllerProvider);
        _ref.invalidate(salesControllerProvider);
        _ref.invalidate(salesHistoryControllerProvider);
        _ref.invalidate(customersControllerProvider);
        _ref.invalidate(productsControllerProvider);
        _ref.invalidate(salesProductsControllerProvider);
        _ref.invalidate(ordersProductsControllerProvider);
        _ref.invalidate(allProductsProvider);
        _ref.invalidate(allCustomersProvider);
        _ref.invalidate(allSalesProvider);
        _ref.invalidate(todayRevenueProvider);
        _ref.invalidate(lowStockProductsProvider);
        _ref.invalidate(debtorsProvider);
        _ref.invalidate(reportRepositoryProvider);
        _ref.invalidate(dashboardRepositoryProvider);
      }

      try {
        final authService = _ref.read(authServiceProvider);
        await authService.checkCurrentUserSessionOnline();
      } catch (e, st) {
        TelemetryService().logError(e, st, context: 'SyncNotifier.checkCurrentUserSessionOnline', level: LogLevel.warning);
      }

      if (result.success) {
        state = state.copyWith(
          status: SyncStatus.success,
          lastSyncedCount: result.synced,
          lastSyncAt: DateTime.now(),
          lastError: null,
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
          status: SyncStatus.error,
          lastError:
              result.errors.isNotEmpty ? result.errors.first : 'Sync failed',
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
        status: SyncStatus.error,
        lastError: e.toString(),
      );
    } finally {
      if (_syncRequestedWhileRunning) {
        _syncRequestedWhileRunning = false;
        unawaited(Future<void>.microtask(triggerSync));
      }
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
    _periodicSyncTimer?.cancel();
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
final incidentReplayProvider =
    FutureProvider.family.autoDispose<ReplayReport, String>(
  (ref, correlationId) async {
    ref.watch(syncProvider);
    final db = kIsWeb ? null : await DatabaseManager().getDatabase();
    final engine = SyncReplayEngine(db: db);
    return engine.generateReport(correlationId);
  },
);
