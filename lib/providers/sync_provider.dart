import 'package:serenutos/providers/database_provider.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
// lib/providers/sync_provider.dart
// Serenut OS — Offline Sync Riverpod Provider + AppLifecycle Trigger
// Created: 24 Jun 2026

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:serenutos/infrastructure/sync_v4/sync_v4_service.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_outbox.dart';
import 'package:serenutos/domain/services/sync_state_machine.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/order_details_controller.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/infrastructure/sync_v4/sms_cloud_outbox.dart';
import 'package:serenutos/providers/sms_provider.dart';
import 'package:serenutos/infrastructure/services/dataset_loader_service.dart';
import 'package:serenutos/core_next/infrastructure/database/app_database.dart';
import 'package:serenutos/core_next/infrastructure/sync/sync_v4_http_client.dart';
import 'package:serenutos/core_next/infrastructure/sync/sync_v4_outbox_processor.dart';
import 'package:serenutos/core_next/infrastructure/sync/sync_v4_pull_ingestion_service.dart';
import 'package:serenutos/core_next/infrastructure/sync/sync_v4_pull_worker.dart';

// ── Sync Status ───────────────────────────────────────────────────────────────
enum SyncStatus { idle, syncing, success, error }

class SyncState {
  final SyncStatus status;
  final int? lastSyncedCount;
  final String? lastError;
  final String? userFriendlyError;
  final DateTime? lastSyncAt;
  final int pendingOutboxCount;
  final int unresolvedConflictCount;

  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSyncedCount,
    this.lastError,
    this.userFriendlyError,
    this.lastSyncAt,
    this.pendingOutboxCount = 0,
    this.unresolvedConflictCount = 0,
  });

  SyncState copyWith({
    SyncStatus? status,
    int? lastSyncedCount,
    String? lastError,
    String? userFriendlyError,
    bool clearError = false,
    DateTime? lastSyncAt,
    int? pendingOutboxCount,
    int? unresolvedConflictCount,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSyncedCount: lastSyncedCount ?? this.lastSyncedCount,
      lastError: clearError ? null : (lastError ?? this.lastError),
      userFriendlyError:
          clearError ? null : (userFriendlyError ?? this.userFriendlyError),
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      pendingOutboxCount: pendingOutboxCount ?? this.pendingOutboxCount,
      unresolvedConflictCount:
          unresolvedConflictCount ?? this.unresolvedConflictCount,
    );
  }
}

// ── Sync Notifier ─────────────────────────────────────────────────────────────
/// Core Next Senkronizasyon Yürütücü Fonksiyon Arayüzü
typedef CoreNextSyncExecutor = Future<void> Function();

/// Core Next Senkronizasyon Yürütücü Sağlayıcısı
final coreNextSyncExecutorProvider = Provider<CoreNextSyncExecutor?>((ref) {
  return () async {
    final licenseService = ref.read(licenseServiceProvider);
    final lic = licenseService.getLicenseInfo();
    final deviceActivationId = lic?.activationId;
    final deviceId = ref.read(deviceManagerProvider).getDeviceId();
    final apiClient = ref.read(apiClientProvider);
    final rawBaseUrl = apiClient.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final syncBaseUrl = rawBaseUrl.endsWith('/api/v1')
        ? '${rawBaseUrl.substring(0, rawBaseUrl.length - '/api/v1'.length)}/api/v4/sync'
        : (rawBaseUrl.endsWith('/api/v4/sync')
            ? rawBaseUrl
            : '$rawBaseUrl/api/v4/sync');

    if (deviceActivationId == null || deviceActivationId.isEmpty) {
      return;
    }

    final coreDb = await CoreAppDatabase.open();
    final httpClient = SyncV4HttpClient(
      baseUrl: syncBaseUrl,
      deviceActivationId: deviceActivationId,
      deviceId: deviceId,
      tokenProvider: () async => apiClient.jwtToken,
    );
    final outboxProcessor = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient);
    final ingestionService = SyncV4PullIngestionService(coreDb, localDeviceId: deviceId);

    final currentCursor = await ingestionService.getSavedCursor();
    if (currentCursor == 0 && !kIsWeb) {
      try {
        final legacyDb = await ref.read(databaseProvider.future);
        final cursorRows = await legacyDb.query(
          'sync_cursor_v4',
          where: 'key = ?',
          whereArgs: ['global'],
          limit: 1,
        );
        final legacyCursor =
            (cursorRows.firstOrNull?['cursor'] as num?)?.toInt() ?? 0;
        if (legacyCursor > 0) {
          await coreDb.db.insert(
            'app_settings',
            {
              'key': 'sync_pull_cursor',
              'value': '$legacyCursor',
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      } catch (e) {
        debugPrint('[SyncProvider] Legacy sync cursor carryover error: $e');
      }
    }

    final pullWorker = SyncV4PullWorker(
      httpClient: httpClient,
      ingestionService: ingestionService,
    );

    await outboxProcessor.processOutbox();
    await pullWorker.pullAll();
  };
});

class SyncNotifier extends StateNotifier<SyncState>
    with WidgetsBindingObserver {
  final Ref _ref;
  SyncV4Service? _syncService;

  /// Active state machine for the current sync session.
  /// Updated on every triggerSync() call with a fresh session.
  SyncStateMachine? _machine;
  Timer? _periodicSyncTimer;
  bool _syncRequestedWhileRunning = false;
  bool _resetInProgress = false;
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
        catalogSourceResetter: () =>
            _ref.read(datasetLoaderServiceProvider).unmountActiveVersion(),
      );
      await refreshPendingCount();
      await triggerSync();
      _periodicSyncTimer ??= Timer.periodic(
        const Duration(seconds: 15),
        (_) => triggerSync(),
      );
    } catch (e, st) {
      // Silent — sync will be retried on next foreground
      TelemetryService().logError(e, st,
          context: 'SyncNotifier.initSync', level: LogLevel.warning);
    }
  }

  /// Refreshes the count of pending outbox records from SQLite.
  Future<void> refreshPendingCount() async {
    if (kIsWeb) return;
    try {
      final db = await _ref.read(databaseProvider.future);
      final count = await SyncOutboxV4.getPendingCount(db);
      var conflictCount = 0;
      try {
        final conflicts = await db.rawQuery(
          'SELECT COUNT(*) AS count FROM sync_conflicts_v4 WHERE resolved_at IS NULL',
        );
        conflictCount = (conflicts.first['count'] as num?)?.toInt() ?? 0;
      } catch (_) {
        // Older/recovered databases may not have the conflict table yet.
      }
      state = state.copyWith(
        pendingOutboxCount: count,
        unresolvedConflictCount: conflictCount,
      );
    } catch (_) {
      // Ignored: fallback or safe default applied
    }
  }

  /// Returns unresolved sync conflict records from SQLite.
  Future<List<Map<String, Object?>>> getUnresolvedConflicts({int limit = 100}) async {
    if (kIsWeb) return const [];
    try {
      final db = await _ref.read(databaseProvider.future);
      return await db.rawQuery('''
        SELECT entity_type, entity_id, server_revision, detected_at
        FROM sync_conflicts_v4
        WHERE resolved_at IS NULL
        ORDER BY detected_at DESC
        LIMIT ?
      ''', [limit]);
    } catch (_) {
      return const [];
    }
  }

  /// Translates low-level technical sync errors into actionable Turkish messages for cashiers.
  String _humanizeSyncError(String rawError) {
    final lower = rawError.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection refused') ||
        lower.contains('clientexception') ||
        lower.contains('connection timed out') ||
        lower.contains('os error: no address associated with hostname')) {
      return 'Sunucuya ulaşılamıyor. Satışlarınız ve işlemleriniz cihazda güvende saklanıyor; bağlantı geldiğinde otomatik eşitlenecek.';
    }
    if (lower.contains('active_device_activation_required') ||
        lower.contains('cihaz aktivasyonu')) {
      return 'Cihaz aktivasyonu veya lisans onayı gerekiyor.';
    }
    if (lower.contains('unauthorized') || lower.contains('401')) {
      return 'Oturum süresi doldu. Lütfen tekrar giriş yapın.';
    }
    if (lower.contains('conflict')) {
      return 'Farklı bir cihazdaki son kayıtlarla senkronizasyon çakışması tespit edildi.';
    }
    if (rawError.trim().isEmpty) {
      return 'Bilinmeyen bir senkronizasyon uyarısı.';
    }
    return rawError;
  }

  /// Force a full re-sync from server by clearing the last sync timestamp cursor.
  Future<void> forceFullSync() async {
    final cutoff = DatabaseManager.cutoffMaintenanceLock;
    if (cutoff != null && !cutoff.state.isWritePermitted) {
      cutoff.assertWritePermitted(operation: 'SyncNotifier.forceFullSync');
    }
    try {
      final db = kIsWeb ? null : await _ref.read(databaseProvider.future);
      await db
          ?.delete('sync_cursor_v4', where: 'key = ?', whereArgs: ['global']);
    } catch (e, st) {
      TelemetryService().logError(e, st,
          context: 'SyncNotifier.forceFullSync', level: LogLevel.warning);
    }

    state = const SyncState();
    await triggerSync();
  }

  Future<void> resetOperationalData() async {
    await _waitForActiveSync();
    final service = _syncService;
    if (service == null) {
      throw StateError(
          'Senkronizasyon servisi henüz hazır değil. Lütfen tekrar deneyin.');
    }
    _resetInProgress = true;
    state = state.copyWith(status: SyncStatus.syncing, lastError: null);
    try {
      await service.resetOperationalData();
      state = state.copyWith(
        status: SyncStatus.success,
        lastSyncedCount: 0,
        lastSyncAt: DateTime.now(),
        lastError: null,
      );
    } catch (error) {
      state =
          state.copyWith(status: SyncStatus.error, lastError: error.toString());
      rethrow;
    } finally {
      _resetInProgress = false;
    }
  }

  Future<void> resetProductCatalog() async {
    await _waitForActiveSync();
    final service = _syncService;
    if (service == null) {
      throw StateError(
          'Senkronizasyon servisi henüz hazır değil. Lütfen tekrar deneyin.');
    }
    _resetInProgress = true;
    state = state.copyWith(status: SyncStatus.syncing, lastError: null);
    try {
      await service.resetProductCatalog();
      _invalidateProductProjections();
      state = state.copyWith(
        status: SyncStatus.success,
        lastSyncedCount: 0,
        lastSyncAt: DateTime.now(),
        lastError: null,
      );
    } catch (error) {
      state =
          state.copyWith(status: SyncStatus.error, lastError: error.toString());
      rethrow;
    } finally {
      _resetInProgress = false;
    }
  }

  void _invalidateProductProjections() {
    _ref.invalidate(productRepositoryProvider);
    _ref.invalidate(productsControllerProvider);
    _ref.invalidate(salesProductsControllerProvider);
    _ref.invalidate(ordersProductsControllerProvider);
    _ref.invalidate(allProductsProvider);
    _ref.invalidate(lowStockProductsProvider);
    _ref.invalidate(productInventorySummaryProvider);
    _ref.read(productCategoriesStateProvider.notifier).state = [];
    _ref.read(productCategoryFilterProvider.notifier).state = null;
    _ref.read(salesProductCategoryFilterProvider.notifier).state = null;
    _ref.read(ordersProductCategoryFilterProvider.notifier).state = null;
  }

  /// Prevents a database write from racing with factory-reset file removal.
  Future<void> prepareForFactoryReset() async {
    await _waitForActiveSync();
    _resetInProgress = true;
    _syncRequestedWhileRunning = false;
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _syncService = null;
    state = const SyncState();
  }

  Future<void> _waitForActiveSync() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (state.status == SyncStatus.syncing &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (state.status == SyncStatus.syncing) {
      throw StateError(
          'Senkronizasyon tamamlanamadı. İnternet bağlantısını kontrol edip tekrar deneyin.');
    }
  }

  /// Trigger sync manually (e.g., after a sale is created).
  Future<void> triggerSync() async {
    if (_resetInProgress) return;
    final cutoff = DatabaseManager.cutoffMaintenanceLock;
    if (cutoff != null && !cutoff.state.isWritePermitted) {
      debugPrint('[SyncNotifier] Kesim/bakım kilidi aktif (${cutoff.state.phase}). Senkronizasyon bekletiliyor.');
      return;
    }
    final isCoreNextEnabled = _ref.read(coreNextSalesEngineEnabledProvider);
    final coreNextSync =
        isCoreNextEnabled ? _ref.read(coreNextSyncExecutorProvider) : null;
    final service = _syncService;
    if (service == null && coreNextSync == null) return;
    if (state.status == SyncStatus.syncing) {
      // Never lose a mutation/event that arrives during an active pass. One
      // trailing pass is sufficient because the outbox coalesces entity edits.
      _syncRequestedWhileRunning = true;
      return;
    }

    if (service == null) {
      state = state.copyWith(status: SyncStatus.syncing);
      try {
        await coreNextSync!();
        state = state.copyWith(
          status: SyncStatus.success,
          lastSyncAt: DateTime.now(),
          lastError: null,
          clearError: true,
        );
      } catch (e) {
        final errStr = e.toString();
        state = state.copyWith(
          status: SyncStatus.error,
          lastError: errStr,
          userFriendlyError: _humanizeSyncError(errStr),
        );
      }
      return;
    }

    if (_ref.read(apiClientProvider).isSessionInvalidated) {
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
      final hasAccessToken =
          _ref.read(apiClientProvider).jwtToken?.isNotEmpty ?? false;
      final hasRefreshToken =
          _ref.read(authServiceProvider).getRefreshToken()?.isNotEmpty ?? false;

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

      const err =
          'active_device_activation_required: Cihaz aktivasyonu veya lisansı gerekli.';
      state = state.copyWith(
        status: SyncStatus.error,
        lastError: err,
        userFriendlyError: _humanizeSyncError(err),
      );
      await refreshPendingCount();
      return;
    }

    state = state.copyWith(status: SyncStatus.syncing);
    try {
      if (coreNextSync != null) {
        try {
          await coreNextSync();
        } catch (e, st) {
          TelemetryService().logError(
            e,
            st,
            context: 'SyncNotifier.coreNextSync',
            level: LogLevel.warning,
          );
        }
      }

      final db = kIsWeb ? null : await _ref.read(databaseProvider.future);
      final machine = SyncStateMachine(db: db);
      _machine = machine;

      final result = await service.sync();
      await SmsCloudOutbox(_ref.read(apiClientProvider)).flush();

      // Repository consumers keep their own AsyncNotifier caches. Rebuild them
      // after a remote pull so open screens immediately show changes made on another device.
      // Do not invalidate on local push only, as local writes are already applied.
      if (result.pulled > 0 || result.reconciled > 0) {
        final types = result.pulledEntityTypes;
        final invalidateAll = types.isEmpty;

        if (invalidateAll ||
            types.contains('settings') ||
            types.contains('company')) {
          _ref.invalidate(settingsProvider);
          _ref.invalidate(settingsNotifierProvider);
        }

        if (invalidateAll || types.contains('product')) {
          _ref.invalidate(productRepositoryProvider);
          _ref.invalidate(productsControllerProvider);
          _ref.invalidate(salesProductsControllerProvider);
          _ref.invalidate(ordersProductsControllerProvider);
          _ref.invalidate(allProductsProvider);
          _ref.invalidate(lowStockProductsProvider);
          _ref.invalidate(productInventorySummaryProvider);
        }

        if (invalidateAll ||
            types.contains('customer') ||
            result.reconciled > 0) {
          _ref.invalidate(customerRepositoryProvider);
          _ref.invalidate(customersControllerProvider);
          _ref.invalidate(customerBalanceSummaryProvider);
          _ref.invalidate(customerLookupMapProvider);
          _ref.invalidate(salesCustomersControllerProvider);
          _ref.invalidate(ordersCustomersControllerProvider);
          _ref.invalidate(collectionCustomersControllerProvider);
          _ref.invalidate(allCustomersProvider);
          _ref.invalidate(debtorsProvider);
        }

        if (invalidateAll || types.contains('order')) {
          _ref.invalidate(orderRepositoryProvider);
          _ref.invalidate(ordersControllerProvider);
          _ref.invalidate(orderDetailProvider);
          _ref.invalidate(orderPaymentInfoProvider);
          _ref.invalidate(ordersCustomersControllerProvider);
          _ref.invalidate(ordersProductsControllerProvider);
          _ref.invalidate(customerLookupMapProvider);
          _ref.invalidate(dashboardProvider);
          _ref.invalidate(dashboardRepositoryProvider);
        }

        if (invalidateAll ||
            types.contains('sale') ||
            types.contains('financial_transaction')) {
          _ref.invalidate(saleRepositoryProvider);
          _ref.invalidate(financialTransactionRepositoryProvider);
          _ref.invalidate(salesControllerProvider);
          _ref.invalidate(salesHistoryControllerProvider);
          _ref.invalidate(allSalesProvider);
          _ref.invalidate(todayRevenueProvider);
          _ref.invalidate(reportRepositoryProvider);
          _ref.invalidate(dashboardRepositoryProvider);
          _ref.invalidate(dashboardProvider);
        }
      }

      try {
        final authService = _ref.read(authServiceProvider);
        await authService.checkCurrentUserSessionOnline();
      } catch (e, st) {
        TelemetryService().logError(e, st,
            context: 'SyncNotifier.checkCurrentUserSessionOnline',
            level: LogLevel.warning);
      }

      if (result.success) {
        state = state.copyWith(
          status: SyncStatus.success,
          lastSyncedCount: result.synced,
          lastSyncAt: DateTime.now(),
          clearError: true,
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
        final err =
            result.errors.isNotEmpty ? result.errors.first : 'Sync failed';
        state = state.copyWith(
          status: SyncStatus.error,
          lastError: err,
          userFriendlyError: _humanizeSyncError(err),
        );
      }
    } catch (e, st) {
      final errStr = e.toString();
      final isSessionExpired = errStr.contains('Session expired') ||
          errStr.contains('Status: 401') ||
          errStr.contains('Status: 403');
      final isNetworkIssue = e.runtimeType.toString() == 'SocketException' ||
          errStr.contains('SocketException') ||
          errStr.contains('No Internet connection') ||
          errStr.contains('Connection refused') ||
          errStr.contains('Failed host lookup') ||
          errStr.contains('Network is unreachable') ||
          errStr.contains('Status: 408') ||
          errStr.contains('Status: 502') ||
          errStr.contains('Status: 503') ||
          errStr.contains('Status: 504') ||
          errStr.contains('TimeoutException') ||
          errStr.contains('ClientException') ||
          errStr.contains('HandshakeException') ||
          errStr.contains('zaman aşımı');

      if (!isSessionExpired && !isNetworkIssue) {
        await TelemetryService().logError(
          e,
          st,
          context: 'SyncNotifier.triggerSync',
          correlationId: _machine?.sessionId,
        );
      } else {
        await TelemetryService().logStructured(
          event: isSessionExpired
              ? 'sync_session_expired'
              : 'sync_network_offline',
          level: LogLevel.warning,
          correlationId: _machine?.sessionId,
          metadata: {'error': errStr},
        );
      }
      final rawErr = e.toString();
      state = state.copyWith(
        status: SyncStatus.error,
        lastError: rawErr,
        userFriendlyError: _humanizeSyncError(rawErr),
      );
    } finally {
      // WhatsApp delivery uses its own API queue and must not depend on the
      // business-data sync succeeding. Retry it after both successful and
      // failed sync passes; the durable outbox retains messages on failure.
      unawaited(_ref.read(whatsappNotificationOutboxProvider).flush());
      await refreshPendingCount();
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
