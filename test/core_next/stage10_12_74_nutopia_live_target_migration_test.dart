// test/core_next/stage10_12_74_nutopia_live_target_migration_test.dart
// STAGE 10.12.74: Nutopia Live Backup to Isolated nutopia_core_next_live.db Migration & Reconciliation
// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const backupDir = 'backups/nutopia_live_20261021_2055';
  final backupPath = File('$backupDir/nutopia_live_backup.db').absolute.path;
  final targetDbPath = File('$backupDir/nutopia_core_next_live.db').absolute.path;

  group('STAGE 10.12.74: Nutopia Canlı Yedekten İzole Core Next Hedefi Oluşturma', () {
    late Database sourceDb;
    late CoreAppDatabase targetDb;

    setUpAll(() async {
      expect(File(backupPath).existsSync(), isTrue, reason: 'Yedek dosyası mevcut olmalıdır.');

      // Hedef dosya varsa temiz başla
      final targetFile = File(targetDbPath);
      if (targetFile.existsSync()) {
        targetFile.deleteSync();
      }

      sourceDb = await databaseFactory.openDatabase(
        backupPath,
        options: OpenDatabaseOptions(readOnly: true),
      );

      targetDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
    });

    tearDownAll(() async {
      await sourceDb.close();
      await targetDb.close();
    });

    test('1. MigrationBridgeEngine ile Tam Kapsamlı (Full Scope) Aktarım', () async {
      final engine = MigrationBridgeEngine(targetDb);
      final report = await engine.migrateFromLegacy(
        sourceDb,
        legacyFilePath: backupPath,
        fullScope: true,
      );

      print('MIGRATION REPORT:');
      print('  Success: ${report.isSuccess}');
      print('  Products: ${report.productsMigrated}');
      print('  Customers: ${report.customersMigrated}');
      print('  Sales: ${report.salesMigrated}');
      print('  Sale Items: ${report.saleItemsMigrated}');
      print('  Orders: ${report.ordersMigrated}');
      print('  Ledger Entries: ${report.ledgerEntriesMigrated}');
      print('  Cash Transactions: ${report.cashTransactionsMigrated}');
      print('  Duration: ${report.durationMs}ms');

      expect(report.isSuccess, isTrue, reason: report.errorMessage);
      expect(report.productsMigrated, equals(37682));
      expect(report.customersMigrated, equals(626));
      expect(report.salesMigrated, equals(52));
      expect(report.saleItemsMigrated, equals(120));
      expect(report.ordersMigrated, equals(846));
    });

    test('2. Bütünlük ve Yabancı Anahtar (FK) Kontrolleri', () async {
      final integrityCheck = await targetDb.db.rawQuery('PRAGMA integrity_check;');
      final integrityResult = integrityCheck.first.values.first.toString();
      print('TARGET INTEGRITY: $integrityResult');
      expect(integrityResult, equals('ok'));

      final fkCheck = await targetDb.db.rawQuery('PRAGMA foreign_key_check;');
      print('TARGET FK VIOLATIONS: ${fkCheck.length}');
      expect(fkCheck, isEmpty);
    });

    test('3. Müşteri ve Kuruş Bakiye Mutabakatı', () async {
      final custCount = Sqflite.firstIntValue(
        await targetDb.db.rawQuery('SELECT COUNT(*) FROM customers'),
      );
      print('TARGET CUSTOMERS COUNT: $custCount');
      expect(custCount, equals(626));

      final targetBalanceSum = Sqflite.firstIntValue(
        await targetDb.db.rawQuery('SELECT SUM(balance_cents) FROM customers'),
      );
      print('TARGET BALANCE SUM (cents): $targetBalanceSum');
      // Kaynakta -135,263.18 TL -> Hedefte -13,526,318 kuruş
      expect(targetBalanceSum, equals(-13526318));
    });

    test('4. Taksit Planları ve Kalemleri Mutabakatı', () async {
      final planCount = Sqflite.firstIntValue(
        await targetDb.db.rawQuery('SELECT COUNT(*) FROM customer_installment_plans'),
      );
      print('TARGET PLAN COUNT: $planCount');
      expect(planCount, equals(2));

      final instCount = Sqflite.firstIntValue(
        await targetDb.db.rawQuery('SELECT COUNT(*) FROM customer_installments'),
      );
      print('TARGET INSTALLMENT COUNT: $instCount');
      expect(instCount, equals(9));

      // Negatif taksit kaydının korunması
      final negInst = await targetDb.db.rawQuery(
        "SELECT id, amount_cents, status FROM customer_installments WHERE id = 'inst-ab6352d3-eeee-4f64-a2d0-923554147896'",
      );
      expect(negInst.isNotEmpty, isTrue);
      print('NEGATIVE INST IN TARGET: ${negInst.first}');
      expect(negInst.first['amount_cents'], equals(-446532));
    });

    test('5. Finansal Hareketler (Ledger Entries & Cash Transactions) Mutabakatı', () async {
      final ledgerCount = Sqflite.firstIntValue(
        await targetDb.db.rawQuery('SELECT COUNT(*) FROM ledger_entries'),
      );
      final cashCount = Sqflite.firstIntValue(
        await targetDb.db.rawQuery('SELECT COUNT(*) FROM cash_transactions'),
      );
      print('TARGET LEDGER ENTRIES: $ledgerCount');
      print('TARGET CASH TRANSACTIONS: $cashCount');
      print('TOTAL FINANCIAL MOVEMENTS: ${ledgerCount! + cashCount!}');
      expect(ledgerCount + cashCount, equals(1526));
    });
  });
}
