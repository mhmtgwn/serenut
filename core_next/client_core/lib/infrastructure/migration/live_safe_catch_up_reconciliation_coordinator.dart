// core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart
// SERENUT OS — STAGE 10.12.46
// Canlı İşletme Kapsamlı Eşzamanlı Değişiklik Yakalama (Catch-Up) ve Mutabakat Koordinatörü

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';

/// Mutabakat Kararı
enum CutoverReconciliationDecision {
  cutoverApproved,
  cutoverBlockedConcurrentWrites,
  cutoverBlockedVarianceDetected,
  cutoverBlockedIntegrityError;
}

/// Ayrıntılı Değişiklik Yakalama İstatistikleri
class CatchUpStatistics {
  final int productsUpdated;
  final int customersUpdated;
  final int salesMigrated;
  final int saleItemsMigrated;
  final int ledgerEntriesMigrated;
  final int ordersMigrated;
  final int refundsMigrated;
  final int syncEventsMigrated;
  final int paymentsMigrated;
  final int totalCatchUpRecords;

  const CatchUpStatistics({
    this.productsUpdated = 0,
    this.customersUpdated = 0,
    this.salesMigrated = 0,
    this.saleItemsMigrated = 0,
    this.ledgerEntriesMigrated = 0,
    this.ordersMigrated = 0,
    this.refundsMigrated = 0,
    this.syncEventsMigrated = 0,
    this.paymentsMigrated = 0,
    this.totalCatchUpRecords = 0,
  });

  @override
  String toString() =>
      'CatchUpStatistics(Ürünler: $productsUpdated, Müşteriler: $customersUpdated, Satışlar: $salesMigrated, Kalemler: $saleItemsMigrated, Defter: $ledgerEntriesMigrated, İadeler: $refundsMigrated, Outbox: $syncEventsMigrated, Ödemeler: $paymentsMigrated, Toplam: $totalCatchUpRecords)';
}

/// Kapsamlı Mutabakat Raporu
class LiveReconciliationReport {
  final CutoverReconciliationDecision decision;
  final bool isMatched;
  final int legacySalesCount;
  final int coreSalesCount;
  final int legacyTotalSalesCents;
  final int coreTotalSalesCents;
  final double legacyStockSum;
  final double coreStockSum;
  final int legacyCustomerBalanceCents;
  final int coreCustomerBalanceCents;
  final int catchUpRecordsMigrated;
  final CatchUpStatistics statistics;
  final String details;

  const LiveReconciliationReport({
    required this.decision,
    required this.isMatched,
    required this.legacySalesCount,
    required this.coreSalesCount,
    required this.legacyTotalSalesCents,
    required this.coreTotalSalesCents,
    required this.legacyStockSum,
    required this.coreStockSum,
    required this.legacyCustomerBalanceCents,
    required this.coreCustomerBalanceCents,
    required this.catchUpRecordsMigrated,
    this.statistics = const CatchUpStatistics(),
    required this.details,
  });

  @override
  String toString() =>
      'LiveReconciliationReport(decision: $decision, matched: $isMatched, catchUp: $catchUpRecordsMigrated, details: $details)';
}

/// Defter Sıfır Tutar Onarım Sonucu
class LedgerRepairResult {
  final int totalScanned;
  final int repairedCount;
  final int preservedZeroCount;
  final int skippedAlreadyValidCount;
  final int conflictCount;
  final int totalRepairedVolumeCents;
  final List<String> repairDetails;
  final List<String> conflicts;

  const LedgerRepairResult({
    required this.totalScanned,
    required this.repairedCount,
    required this.preservedZeroCount,
    required this.skippedAlreadyValidCount,
    required this.conflictCount,
    required this.totalRepairedVolumeCents,
    required this.repairDetails,
    required this.conflicts,
  });

  @override
  String toString() =>
      'LedgerRepairResult(scanned: $totalScanned, repaired: $repairedCount, preservedZero: $preservedZeroCount, conflicts: $conflictCount, volume: ${totalRepairedVolumeCents / 100.0} TL)';
}

/// Canlı Eşzamanlı Yazma, Çoklu Tablo Catch-Up ve Mutabakat Koordinatörü
class LiveSafeCatchUpReconciliationCoordinator {
  const LiveSafeCatchUpReconciliationCoordinator();

  /// Authoritative kuruş tutarını güvenle çözer.
  ///
  /// Kurallar:
  /// 1. rawMinor == 0 ve rawAmount != 0 ise (unpopulated legacy default 0): rawAmount * 100 alınır.
  /// 2. rawMinor == 0 ve rawAmount == 0 ise: 0 kuruş (gerçek sıfır) korunur.
  /// 3. rawMinor == null ise: rawAmount * 100 güvenli fallback olarak alınır.
  /// 4. rawMinor != 0 ve beklenen değerle uyuşuyorsa: rawMinor kuruşu doğrudan alınır.
  static int resolveAmountCents(dynamic rawAmount, dynamic rawMinor) {
    final rawAmountNum = rawAmount is num
        ? rawAmount
        : (rawAmount != null ? num.tryParse(rawAmount.toString()) : null);
    final rawMinorNum = rawMinor is num
        ? rawMinor
        : (rawMinor != null ? num.tryParse(rawMinor.toString()) : null);

    final double expectedDouble = (rawAmountNum?.toDouble() ?? 0.0);
    final int expectedFromAmount = (expectedDouble * 100).round();

    if (rawMinorNum == null) {
      return expectedFromAmount;
    }

    final int minorCents = rawMinorNum.toInt();
    if (minorCents == expectedFromAmount) {
      return minorCents;
    }

    // Unpopulated legacy default column (DEFAULT 0)
    if (minorCents == 0 && expectedFromAmount != 0) {
      return expectedFromAmount;
    }

    // Minor cents explicitly provided while rawAmount is 0
    if (expectedFromAmount == 0 && minorCents != 0) {
      return minorCents;
    }

    return expectedFromAmount;
  }

  static int _resolveAmountCents(dynamic rawAmount, dynamic rawMinor) =>
      resolveAmountCents(rawAmount, rawMinor);

  static String _mapLegacyPaymentMethod(String? raw) {
    final method = (raw ?? 'cash').toString().toLowerCase().trim();
    if (method.contains('mixed') ||
        method.contains('karma') ||
        method.contains('split') ||
        method.contains('parcali')) {
      return 'mixed';
    } else if (method.contains('card') || method.contains('kart')) {
      return 'creditCard';
    } else if (method.contains('bank') ||
        method.contains('havale') ||
        method.contains('eft')) {
      return 'bankTransfer';
    } else if (method.contains('debt') ||
        method.contains('veresiye') ||
        method.contains('account') ||
        method.contains('vadeli')) {
      return 'onAccount';
    }
    return 'cash';
  }

  static int _parseTimestampMs(dynamic val) {
    if (val == null) return DateTime.now().millisecondsSinceEpoch;
    if (val is int) return val;
    if (val is num) return val.toInt();
    final str = val.toString().trim();
    if (str.isEmpty) return DateTime.now().millisecondsSinceEpoch;
    final numeric = int.tryParse(str);
    if (numeric != null) {
      if (numeric >= 1000000000 && numeric < 10000000000) {
        return numeric * 1000;
      }
      return numeric;
    }
    final parsed = DateTime.tryParse(str);
    if (parsed != null) {
      return parsed.millisecondsSinceEpoch;
    }
    final isoNormalized = DateTime.tryParse(str.replaceAll(' ', 'T'));
    if (isoNormalized != null) {
      return isoNormalized.millisecondsSinceEpoch;
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  static String _buildTimestampWhereClause(String col) {
    return "((typeof($col) == 'text' AND CAST($col AS INTEGER) >= ?) OR (typeof($col) == 'text' AND $col >= ?) OR (typeof($col) != 'text' AND $col >= ?) OR (strftime('%s', $col) IS NOT NULL AND CAST(strftime('%s', $col) AS INTEGER) * 1000 >= ?))";
  }

  static List<dynamic> _buildTimestampParams(int cutoff, String cutoffIso) {
    return [cutoff, cutoffIso, cutoff, cutoff];
  }

  static Future<T> _executeWithRetry<T>(
    Future<T> Function() action, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 50),
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await action();
      } catch (e) {
        attempt++;
        final errStr = e.toString().toLowerCase();
        final isBusyOrLocked = errStr.contains('busy') ||
            errStr.contains('locked') ||
            errStr.contains('code 5') ||
            errStr.contains('code 6');
        if (attempt >= maxRetries || !isBusyOrLocked) {
          rethrow;
        }
        await Future<void>.delayed(initialDelay * attempt);
      }
    }
  }

  static String _resolveSaleStatus(Map<String, dynamic> row) {
    if (row['is_deleted'] == 1) return 'CANCELLED';
    final fsm = row['fsm_state']?.toString().toUpperCase();
    final status = row['status']?.toString().toUpperCase();
    final effective = fsm ?? status ?? 'COMPLETED';
    if (effective.contains('CANCEL')) return 'CANCELLED';
    if (effective.contains('PARTIAL')) return 'PARTIALLY_REFUNDED';
    if (effective.contains('REFUND')) return 'REFUNDED';
    return 'COMPLETED';
  }

  /// Canlı veritabanındaki tüm yeni/güncellenen hareketleri Core Next'e aktarır ve kesin mutabakatı doğrular.
  Future<LiveReconciliationReport> performCatchUpAndReconcile({
    required Database legacyDb,
    required CoreAppDatabase targetCoreDb,
    required String legacyDbPath,
    int? lastMigrationCutoffTimestamp,
    bool persistCutoverStatus = true,
  }) async {
    int pUpdated = 0;
    int cUpdated = 0;
    int sMigrated = 0;
    int itemsMigrated = 0;
    int ledgerMigrated = 0;
    int ordersMigrated = 0;
    int refundsMigrated = 0;
    int syncEventsMigrated = 0;
    int paymentsMigrated = 0;

    final cutoff = lastMigrationCutoffTimestamp ?? 0;
    final cutoffIso = DateTime.fromMillisecondsSinceEpoch(cutoff).toIso8601String();
    final discrepanciesDetected = <String>[];

    // 1. Canlı WAL veya etkin yazma kontrolü
    final walFile = File('$legacyDbPath-wal');
    if (walFile.existsSync() && walFile.lengthSync() > 10 * 1024 * 1024) {
      debugPrint('[CatchUpCoordinator] ⚠️ Canlı WAL boyutu yüksek (${walFile.lengthSync()} bayt).');
    }

    // 2. KAPSAMLI DELTA YAKALAMA (CATCH-UP)

    // A) Ürünler & Stok Değişiklikleri (Monoton zaman damgası koruması ile)
    try {
      final legacyProdTable = await legacyDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='products'");
      if (legacyProdTable.isNotEmpty) {
        final prodColsInfo = await legacyDb.rawQuery('PRAGMA table_info(products);');
        final prodCols = prodColsInfo.map((c) => c['name'] as String).toSet();
        final hasUpdatedCol = prodCols.contains('updated_at');
        final hasCreatedCol = prodCols.contains('created_at');

        String? whereClause;
        List<dynamic>? params;
        if (hasUpdatedCol && hasCreatedCol) {
          whereClause = '(${_buildTimestampWhereClause('updated_at')} OR ${_buildTimestampWhereClause('created_at')})';
          params = [..._buildTimestampParams(cutoff, cutoffIso), ..._buildTimestampParams(cutoff, cutoffIso)];
        } else if (hasUpdatedCol) {
          whereClause = _buildTimestampWhereClause('updated_at');
          params = _buildTimestampParams(cutoff, cutoffIso);
        } else if (hasCreatedCol) {
          whereClause = _buildTimestampWhereClause('created_at');
          params = _buildTimestampParams(cutoff, cutoffIso);
        }

        final deltaProducts = whereClause != null
            ? await legacyDb.query('products', where: whereClause, whereArgs: params)
            : <Map<String, Object?>>[];
        if (deltaProducts.isNotEmpty) {
          debugPrint('[CatchUpCoordinator] 🔄 ${deltaProducts.length} adet yeni/güncellenen ürün yakalandı.');
          await _executeWithRetry(() => targetCoreDb.transaction((txn) async {
            for (final row in deltaProducts) {
              final rawId = (row['id'] ?? row['barcode'] ?? row['sku'])?.toString();
              if (rawId == null || rawId.isEmpty) continue;
              final barcode = (row['barcode'] ?? row['sku'] ?? rawId).toString();
              final name = row['name']?.toString() ?? 'İsimsiz Ürün';

              final priceCents = _resolveAmountCents(row['price'], row['price_minor']);
              final costCents = row['purchase_price_minor'] != null || row['purchase_price'] != null
                  ? _resolveAmountCents(row['purchase_price'], row['purchase_price_minor'])
                  : null;

              final stock = (row['stock_quantity'] ?? row['quantity'] ?? 0.0) as num;
              final vatRate = (row['vat'] ?? row['vat_rate'] ?? 20) as num;
              final isActive = (row['is_active'] as int? ?? 1);
              final isDeleted = (row['is_deleted'] as int? ?? 0);

              final updatedVal = hasUpdatedCol ? (row['updated_at'] ?? row['created_at']) : row['created_at'];
              final int updatedMs = _parseTimestampMs(updatedVal);

              final inserted = await txn.rawInsert('''
                INSERT INTO products (
                  id, barcode, name, price_cents, cost_price_cents, vat_rate, unit,
                  stock_quantity, critical_threshold, is_active, is_deleted, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, 'piece', ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  barcode = excluded.barcode,
                  name = excluded.name,
                  price_cents = excluded.price_cents,
                  cost_price_cents = excluded.cost_price_cents,
                  vat_rate = excluded.vat_rate,
                  stock_quantity = excluded.stock_quantity,
                  critical_threshold = excluded.critical_threshold,
                  is_active = excluded.is_active,
                  is_deleted = excluded.is_deleted,
                  updated_at = excluded.updated_at
                WHERE excluded.updated_at >= products.updated_at
              ''', [
                rawId,
                barcode,
                name,
                priceCents,
                costCents,
                vatRate.toInt(),
                stock.toDouble(),
                (row['min_stock'] as num? ?? 5).toDouble(),
                isActive,
                isDeleted,
                updatedMs,
              ]);
              if (inserted > 0) pUpdated++;
            }
          }));
        }
      }
    } catch (e) {
      debugPrint('[CatchUpCoordinator] Note on product catch-up: $e');
      discrepanciesDetected.add('Ürün delta aktarım hatası: $e');
    }

    // B) Müşteriler & Cari Defter Bakiyeleri (Monoton zaman damgası koruması ile)
    try {
      final legacyCustTable = await legacyDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='customers'");
      if (legacyCustTable.isNotEmpty) {
        final custColsInfo = await legacyDb.rawQuery('PRAGMA table_info(customers);');
        final custCols = custColsInfo.map((c) => c['name'] as String).toSet();
        final hasUpdatedCol = custCols.contains('updated_at');
        final hasCreatedCol = custCols.contains('created_at');

        String? whereClause;
        List<dynamic>? params;
        if (hasUpdatedCol && hasCreatedCol) {
          whereClause = '(${_buildTimestampWhereClause('updated_at')} OR ${_buildTimestampWhereClause('created_at')})';
          params = [..._buildTimestampParams(cutoff, cutoffIso), ..._buildTimestampParams(cutoff, cutoffIso)];
        } else if (hasUpdatedCol) {
          whereClause = _buildTimestampWhereClause('updated_at');
          params = _buildTimestampParams(cutoff, cutoffIso);
        } else if (hasCreatedCol) {
          whereClause = _buildTimestampWhereClause('created_at');
          params = _buildTimestampParams(cutoff, cutoffIso);
        }

        final deltaCusts = whereClause != null
            ? await legacyDb.query('customers', where: whereClause, whereArgs: params)
            : <Map<String, Object?>>[];
        if (deltaCusts.isNotEmpty) {
          debugPrint('[CatchUpCoordinator] 🔄 ${deltaCusts.length} adet yeni/güncellenen cari yakalandı.');
          await _executeWithRetry(() => targetCoreDb.transaction((txn) async {
            for (final row in deltaCusts) {
              var id = row['id']?.toString() ?? '';
              if (id.trim().isEmpty) id = 'customer-pesin-default';
              final name = row['name']?.toString() ?? 'İsimsiz Müşteri';
              final balanceCents = _resolveAmountCents(row['balance'], row['balance_minor']);

              final updatedVal = hasUpdatedCol ? (row['updated_at'] ?? row['created_at']) : row['created_at'];
              final int updatedMs = _parseTimestampMs(updatedVal);

              final phoneVal = (row['phone'] ?? row['phone_number'] ?? row['gsm'])?.toString();

              final inserted = await txn.rawInsert('''
                INSERT INTO customers (
                  id, name, phone, email, balance_cents, notes, is_active, is_deleted, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  name = excluded.name,
                  phone = excluded.phone,
                  email = excluded.email,
                  balance_cents = excluded.balance_cents,
                  notes = excluded.notes,
                  is_active = excluded.is_active,
                  is_deleted = excluded.is_deleted,
                  updated_at = excluded.updated_at
                WHERE excluded.updated_at >= customers.updated_at
              ''', [
                id,
                name,
                phoneVal,
                row['email']?.toString(),
                balanceCents,
                row['notes']?.toString(),
                (row['is_active'] as int? ?? 1),
                (row['is_deleted'] as int? ?? 0),
                updatedMs,
              ]);
              if (inserted > 0) cUpdated++;
            }
          }));
        }
      }
    } catch (e) {
      debugPrint('[CatchUpCoordinator] Note on customer catch-up: $e');
      discrepanciesDetected.add('Müşteri delta aktarım hatası: $e');
    }

    // C) Satışlar, Güncellemeler/İptaller ve Gerçek Ödeme Parçaları
    final caughtUpSaleIds = <String>[];
    try {
      final legacySaleTable = await legacyDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='sales'");
      if (legacySaleTable.isNotEmpty) {
        final saleColsInfo = await legacyDb.rawQuery('PRAGMA table_info(sales);');
        final saleCols = saleColsInfo.map((c) => c['name'] as String).toSet();
        final hasCreatedCol = saleCols.contains('created_at');
        final hasUpdatedCol = saleCols.contains('updated_at');

        String? whereClause;
        List<dynamic>? params;
        if (hasUpdatedCol && hasCreatedCol) {
          whereClause = '(${_buildTimestampWhereClause('updated_at')} OR ${_buildTimestampWhereClause('created_at')})';
          params = [..._buildTimestampParams(cutoff, cutoffIso), ..._buildTimestampParams(cutoff, cutoffIso)];
        } else if (hasUpdatedCol) {
          whereClause = _buildTimestampWhereClause('updated_at');
          params = _buildTimestampParams(cutoff, cutoffIso);
        } else if (hasCreatedCol) {
          whereClause = _buildTimestampWhereClause('created_at');
          params = _buildTimestampParams(cutoff, cutoffIso);
        }

        final deltaSales = whereClause != null
            ? await legacyDb.query('sales', where: whereClause, whereArgs: params)
            : await legacyDb.query('sales');

        if (deltaSales.isNotEmpty) {
          debugPrint('[CatchUpCoordinator] 🔄 ${deltaSales.length} adet yeni/güncellenen canlı satış yakalandı.');
          final legacySalePaymentsTable = await legacyDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='sale_payments'");

          await _executeWithRetry(() => targetCoreDb.transaction((txn) async {
            for (final row in deltaSales) {
              final saleId = row['id']?.toString() ?? '';
              if (saleId.isEmpty) continue;

              final totalCents = _resolveAmountCents(
                row['total_amount'] ?? row['total'],
                row['total_amount_minor'],
              );
              final paidCents = _resolveAmountCents(
                row['paid_amount'] ?? row['paid'] ?? (totalCents / 100.0),
                row['paid_amount_minor'],
              );
              final discountCents = _resolveAmountCents(
                row['discount_amount'] ?? row['discount'],
                row['discount_amount_minor'],
              );
              final debtCents = totalCents - paidCents;
              final status = _resolveSaleStatus(row);

              final createdAtVal = row['created_at'];
              final int createdAtMs = _parseTimestampMs(createdAtVal);

              final custId = row['customer_id']?.toString() ?? 'customer-pesin-default';
              // Yabancı anahtar bütünlüğü için cari kaydını güvenceye al
              await txn.insert('customers', {
                'id': custId,
                'name': 'Müşteri $custId',
                'balance_cents': 0,
                'is_active': 1,
                'is_deleted': 0,
                'updated_at': createdAtMs,
              }, conflictAlgorithm: ConflictAlgorithm.ignore);

              final receiptNo = (row['receipt_number'] ?? row['receipt_no'] ?? 'REC-$saleId').toString();

              final existingSales = await txn.query(
                'sales',
                columns: ['id', 'status', 'total_cents', 'paid_cents'],
                where: 'id = ?',
                whereArgs: [saleId],
              );
              final isNewSale = existingSales.isEmpty;
              final isModifiedSale = !isNewSale &&
                  (existingSales.first['status'] != status ||
                      (existingSales.first['total_cents'] as num?)?.toInt() != totalCents ||
                      (existingSales.first['paid_cents'] as num?)?.toInt() != paidCents);

              await txn.rawInsert('''
                INSERT INTO sales (
                  id, receipt_no, customer_id, subtotal_cents, discount_cents,
                  vat_total_cents, total_cents, paid_cents, debt_cents, status,
                  idempotency_key, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  receipt_no = excluded.receipt_no,
                  customer_id = excluded.customer_id,
                  subtotal_cents = excluded.subtotal_cents,
                  discount_cents = excluded.discount_cents,
                  vat_total_cents = excluded.vat_total_cents,
                  total_cents = excluded.total_cents,
                  paid_cents = excluded.paid_cents,
                  debt_cents = excluded.debt_cents,
                  status = CASE
                    WHEN sales.status IN ('CANCELLED', 'REFUNDED') AND excluded.status = 'COMPLETED' THEN sales.status
                    ELSE excluded.status
                  END,
                  idempotency_key = excluded.idempotency_key
              ''', [
                saleId,
                receiptNo,
                custId,
                totalCents + discountCents,
                discountCents,
                0,
                totalCents,
                paidCents,
                debtCents,
                status,
                row['idempotency_key']?.toString() ?? 'idem_$saleId',
                createdAtMs,
              ]);

              if (isNewSale || isModifiedSale) {
                sMigrated++;
                caughtUpSaleIds.add(saleId);
              }

              // Ödeme Parçaları: Gerçek sale_payments kayıtlarını koru ve doğrula
              bool hasStructuredPayments = false;
              if (legacySalePaymentsTable.isNotEmpty) {
                final spRows = await legacyDb.query(
                  'sale_payments',
                  where: 'sale_id = ?',
                  whereArgs: [saleId],
                );
                if (spRows.isNotEmpty) {
                  hasStructuredPayments = true;
                  int sumSpCents = 0;
                  for (final sp in spRows) {
                    final spId = (sp['id'] ?? '$saleId-pay-${sp['payment_type']}').toString();
                    final spType = _mapLegacyPaymentMethod(sp['payment_type']?.toString());
                    final spAmountCents = _resolveAmountCents(
                      sp['amount'],
                      sp['amount_minor'] ?? sp['amount_cents'],
                    );
                    sumSpCents += spAmountCents;

                    await txn.rawInsert('''
                      INSERT INTO sale_payments (
                        id, sale_id, payment_type, amount_cents, reference_note, created_at
                      ) VALUES (?, ?, ?, ?, ?, ?)
                      ON CONFLICT(id) DO UPDATE SET
                        payment_type = excluded.payment_type,
                        amount_cents = excluded.amount_cents,
                        reference_note = excluded.reference_note
                    ''', [
                      spId,
                      saleId,
                      spType,
                      spAmountCents,
                      sp['reference_note']?.toString(),
                      createdAtMs,
                    ]);
                    paymentsMigrated++;
                  }

                  // Finansal mutabakat kontrolü: Parçaların toplamı ile satış tahsilatı uyuşuyor mu?
                  if (status != 'CANCELLED' && (sumSpCents - paidCents).abs() > 1) {
                    discrepanciesDetected.add(
                      'Satış $saleId için gerçek ödeme parçaları toplamı ($sumSpCents kuruş) ile tahsil edilen tutar ($paidCents kuruş) uyuşmuyor!',
                    );
                  }
                }
              }

              // Yapısal ödeme tablosu yoksa veya boşsa: Güvenli tekil fallback
              if (!hasStructuredPayments) {
                final mappedPaymentType = _mapLegacyPaymentMethod(row['payment_method']?.toString());
                if (paidCents > 0) {
                  await txn.rawInsert('''
                    INSERT INTO sale_payments (
                      id, sale_id, payment_type, amount_cents, reference_note, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                      payment_type = excluded.payment_type,
                      amount_cents = excluded.amount_cents
                  ''', [
                    '$saleId-pay-legacy-paid',
                    saleId,
                    mappedPaymentType,
                    paidCents,
                    'Eski Satış Aktarımı (${row['payment_method']})',
                    createdAtMs,
                  ]);
                  paymentsMigrated++;
                }

                if (debtCents > 0) {
                  await txn.rawInsert('''
                    INSERT INTO sale_payments (
                      id, sale_id, payment_type, amount_cents, reference_note, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                      payment_type = excluded.payment_type,
                      amount_cents = excluded.amount_cents
                  ''', [
                    '$saleId-pay-legacy-debt',
                    saleId,
                    'onAccount',
                    debtCents,
                    'Eski Satış Vadeli Borç',
                    createdAtMs,
                  ]);
                  paymentsMigrated++;
                }
              }
            }
          }));

          // Satış Kalemleri (Sale Items)
          if (caughtUpSaleIds.isNotEmpty) {
            final legacyItemsTable = await legacyDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='sale_items'");
            if (legacyItemsTable.isNotEmpty) {
              final placeholders = List.filled(caughtUpSaleIds.length, '?').join(',');
              final items = await legacyDb.rawQuery('''
                SELECT id, sale_id, product_id, product_name, quantity, unit_price, subtotal, created_at
                FROM sale_items
                WHERE sale_id IN ($placeholders)
              ''', caughtUpSaleIds);

              if (items.isNotEmpty) {
                await _executeWithRetry(() => targetCoreDb.transaction((txn) async {
                  for (final item in items) {
                    final itemId = item['id']?.toString() ?? '';
                    final saleId = item['sale_id']?.toString() ?? '';
                    final prodId = item['product_id']?.toString() ?? '';
                    if (itemId.isEmpty || saleId.isEmpty) continue;

                    final priceCents = (((item['unit_price'] as num?)?.toDouble() ?? 0.0) * 100).round();
                    final subtotalCents = (((item['subtotal'] as num?)?.toDouble() ?? 0.0) * 100).round();
                    final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;

                    final ins = await txn.rawInsert('''
                      INSERT OR IGNORE INTO sale_items (
                        id, sale_id, product_id, barcode, product_name, unit_price_cents,
                        quantity, discount_cents, vat_rate, total_cents
                      ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 20, ?)
                    ''', [
                      itemId,
                      saleId,
                      prodId,
                      prodId,
                      item['product_name']?.toString() ?? 'Ürün',
                      priceCents,
                      qty,
                      subtotalCents,
                    ]);
                    if (ins > 0) itemsMigrated++;
                  }
                }));
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[CatchUpCoordinator] Note on sale catch-up: $e');
      discrepanciesDetected.add('Satış delta aktarım hatası: $e');
    }

    // D) İadeler (Refunds -> refunds tablosu ve satış durumu güncellemesi)
    try {
      final legacyRefundTable = await legacyDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='refunds'");
      if (legacyRefundTable.isNotEmpty) {
        final refColsInfo = await legacyDb.rawQuery('PRAGMA table_info(refunds);');
        final refCols = refColsInfo.map((c) => c['name'] as String).toSet();
        final hasCreatedCol = refCols.contains('created_at');

        final deltaRefunds = hasCreatedCol
            ? await legacyDb.query('refunds',
                where: _buildTimestampWhereClause('created_at'),
                whereArgs: _buildTimestampParams(cutoff, cutoffIso))
            : await legacyDb.query('refunds');

        if (deltaRefunds.isNotEmpty) {
          debugPrint('[CatchUpCoordinator] 🔄 ${deltaRefunds.length} adet iade yakalandı.');
          await _executeWithRetry(() => targetCoreDb.transaction((txn) async {
            for (final ref in deltaRefunds) {
              final refId = ref['id']?.toString() ?? '';
              final saleId = ref['sale_id']?.toString() ?? '';
              if (refId.isEmpty || saleId.isEmpty) continue;

              final amountCents = _resolveAmountCents(ref['amount'], ref['amount_minor']);
              final reason = ref['reason']?.toString() ?? 'Müşteri İadesi';
              final refundMethod = ref['refund_method']?.toString() ?? 'cash';
              final createdAtVal = ref['created_at'];
              final int createdAtMs = _parseTimestampMs(createdAtVal);

              // İlgili satışı hedef DB'de bul ve durumunu güncelle
              final targetSale = await txn.query('sales', where: 'id = ?', whereArgs: [saleId]);
              String custId = 'customer-pesin-default';
              if (targetSale.isNotEmpty) {
                final saleTotal = (targetSale.first['total_cents'] as num?)?.toInt() ?? 0;
                final isFullRefund = amountCents >= saleTotal && saleTotal > 0;
                final newStatus = isFullRefund ? 'REFUNDED' : 'PARTIALLY_REFUNDED';
                await txn.update(
                  'sales',
                  {'status': newStatus},
                  where: 'id = ?',
                  whereArgs: [saleId],
                );
                custId = targetSale.first['customer_id']?.toString() ?? custId;
              }

              // Defter hareketi (ledger_entries) ekle
              await txn.insert('customers', {
                'id': custId,
                'name': 'Müşteri $custId',
                'balance_cents': 0,
                'is_active': 1,
                'is_deleted': 0,
                'updated_at': createdAtMs,
              }, conflictAlgorithm: ConflictAlgorithm.ignore);

              await txn.rawInsert('''
                INSERT OR IGNORE INTO ledger_entries (
                  id, customer_id, reference_sale_id, entry_type, amount_cents,
                  balance_after_cents, description, created_at
                ) VALUES (?, ?, ?, 'REFUND', ?, 0, ?, ?)
              ''', [
                'ref-$refId',
                custId,
                saleId,
                amountCents,
                'İade: $reason ($refundMethod)',
                createdAtMs,
              ]);

              refundsMigrated++;
            }
          }));
        }
      }
    } catch (e) {
      debugPrint('[CatchUpCoordinator] Note on refund catch-up: $e');
      discrepanciesDetected.add('İade delta aktarım hatası: $e');
    }

    // E) Defter Hareketleri (Financial Transactions -> ledger_entries)
    try {
      final legacyFinTable = await legacyDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='financial_transactions'");
      if (legacyFinTable.isNotEmpty) {
        final finColsInfo = await legacyDb.rawQuery('PRAGMA table_info(financial_transactions);');
        final finCols = finColsInfo.map((c) => c['name'] as String).toSet();
        final hasCreatedCol = finCols.contains('created_at');
        final finTxs = hasCreatedCol
            ? await legacyDb.query('financial_transactions',
                where: _buildTimestampWhereClause('created_at'),
                whereArgs: _buildTimestampParams(cutoff, cutoffIso))
            : await legacyDb.query('financial_transactions');

        if (finTxs.isNotEmpty) {
          debugPrint('[CatchUpCoordinator] 🔄 ${finTxs.length} adet yeni defter hareketi yakalandı.');
          await _executeWithRetry(() => targetCoreDb.transaction((txn) async {
            for (final tx in finTxs) {
              final txId = tx['id']?.toString() ?? '';
              if (txId.isEmpty) continue;

              final amountCents = resolveAmountCents(tx['amount'], tx['amount_minor']);
              final createdAtVal = tx['created_at'];
              final int createdAtMs = _parseTimestampMs(createdAtVal);

              final custId = tx['customer_id']?.toString() ?? 'customer-pesin-default';
              await txn.insert('customers', {
                'id': custId,
                'name': 'Müşteri $custId',
                'balance_cents': 0,
                'is_active': 1,
                'is_deleted': 0,
                'updated_at': createdAtMs,
              }, conflictAlgorithm: ConflictAlgorithm.ignore);

              final refId = tx['reference_id']?.toString();
              String? refSaleId;
              if (refId != null && refId.isNotEmpty) {
                final s = await txn.query('sales', columns: ['id'], where: 'id = ?', whereArgs: [refId]);
                if (s.isNotEmpty) refSaleId = refId;
              }

              final ins = await txn.rawInsert('''
                INSERT OR IGNORE INTO ledger_entries (
                  id, customer_id, reference_sale_id, entry_type, amount_cents,
                  balance_after_cents, description, created_at
                ) VALUES (?, ?, ?, ?, ?, 0, ?, ?)
              ''', [
                txId,
                custId,
                refSaleId,
                tx['type']?.toString() ?? 'transaction',
                amountCents,
                tx['description']?.toString() ?? 'Catch-up defter kaydı',
                createdAtMs,
              ]);
              if (ins > 0) ledgerMigrated++;
            }
          }));
        }

        // E.1) Tarihsel Sıfır Tutarlı Defter Kayıtlarını Onar (Reconciliation Pass)
        final repairResult = await repairHistoricalLedgerEntries(
          legacyDb: legacyDb,
          targetDb: targetCoreDb.db,
        );
        if (repairResult.repairedCount > 0) {
          debugPrint('[CatchUpCoordinator] 🛠️ ${repairResult.repairedCount} adet tarihsel sıfır tutarlı defter kaydı onarıldı.');
          ledgerMigrated += repairResult.repairedCount;
        }
      }
    } catch (e) {
      debugPrint('[CatchUpCoordinator] Note on ledger catch-up: $e');
      discrepanciesDetected.add('Defter delta aktarım hatası: $e');
    }

    // F) Çevrimdışı Senkronizasyon Kuyruğu (sync_outbox_v4 -> sync_events)
    try {
      final legacyOutboxTable = await legacyDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='sync_outbox_v4'");
      if (legacyOutboxTable.isNotEmpty) {
        final pendingRows = await legacyDb.query(
          'sync_outbox_v4',
          where: "state IN ('PENDING', 'IN_FLIGHT', 'TRANSIENT_ERROR')",
        );
        if (pendingRows.isNotEmpty) {
          debugPrint('[CatchUpCoordinator] 🔄 ${pendingRows.length} adet bekleyen çevrimdışı senkronizasyon olayı yakalandı.');
          await _executeWithRetry(() => targetCoreDb.transaction((txn) async {
            for (final row in pendingRows) {
              final eventId = (row['mutation_id'] ?? 'legacy-mutation-${row['id']}').toString();
              final entityType = (row['entity_type'] ?? 'unknown').toString();
              final entityId = (row['entity_id'] ?? '').toString();
              final operation = (row['operation'] ?? 'UPSERT').toString();
              final payloadJson = (row['payload'] ?? '{}').toString();
              final baseRevision = (row['base_revision'] as num? ?? 0).toInt();
              final attempts = (row['attempts'] as num? ?? 0).toInt();

              final createdAtVal = row['created_at'];
              final int createdAtMs = _parseTimestampMs(createdAtVal);

              final ins = await txn.rawInsert('''
                INSERT INTO sync_events (
                  event_id, entity_type, entity_id, operation, payload_json,
                  base_revision, client_timestamp, sync_state, attempts, causal_sequence
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 'PENDING', ?, ?)
                ON CONFLICT(event_id) DO UPDATE SET
                  sync_state = excluded.sync_state,
                  attempts = excluded.attempts
              ''', [
                eventId,
                entityType,
                entityId,
                operation,
                payloadJson,
                baseRevision,
                createdAtMs,
                attempts,
                (row['id'] as num? ?? 0).toInt(),
              ]);
              if (ins > 0) syncEventsMigrated++;
            }
          }));
        }
      }
    } catch (e) {
      debugPrint('[CatchUpCoordinator] Note on sync outbox catch-up: $e');
      discrepanciesDetected.add('Senkronizasyon kuyruğu delta aktarım hatası: $e');
    }

    final totalCatchUp = pUpdated +
        cUpdated +
        sMigrated +
        itemsMigrated +
        ledgerMigrated +
        ordersMigrated +
        refundsMigrated +
        syncEventsMigrated;

    final stats = CatchUpStatistics(
      productsUpdated: pUpdated,
      customersUpdated: cUpdated,
      salesMigrated: sMigrated,
      saleItemsMigrated: itemsMigrated,
      ledgerEntriesMigrated: ledgerMigrated,
      ordersMigrated: ordersMigrated,
      refundsMigrated: refundsMigrated,
      syncEventsMigrated: syncEventsMigrated,
      paymentsMigrated: paymentsMigrated,
      totalCatchUpRecords: totalCatchUp,
    );

    // 3. ÇAPRAZ TABLO MUTABAKAT SORGULARI

    // A) Satış Adet ve Toplam Tutar
    final legSaleCountRow = await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sales;');
    final coreSaleCountRow = await targetCoreDb.db.rawQuery('SELECT COUNT(*) as c FROM sales;');
    final legSaleCount = (legSaleCountRow.first['c'] as num?)?.toInt() ?? 0;
    final coreSaleCount = (coreSaleCountRow.first['c'] as num?)?.toInt() ?? 0;

    final legSaleTotalRow = await legacyDb.rawQuery('SELECT COALESCE(SUM(total_amount), 0.0) as t FROM sales;');
    final coreSaleTotalRow = await targetCoreDb.db.rawQuery('SELECT COALESCE(SUM(total_cents), 0) as t FROM sales;');
    final legSaleTotalCents = (((legSaleTotalRow.first['t'] as num?)?.toDouble() ?? 0.0) * 100).round();
    final coreSaleTotalCents = (coreSaleTotalRow.first['t'] as num?)?.toInt() ?? 0;

    // B) Stok Miktarları
    final prodColsInfo = await legacyDb.rawQuery('PRAGMA table_info(products);');
    final prodCols = prodColsInfo.map((c) => c['name'] as String).toSet();
    final stockCol = prodCols.contains('stock_quantity')
        ? 'stock_quantity'
        : (prodCols.contains('quantity') ? 'quantity' : '0.0');

    final legStockRow = await legacyDb.rawQuery(
      'SELECT COALESCE(SUM($stockCol), 0.0) as s FROM products;',
    );
    final coreStockRow = await targetCoreDb.db.rawQuery('SELECT COALESCE(SUM(stock_quantity), 0.0) as s FROM products;');
    final legStockSum = (legStockRow.first['s'] as num?)?.toDouble() ?? 0.0;
    final coreStockSum = (coreStockRow.first['s'] as num?)?.toDouble() ?? 0.0;

    // C) Müşteri Bakiyeleri
    final legCustBalRow = await legacyDb.rawQuery('SELECT COALESCE(SUM(balance), 0.0) as b FROM customers;');
    final coreCustBalRow = await targetCoreDb.db.rawQuery('SELECT COALESCE(SUM(balance_cents), 0) as b FROM customers;');
    final legCustBalCents = (((legCustBalRow.first['b'] as num?)?.toDouble() ?? 0.0) * 100).round();
    final coreCustBalCents = (coreCustBalRow.first['b'] as num?)?.toInt() ?? 0;

    // D) Ödemeler ve Satışlar Tutarlılığı
    final targetPaySumRow = await targetCoreDb.db.rawQuery(
      "SELECT COALESCE(SUM(amount_cents), 0) as t FROM sale_payments WHERE sale_id IN (SELECT id FROM sales WHERE status != 'CANCELLED');",
    );
    final coreActivePaySumCents = (targetPaySumRow.first['t'] as num?)?.toInt() ?? 0;
    final targetActiveSalesTotalRow = await targetCoreDb.db.rawQuery(
      "SELECT COALESCE(SUM(total_cents), 0) as t FROM sales WHERE status != 'CANCELLED';",
    );
    final coreActiveSalesTotalCents = (targetActiveSalesTotalRow.first['t'] as num?)?.toInt() ?? 0;
    final paymentsSalesMatch = (coreActivePaySumCents - coreActiveSalesTotalCents).abs() <= 1;

    // E) Bütünlük ve Yabancı Anahtar Kontrolleri
    final integrityRes = await targetCoreDb.db.rawQuery('PRAGMA integrity_check;');
    final fkRes = await targetCoreDb.db.rawQuery('PRAGMA foreign_key_check;');
    final isIntegrityOk = integrityRes.isNotEmpty &&
        integrityRes.first.values.first == 'ok' &&
        fkRes.isEmpty &&
        discrepanciesDetected.isEmpty;

    // 4. FARK ANALİZİ VE CUTOVER KARARI
    final salesCountMatch = legSaleCount == coreSaleCount;
    final salesTotalMatch = legSaleTotalCents == coreSaleTotalCents;
    final stockDiff = (legStockSum - coreStockSum).abs();
    final stockMatch = stockDiff < 0.001;
    final balanceDiff = (legCustBalCents - coreCustBalCents).abs();
    final balanceMatch = balanceDiff <= 1; // 1 kuruş yuvarlama toleransı

    final isAllMatched = isIntegrityOk &&
        salesCountMatch &&
        salesTotalMatch &&
        stockMatch &&
        balanceMatch &&
        paymentsSalesMatch;

    if (isAllMatched) {
      if (persistCutoverStatus) {
        await targetCoreDb.db.insert(
          'app_settings',
          {
            'key': 'cutover_reconciliation_status',
            'value': 'approved',
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return LiveReconciliationReport(
        decision: CutoverReconciliationDecision.cutoverApproved,
        isMatched: true,
        legacySalesCount: legSaleCount,
        coreSalesCount: coreSaleCount,
        legacyTotalSalesCents: legSaleTotalCents,
        coreTotalSalesCents: coreSaleTotalCents,
        legacyStockSum: legStockSum,
        coreStockSum: coreStockSum,
        legacyCustomerBalanceCents: legCustBalCents,
        coreCustomerBalanceCents: coreCustBalCents,
        catchUpRecordsMigrated: totalCatchUp,
        statistics: stats,
        details: 'Tüm mutabakat kriterleri (satış, stok, bakiye, ödemeler, PRAGMA) %100 doğrulandı. Cutover onaylandı.',
      );
    } else {
      if (persistCutoverStatus) {
        await targetCoreDb.db.insert(
          'app_settings',
          {
            'key': 'cutover_reconciliation_status',
            'value': 'blocked',
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final reasons = <String>[];
      if (discrepanciesDetected.isNotEmpty) reasons.addAll(discrepanciesDetected);
      if (!isIntegrityOk && discrepanciesDetected.isEmpty) reasons.add('Hedef SQLite bütünlük veya FK kontrolü başarısız');
      if (!salesCountMatch) reasons.add('Satış adedi uyumsuz ($legSaleCount != $coreSaleCount)');
      if (!salesTotalMatch) reasons.add('Satış tutarı uyumsuz ($legSaleTotalCents != $coreSaleTotalCents)');
      if (!stockMatch) reasons.add('Stok toplamı uyumsuz ($legStockSum != $coreStockSum, fark: $stockDiff)');
      if (!balanceMatch) reasons.add('Müşteri bakiye toplamı uyumsuz ($legCustBalCents != $coreCustBalCents)');
      if (!paymentsSalesMatch) reasons.add('Ödeme parçaları toplamı satış toplamına uyuşmuyor ($coreActivePaySumCents != $coreActiveSalesTotalCents)');

      final decision = (!isIntegrityOk || !paymentsSalesMatch || discrepanciesDetected.isNotEmpty)
          ? CutoverReconciliationDecision.cutoverBlockedIntegrityError
          : CutoverReconciliationDecision.cutoverBlockedVarianceDetected;

      return LiveReconciliationReport(
        decision: decision,
        isMatched: false,
        legacySalesCount: legSaleCount,
        coreSalesCount: coreSaleCount,
        legacyTotalSalesCents: legSaleTotalCents,
        coreTotalSalesCents: coreSaleTotalCents,
        legacyStockSum: legStockSum,
        coreStockSum: coreStockSum,
        legacyCustomerBalanceCents: legCustBalCents,
        coreCustomerBalanceCents: coreCustBalCents,
        catchUpRecordsMigrated: totalCatchUp,
        statistics: stats,
        details: 'Canlı işlem mutabakatı engellendi: ${reasons.join(", ")}',
      );
    }
  }

  /// Hedef veritabanında geçmişte hatalı olarak 0 kuruş kaydedilmiş olan ledger_entries
  /// kayıtlarını, kaynak financial_transactions tablosundaki doğrulanmış tutarlarla onarır.
  ///
  /// Kurallar:
  /// - Kararlı ID üzerinden güvenilir kaynak eşleşmesi.
  /// - Gerçek sıfır tutarlı kayıtlar (amount == 0 && amount_minor == 0) korunur.
  /// - Semantik çelişki (müşteri veya tür uyuşmazlığı) varsa onarım yapılmaz, çakışma raporlanır.
  /// - Transaction içinde atomik yürütülür.
  /// - İkinci çalıştırmada tam idempotency garanti edilir.
  Future<LedgerRepairResult> repairHistoricalLedgerEntries({
    required Database legacyDb,
    required Database targetDb,
  }) async {
    final legacyFtTable = await legacyDb.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='financial_transactions';",
    );
    final targetLedgerTable = await targetDb.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='ledger_entries';",
    );

    if (legacyFtTable.isEmpty || targetLedgerTable.isEmpty) {
      return const LedgerRepairResult(
        totalScanned: 0,
        repairedCount: 0,
        preservedZeroCount: 0,
        skippedAlreadyValidCount: 0,
        conflictCount: 0,
        totalRepairedVolumeCents: 0,
        repairDetails: ['Gerekli tablolar bulunamadı'],
        conflicts: [],
      );
    }

    final targetZeros = await targetDb.query(
      'ledger_entries',
      where: 'amount_cents = 0',
    );

    if (targetZeros.isEmpty) {
      return const LedgerRepairResult(
        totalScanned: 0,
        repairedCount: 0,
        preservedZeroCount: 0,
        skippedAlreadyValidCount: 0,
        conflictCount: 0,
        totalRepairedVolumeCents: 0,
        repairDetails: ['Onarılacak sıfır tutarlı kayıt bulunamadı (Tümü güncel)'],
        conflicts: [],
      );
    }

    int repairedCount = 0;
    int preservedZeroCount = 0;
    int conflictCount = 0;
    int totalRepairedVolumeCents = 0;
    final repairDetails = <String>[];
    final conflicts = <String>[];

    await _executeWithRetry(() => targetDb.transaction((txn) async {
      for (final targetRow in targetZeros) {
        final id = targetRow['id']?.toString() ?? '';
        if (id.isEmpty) continue;

        final legacyRows = await legacyDb.query(
          'financial_transactions',
          where: 'id = ?',
          whereArgs: [id],
        );

        if (legacyRows.isEmpty) {
          conflicts.add('Kaynak karşılığı bulunamadı: ID $id');
          conflictCount++;
          continue;
        }

        final legacyRow = legacyRows.first;

        // Semantik kontrol: Tür ve Cari eşleşmesi
        final legType = (legacyRow['type'] ?? '').toString().toLowerCase().trim();
        final tgtType = (targetRow['entry_type'] ?? '').toString().toLowerCase().trim();
        if (legType.isNotEmpty && tgtType.isNotEmpty && legType != tgtType) {
          conflicts.add('Semantik tür çelişkisi: ID $id (Kaynak: $legType, Hedef: $tgtType)');
          conflictCount++;
          continue;
        }

        final legCustId = (legacyRow['customer_id'] ?? '').toString().trim();
        final tgtCustId = (targetRow['customer_id'] ?? '').toString().trim();
        final effectiveLegCustId = legCustId.isEmpty ? 'customer-pesin-default' : legCustId;
        if (tgtCustId.isNotEmpty && tgtCustId != 'customer-pesin-default' && effectiveLegCustId != tgtCustId) {
          conflicts.add('Müşteri kimlik çelişkisi: ID $id (Kaynak: $effectiveLegCustId, Hedef: $tgtCustId)');
          conflictCount++;
          continue;
        }

        final resolvedCents = resolveAmountCents(
          legacyRow['amount'],
          legacyRow['amount_minor'],
        );

        if (resolvedCents == 0) {
          // Gerçek sıfır tutarlı kayıt: Korunur, değiştirilmez
          preservedZeroCount++;
          repairDetails.add('Gerçek sıfır tutar korundu: ID $id');
          continue;
        }

        // Güvenli onarım güncellemesi (balance_after_cents körlemesine değiştirilmez)
        final updatedRows = await txn.update(
          'ledger_entries',
          {
            'amount_cents': resolvedCents,
          },
          where: 'id = ? AND amount_cents = 0',
          whereArgs: [id],
        );

        if (updatedRows > 0) {
          repairedCount++;
          totalRepairedVolumeCents += resolvedCents;
          repairDetails.add('Onarıldı: ID $id -> $resolvedCents kuruş (${resolvedCents / 100.0} TL)');
        }
      }
    }));

    return LedgerRepairResult(
      totalScanned: targetZeros.length,
      repairedCount: repairedCount,
      preservedZeroCount: preservedZeroCount,
      skippedAlreadyValidCount: 0,
      conflictCount: conflictCount,
      totalRepairedVolumeCents: totalRepairedVolumeCents,
      repairDetails: repairDetails,
      conflicts: conflicts,
    );
  }
}
