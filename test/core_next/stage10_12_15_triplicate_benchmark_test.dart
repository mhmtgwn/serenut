// test/core_next/stage10_12_15_triplicate_benchmark_test.dart
// STAGE 10.12.15 — 3 Tekrarlı Gerçek Veri Performans ve Mutabakat Ölçümü

@Timeout(Duration(minutes: 10))
library stage10_12_15_triplicate_benchmark_test;

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

String calcSha256(String filePath) {
  final bytes = File(filePath).readAsBytesSync();
  return sha256.convert(bytes).toString().toLowerCase();
}

class RunMetrics {
  final int runIndex;
  final String sourcePath;
  final String targetPath;
  final String shaBefore;
  final String shaAfter;
  final int totalMs;
  final int backupMs;
  final int migrationMs;
  final int reconciliationMs;

  final int totalProducts;
  final int activeProducts;
  final int deletedProducts;
  final int totalCustomers;
  final int totalCustomerBalanceCents;
  final int totalSales;
  final int totalSalesCents;
  final int totalSaleItems;
  final int totalOrders;
  final int totalOrderCents;
  final int totalLedgerEntries;
  final int anonymousCashCount;
  final int anonymousCashCents;
  final String integrityCheck;
  final int foreignKeyViolations;

  RunMetrics({
    required this.runIndex,
    required this.sourcePath,
    required this.targetPath,
    required this.shaBefore,
    required this.shaAfter,
    required this.totalMs,
    required this.backupMs,
    required this.migrationMs,
    required this.reconciliationMs,
    required this.totalProducts,
    required this.activeProducts,
    required this.deletedProducts,
    required this.totalCustomers,
    required this.totalCustomerBalanceCents,
    required this.totalSales,
    required this.totalSalesCents,
    required this.totalSaleItems,
    required this.totalOrders,
    required this.totalOrderCents,
    required this.totalLedgerEntries,
    required this.anonymousCashCount,
    required this.anonymousCashCents,
    required this.integrityCheck,
    required this.foreignKeyViolations,
  });

  Map<String, dynamic> toJson() => {
    'runIndex': runIndex,
    'totalMs': totalMs,
    'backupMs': backupMs,
    'migrationMs': migrationMs,
    'reconciliationMs': reconciliationMs,
    'totalProducts': totalProducts,
    'activeProducts': activeProducts,
    'deletedProducts': deletedProducts,
    'totalCustomers': totalCustomers,
    'totalCustomerBalanceCents': totalCustomerBalanceCents,
    'totalSales': totalSales,
    'totalSalesCents': totalSalesCents,
    'totalSaleItems': totalSaleItems,
    'totalOrders': totalOrders,
    'totalOrderCents': totalOrderCents,
    'totalLedgerEntries': totalLedgerEntries,
    'anonymousCashCount': anonymousCashCount,
    'anonymousCashCents': anonymousCashCents,
    'integrityCheck': integrityCheck,
    'foreignKeyViolations': foreignKeyViolations,
    'shaBefore': shaBefore,
    'shaAfter': shaAfter,
    'sourcePath': sourcePath,
    'targetPath': targetPath,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const rawNutopiaPath = 'backups/raw_tenants_20261016/raw_nutopia_v60.db';
  const expectedSha = 'e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24';

  test('STAGE 10.12.15 — 3 Tekrarlı Gerçek Veri Performans ve Mutabakat Testi', () async {
    final originalSha = calcSha256(rawNutopiaPath);
    expect(originalSha, equals(expectedSha));

    final results = <RunMetrics>[];

    for (int i = 1; i <= 3; i++) {
      final tempDir = Directory.systemTemp.createTempSync('benchmark_run_${i}_');
      final isolatedSourcePath = p.join(tempDir.path, 'source_nutopia_run_$i.db');
      final isolatedTargetPath = p.join(tempDir.path, 'target_core_run_$i.db');
      final backupDir = p.join(tempDir.path, 'backups_run_$i');

      File(rawNutopiaPath).copySync(isolatedSourcePath);
      final shaBefore = calcSha256(isolatedSourcePath);

      final legacyDb = await openDatabase(isolatedSourcePath, readOnly: false);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final totalSw = Stopwatch()..start();
      final backupSw = Stopwatch();
      final migrationSw = Stopwatch();
      final reconciliationSw = Stopwatch();

      final bridge = MigrationBridgeEngine(coreDb);

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: isolatedSourcePath,
        customBackupDirectory: backupDir,
        prefs: prefs,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          migrationSw.start();
          final rep = await bridge.migrateFromLegacy(
            legacyDb,
            legacyFilePath: legacyFilePath,
            fullScope: fullScope,
          );
          migrationSw.stop();
          return rep;
        },
      );

      backupSw.start();
      final result = await coordinator.coordinate();
      backupSw.stop();
      totalSw.stop();

      expect(result.isSuccess, isTrue, reason: 'Koşu #$i başarısız: ${result.errorMessage}');

      reconciliationSw.start();
      final prodTotalRes = await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM products;');
      final totalProducts = (prodTotalRes.first['c'] as num).toInt();
      final prodActiveRes = await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM products WHERE is_deleted = 0;');
      final activeProducts = (prodActiveRes.first['c'] as num).toInt();
      final prodDeletedRes = await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM products WHERE is_deleted = 1;');
      final deletedProducts = (prodDeletedRes.first['c'] as num).toInt();

      final custRes = await coreDb.db.rawQuery('SELECT COUNT(*) as c, COALESCE(SUM(balance_cents), 0) as s FROM customers;');
      final totalCustomers = (custRes.first['c'] as num).toInt();
      final totalCustBalCents = (custRes.first['s'] as num).toInt();

      final salesRes = await coreDb.db.rawQuery('SELECT COUNT(*) as c, COALESCE(SUM(total_cents), 0) as s FROM sales;');
      final totalSales = (salesRes.first['c'] as num).toInt();
      final totalSalesCents = (salesRes.first['s'] as num).toInt();

      final itemsRes = await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM sale_items;');
      final totalSaleItems = (itemsRes.first['c'] as num).toInt();

      // Siparişler: orders tablosu
      final ordersTable = await legacyDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='orders'");
      int totalOrders = 0;
      int totalOrderCents = 0;
      if (ordersTable.isNotEmpty) {
        final cols = await legacyDb.rawQuery("PRAGMA table_info(orders);");
        final colNames = cols.map((c) => c['name'] as String).toSet();
        final amountCol = colNames.contains('total_amount_minor')
            ? 'total_amount_minor'
            : (colNames.contains('total_price')
                ? 'total_price'
                : (colNames.contains('total_amount')
                    ? 'total_amount'
                    : (colNames.contains('total') ? 'total' : null)));
        final ordRes = amountCol != null
            ? await legacyDb.rawQuery('SELECT COUNT(*) as c, COALESCE(SUM($amountCol), 0) as s FROM orders;')
            : await legacyDb.rawQuery('SELECT COUNT(*) as c, 0 as s FROM orders;');
        totalOrders = (ordRes.first['c'] as num?)?.toInt() ?? 0;
        totalOrderCents = (ordRes.first['s'] as num?)?.toInt() ?? 0;
      }

      final ledgerRes = await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM ledger_entries;');
      final totalLedger = (ledgerRes.first['c'] as num).toInt();

      final cashRes = await coreDb.db.rawQuery("SELECT COUNT(*) as c, COALESCE(SUM(amount_cents), 0) as s FROM cash_transactions WHERE category = 'SALE';");
      final anonCashCount = (cashRes.first['c'] as num).toInt();
      final anonCashCents = (cashRes.first['s'] as num).toInt();

      final integrityRes = await coreDb.db.rawQuery('PRAGMA integrity_check;');
      final integrityCheck = integrityRes.first.values.first.toString();

      final fkRes = await coreDb.db.rawQuery('PRAGMA foreign_key_check;');
      final fkViolations = fkRes.length;
      reconciliationSw.stop();

      await legacyDb.close();
      await coreDb.close();

      final shaAfter = calcSha256(isolatedSourcePath);
      expect(calcSha256(rawNutopiaPath), equals(expectedSha));

      final metrics = RunMetrics(
        runIndex: i,
        sourcePath: isolatedSourcePath,
        targetPath: isolatedTargetPath,
        shaBefore: shaBefore,
        shaAfter: shaAfter,
        totalMs: totalSw.elapsedMilliseconds,
        backupMs: backupSw.elapsedMilliseconds - migrationSw.elapsedMilliseconds,
        migrationMs: migrationSw.elapsedMilliseconds,
        reconciliationMs: reconciliationSw.elapsedMilliseconds,
        totalProducts: totalProducts,
        activeProducts: activeProducts,
        deletedProducts: deletedProducts,
        totalCustomers: totalCustomers,
        totalCustomerBalanceCents: totalCustBalCents,
        totalSales: totalSales,
        totalSalesCents: totalSalesCents,
        totalSaleItems: totalSaleItems,
        totalOrders: totalOrders,
        totalOrderCents: totalOrderCents,
        totalLedgerEntries: totalLedger,
        anonymousCashCount: anonCashCount,
        anonymousCashCents: anonCashCents,
        integrityCheck: integrityCheck,
        foreignKeyViolations: fkViolations,
      );

      results.add(metrics);
      print('=== KOŞU #$i TAMAMLANDI ===');
      print('  Toplam Süre        : ${metrics.totalMs} ms');
      print('  Yedekleme & Check  : ${metrics.backupMs} ms');
      print('  Toplu Veri Göçü    : ${metrics.migrationMs} ms');
      print('  Adli Mutabakat     : ${metrics.reconciliationMs} ms');
      print('  Toplam Ürün        : $totalProducts (Aktif: $activeProducts, Silinmiş: $deletedProducts)');
      print('  Müşteri Sayısı     : $totalCustomers, Bakiye: ${totalCustBalCents / 100} TL ($totalCustBalCents kuruş)');
      print('  Satış Sayısı       : $totalSales, Tutar: ${totalSalesCents / 100} TL ($totalSalesCents kuruş)');
      print('  Satış Kalemleri    : $totalSaleItems');
      print('  Siparişler         : $totalOrders (Tutar: ${totalOrderCents / 100} TL)');
      print('  Defter Hareketleri : $totalLedger');
      print('  Müşterisiz Nakit   : $anonCashCount ($anonCashCents kuruş)');
      print('  PRAGMA integrity   : $integrityCheck, FK İhlali: $fkViolations');

      CoreNextBootstrapCoordinator.resetExecutionLock();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }

    final avgTotalMs = results.map((r) => r.totalMs).reduce((a, b) => a + b) ~/ results.length;
    final avgBackupMs = results.map((r) => r.backupMs).reduce((a, b) => a + b) ~/ results.length;
    final avgMigMs = results.map((r) => r.migrationMs).reduce((a, b) => a + b) ~/ results.length;

    print('\n=========================================');
    print('STAGE 10.12.15 ÜÇ KOŞU ORTALAMA RAPORU:');
    print('  Ortalama Toplam Süre    : $avgTotalMs ms (${(avgTotalMs / 1000).toStringAsFixed(2)} s)');
    print('  Ortalama Yedekleme      : $avgBackupMs ms (${(avgBackupMs / 1000).toStringAsFixed(2)} s)');
    print('  Ortalama Toplu Göç      : $avgMigMs ms (${(avgMigMs / 1000).toStringAsFixed(2)} s)');
    print('=========================================');

    // JSON dosyasını kaydet
    final jsonStr = jsonEncode({
      'runs': results.map((r) => r.toJson()).toList(),
      'average': {
        'totalMs': avgTotalMs,
        'backupMs': avgBackupMs,
        'migrationMs': avgMigMs,
      }
    });
    File('C:\\Users\\notop\\.gemini\\antigravity-ide\\brain\\00a8352b-bdb1-41cc-908d-297deec4e52a\\scratch\\triplicate_benchmark_output.json')
        .writeAsStringSync(jsonStr);
  });
}
