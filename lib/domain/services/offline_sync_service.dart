// lib/domain/services/offline_sync_service.dart
// Serenut OS — Offline Sync Service (Production Implementation)
// Real HTTP with exponential backoff, idempotent uploads, and sync queue
// Updated: 24 Jun 2026

import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/services/version_checker.dart';
import 'package:serenutos/domain/services/trial_manager.dart';

import 'package:serenutos/domain/services/sync_chaos_injector.dart';
import 'package:serenutos/domain/services/sync_state_machine.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/domain/services/hash_validation_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/config/utils.dart';

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

  static const int _maxRetries = 3;
  static const int _baseBackoffMs = 1000; // 1s base

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
        _licenseService = licenseService,
        _trialManager = trialManager,
        _apiClient = apiClient ?? ApiClient(),
        _chaosInjector = chaosInjector,
        _stateMachine = stateMachine;

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
      if (info == null ||
          token == null ||
          !_licenseService.verifyLicenseToken(token)) {
        await TelemetryService().logStructured(
          event: 'sync_license_invalid',
          level: LogLevel.error,
          correlationId: _stateMachine?.sessionId,
          metadata: {'reason': 'Invalid or missing license token'},
        );
        return const SyncResult(synced: 0, failed: 0, errors: [
          'Bulut senkronizasyonu için geçerli bir ticari lisans bulunamadı.'
        ]);
      }
      if (!info.features.contains('cloud_sync')) {
        await TelemetryService().logStructured(
          event: 'sync_license_invalid',
          level: LogLevel.error,
          correlationId: _stateMachine?.sessionId,
          metadata: {'reason': 'cloud_sync feature disabled'},
        );
        return const SyncResult(synced: 0, failed: 0, errors: [
          'Mevcut lisans paketiniz bulut senkronizasyonu (cloud_sync) özelliğini desteklemiyor.'
        ]);
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
        errors: [
          'Veritabanı şema uyuşmazlığı tespit edildi. Senkronizasyon güvenlik nedeniyle durduruldu. Lütfen uygulamayı güncelleyin.'
        ],
      );
    }

    if (_isSyncing) {
      return const SyncResult(
          synced: 0, failed: 0, errors: ['Sync already in progress']);
    }

    _isSyncing = true;
    final errors = <String>[];
    int synced = 0;
    int failed = 0;

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

        final syncRes = await _syncSaleWithRetry(sale);
        if (syncRes.success) {
          if (_chaosInjector != null) {
            await _chaosInjector!
                .trigger(FaultHook.afterPushBeforeCommit, saleId: sale.id);
          }

          // Mark as synced in local DB — ONLY after remote confirmation
          final updated = SaleEntity(
            id: sale.id,
            customerId: sale.customerId,
            totalAmount: sale.totalAmount,
            paidAmount: sale.paidAmount,
            paymentMethod: sale.paymentMethod,
            status: sale.status,
            createdAt: sale.createdAt,
            items: sale.items,
            idempotencyKey: sale.idempotencyKey,
            isSynced: 1,
          );
          try {
            await _saleRepository.update(updated);
            synced++;
            if (_stateMachine != null) {
              await _stateMachine!
                  .transition(SyncTrigger.pushSuccess, saleId: sale.id);
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
          errors.add(
              'Remote sync failed for sale ${sale.id}: ${syncRes.errorMessage}');

          // Mark as poison record (failed) in local DB
          final updated = SaleEntity(
            id: sale.id,
            customerId: sale.customerId,
            totalAmount: sale.totalAmount,
            paidAmount: sale.paidAmount,
            paymentMethod: sale.paymentMethod,
            status: sale.status,
            createdAt: sale.createdAt,
            items: sale.items,
            idempotencyKey: sale.idempotencyKey,
            isSynced: syncRes.isPermanent ? -1 : 0,
          );
          try {
            await _saleRepository.update(updated);

            if (syncRes.isPermanent) {
              // Only validation/mapping failures belong in the DLQ. Network,
              // throttling and server failures remain pending for a later run.
              final db = await DatabaseManager().getDatabase();
              await db.insert('failed_push_log', {
                'id': const Uuid().v4(),
                'sale_id': sale.id,
                'error_message': syncRes.errorMessage,
                'attempt_count': _maxRetries,
                'last_attempt_at': DateTime.now().toIso8601String(),
                'next_retry_at': DateTime.now()
                    .add(const Duration(hours: 1))
                    .toIso8601String(),
                'resolved': 0,
              });
            }
          } catch (e) {
            debugPrint('[OfflineSync] Error writing to DLQ: $e');
          }

          await TelemetryService().logStructured(
            event: 'sync_remote_post_failed',
            level: LogLevel.error,
            correlationId: _stateMachine?.sessionId,
            metadata: {
              'saleId': sale.id,
              'error': syncRes.errorMessage,
            },
          );
          if (_stateMachine != null) {
            try {
              await _stateMachine!
                  .transition(SyncTrigger.maxRetriesExceeded, saleId: sale.id);
            } catch (_) {}
          }
        }
      }

      // Pull updates from SaaS backend (Pull Sync)
      if (_chaosInjector != null) {
        await _chaosInjector!.trigger(FaultHook.beforePull);
      }
      await _pullUpdates(errors);

      if (_stateMachine != null &&
          _stateMachine!.currentState == SyncState.syncing) {
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
      final sharedPrefs = _licenseService.prefs;
      final lastTimestamp = sharedPrefs.getInt('last_sync_timestamp') ?? 0;

      int maxLocalClock = 0;
      if (_transactionRepository != null) {
        maxLocalClock = await _transactionRepository!.getMaxLogicalClock();
      }

      final db = await DatabaseManager().getDatabase();
      final affectedCustomerIds = <String>{};

      bool hasMore = true;
      int currentTimestamp = lastTimestamp;

      while (hasMore) {
        final response = await _apiClient
            .get('/sync/pull?last_timestamp=$currentTimestamp&limit=500');
        if (response.statusCode != 200) {
          errors.add('Pull sync failed with status: ${response.statusCode}');
          break;
        }

        final data = response.json;
        if (data is! Map<String, dynamic> ||
            !data.containsKey('transactions')) {
          break;
        }

        final txs = data['transactions'] as List<dynamic>;
        if (txs.isEmpty) {
          break;
        }

        // Sort to enforce dependency order: product -> customer -> sale -> financial_transaction
        txs.sort((a, b) {
          final tA =
              a is Map<String, dynamic> ? (a['type'] as String? ?? '') : '';
          final tB =
              b is Map<String, dynamic> ? (b['type'] as String? ?? '') : '';

          int weight(String type) {
            switch (type) {
              case 'product':
                return 1;
              case 'customer':
                return 2;
              case 'sale':
                return 3;
              case 'financial_transaction':
                return 4;
              default:
                return 5;
            }
          }

          return weight(tA).compareTo(weight(tB));
        });

        await db.transaction((txn) async {
          for (final txMap in txs) {
            if (txMap is Map<String, dynamic>) {
              final type = txMap['type'] as String? ?? 'financial_transaction';
              final payload = txMap['payload'] as Map<String, dynamic>;
              final id = payload['id'] as String;

              if (type == 'product') {
                await txn.insert(
                  'products',
                  {
                    'id': payload['id'],
                    'name': payload['name'],
                    'barcode': payload['barcode'],
                    'price': payload['price'] != null
                        ? (payload['price'] as num).toDouble()
                        : 0.0,
                    'cost': payload['cost'] != null
                        ? (payload['cost'] as num).toDouble()
                        : 0.0,
                    'vat_rate': payload['vat_rate'] != null
                        ? (payload['vat_rate'] as num).toDouble()
                        : (payload['vat'] != null
                            ? (payload['vat'] as num).toDouble()
                            : 0.0),
                    'category': payload['category'],
                    'image_url': payload['image_url'] ?? payload['image_path'],
                    'stock': payload['stock'] != null
                        ? (payload['stock'] as num).toInt()
                        : (payload['quantity'] != null
                            ? (payload['quantity'] as num).toInt()
                            : 0),
                    'is_deleted': (payload['is_deleted'] == true ||
                            payload['is_deleted'] == 1)
                        ? 1
                        : 0,
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
                await txn.insert(
                  'customers',
                  {
                    'id': payload['id'],
                    'name': payload['name'],
                    'normalized_name':
                        (payload['name'] as String? ?? '').normalizeTurkish,
                    'email': payload['email'],
                    'normalized_email':
                        (payload['email'] as String? ?? '').toLowerCase(),
                    'phone': payload['phone'],
                    'balance': payload['balance'] != null
                        ? (payload['balance'] as num).toDouble()
                        : 0.0,
                    'is_deleted': (payload['is_deleted'] == true ||
                            payload['is_deleted'] == 1)
                        ? 1
                        : 0,
                    'created_at': payload['created_at'],
                    'updated_at': payload['updated_at'],
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
              } else if (type == 'sale') {
                // Dependency quarantine check: Parent customer must exist
                final customerId = payload['customer_id'] as String?;
                bool parentExists = true;
                if (customerId != null && customerId.isNotEmpty) {
                  final custCheck = await txn.query('customers',
                      where: 'id = ?', whereArgs: [customerId], limit: 1);
                  if (custCheck.isEmpty) {
                    parentExists = false;
                  }
                }
                if (!parentExists) {
                  errors.add(
                      'Parent customer $customerId not found for sale ${payload['id']}. Sale quarantined.');
                  continue;
                }

                // Immutable Transaction Logic (LWW uygulanmaz)
                final existingSale = await txn.query('sales',
                    where: 'id = ?', whereArgs: [payload['id']], limit: 1);
                if (existingSale.isNotEmpty) {
                  // Mevcut kaydın ve gelen payload'un Hash doğrulaması
                  final localVal = existingSale.first['total_amount'];
                  final remoteVal = payload['total_amount'] != null
                      ? (payload['total_amount'] as num).toDouble()
                      : 0.0;
                  // Basit hash/eşitlik kontrolü (Gerçek sistemde canonical hash compare yapılmalıdır)
                  if (localVal != remoteVal) {
                    await TelemetryService().logStructured(
                      event: 'sync_immutable_conflict_alarm',
                      level: LogLevel.critical,
                      metadata: {
                        'sale_id': payload['id'],
                        'local_amount': localVal,
                        'remote_amount': remoteVal,
                        'reason':
                            'Silent data corruption detected on immutable record.'
                      },
                    );
                    errors.add(
                        "Veri Uyuşmazlığı: ${payload['id']} ID'li satış kaydı değiştirilmeye çalışıldı. Quarantine'a alındı.");
                    // Dead-letter kuyruğuna atılabilir. Şimdilik ignore edip alarm üretiyoruz.
                  }
                  continue; // Her halükarda üzerine yazmıyoruz (Immutable)
                }

                await txn.insert(
                  'sales',
                  {
                    'id': payload['id'],
                    'customer_id': payload['customer_id'],
                    'total_amount': payload['total_amount'] != null
                        ? (payload['total_amount'] as num).toDouble()
                        : 0.0,
                    'paid_amount': payload['paid_amount'] != null
                        ? (payload['paid_amount'] as num).toDouble()
                        : 0.0,
                    'payment_method': payload['payment_method'],
                    'status': payload['status'],
                    'created_at': payload['created_at'],
                    'updated_at': payload['updated_at'],
                    'idempotency_key': payload['idempotency_key'],
                    'is_synced': 1,
                    'created_by': payload['created_by'],
                    'is_deleted': (payload['is_deleted'] == true ||
                            payload['is_deleted'] == 1)
                        ? 1
                        : 0,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );

                if (payload['items'] != null) {
                  final items = payload['items'] as List<dynamic>;

                  for (final item in items) {
                    if (item is Map<String, dynamic>) {
                      // Dependency check: Product must exist
                      final prodId = item['product_id'] ?? item['productId'];
                      final prodCheck = await txn.query('products',
                          where: 'id = ?', whereArgs: [prodId], limit: 1);
                      if (prodCheck.isEmpty) {
                        errors.add(
                            'Product $prodId not found for sale item. Item skipped.');
                        continue;
                      }

                      await txn.insert(
                        'sale_items',
                        {
                          'id': item['id'] ??
                              'si-${payload['id']}-${item['product_id'] ?? item['productId']}',
                          'sale_id': payload['id'],
                          'product_id': item['product_id'] ?? item['productId'],
                          'quantity': item['quantity'] != null
                              ? (item['quantity'] as num).toDouble()
                              : (item['qty'] != null
                                  ? (item['qty'] as num).toDouble()
                                  : 0.0),
                          'unit_price': item['unit_price'] != null
                              ? (item['unit_price'] as num).toDouble()
                              : (item['unitPrice'] != null
                                  ? (item['unitPrice'] as num).toDouble()
                                  : 0.0),
                          'total_price': item['total_price'] != null
                              ? (item['total_price'] as num).toDouble()
                              : 0.0,
                        },
                        conflictAlgorithm: ConflictAlgorithm.ignore,
                      );
                    }
                  }
                }
              } else if (type == 'financial_transaction') {
                final customerId = payload['customer_id'] as String?;
                bool parentExists = true;
                if (customerId != null && customerId.isNotEmpty) {
                  final custCheck = await txn.query('customers',
                      where: 'id = ?', whereArgs: [customerId], limit: 1);
                  if (custCheck.isEmpty) {
                    parentExists = false;
                  }
                }
                if (!parentExists) {
                  errors.add(
                      'Parent customer $customerId not found for transaction ${payload['id']}. Transaction quarantined.');
                  continue;
                }

                if (customerId != null && customerId.isNotEmpty) {
                  affectedCustomerIds.add(customerId);
                }

                final existing = await txn.query(
                  'financial_transactions',
                  where: 'id = ?',
                  whereArgs: [id],
                  limit: 1,
                );

                if (existing.isEmpty) {
                  final entity = FinancialTransactionEntity.fromMap(payload);

                  // Validation Guard 1: Logical Clock Spoofing Check
                  final bool isLogicalClockInflated =
                      entity.logicalClock > maxLocalClock + 10000;

                  // Validation Guard 2: Future Timestamp spoofing check (1-day grace window)
                  final bool isFutureClock = entity.date
                      .isAfter(DateTime.now().add(const Duration(days: 1)));

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
                    errors.add(
                        'Security anomaly: Transaction ${entity.id} rejected due to: $reason');
                    continue;
                  }

                  int nextClock = entity.logicalClock;
                  if (nextClock == 0) {
                    final result = await txn.rawQuery(
                        'SELECT MAX(logical_clock) as max_clock FROM financial_transactions');
                    final maxClock = Sqflite.firstIntValue(result) ?? 0;
                    nextClock = maxClock + 1;
                  }

                  final txDeviceId = entity.deviceId ?? 'unknown-device';

                  await txn.insert('financial_transactions', {
                    'id': entity.id,
                    'type': entity.type,
                    'customer_id': entity.customerId,
                    'amount': entity.amount,
                    'paid_amount': entity.paidAmount,
                    'debt_amount': entity.debtAmount,
                    'reference_id': entity.referenceId,
                    'metadata': entity.metadata != null
                        ? jsonEncode(entity.metadata)
                        : null,
                    'created_at': entity.date.toIso8601String(),
                    'logical_clock': nextClock,
                    'device_id': txDeviceId,
                  });
                }
              }
            }
          }

          if (affectedCustomerIds.isNotEmpty) {
            for (final customerId in affectedCustomerIds) {
              final expectedResult = await txn
                  .rawQuery(DatabaseManager.customerBalanceSql, [customerId]);

              final expectedBalance =
                  (expectedResult.first['expected'] as num?)?.toDouble() ?? 0.0;
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
          }
        });

        final nextTimestamp = data['last_timestamp'] as int?;
        if (nextTimestamp != null && nextTimestamp > currentTimestamp) {
          currentTimestamp = nextTimestamp;
          await sharedPrefs.setInt('last_sync_timestamp', nextTimestamp);
        } else {
          hasMore = false;
        }

        final serverHasMore = data['has_more'] as bool? ?? false;
        if (!serverHasMore) {
          hasMore = false;
          final serverChecksum = data['checksum'] as String?;
          if (serverChecksum != null) {
            final hashService = HashValidationService();
            final isMatch =
                await hashService.verifyChecksumMatch(serverChecksum);
            if (!isMatch) {
              errors.add(
                  'Veri tutarlılık hatası: Sunucu ve istemci checksum değerleri eşleşmiyor.');
            }
          }
        }
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

  Future<SaleSyncResult> _syncSaleWithRetry(SaleEntity sale) async {
    String lastError = 'Bilinmeyen hata';
    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        final success = await _postSale(sale);
        if (success) return const SaleSyncResult(true, '');
        lastError = 'Sunucu isteği başarısız oldu';
      } on SocketException catch (e) {
        // No internet — stop retrying immediately, leave for next cycle
        return SaleSyncResult(false, 'Bağlantı hatası: ${e.message}');
      } on TimeoutException catch (e) {
        lastError = 'Zaman aşımı: ${e.message}';
      } on ArgumentError catch (e) {
        debugPrint('[OfflineSync] ❌ Non-retryable mapping error: $e');
        return SaleSyncResult(false, 'Haritalama hatası: $e',
            isPermanent: true); // Stop retrying immediately
      } on ApiException catch (e) {
        lastError = 'API Hatası (${e.statusCode}): ${e.message}';
        // Permanent 4xx validation or auth errors (excluding 408/429) shouldn't be retried
        if (e.statusCode != null &&
            e.statusCode! >= 400 &&
            e.statusCode! < 500 &&
            e.statusCode! != 408 &&
            e.statusCode! != 429) {
          debugPrint(
              '[OfflineSync] ❌ Permanent client error (${e.statusCode}). Skipping retry.');
          return SaleSyncResult(false, lastError, isPermanent: true);
        }
        // Otherwise (5xx, 408, 429) retry
      } catch (err) {
        // Other unexpected errors — retry
        lastError = 'Beklenmeyen hata: $err';
        debugPrint('[OfflineSync] ❌ Unexpected retryable error: $err');
      }

      if (attempt < _maxRetries) {
        // Exponential backoff: 1s, 2s, 4s
        final delayMs = _baseBackoffMs * (1 << (attempt - 1));
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    return SaleSyncResult(false, lastError);
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
            metadata: {
              'http_status': 409,
              'message': 'Duplicate push conflict detected'
            },
          );
          await _stateMachine!
              .transition(SyncTrigger.startSync, saleId: sale.id);
          await _stateMachine!.transition(
            SyncTrigger.mergeComplete,
            saleId: sale.id,
            metadata: {
              'policy': 'server-authoritative',
              'action': 'marked_synced'
            },
          );
        }
        return true;
      }
      return false;
    }

    try {
      final response =
          await _apiClient.post('/sales', payload, idempotencyKey: sale.id);
      return response.statusCode == 200 || response.statusCode == 201;
    } on ApiException catch (e) {
      debugPrint(
          '[OfflineSync] ❌ ApiException pushing sale (ID: ${sale.id}, local method: ${sale.paymentMethod}, mapped: ${payload['paymentMethod']}): status=${e.statusCode}, body=${e.responseBody}, msg=${e.message}');
      if (e.statusCode == 409) {
        if (_stateMachine != null) {
          await _stateMachine!.transition(
            SyncTrigger.pushConflict,
            saleId: sale.id,
            metadata: {
              'http_status': 409,
              'message': 'Duplicate push conflict detected'
            },
          );
          await _stateMachine!
              .transition(SyncTrigger.startSync, saleId: sale.id);
          await _stateMachine!.transition(
            SyncTrigger.mergeComplete,
            saleId: sale.id,
            metadata: {
              'policy': 'server-authoritative',
              'action': 'marked_synced'
            },
          );
        }
        return true;
      }
      rethrow;
    }
  }

  Map<String, dynamic> _buildPayload(SaleEntity sale) {
    final String serverPaymentMethod = sale.paymentMethod.toLowerCase().trim();

    const methodMapping = {
      'cash': 'cash',
      'nakit': 'cash',
      'card': 'card',
      'kart': 'card',
      'credit': 'credit',
      'debt': 'credit',
      'veresiye': 'credit',
      'mixed': 'mixed',
      'karma': 'mixed',
    };

    final mapped = methodMapping[serverPaymentMethod];
    if (mapped == null) {
      throw ArgumentError(
          'Belirtilen ödeme yöntemi backend şemasına eşlenemedi (Geçersiz yöntem: ${sale.paymentMethod})');
    }

    return {
      'id': sale.id,
      'idempotencyKey': sale.idempotencyKey,
      'customerId': sale.customerId,
      'totalAmount': sale.totalAmount,
      'paidAmount': sale.paidAmount,
      'paymentMethod': mapped,
      'status': sale.status,
      'createdAt': sale.createdAt.toIso8601String(),
      'entitlement_snapshot': sale.entitlementSnapshot,
      'items': sale.items.map((item) {
        return {
          'productId': item['product_id'],
          'qty': item['quantity'] ?? item['qty'],
          'unitPrice': item['unit_price'] ?? item['unitPrice'],
        };
        return item;
      }).toList(),
    };
  }

  void dispose() {}
}

class SaleSyncResult {
  final bool success;
  final String errorMessage;
  final bool isPermanent;
  const SaleSyncResult(this.success, this.errorMessage,
      {this.isPermanent = false});
}
