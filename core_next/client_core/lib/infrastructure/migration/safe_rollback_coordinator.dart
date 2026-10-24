// core_next/client_core/lib/infrastructure/migration/safe_rollback_coordinator.dart
// SERENUT OS — STAGE 10.12.78
// GÜVENLİ VE ATOMİK GERİ DÖNÜŞ KOORDİNATÖRÜ (SAFE ROLLBACK COORDINATOR)
//
// Core Next aktifken oluşan yeni satış, tahsilat, iade, iptal, sipariş ve finansal hareketlerin
// geri dönüşte kaybolmamasını güvence altına alır.
// İşlemleri kesim kilidi (CutoffMaintenanceLock), tersine aktarım (ReverseMigrationEngine)
// ve post-mutabakat doğrulaması ile fail-closed mimaride yürütür.

import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/infrastructure/migration/cutoff_maintenance_lock.dart';
import 'package:serenutos/infrastructure/migration/safe_rollback_coordinator.dart';
import '../database/app_database.dart';
import 'migration_bridge_engine.dart';

/// Geri dönüş mutabakat raporu
class RollbackReconciliationReport {
  final bool isReconciled;
  final int coreSalesCount;
  final int legacySalesAndRefundsCount;
  final int coreLedgerCount;
  final int legacyTransactionsCount;
  final int coreCustomerCount;
  final int legacyCustomerCount;
  final List<String> discrepancies;

  const RollbackReconciliationReport({
    required this.isReconciled,
    required this.coreSalesCount,
    required this.legacySalesAndRefundsCount,
    required this.coreLedgerCount,
    required this.legacyTransactionsCount,
    required this.coreCustomerCount,
    required this.legacyCustomerCount,
    this.discrepancies = const [],
  });

  @override
  String toString() =>
      'RollbackReconciliationReport(isReconciled: $isReconciled, discrepancies: ${discrepancies.length})';
}

/// Güvenli Geri Dönüş Koordinatörü
class SafeRollbackCoordinator {
  static const String prefKeyRollbackState = 'core_next_rollback_state';
  static const String prefKeyRollbackStartedAt = 'core_next_rollback_started_at';
  static const String prefKeyRollbackCompletedAt = 'core_next_rollback_completed_at';
  static const String prefKeyRollbackLastError = 'core_next_rollback_last_error';

  final CutoffMaintenanceLock? cutoffLock;

  const SafeRollbackCoordinator({this.cutoffLock});

  /// Statik yürütücü (SafeRollbackRunner ile doğrudan uyumlu)
  static Future<SafeRollbackResult> runRollback({
    required Database legacyDb,
    required dynamic coreDb,
    required SharedPreferences prefs,
    required String tenantId,
    CutoffMaintenanceLock? cutoffLock,
    Duration drainTimeout = const Duration(seconds: 15),
  }) async {
    final coordinator = SafeRollbackCoordinator(cutoffLock: cutoffLock);
    return await coordinator.executeRollback(
      legacyDb: legacyDb,
      coreDb: coreDb,
      prefs: prefs,
      tenantId: tenantId,
      drainTimeout: drainTimeout,
    );
  }

  /// Esnek yürütme metodu (hem Database hem CoreAppDatabase kabul eder)
  Future<SafeRollbackResult> executeRollback({
    required Database legacyDb,
    required dynamic coreDb,
    required SharedPreferences prefs,
    required String tenantId,
    Duration drainTimeout = const Duration(seconds: 15),
    bool simulateReconciliationFailure = false,
  }) {
    final CoreAppDatabase effectiveCoreDb =
        (coreDb is Database) ? CoreAppDatabase(coreDb) : (coreDb as CoreAppDatabase);
    return executeSafeRollback(
      legacyDb: legacyDb,
      coreDb: effectiveCoreDb,
      prefs: prefs,
      tenantId: tenantId,
      drainTimeout: drainTimeout,
      simulateReconciliationFailure: simulateReconciliationFailure,
    );
  }

  /// Güvenli geri dönüş akışını yürütür:
  /// 1. Kesim kilidi ile yeni yazmaları durdurur ve devam eden işlemleri boşaltır.
  /// 2. SharedPreferences durumunu 'in_progress' olarak işaretler (crash recovery koruması).
  /// 3. Tersine aktarımı (ReverseMigrationEngine) transaction ve idempotency ile çalıştırır.
  /// 4. Post-mutabakat ile kayıt sayılarını ve finansal tutarları teyit eder.
  /// 5. Yalnızca mutabakat %100 başarılıysa SharedPreferences ve routing bayraklarını günceller.
  /// 6. Aktarım başarısızsa legacy routing'e geçilmesini KESİNLİKLE ENGELLER.
  Future<SafeRollbackResult> executeSafeRollback({
    required Database legacyDb,
    required CoreAppDatabase coreDb,
    required SharedPreferences prefs,
    required String tenantId,
    Duration drainTimeout = const Duration(seconds: 15),
    bool simulateReconciliationFailure = false,
  }) async {
    final stopwatch = Stopwatch()..start();

    // ── ADIM 1: YENİ YAZMALARI DURDUR VE BOŞALT (CUTOFF LOCK) ────────────────
    if (cutoffLock != null) {
      final lockAcquired = await cutoffLock!.acquireLock(
        tenantId: tenantId,
        reason: 'Core Next Safe Rollback to Legacy',
        timeout: drainTimeout,
      );
      if (!lockAcquired) {
        stopwatch.stop();
        await prefs.setString(prefKeyRollbackState, 'failed_blocked');
        await prefs.setString(
          prefKeyRollbackLastError,
          'Kesim kilidi alınamadı veya devam eden işlemler zaman aşımında boşaltılamadı.',
        );
        return SafeRollbackResult(
          isSuccess: false,
          status: 'drain_timeout',
          errorMessage: 'İşlemler boşaltılamadı (drain timeout). Rollback güvenle durduruldu.',
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }
    }

    // ── ADIM 2: DURUMU 'in_progress' OLARAK KAYDET (CRASH RESILIENCE) ─────────
    await prefs.setString(prefKeyRollbackState, 'in_progress');
    await prefs.setString(prefKeyRollbackStartedAt, DateTime.now().toIso8601String());

    // ── ADIM 3: TERSİNE AKTARIMI ÇALIŞTIR (TRANSACTION & IDEMPOTENCY) ─────────
    ReverseMigrationReport? migReport;
    try {
      migReport = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreDb,
      );

      if (!migReport.isSuccess) {
        stopwatch.stop();
        await prefs.setString(prefKeyRollbackState, 'failed_blocked');
        await prefs.setString(
          prefKeyRollbackLastError,
          migReport.errorMessage ?? 'Tersine aktarım motoru başarısız oldu.',
        );
        // Fail-Closed: Legacy routing AÇILMAZ!
        return SafeRollbackResult(
          isSuccess: false,
          status: 'transfer_failed',
          errorMessage: migReport.errorMessage,
          migrationReport: migReport,
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }
    } catch (e) {
      stopwatch.stop();
      await prefs.setString(prefKeyRollbackState, 'failed_blocked');
      await prefs.setString(prefKeyRollbackLastError, e.toString());
      return SafeRollbackResult(
        isSuccess: false,
        status: 'transfer_failed',
        errorMessage: 'Aktarım sırasında beklenmeyen istisna: $e',
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // ── ADIM 4: POST-MUTABAKAT DOĞRULAMASI (KAYIT VE FİNANSAL DEĞİŞMEZLER) ───
    final recReport = await _verifyRollbackReconciliation(
      legacyDb: legacyDb,
      coreDb: coreDb,
      simulateFailure: simulateReconciliationFailure,
    );

    if (!recReport.isReconciled) {
      stopwatch.stop();
      await prefs.setString(prefKeyRollbackState, 'failed_blocked');
      final errorMsg =
          'Geri dönüş mutabakat hatası: ${recReport.discrepancies.join("; ")}';
      await prefs.setString(prefKeyRollbackLastError, errorMsg);

      // KESİN GÜVENLİK SINIRI: Mutabakat sağlanamadıysa legacy routing KESİNLİKLE AÇILMAZ.
      return SafeRollbackResult(
        isSuccess: false,
        status: 'reconciliation_failed',
        errorMessage: errorMsg,
        migrationReport: migReport,
        reconciliationReport: recReport,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // ── ADIM 5: ONAYLI GEÇİŞ VE YÖNLENDİRME GÜNCELLEMESİ ───────────────────────
    // 1. Hedef app_settings güncelle
    await coreDb.db.insert(
      'app_settings',
      {
        'key': 'legacy_migration_completed',
        'value': 'rolled_back',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 2. SharedPreferences durumlarını kalıcı güncelle
    await prefs.setString(prefKeyRollbackState, 'completed');
    await prefs.setString(prefKeyRollbackCompletedAt, DateTime.now().toIso8601String());
    await prefs.remove(prefKeyRollbackLastError);

    // 3. Pilot kapısını devre dışı bırak ve kill-switch'i aktif et
    await prefs.setBool(PilotCutoverGate.prefKeyPilotEnabled, false);
    await prefs.setBool(PilotCutoverGate.prefKeyKillSwitch, true);

    // 4. Kesim kilidini güvenle serbest bırak
    if (cutoffLock != null) {
      await cutoffLock!.releaseLock();
    }

    stopwatch.stop();
    return SafeRollbackResult(
      isSuccess: true,
      status: 'completed',
      migrationReport: migReport,
      reconciliationReport: recReport,
      durationMs: stopwatch.elapsedMilliseconds,
    );
  }

  /// Tersine aktarım sonrası kaynak ve hedef tablolar arasındaki tutarlılığı doğrular
  Future<RollbackReconciliationReport> _verifyRollbackReconciliation({
    required Database legacyDb,
    required CoreAppDatabase coreDb,
    bool simulateFailure = false,
  }) async {
    final discrepancies = <String>[];

    if (simulateFailure) {
      discrepancies.add('Simüle edilmiş yapay mutabakat hatası.');
      return RollbackReconciliationReport(
        isReconciled: false,
        coreSalesCount: 0,
        legacySalesAndRefundsCount: 0,
        coreLedgerCount: 0,
        legacyTransactionsCount: 0,
        coreCustomerCount: 0,
        legacyCustomerCount: 0,
        discrepancies: discrepancies,
      );
    }

    // 1. Satış ve İade Sayıları Kontrolü
    final coreSales = await coreDb.db.query('sales');
    final coreSalesCount = coreSales.length;

    final legacySales = await legacyDb.query('sales');
    final legacySalesCount = legacySales.length;

    int legacyRefundsCount = 0;
    final hasRefunds = await legacyDb.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='refunds'",
    );
    if (hasRefunds.isNotEmpty) {
      final legRef = await legacyDb.query('refunds');
      legacyRefundsCount = legRef.length;
    }

    final totalLegacySalesAndRefunds = legacySalesCount + legacyRefundsCount;
    // Core Next'teki her satış ID'si Legacy sales veya refunds tablosunda mevcut olmalı
    final legacySaleIds = legacySales.map((r) => r['id'].toString()).toSet();
    if (hasRefunds.isNotEmpty) {
      final legRefs = await legacyDb.query('refunds', columns: ['id']);
      legacySaleIds.addAll(legRefs.map((r) => r['id'].toString()));
    }

    for (final cs in coreSales) {
      final csId = cs['id'].toString();
      if (!legacySaleIds.contains(csId)) {
        discrepancies.add('Core Next satışı [$csId] legacy DB içinde bulunamadı.');
      }
    }

    // 2. Müşteri (Cari) Sayıları ve Bakiyeleri Kontrolü
    final coreCustomers = await coreDb.db.query('customers');
    final coreCustCount = coreCustomers.length;

    final legacyCustomers = await legacyDb.query('customers');
    final legCustCount = legacyCustomers.length;

    final legacyCustMap = {for (final r in legacyCustomers) r['id'].toString(): r};
    for (final cc in coreCustomers) {
      final cid = cc['id'].toString();
      final legC = legacyCustMap[cid];
      if (legC == null) {
        discrepancies.add('Core Next müşterisi [$cid] legacy DB içinde bulunamadı.');
      } else {
        final coreBalCents = (cc['balance_cents'] as num? ?? 0).toInt();
        final rawMinor = legC['balance_minor'];
        final legBalCents = (rawMinor is num && rawMinor.toInt() != 0)
            ? rawMinor.toInt()
            : (((legC['balance'] as num?)?.toDouble() ?? 0.0) * 100).round();
        if (coreBalCents != legBalCents) {
          discrepancies.add(
            'Müşteri [$cid] bakiye uyuşmazlığı: Core ($coreBalCents kuruş) != Legacy ($legBalCents kuruş).',
          );
        }
      }
    }

    // 3. Cari Defter Hareketleri (Ledger vs Financial Transactions)
    final coreLedger = await coreDb.db.query('ledger_entries');
    final coreLedgerCount = coreLedger.length;

    int legacyFtCount = 0;
    final hasFt = await legacyDb.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='financial_transactions'",
    );
    if (hasFt.isNotEmpty) {
      final legacyFt = await legacyDb.query('financial_transactions');
      legacyFtCount = legacyFt.length;

      final legFtIds = legacyFt.map((r) => r['id'].toString()).toSet();
      for (final le in coreLedger) {
        final leId = le['id'].toString();
        if (!legFtIds.contains(leId)) {
          discrepancies.add('Core Next defter kaydı [$leId] legacy financial_transactions içinde bulunamadı.');
        }
      }
    }

    // 4. Ürün Stok Bütünlüğü
    final coreProducts = await coreDb.db.query('products');
    final legacyProducts = await legacyDb.query('products');
    final legProdMap = {for (final r in legacyProducts) r['id'].toString(): r};

    for (final cp in coreProducts) {
      final pid = cp['id'].toString();
      final legP = legProdMap[pid];
      if (legP == null) {
        discrepancies.add('Core Next ürünü [$pid] legacy DB içinde bulunamadı.');
      } else {
        final coreStock = (cp['stock_quantity'] as num? ?? 0.0).toDouble();
        final legStock = (legP['quantity'] as num? ?? 0.0).toDouble();
        if ((coreStock - legStock).abs() > 0.001) {
          discrepancies.add(
            'Ürün [$pid] stok miktarı uyuşmuyor: Core ($coreStock) != Legacy ($legStock).',
          );
        }
      }
    }

    final isReconciled = discrepancies.isEmpty;
    return RollbackReconciliationReport(
      isReconciled: isReconciled,
      coreSalesCount: coreSalesCount,
      legacySalesAndRefundsCount: totalLegacySalesAndRefunds,
      coreLedgerCount: coreLedgerCount,
      legacyTransactionsCount: legacyFtCount,
      coreCustomerCount: coreCustCount,
      legacyCustomerCount: legCustCount,
      discrepancies: discrepancies,
    );
  }
}
