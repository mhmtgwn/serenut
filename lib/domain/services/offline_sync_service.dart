// lib/domain/services/offline_sync_service.dart
// Serenut POS — Offline Sync Service (Production Implementation)
// Real HTTP with exponential backoff, idempotent uploads, and sync queue
// Updated: 24 Jun 2026

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/services/version_checker.dart';
import 'package:serenutos/domain/services/trial_manager.dart';

import 'package:serenutos/domain/services/sync_chaos_injector.dart';
import 'package:serenutos/domain/services/sync_state_machine.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:sqflite/sqflite.dart';

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
  final TrialManager? _trialManager;
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
    TrialManager? trialManager,
    ApiClient? apiClient,
    SyncChaosInjector? chaosInjector,
    SyncStateMachine? stateMachine,
  })  : _saleRepository = saleRepository,
        _transactionRepository = transactionRepository,
        _licenseService  = licenseService,
        _trialManager    = trialManager,
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
    final isTrial = _trialManager?.isTrialActive() ?? false;
    if (!isTrial) {
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

      // İSTEK 3 DÜZELTMESİ: findAll().where(isSynced==0) yerine findUnsynced() SQL filtresi.
      // Sadece bekleyen satışlar çekilir; tüm satış geçmişi RAM'e yüklenmiyor.
      final unsynced = await _saleRepository.findUnsynced();

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

        if (data is Map<String, dynamic> && data.containsKey('transactions')) {
          final txs = data['transactions'] as List<dynamic>;
          final db = await DatabaseManager().getDatabase();
          final affectedCustomerIds = <String>{};
          
          // YÜKSEK A DÜZELTMESİ: findAll() + döngü (O(n) RAM) yerine tek SQL MAX() sorgusu.
          // Önceki kod: tüm yerel transaction listesini RAM'e çekip döngüyle max'ı arıyordu.
          // Yeni kod: getMaxLogicalClock() → SELECT MAX(logical_clock) FROM financial_transactions
          int maxLocalClock = 0;
          if (_transactionRepository != null) {
            maxLocalClock = await _transactionRepository!.getMaxLogicalClock();
          }

          for (final txMap in txs) {
            if (txMap is Map<String, dynamic>) {
              final type = txMap['type'] as String? ?? 'financial_transaction';
              final payload = txMap['payload'] as Map<String, dynamic>;
              final id = payload['id'] as String;

              if (type == 'product') {
                await db.insert(
                  'products',
                  {
                    'id': payload['id'],
                    'name': payload['name'],
                    'barcode': payload['barcode'],
                    'price': payload['price'] != null ? (payload['price'] as num).toDouble() : 0.0,
                    'cost': payload['cost'] != null ? (payload['cost'] as num).toDouble() : 0.0,
                    'vat_rate': payload['vat_rate'] != null ? (payload['vat_rate'] as num).toDouble() : 0.0,
                    'category': payload['category'],
                    'image_url': payload['image_url'],
                    'stock': payload['stock'] != null ? (payload['stock'] as num).toInt() : 0,
                    'is_deleted': (payload['is_deleted'] == true || payload['is_deleted'] == 1) ? 1 : 0,
                    'created_at': payload['created_at'],
                    'updated_at': payload['updated_at'],
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
              } else if (type == 'customer') {
                final customerId = payload['id'] as String?;
                if (customerId != null && customerId.isNotEmpty) {
                  affectedCustomerIds.add(customerId);
                }
                await db.insert(
                  'customers',
                  {
                    'id': payload['id'],
                    'name': payload['name'],
                    'email': payload['email'],
                    'phone': payload['phone'],
                    'balance': payload['balance'] != null ? (payload['balance'] as num).toDouble() : 0.0,
                    'is_deleted': (payload['is_deleted'] == true || payload['is_deleted'] == 1) ? 1 : 0,
                    'created_at': payload['created_at'],
                    'updated_at': payload['updated_at'],
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
              } else if (type == 'sale') {
                await db.insert(
                  'sales',
                  {
                    'id': payload['id'],
                    'customer_id': payload['customer_id'],
                    'total_amount': payload['total_amount'] != null ? (payload['total_amount'] as num).toDouble() : 0.0,
                    'paid_amount': payload['paid_amount'] != null ? (payload['paid_amount'] as num).toDouble() : 0.0,
                    'payment_method': payload['payment_method'],
                    'status': payload['status'],
                    'created_at': payload['created_at'],
                    'updated_at': payload['updated_at'],
                    'idempotency_key': payload['idempotency_key'],
                    'is_synced': 1,
                    'created_by': payload['created_by'],
                    'is_deleted': (payload['is_deleted'] == true || payload['is_deleted'] == 1) ? 1 : 0,
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );

                if (payload['items'] != null) {
                  final items = payload['items'] as List<dynamic>;
                  await db.delete('sale_items', where: 'sale_id = ?', whereArgs: [payload['id']]);
                  
                  for (final item in items) {
                    if (item is Map<String, dynamic>) {
                      await db.insert(
                        'sale_items',
                        {
                          'id': item['id'] ?? 'si-${payload['id']}-${item['product_id'] ?? item['productId']}',
                          'sale_id': payload['id'],
                          'product_id': item['product_id'] ?? item['productId'],
                          'quantity': item['quantity'] != null ? (item['quantity'] as num).toDouble() : (item['qty'] != null ? (item['qty'] as num).toDouble() : 0.0),
                          'unit_price': item['unit_price'] != null ? (item['unit_price'] as num).toDouble() : (item['unitPrice'] != null ? (item['unitPrice'] as num).toDouble() : 0.0),
                          'total_price': item['total_price'] != null ? (item['total_price'] as num).toDouble() : 0.0,
                        },
                        conflictAlgorithm: ConflictAlgorithm.replace,
                      );
                    }
                  }
                }
              } else if (type == 'financial_transaction') {
                final customerId = payload['customer_id'] as String?;
                if (customerId != null && customerId.isNotEmpty) {
                  affectedCustomerIds.add(customerId);
                }
                if (_transactionRepository != null) {
                  final exists = await _transactionRepository!.exists(id);
                  
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
            }
          }

          if (affectedCustomerIds.isNotEmpty) {
            await db.transaction((txn) async {
              for (final customerId in affectedCustomerIds) {
                final expectedResult = await txn.rawQuery(DatabaseManager.customerBalanceSql, [customerId]);
                
                final expectedBalance = (expectedResult.first['expected'] as num?)?.toDouble() ?? 0.0;
                await txn.update(
                  'customers',
                  {'balance': expectedBalance},
                  where: 'id = ?',
                  whereArgs: [customerId],
                );
                
                await TelemetryService().logStructured(
                  event: 'sync_customer_balance_updated',
                  level: LogLevel.info,
                  correlationId: _stateMachine?.sessionId,
                  metadata: {
                    'customerId': customerId,
                    'balance': expectedBalance,
                  },
                );
              }
            });
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
      debugPrint('[OfflineSync] ❌ ApiException pushing sale (ID: ${sale.id}, local method: ${sale.paymentMethod}, mapped: ${payload['payment_method']}): status=${e.statusCode}, body=${e.responseBody}, msg=${e.message}');
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
    } catch (err) {
      debugPrint('[OfflineSync] ❌ Unhandled error pushing sale: $err');
      return false;
    }
  }

  Map<String, dynamic> _buildPayload(SaleEntity sale) {
    String serverPaymentMethod = sale.paymentMethod;
    if (!['cash', 'card', 'credit', 'debt', 'mixed'].contains(serverPaymentMethod)) {
      if (serverPaymentMethod == 'karma') {
        serverPaymentMethod = 'mixed';
      } else {
        serverPaymentMethod = 'cash';
      }
    }

    return {
      'id':              sale.id,
      'idempotencyKey':  sale.idempotencyKey,
      'customerId':      sale.customerId,
      'totalAmount':     sale.totalAmount,
      'paidAmount':      sale.paidAmount,
      'paymentMethod':   serverPaymentMethod,
      'status':          sale.status,
      'createdAt':       sale.createdAt.toIso8601String(),
      'items':           sale.items.map((item) {
        if (item is Map<String, dynamic>) {
          return {
            'productId': item['product_id'],
            'qty': item['quantity'] ?? item['qty'],
            'unitPrice': item['unit_price'] ?? item['unitPrice'],
          };
        }
        return item;
      }).toList(),
    };
  }

  void dispose() {}
}
