// test/core_next/stage10_12_64_full_scale_export_import_test.dart
// STAGE 10.12.64: Full-Scale Isolated Export/Import, Erkul JSON Adapter & Customer-Level Financial Reconciliation
// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';
import '../../core_next/client_core/lib/infrastructure/migration/erkul_json_importer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final rawNutopiaPath = File('backups/raw_tenants_20261016/raw_nutopia_v60.db').absolute.path;
  final rawSerenutPath = File('backups/raw_tenants_20261016/raw_serenut_v44.db').absolute.path;
  final rawErkulPath = File('backups/raw_tenants_20261016/raw_erkul_source.json').absolute.path;

  final isolatedNutopiaDir = Directory('backups/stage64_isolated/nutopia').absolute.path;
  final isolatedSerenutDir = Directory('backups/stage64_isolated/serenut').absolute.path;
  final isolatedErkulDir = Directory('backups/stage64_isolated/erkul').absolute.path;

  group('STAGE 10.12.64: 1. Değişmez Güvenlik Sınırları & Salt-Okunur Kaynaklar', () {
    test('Kural 1: coreNextSalesEngineEnabledProvider kesinlikle false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
    });

    test('Kural 2: DatabaseManager.databaseRoutingHook kesinlikle null', () {
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });

    test('Kural 3: coreNextSaleExecutorProvider kesinlikle null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSaleExecutorProvider), isNull);
    });

    test('Kural 4: Kaynak arşivler mevcuttur ve boyutları doğrulanır', () {
      expect(File(rawNutopiaPath).existsSync(), isTrue);
      expect(File(rawSerenutPath).existsSync(), isTrue);
      expect(File(rawErkulPath).existsSync(), isTrue);

      expect(File(rawNutopiaPath).lengthSync(), equals(59764736));
      expect(File(rawSerenutPath).lengthSync(), equals(6516736));
      expect(File(rawErkulPath).lengthSync(), equals(485357));
    });
  });

  group('STAGE 10.12.64: 2. Erkul Çeyiz JSON Adaptörü & Kuruş Hassasiyetinde Finansal Mutabakat', () {
    late String erkulTargetDbPath;
    CoreAppDatabase? targetDb;

    setUpAll(() async {
      erkulTargetDbPath = '$isolatedErkulDir/erkul_core_next.db';
      await databaseFactory.deleteDatabase(erkulTargetDbPath);
      targetDb = await CoreAppDatabase.open(inMemoryOrCustomPath: erkulTargetDbPath);
    });

    tearDownAll(() async {
      if (targetDb != null) {
        await targetDb!.close();
        targetDb = null;
      }
    });

    test('Erkul JSON Adaptörü: Tam aktarım, bakiye rekonstrüksiyonu ve mutabakat', () async {
      final importer = ErkulJsonImporter(targetDb!);
      final report = await importer.importFromFile(rawErkulPath);

      expect(report.isSuccess, isTrue, reason: report.errorMessage);
      expect(report.usersMigrated, equals(1));
      expect(report.categoriesMigrated, greaterThanOrEqualTo(4));
      expect(report.productsMigrated, equals(26));
      expect(report.customersMigrated, equals(401));
      expect(report.activeCustomersCount, equals(381));
      expect(report.deletedCustomersCount, equals(20));
      expect(report.salesMigrated, equals(5));
      expect(report.saleItemsMigrated, equals(5));
      expect(report.ledgerEntriesMigrated, equals(539));
      expect(report.ordersMigrated, equals(1));
      expect(report.orderItemsMigrated, equals(1));

      // Finansal İşlem Dağılımı ve Kuruş Tutarları
      expect(report.manualDebtCount, equals(423));
      expect(report.manualDebtTotalCents, equals(431074500)); // 4,310,745.00 TL
      expect(report.collectionCount, equals(109));
      expect(report.collectionTotalCents, equals(54164000)); // 541,640.00 TL
      expect(report.saleTxCount, equals(6));
      expect(report.saleTxTotalCents, equals(3003000)); // 30,030.00 TL
      expect(report.paymentCount, equals(1));
      expect(report.paymentTotalCents, equals(1000)); // 10.00 TL

      // 381 Aktif Müşteri Gerçek Alacak: 3,787,125.00 TL (378,712,500 kuruş)
      expect(report.activeCustomerReceivableCents, equals(378712500));
      // 20 Silinmiş Müşteri Kapanmış Bakiye: 0 kuruş
      expect(report.deletedCustomerBalanceCents, equals(0));

      // Hedef Veritabanında Doğrudan SQL Doğrulaması
      final activeBalRows = await targetDb!.query(
        'customers',
        columns: ['SUM(balance_cents) as total_bal'],
        where: 'is_deleted = 0 AND is_active = 1',
      );
      final activeTotalBal = (activeBalRows.first['total_bal'] as num).toInt();
      // Serenut OS borç gösterimi negatiftir: -378,712,500 kuruş (-3,787,125.00 TL)
      expect(activeTotalBal, equals(-378712500));

      final deletedBalRows = await targetDb!.query(
        'customers',
        columns: ['SUM(balance_cents) as total_bal'],
        where: 'is_deleted = 1 OR is_active = 0',
      );
      final deletedTotalBal = (deletedBalRows.first['total_bal'] as num?)?.toInt() ?? 0;
      expect(deletedTotalBal, equals(0));

      // Defter Bakiyesi ile Müşteri Bakiyesi Uyumu (Double-entry Ledger Check)
      final ledgerRows = await targetDb!.query(
        'ledger_entries',
        columns: ['customer_id', 'balance_after_cents'],
        orderBy: 'created_at DESC',
      );
      final latestLedgerByCust = <String, int>{};
      for (final r in ledgerRows) {
        final cid = r['customer_id'] as String;
        latestLedgerByCust.putIfAbsent(cid, () => (r['balance_after_cents'] as num).toInt());
      }
      for (final cid in latestLedgerByCust.keys) {
        final cRow = await targetDb!.query('customers', columns: ['balance_cents'], where: 'id = ?', whereArgs: [cid]);
        final cBal = (cRow.first['balance_cents'] as num).toInt();
        expect(latestLedgerByCust[cid], equals(cBal), reason: 'Müşteri $cid için son defter bakiyesi müşteri bakiyesine eşit olmalıdır');
      }

      // SQLite Bütünlük Denetimleri
      final integrityCheck = await targetDb!.db.rawQuery('PRAGMA integrity_check;');
      expect(integrityCheck.first.values.first, equals('ok'));

      final fkCheck = await targetDb!.db.rawQuery('PRAGMA foreign_key_check;');
      expect(fkCheck, isEmpty);

      // Ayarlar kontrolü
      final settings = await targetDb!.query('app_settings');
      final sMap = {for (final s in settings) s['key']: s['value']};
      expect(sMap['tenant_id'], equals('erkul'));
      expect(sMap['business_name'], equals('ERKUL ÇEYİZ'));
      expect(sMap['legacy_migration_completed'], equals('true'));
    });

    test('Erkul JSON Adaptörü: Idempotens (İkinci çalıştırmada kayıt veya bakiye çoğalmaz)', () async {
      final importer = ErkulJsonImporter(targetDb!);
      final report1 = await importer.importFromFile(rawErkulPath);
      expect(report1.isSuccess, isTrue);

      // İkinci çalıştırma
      final report2 = await importer.importFromFile(rawErkulPath);
      expect(report2.isSuccess, isTrue);

      // Kayıt sayıları değişmemeli
      final custCount = Sqflite.firstIntValue(await targetDb!.db.rawQuery('SELECT COUNT(*) FROM customers'));
      expect(custCount, equals(401));

      final prodCount = Sqflite.firstIntValue(await targetDb!.db.rawQuery('SELECT COUNT(*) FROM products'));
      expect(prodCount, equals(26));

      final saleCount = Sqflite.firstIntValue(await targetDb!.db.rawQuery('SELECT COUNT(*) FROM sales'));
      expect(saleCount, equals(5));

      final activeBal = Sqflite.firstIntValue(
        await targetDb!.db.rawQuery('SELECT SUM(balance_cents) FROM customers WHERE is_deleted = 0 AND is_active = 1'),
      );
      expect(activeBal, equals(-378712500));
    });

    test('Erkul JSON Adaptörü: Bilinmeyen işlem türü aktarımı bloke eder ve rollback yapar (Fail-Closed)', () async {
      final failDbPath = '$isolatedErkulDir/erkul_fail_closed_test.db';
      await databaseFactory.deleteDatabase(failDbPath);
      final failDb = await CoreAppDatabase.open(inMemoryOrCustomPath: failDbPath);

      try {
        final invalidJson = jsonDecode(await File(rawErkulPath).readAsString(encoding: utf8)) as Map<String, dynamic>;
        final fts = List<Map<String, dynamic>>.from(invalidJson['financial_transactions'] as List);
        // Bilinmeyen bir işlem türü ekle
        fts.add({
          'id': 'trans-corrupt-unknown-type-999',
          'customer_id': '31e32d8d-ee87-46af-a4ed-4e073520f7ec',
          'type': 'unauthorized_crypto_swap',
          'amount': 50000.0,
          'created_at': '2026-10-14T10:00:00.000000+00:00',
        });
        invalidJson['financial_transactions'] = fts;

        final importer = ErkulJsonImporter(failDb);
        final report = await importer.importFromJson(invalidJson);

        expect(report.isSuccess, isFalse);
        expect(report.errorMessage, contains('UnrecognizedFinancialTransactionTypeException'));
        expect(report.errorMessage, contains('unauthorized_crypto_swap'));

        // Rollback: Veritabanında hiçbir müşteri veya ürün kalmamalı
        final cCount = Sqflite.firstIntValue(await failDb.db.rawQuery('SELECT COUNT(*) FROM customers'));
        expect(cCount, equals(0));
      } finally {
        await failDb.close();
      }
    });
  });

  group('STAGE 10.12.64: 3. Serenut Tam Ölçekli İzole Veri Aktarımı (v44)', () {
    late String serenutWorkDbPath;
    late String serenutTargetDbPath;
    CoreAppDatabase? targetDb;
    Database? workDb;

    setUpAll(() async {
      serenutWorkDbPath = '$isolatedSerenutDir/serenut_source_work.db';
      serenutTargetDbPath = '$isolatedSerenutDir/serenut_core_next.db';

      // İzole çalışma kopyası oluştur
      await databaseFactory.deleteDatabase(serenutWorkDbPath);
      File(rawSerenutPath).copySync(serenutWorkDbPath);

      await databaseFactory.deleteDatabase(serenutTargetDbPath);
      targetDb = await CoreAppDatabase.open(inMemoryOrCustomPath: serenutTargetDbPath);
      workDb = await databaseFactory.openDatabase(serenutWorkDbPath);
    });

    tearDownAll(() async {
      if (workDb != null && workDb!.isOpen) {
        await workDb!.close();
        workDb = null;
      }
      if (targetDb != null) {
        await targetDb!.close();
        targetDb = null;
      }
    });

    test('Serenut (v44): MigrationBridgeEngine tam aktarımı, stok ve bakiye doğrulaması', () async {
      final engine = MigrationBridgeEngine(targetDb!);
      final report = await engine.migrateFromLegacy(
        workDb!,
        legacyFilePath: serenutWorkDbPath,
        fullScope: true,
      );

      expect(report.isSuccess, isTrue, reason: report.errorMessage);
      expect(report.productsMigrated, equals(6377));
      expect(report.customersMigrated, equals(7));
      expect(report.salesMigrated, equals(15));
      expect(report.saleItemsMigrated, equals(19));
      expect(report.ledgerEntriesMigrated, equals(12));
      expect(report.cashTransactionsMigrated, equals(10));
      expect(report.ledgerEntriesMigrated + report.cashTransactionsMigrated, equals(22));
      expect(report.ordersMigrated, equals(5));

      // Stok Doğrulaması: Adet ve Kg ayrımı
      final pieceProds = await targetDb!.query('products', where: "unit = 'piece'");
      final kgProds = await targetDb!.query('products', where: "unit = 'kg'");
      expect(pieceProds.length, equals(6368));
      expect(kgProds.length, equals(9));

      // Toplam müşteri bakiyesi: -2,673.00 TL (-267,300 kuruş)
      final balRow = await targetDb!.query('customers', columns: ['SUM(balance_cents) as total_bal']);
      final totalBal = (balRow.first['total_bal'] as num).toInt();
      expect(totalBal, equals(-267300));

      // Bütünlük Denetimleri
      final integrityCheck = await targetDb!.db.rawQuery('PRAGMA integrity_check;');
      expect(integrityCheck.first.values.first, equals('ok'));

      final fkCheck = await targetDb!.db.rawQuery('PRAGMA foreign_key_check;');
      expect(fkCheck, isEmpty);
    });

    test('Serenut (v44): Idempotens (İkinci çalıştırmada kayıt veya bakiye çoğalmaz)', () async {
      final engine = MigrationBridgeEngine(targetDb!);
      final report = await engine.migrateFromLegacy(workDb!, fullScope: true);
      expect(report.isSuccess, isTrue);

      final pCount = Sqflite.firstIntValue(await targetDb!.db.rawQuery('SELECT COUNT(*) FROM products'));
      expect(pCount, equals(6377));

      final cCount = Sqflite.firstIntValue(await targetDb!.db.rawQuery('SELECT COUNT(*) FROM customers'));
      expect(cCount, equals(7));

      final bal = Sqflite.firstIntValue(await targetDb!.db.rawQuery('SELECT SUM(balance_cents) FROM customers'));
      expect(bal, equals(-267300));
    });
  });

  group('STAGE 10.12.64: 4. Nutopia Tam Ölçekli İzole Veri Aktarımı (v60, 60 MB)', () {
    late String nutopiaWorkDbPath;
    late String nutopiaTargetDbPath;
    CoreAppDatabase? targetDb;
    Database? workDb;

    setUpAll(() async {
      nutopiaWorkDbPath = '$isolatedNutopiaDir/nutopia_source_work.db';
      nutopiaTargetDbPath = '$isolatedNutopiaDir/nutopia_core_next.db';

      // İzole çalışma kopyası oluştur
      await databaseFactory.deleteDatabase(nutopiaWorkDbPath);
      File(rawNutopiaPath).copySync(nutopiaWorkDbPath);

      await databaseFactory.deleteDatabase(nutopiaTargetDbPath);
      targetDb = await CoreAppDatabase.open(inMemoryOrCustomPath: nutopiaTargetDbPath);
      workDb = await databaseFactory.openDatabase(nutopiaWorkDbPath);
    });

    tearDownAll(() async {
      if (workDb != null && workDb!.isOpen) {
        await workDb!.close();
        workDb = null;
      }
      if (targetDb != null) {
        await targetDb!.close();
        targetDb = null;
      }
    });

    test('Nutopia (v60): 37,682 ürünlük tam aktarım, kuruş bakiye ve stok mutabakatı', () async {
      final engine = MigrationBridgeEngine(targetDb!);
      final report = await engine.migrateFromLegacy(
        workDb!,
        legacyFilePath: nutopiaWorkDbPath,
        fullScope: true,
      );

      expect(report.isSuccess, isTrue, reason: report.errorMessage);
      expect(report.productsMigrated, equals(37682));
      expect(report.customersMigrated, equals(584));
      expect(report.salesMigrated, equals(52));
      expect(report.saleItemsMigrated, equals(120));
      expect(report.ledgerEntriesMigrated, equals(1403));
      expect(report.cashTransactionsMigrated, equals(21));
      expect(report.ledgerEntriesMigrated + report.cashTransactionsMigrated, equals(1424));
      expect(report.ordersMigrated, equals(792));

      // Stok Birim Ayrımı: 37,673 Adet, 9 Kg
      final pieceCount = Sqflite.firstIntValue(
        await targetDb!.db.rawQuery("SELECT COUNT(*) FROM products WHERE unit = 'piece'"),
      );
      final kgCount = Sqflite.firstIntValue(
        await targetDb!.db.rawQuery("SELECT COUNT(*) FROM products WHERE unit = 'kg'"),
      );
      expect(pieceCount, equals(37673));
      expect(kgCount, equals(9));

      // Kuruş Bakiye Mutabakatı: -134,500.68 TL (-13,450,068 kuruş)
      final bal = Sqflite.firstIntValue(
        await targetDb!.db.rawQuery('SELECT SUM(balance_cents) FROM customers'),
      );
      expect(bal, equals(-13450068));

      // Bütünlük Denetimleri
      final integrityCheck = await targetDb!.db.rawQuery('PRAGMA integrity_check;');
      expect(integrityCheck.first.values.first, equals('ok'));

      final fkCheck = await targetDb!.db.rawQuery('PRAGMA foreign_key_check;');
      expect(fkCheck, isEmpty);
    });

    test('Nutopia (v60): Idempotens (İkinci çalıştırmada kayıt veya bakiye çoğalmaz)', () async {
      final engine = MigrationBridgeEngine(targetDb!);
      final report = await engine.migrateFromLegacy(workDb!, fullScope: true);
      expect(report.isSuccess, isTrue);

      final pCount = Sqflite.firstIntValue(await targetDb!.db.rawQuery('SELECT COUNT(*) FROM products'));
      expect(pCount, equals(37682));

      final cCount = Sqflite.firstIntValue(await targetDb!.db.rawQuery('SELECT COUNT(*) FROM customers'));
      expect(cCount, equals(584));

      final bal = Sqflite.firstIntValue(await targetDb!.db.rawQuery('SELECT SUM(balance_cents) FROM customers'));
      expect(bal, equals(-13450068));
    });

    test('Nutopia (v60): Elle Eklenen Senetli ve Manuel Borç/Taksit İşlemleri Kuruş Hassasiyetinde Mutabakatı', () async {
      // 1. Manuel Borçlar: 54 kayıt, tam 10,335,100 kuruş (103,351.00 TL)
      final manualDebtCount = Sqflite.firstIntValue(
        await targetDb!.db.rawQuery("SELECT COUNT(*) FROM ledger_entries WHERE entry_type = 'MANUAL_DEBT'"),
      );
      final manualDebtSum = Sqflite.firstIntValue(
        await targetDb!.db.rawQuery("SELECT SUM(amount_cents) FROM ledger_entries WHERE entry_type = 'MANUAL_DEBT'"),
      );
      expect(manualDebtCount, equals(54));
      expect(manualDebtSum, equals(10335100));

      // 2. Taksit Planları: 2 kayıt (1 active, 1 cancelled)
      final planCount = Sqflite.firstIntValue(
        await targetDb!.db.rawQuery('SELECT COUNT(*) FROM customer_installment_plans'),
      );
      final planActiveCount = Sqflite.firstIntValue(
        await targetDb!.db.rawQuery("SELECT COUNT(*) FROM customer_installment_plans WHERE status = 'active'"),
      );
      final planCancelledCount = Sqflite.firstIntValue(
        await targetDb!.db.rawQuery("SELECT COUNT(*) FROM customer_installment_plans WHERE status = 'cancelled'"),
      );
      expect(planCount, equals(2));
      expect(planActiveCount, equals(1));
      expect(planCancelledCount, equals(1));

      // 3. Taksit Detayları: 9 taksit (3 active/paid, 6 cancelled)
      final instCount = Sqflite.firstIntValue(
        await targetDb!.db.rawQuery('SELECT COUNT(*) FROM customer_installments'),
      );
      final instPaidCount = Sqflite.firstIntValue(
        await targetDb!.db.rawQuery("SELECT COUNT(*) FROM customer_installments WHERE status = 'paid'"),
      );
      final instCancelledCount = Sqflite.firstIntValue(
        await targetDb!.db.rawQuery("SELECT COUNT(*) FROM customer_installments WHERE status = 'cancelled'"),
      );
      expect(instCount, equals(9));
      expect(instPaidCount, equals(2));
      expect(instCancelledCount, equals(6));

      // 4. Taksit Tahsilatları: 8 adet taksit açıklamalı tahsilat kaydı, 975,332 kuruş (9,753.32 TL)
      final instColCount = Sqflite.firstIntValue(
        await targetDb!.db.rawQuery("SELECT COUNT(*) FROM ledger_entries WHERE entry_type = 'COLLECTION' AND (description LIKE '%Taksit%' OR description LIKE '%taksit%')"),
      );
      final instColSum = Sqflite.firstIntValue(
        await targetDb!.db.rawQuery("SELECT SUM(amount_cents) FROM ledger_entries WHERE entry_type = 'COLLECTION' AND (description LIKE '%Taksit%' OR description LIKE '%taksit%')"),
      );
      expect(instColCount, equals(8));
      expect(instColSum, equals(975332));

      // 5. Satış kayıtlarıyla çakışmama: Hiçbir manual_debt kaydı sale_items veya sales ID'siyle çakışmaz
      final salesOverlap = Sqflite.firstIntValue(
        await targetDb!.db.rawQuery("SELECT COUNT(*) FROM ledger_entries WHERE entry_type = 'MANUAL_DEBT' AND reference_sale_id IN (SELECT id FROM sales)"),
      );
      expect(salesOverlap, equals(0));
    });
  });

  group('STAGE 10.12.64: 5. Üç İşletmenin Kesin Ayrılığı ve ID Çakışma Denetimi', () {
    test('Her işletmenin izole hedefinde sadece kendi kiracı kimliği ve verisi bulunur', () async {
      // 1. Erkul hedefi
      final erkulDb = await CoreAppDatabase.open(inMemoryOrCustomPath: '$isolatedErkulDir/erkul_core_next.db');
      final erkulSettings = await erkulDb.query('app_settings', where: "key = 'tenant_id'");
      expect(erkulSettings.isNotEmpty, isTrue);
      expect(erkulSettings.first['value'], equals('erkul'));
      final erkulNameSettings = await erkulDb.query('app_settings', where: "key = 'business_name'");
      expect(erkulNameSettings.first['value'], equals('ERKUL ÇEYİZ'));
      final erkulProdCount = Sqflite.firstIntValue(await erkulDb.db.rawQuery('SELECT COUNT(*) FROM products'));
      expect(erkulProdCount, equals(26));
      await erkulDb.close();

      // 2. Serenut hedefi
      final serenutDb = await CoreAppDatabase.open(inMemoryOrCustomPath: '$isolatedSerenutDir/serenut_core_next.db');
      final serenutSettings = await serenutDb.query('app_settings', where: "key = 'tenant_id'");
      expect(serenutSettings.isNotEmpty, isTrue);
      expect(serenutSettings.first['value'], equals('serenut'));
      final serenutNameSettings = await serenutDb.query('app_settings', where: "key = 'business_name'");
      expect(serenutNameSettings.first['value'], equals('serenut'));
      final serenutProdCount = Sqflite.firstIntValue(await serenutDb.db.rawQuery('SELECT COUNT(*) FROM products'));
      expect(serenutProdCount, equals(6377));
      await serenutDb.close();

      // 3. Nutopia hedefi
      final nutopiaDb = await CoreAppDatabase.open(inMemoryOrCustomPath: '$isolatedNutopiaDir/nutopia_core_next.db');
      final nutopiaSettings = await nutopiaDb.query('app_settings', where: "key = 'tenant_id'");
      expect(nutopiaSettings.isNotEmpty, isTrue);
      expect(nutopiaSettings.first['value'], equals('nutopia'));
      final nutopiaNameSettings = await nutopiaDb.query('app_settings', where: "key = 'business_name'");
      expect(nutopiaNameSettings.first['value'], equals('Nutopia Fındık Değirmeni'));
      final nutopiaProdCount = Sqflite.firstIntValue(await nutopiaDb.db.rawQuery('SELECT COUNT(*) FROM products'));
      expect(nutopiaProdCount, equals(37682));
      await nutopiaDb.close();
    });
  });
}
