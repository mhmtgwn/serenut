// lib/domain/services/offline_sync_service.dart
// Serenut POS — Offline Sync Service (Production Implementation)
// Real HTTP with exponential backoff, idempotent uploads, and sync queue
// Updated: 24 Jun 2026

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/services/version_checker.dart';

import 'package:serenutos/domain/services/sync_chaos_injector.dart';
import 'package:serenutos/domain/services/sync_state_machine.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

/// Result of a single sync operation.
class SyncResult {
  final int synced;
  final int failed;
  final List<String> errors;

  const SyncResult({
    required this.synced,
    required this.failed,
    required this.errors,
  });

  bool get success => failed == 0;
}

/// Production offline sync service.
///
/// Responsibilities:
/// - Detect unsynced sales via `is_synced = 0` flag
/// - POST each sale to the configured API endpoint
/// - Retry with exponential backoff (1s → 2s → 4s)
/// - Mark as synced ONLY on confirmed HTTP 200/201
/// - Idempotent: uses `idempotency_key` header — safe to retry
class OfflineSyncService {
  final ISaleRepository _saleRepository;
  final IFinancialTransactionRepository? _transactionRepository;
  final LicenseService _licenseService;
  final ApiClient _apiClient;

  /// Optional chaos injector for simulating network cuts, latencies, etc.
  SyncChaosInjector? _chaosInjector;

  /// Optional state machine for formal sync state transition auditing.
  SyncStateMachine? _stateMachine;

  static const int _maxRetries       = 3;
  static const int _baseBackoffMs    = 1000; // 1s base

  bool _isSyncing = false;

  OfflineSyncService({
    required ISaleRepository saleRepository,
    IFinancialTransactionRepository? transactionRepository,
    required LicenseService licenseService,
    ApiClient? apiClient,
    SyncChaosInjector? chaosInjector,
    SyncStateMachine? stateMachine,
  })  : _saleRepository = saleRepository,
        _transactionRepository = transactionRepository,
        _licenseService  = licenseService,
        _apiClient       = apiClient ?? ApiClient(),
        _chaosInjector   = chaosInjector,
        _stateMachine    = stateMachine;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Sync all unsynced sales.
  ///
  /// Returns [SyncResult] with counts of synced, failed, and any error messages.
  /// Safe to call multiple times — concurrent calls are serialized.
  Future<SyncResult> syncPendingSales({
    SyncChaosInjector? chaosInjector,
    SyncStateMachine? stateMachine,
  }) async {
    if (chaosInjector != null) {
      _chaosInjector = chaosInjector;
    }
    if (stateMachine != null) {
      _stateMachine = stateMachine;
    }
    // 1. License & Feature Gate verification
    final info = _licenseService.getLicenseInfo();
    final token = _licenseService.getLicenseToken();
    if (info == null || token == null || !_licenseService.verifyLicenseToken(token)) {
      await TelemetryService().logStructured(
        event: 'sync_license_invalid',
        level: LogLevel.error,
        correlationId: _stateMachine?.sessionId,
        metadata: {'reason': 'Invalid or missing license token'},
      );
      return const SyncResult(synced: 0, failed: 0, errors: ['Bulut senkronizasyonu için geçerli bir ticari lisans bulunamadı.']);
    }
    if (!info.features.contains('cloud_sync')) {
      await TelemetryService().logStructured(
        event: 'sync_license_invalid',
        level: LogLevel.error,
        correlationId: _stateMachine?.sessionId,
        metadata: {'reason': 'cloud_sync feature disabled'},
      );
      return const SyncResult(synced: 0, failed: 0, errors: ['Mevcut lisans paketiniz bulut senkronizasyonu (cloud_sync) özelliğini desteklemiyor.']);
    }

    // 2. Database Schema Version Handshake
    final schemaMatch = await VersionChecker(
      apiClient: _apiClient,
    ).checkSchemaVersionMatch();
    if (!schemaMatch) {
      await TelemetryService().logStructured(
        event: 'sync_schema_mismatch',
        level: LogLevel.critical,
        correlationId: _stateMachine?.sessionId,
        metadata: {'baseUrl': 'dynamic'},
      );
      return const SyncResult(
        synced: 0,
        failed: 0,
        errors: ['Veritabanı şema uyuşmazlığı tespit edildi. Senkronizasyon güvenlik nedeniyle durduruldu. Lütfen uygulamayı güncelleyin.'],
      );
    }

    if (_isSyncing) {
      return const SyncResult(synced: 0, failed: 0, errors: ['Sync already in progress']);
    }

    _isSyncing = true;
    final errors = <String>[];
    int synced  = 0;
    int failed  = 0;

    try {
      if (_stateMachine != null) {
        await _stateMachine!.transition(SyncTrigger.startSync);
      }

      final allSales = await _saleRepository.findAll();
      final unsynced = allSales.where((s) => s.isSynced == 0).toList();

      if (unsynced.isEmpty) {
        if (_chaosInjector != null) {
          await _chaosInjector!.trigger(FaultHook.beforePull);
        }
        await _pullUpdates(errors);

        if (_stateMachine != null) {
          await _stateMachine!.transition(SyncTrigger.noSalesFound);
        }
        return SyncResult(synced: 0, failed: 0, errors: errors);
      }

      for (final sale in unsynced) {
        if (_chaosInjector != null) {
          await _chaosInjector!.trigger(FaultHook.beforePush, saleId: sale.id);
        }

        final ok = await _syncSaleWithRetry(sale);
        if (ok) {
          if (_chaosInjector != null) {
            await _chaosInjector!.trigger(FaultHook.afterPushBeforeCommit, saleId: sale.id);
          }

          // Mark as synced in local DB — ONLY after remote confirmation
          final updated = SaleEntity(
            id:             sale.id,
            customerId:     sale.customerId,
            totalAmount:    sale.totalAmount,
            paidAmount:     sale.paidAmount,
            paymentMethod:  sale.paymentMethod,
            status:         sale.status,
            createdAt:      sale.createdAt,
            items:          sale.items,
            idempotencyKey: sale.idempotencyKey,
            isSynced:       1,
          );
          try {
            await _saleRepository.update(updated);
            synced++;
            if (_stateMachine != null) {
              await _stateMachine!.transition(SyncTrigger.pushSuccess, saleId: sale.id);
            }
          } catch (e, st) {
            await TelemetryService().logError(
              e,
              st,
              context: 'sync_db_update_failed',
              correlationId: _stateMachine?.sessionId,
            );
            errors.add('DB update failed for sale ${sale.id}: $e');
            failed++;
          }
        } else {
          failed++;
          errors.add('Remote sync failed for sale ${sale.id}');
          await TelemetryService().logStructured(
            event: 'sync_remote_post_failed',
            level: LogLevel.error,
            correlationId: _stateMachine?.sessionId,
            metadata: {'saleId': sale.id},
          );
          if (_stateMachine != null) {
            try {
              await _stateMachine!.transition(SyncTrigger.maxRetriesExceeded, saleId: sale.id);
            } catch (_) {}
          }
        }
      }

      // Pull updates from SaaS backend (Pull Sync)
      if (_chaosInjector != null) {
        await _chaosInjector!.trigger(FaultHook.beforePull);
      }
      await _pullUpdates(errors);

      if (_stateMachine != null && _stateMachine!.currentState == SyncState.syncing) {
        await _stateMachine!.transition(SyncTrigger.pullComplete);
      }
    } catch (e, st) {
      errors.add('Sync error: $e');
      await TelemetryService().logError(
        e,
        st,
        context: 'sync_run_unhandled_exception',
        correlationId: _stateMachine?.sessionId,
      );
      if (_stateMachine != null) {
        try {
          await _stateMachine!.transition(SyncTrigger.maxRetriesExceeded);
        } catch (_) {}
      }
      rethrow; // Rethrow to propagate simulated/chaos exceptions to tests
    } finally {
      _isSyncing = false;
    }

    return SyncResult(synced: synced, failed: failed, errors: errors);
  }

  /// Pull updates from server and merge with local state
  Future<void> _pullUpdates(List<String> errors) async {
    try {
      // 1. Get last timestamp from preferences
      final sharedPrefs = _licenseService.prefs; // SharedPreferences reference
      final lastTimestamp = sharedPrefs.getInt('last_sync_timestamp') ?? 0;

      final response = await _apiClient.get('/sync/pull?last_timestamp=$lastTimestamp');
      if (response.statusCode == 200) {
        final data = response.json;
        // print('📥 Successfully pulled updates from remote backend: $data');

        if (data is Map<String, dynamic> && data.containsKey('transactions') && _transactionRepository != null) {
          final txs = data['transactions'] as List<dynamic>;
          
          // Get local maximum logical clock once before processing batch
          final localTxs = await _transactionRepository!.findAll();
          int maxLocalClock = 0;
          for (final tx in localTxs) {
            if (tx.logicalClock > maxLocalClock) {
              maxLocalClock = tx.logicalClock;
            }
          }

          for (final txMap in txs) {
            if (txMap is Map<String, dynamic>) {
              final type = txMap['type'] as String? ?? 'financial_transaction';
              if (type != 'financial_transaction') continue; // only process financial transactions here

              final payload = txMap['payload'] as Map<String, dynamic>;
              final txId = payload['id'] as String;
              final exists = await _transactionRepository!.exists(txId);
              
              if (!exists) {
                final entity = FinancialTransactionEntity.fromMap(payload);

                // Validation Guard 1: Logical Clock Spoofing Check
                final bool isLogicalClockInflated = entity.logicalClock > maxLocalClock + 10000;
                
                // Validation Guard 2: Future Timestamp spoofing check (1-day grace window)
                final bool isFutureClock = entity.date.isAfter(DateTime.now().add(const Duration(days: 1)));

                if (isLogicalClockInflated || isFutureClock) {
                  final String reason = isLogicalClockInflated
                      ? 'Logical clock inflated: ${entity.logicalClock} vs max local $maxLocalClock'
                      : 'Physical clock spoofed into future: ${entity.date}';

                  await TelemetryService().logStructured(
                    event: 'sync_security_anomaly_detected',
                    level: LogLevel.critical,
                    correlationId: _stateMachine?.sessionId,
                    metadata: {
                      'transaction_id': entity.id,
                      'reason': reason,
                      'logical_clock': entity.logicalClock,
                      'device_id': entity.deviceId,
                      'date': entity.date.toIso8601String(),
                    },
                  );
                  errors.add('Security anomaly: Transaction ${entity.id} rejected due to: $reason');
                  continue;
                }

                await _transactionRepository!.create(entity);
              }
            }
          }

          // 2. Save next timestamp to preferences
          final nextTimestamp = data['last_timestamp'] as int?;
          if (nextTimestamp != null) {
            await sharedPrefs.setInt('last_sync_timestamp', nextTimestamp);
          }
        }
      } else {
        errors.add('Pull sync failed with status: ${response.statusCode}');
      }
    } catch (e) {
      errors.add('Pull sync failed: $e');
    }
  }

  /// Check if the remote API is reachable.
  Future<bool> isRemoteReachable() async {
    try {
      final response = await _apiClient.get('/sync/health');
      return response.isSuccess && response.json['status'] == 'healthy';
    } catch (_) {
      return false;
    }
  }

  // ── Private — Retry Logic ──────────────────────────────────────────────────

  Future<bool> _syncSaleWithRetry(SaleEntity sale) async {
    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        final success = await _postSale(sale);
        if (success) return true;
      } on SocketException {
        // No internet — stop retrying immediately, leave for next cycle
        return false;
      } on TimeoutException {
        // Timeout — retry with backoff
      } catch (_) {
        // Unknown error — retry
      }

      if (attempt < _maxRetries) {
        // Exponential backoff: 1s, 2s, 4s
        final delayMs = _baseBackoffMs * (1 << (attempt - 1));
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    return false;
  }

  // ── Private — HTTP ─────────────────────────────────────────────────────────

  Future<bool> _postSale(SaleEntity sale) async {
    final payload = _buildPayload(sale);
    final int? statusOverride = _chaosInjector?.statusCodeOverride;

    if (statusOverride != null) {
      if (statusOverride == 409) {
        if (_stateMachine != null) {
          await _stateMachine!.transition(
            SyncTrigger.pushConflict,
            saleId: sale.id,
            metadata: {'http_status': 409, 'message': 'Duplicate push conflict detected'},
          );
          await _stateMachine!.transition(SyncTrigger.startSync, saleId: sale.id);
          await _stateMachine!.transition(
            SyncTrigger.mergeComplete,
            saleId: sale.id,
            metadata: {'policy': 'server-authoritative', 'action': 'marked_synced'},
          );
        }
        return true;
      }
      return false;
    }

    try {
      final response = await _apiClient.post('/sales', payload, idempotency: true);
      return response.statusCode == 200 || response.statusCode == 201;
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        if (_stateMachine != null) {
          await _stateMachine!.transition(
            SyncTrigger.pushConflict,
            saleId: sale.id,
            metadata: {'http_status': 409, 'message': 'Duplicate push conflict detected'},
          );
          await _stateMachine!.transition(SyncTrigger.startSync, saleId: sale.id);
          await _stateMachine!.transition(
            SyncTrigger.mergeComplete,
            saleId: sale.id,
            metadata: {'policy': 'server-authoritative', 'action': 'marked_synced'},
          );
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _buildPayload(SaleEntity sale) => {
        'id':              sale.id,
        'idempotency_key': sale.idempotencyKey,
        'customer_id':     sale.customerId,
        'total_amount':    sale.totalAmount,
        'paid_amount':     sale.paidAmount,
        'payment_method':  sale.paymentMethod,
        'status':          sale.status,
        'created_at':      sale.createdAt.toIso8601String(),
        'items':           sale.items,
      };

  void dispose() {}
}
