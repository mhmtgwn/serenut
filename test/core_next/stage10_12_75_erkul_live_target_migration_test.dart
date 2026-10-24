
// test/core_next/stage10_12_75_erkul_live_target_migration_test.dart
// STAGE 10.12.75: Erkul Çeyiz Isolated Core Next Target Generation & Reconciliation
// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/erkul_json_importer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const sourceJsonPath = 'backups/raw_tenants_20261016/raw_erkul_source.json';
  const targetDir = 'backups/erkul_live_20261021';
  final targetDbPath = File('$targetDir/erkul_core_next.db').absolute.path;

  group('STAGE 10.12.75: Erkul Çeyiz İzole Hedef Oluşturma ve Mutabakat', () {
    late CoreAppDatabase targetDb;

    setUpAll(() async {
      expect(File(sourceJsonPath).existsSync(), isTrue, reason: 'Kaynak Erkul JSON dosyası mevcut olmalıdır.');

      final dir = Directory(targetDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final targetFile = File(targetDbPath);
      if (targetFile.existsSync()) {
        targetFile.deleteSync();
      }

      targetDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
    });

    tearDownAll(() async {
      await targetDb.close();
    });

    test('1. ErkulJsonImporter ile İçe Aktarım', () async {
      final importer = ErkulJsonImporter(targetDb);
      final report = await importer.importFromFile(sourceJsonPath);

      print('ERKUL IMPORT REPORT:');
      print('  Success: ${report.isSuccess}');
      print('  Users: ${report.usersMigrated}');
      print('  Categories: ${report.categoriesMigrated}');
      print('  Products: ${report.productsMigrated}');
      print('  Customers: ${report.customersMigrated} (Active: ${report.activeCustomersCount}, Deleted: ${report.deletedCustomersCount})');
      print('  Sales: ${report.salesMigrated}');
      print('  Sale Items: ${report.saleItemsMigrated}');
      print('  Orders: ${report.ordersMigrated}');
      print('  Order Items: ${report.orderItemsMigrated}');
      print('  Ledger Entries: ${report.ledgerEntriesMigrated}');
      print('  Manual Debt: ${report.manualDebtCount} (${report.manualDebtTotalCents} cents)');
      print('  Collection: ${report.collectionCount} (${report.collectionTotalCents} cents)');
      print('  Duration: ${report.durationMs}ms');

      expect(report.isSuccess, isTrue, reason: report.errorMessage);
      expect(report.productsMigrated, equals(26));
      expect(report.customersMigrated, equals(401));
      expect(report.activeCustomersCount, equals(381));
      expect(report.deletedCustomersCount, equals(20));
      expect(report.salesMigrated, equals(5));
      expect(report.saleItemsMigrated, equals(5));
      expect(report.ordersMigrated, equals(1));
      expect(report.orderItemsMigrated, equals(1));
      expect(report.ledgerEntriesMigrated, equals(539));
      expect(report.manualDebtCount, equals(423));
      expect(report.collectionCount, equals(109));
    });

    test('2. Bütünlük ve Yabancı Anahtar (FK) Kontrolleri', () async {
      final integrityCheck = await targetDb.db.rawQuery('PRAGMA integrity_check;');
      final integrityResult = integrityCheck.first.values.first.toString();
      print('ERKUL INTEGRITY: $integrityResult');
      expect(integrityResult, equals('ok'));

      final fkCheck = await targetDb.db.rawQuery('PRAGMA foreign_key_check;');
      print('ERKUL FK VIOLATIONS: ${fkCheck.length}');
      expect(fkCheck, isEmpty);
    });

    test('3. Kaynakta Olmayan Veri Üretmeme İlkesi', () async {
      final planCount = Sqflite.firstIntValue(
        await targetDb.db.rawQuery('SELECT COUNT(*) FROM customer_installment_plans'),
      );
      expect(planCount, equals(0));

      final instCount = Sqflite.firstIntValue(
        await targetDb.db.rawQuery('SELECT COUNT(*) FROM customer_installments'),
      );
      expect(instCount, equals(0));
    });

    test('4. Kuruş Bakiye ve Finansal Mutabakat', () async {
      final totalBalanceCents = Sqflite.firstIntValue(
        await targetDb.db.rawQuery('SELECT SUM(balance_cents) FROM customers'),
      );
      print('ERKUL TOTAL BALANCE CENTS: $totalBalanceCents');

      final activeBalanceCents = Sqflite.firstIntValue(
        await targetDb.db.rawQuery('SELECT SUM(balance_cents) FROM customers WHERE is_deleted = 0'),
      );
      print('ERKUL ACTIVE BALANCE CENTS: $activeBalanceCents');

      final deletedBalanceCents = Sqflite.firstIntValue(
        await targetDb.db.rawQuery('SELECT SUM(balance_cents) FROM customers WHERE is_deleted = 1'),
      );
      print('ERKUL DELETED BALANCE CENTS: $deletedBalanceCents');

      expect(totalBalanceCents, equals(activeBalanceCents! + deletedBalanceCents!));

      // 539 hareketin tamamı ledger_entries içinde mi?
      final ledgerCount = Sqflite.firstIntValue(
        await targetDb.db.rawQuery('SELECT COUNT(*) FROM ledger_entries'),
      );
      expect(ledgerCount, equals(539));
    });
  });
}
