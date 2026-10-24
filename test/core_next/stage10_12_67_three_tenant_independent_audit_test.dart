// test/core_next/stage10_12_67_three_tenant_independent_audit_test.dart
// STAGE 10.12.67: Üç İşletme Tam Kapsamlı Bağımsız Aktarım Mutabakatı Testi
// Bu test HİÇBİR veritabanına veya dosyaya YAZMAZ. Salt-okunur (readOnly: true) modda çalışır.
// ignore_for_file: avoid_relative_lib_imports, prefer_single_quotes

import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final nutopiaSrcPath = File('backups/raw_tenants_20261016/raw_nutopia_v60.db').absolute.path;
  final nutopiaTgtPath = File('backups/stage64_isolated/nutopia/nutopia_core_next.db').absolute.path;

  final serenutSrcPath = File('backups/raw_tenants_20261016/raw_serenut_v44.db').absolute.path;
  final serenutTgtPath = File('backups/stage64_isolated/serenut/serenut_core_next.db').absolute.path;

  final erkulSrcPath = File('backups/raw_tenants_20261016/raw_erkul_source.json').absolute.path;
  final erkulTgtPath = File('backups/stage64_isolated/erkul/erkul_core_next.db').absolute.path;

  group('STAGE 10.12.67: 1. Değişmez Güvenlik Sınırları & Salt-Okunur Dosya Bütünlüğü', () {
    test('Kural 1: Güvenlik bayrakları kesinlikle devredışıdır', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
      expect(DatabaseManager.databaseRoutingHook, isNull);
      expect(container.read(coreNextSaleExecutorProvider), isNull);
    });

    test('Kural 2: Altı dosya mevcuttur, boyutları doğrulanır', () {
      expect(File(nutopiaSrcPath).lengthSync(), equals(59764736));
      expect(File(nutopiaTgtPath).lengthSync(), equals(17018880));

      expect(File(serenutSrcPath).lengthSync(), equals(6516736));
      expect(File(serenutTgtPath).lengthSync(), equals(2359296));

      expect(File(erkulSrcPath).lengthSync(), equals(485357));
      expect(File(erkulTgtPath).lengthSync(), equals(565248));
    });
  });

  group('STAGE 10.12.67: 2. İşletme İzolasyonu ve Çapraz Veri Sızıntısı Olmadığının Kanıtı', () {
    test('Her üç hedefin app_settings tablosunda doğru kiracı kimliği ve adı vardır', () async {
      final nDb = await openReadOnlyDatabase(nutopiaTgtPath);
      final sDb = await openReadOnlyDatabase(serenutTgtPath);
      final eDb = await openReadOnlyDatabase(erkulTgtPath);

      final nSet = await nDb.query('app_settings');
      final sSet = await sDb.query('app_settings');
      final eSet = await eDb.query('app_settings');

      final nMap = {for (final r in nSet) r['key'] as String: r['value'] as String};
      final sMap = {for (final r in sSet) r['key'] as String: r['value'] as String};
      final eMap = {for (final r in eSet) r['key'] as String: r['value'] as String};

      expect(nMap['tenant_id'], equals('nutopia'));
      expect(nMap['business_name'], equals('Nutopia Fındık Değirmeni'));

      expect(sMap['tenant_id'], equals('serenut'));
      expect(sMap['business_name'], equals('serenut'));

      expect(eMap['tenant_id'], equals('erkul'));
      expect(eMap['business_name'], equals('ERKUL ÇEYİZ'));

      await nDb.close();
      await sDb.close();
      await eDb.close();
    });

    test('Erkul Çeyiz verileri Nutopia veya Serenut hedeflerine kesinlikle sızmamıştır', () async {
      final erkulJson = jsonDecode(File(erkulSrcPath).readAsStringSync()) as Map<String, dynamic>;
      final erkulCustIds = ((erkulJson['customers'] as List?) ?? []).map((c) => c['id'] as String).toSet();
      final erkulProdIds = ((erkulJson['products'] as List?) ?? []).map((p) => p['id'] as String).toSet();

      final nDb = await openReadOnlyDatabase(nutopiaTgtPath);
      final sDb = await openReadOnlyDatabase(serenutTgtPath);

      final nCusts = (await nDb.query('customers', columns: ['id'])).map((r) => r['id'] as String).toSet();
      final sCusts = (await sDb.query('customers', columns: ['id'])).map((r) => r['id'] as String).toSet();

      final nProds = (await nDb.query('products', columns: ['id'])).map((r) => r['id'] as String).toSet();
      final sProds = (await sDb.query('products', columns: ['id'])).map((r) => r['id'] as String).toSet();

      expect(erkulCustIds.intersection(nCusts), isEmpty);
      expect(erkulCustIds.intersection(sCusts), isEmpty);
      expect(erkulProdIds.intersection(nProds), isEmpty);
      expect(erkulProdIds.intersection(sProds), isEmpty);

      await nDb.close();
      await sDb.close();
    });
  });

  group('STAGE 10.12.67: 3. Serenut Ürün ve Stok Çelişkisinin Kök Neden Kanıtı', () {
    late Database sSrcDb;
    late Database sTgtDb;

    setUpAll(() async {
      sSrcDb = await openReadOnlyDatabase(serenutSrcPath);
      sTgtDb = await openReadOnlyDatabase(serenutTgtPath);
    });

    tearDownAll(() async {
      await sSrcDb.close();
      await sTgtDb.close();
    });

    test('Serenut (v44): 6368/9 vs 6369/8 çelişkisinin kök nedeni Mancar ürünüdür', () async {
      // 1. Kaynakta toplam ürün 6377'dir
      final srcTotal = Sqflite.firstIntValue(await sSrcDb.rawQuery('SELECT COUNT(*) FROM products'));
      expect(srcTotal, equals(6377));

      // 2. unit = 'adet' ve sale_type = 'piece' -> 6368 adet ürün, 636,640 adet stok
      final pieceRows = await sSrcDb.rawQuery(
        "SELECT COUNT(*) as cnt, SUM(quantity) as stock FROM products WHERE unit = 'adet' AND sale_type = 'piece'",
      );
      expect(pieceRows.first['cnt'], equals(6368));
      expect(pieceRows.first['stock'], equals(636640));

      // 3. unit = 'kg' ve sale_type = 'weighed' -> 8 kg ürün, 705 kg stok
      final kgWeighedRows = await sSrcDb.rawQuery(
        "SELECT COUNT(*) as cnt, SUM(quantity) as stock FROM products WHERE unit = 'kg' AND sale_type = 'weighed'",
      );
      expect(kgWeighedRows.first['cnt'], equals(8));
      expect(kgWeighedRows.first['stock'], equals(705));

      // 4. KÖK NEDEN: 1 ürünün ('123456', 'Mancar') unit'i 'adet' iken sale_type'ı 'weighed'dir!
      final mancar = await sSrcDb.rawQuery(
        "SELECT id, name, unit, sale_type, quantity FROM products WHERE id = '123456'",
      );
      expect(mancar.length, equals(1));
      expect(mancar.first['name'], equals('Mancar'));
      expect(mancar.first['unit'], equals('adet'));
      expect(mancar.first['sale_type'], equals('weighed'));
      expect(mancar.first['quantity'], equals(100));

      // 5. Migration kuralı (sale_type == 'weighed' || unit == 'kg') -> 'kg'
      // Bu kural Mancar'ı tartılı ürün kabul eder, dolayısıyla hedefte:
      // kg ürün sayısı: 8 + 1 = 9 adet, stok: 705 + 100 = 805 kg
      // piece ürün sayısı: 6368 adet, stok: 636,640 adet
      final tgtPiece = await sTgtDb.rawQuery(
        "SELECT COUNT(*) as cnt, SUM(stock_quantity) as stock FROM products WHERE unit = 'piece'",
      );
      final tgtKg = await sTgtDb.rawQuery(
        "SELECT COUNT(*) as cnt, SUM(stock_quantity) as stock FROM products WHERE unit = 'kg'",
      );
      expect(tgtPiece.first['cnt'], equals(6368));
      expect(tgtPiece.first['stock'], equals(636640.0));
      expect(tgtKg.first['cnt'], equals(9));
      expect(tgtKg.first['stock'], equals(805.0));

      final tgtTotal = Sqflite.firstIntValue(await sTgtDb.rawQuery('SELECT COUNT(*) FROM products'));
      expect(tgtTotal, equals(6377));
    });

    test('Serenut (v44): Finansal Bakiye ve Defter Mutabakatı (-2,673.00 TL)', () async {
      final srcBal = await sSrcDb.rawQuery('SELECT SUM(balance) FROM customers');
      expect((srcBal.first.values.first as num).toDouble(), equals(-2673.0));

      final tgtBalCents = Sqflite.firstIntValue(await sTgtDb.rawQuery('SELECT SUM(balance_cents) FROM customers'));
      expect(tgtBalCents, equals(-267300)); // -2,673.00 TL

      final ledgerCount = Sqflite.firstIntValue(await sTgtDb.rawQuery('SELECT COUNT(*) FROM ledger_entries'));
      final cashCount = Sqflite.firstIntValue(await sTgtDb.rawQuery('SELECT COUNT(*) FROM cash_transactions'));
      expect(ledgerCount, equals(12));
      expect(cashCount, equals(10));
      expect(ledgerCount! + cashCount!, equals(22));
    });
  });

  group('STAGE 10.12.67: 4. Erkul Çeyiz Finansal Semantik ve Müşteri Mutabakatı', () {
    late Database eTgtDb;
    late Map<String, dynamic> erkulJson;

    setUpAll(() async {
      eTgtDb = await openReadOnlyDatabase(erkulTgtPath);
      erkulJson = jsonDecode(File(erkulSrcPath).readAsStringSync()) as Map<String, dynamic>;
    });

    tearDownAll(() async {
      await eTgtDb.close();
    });

    test('Erkul Çeyiz: 401 Müşteri, 26 Ürün, 5 Satış, 539 Defter İşlemi Tam Eşleşmesi', () async {
      final custs = (erkulJson['customers'] as List?) ?? [];
      final prods = (erkulJson['products'] as List?) ?? [];
      final sales = (erkulJson['sales'] as List?) ?? [];
      final fts = (erkulJson['financial_transactions'] as List?) ?? [];

      expect(custs.length, equals(401));
      expect(prods.length, equals(26));
      expect(sales.length, equals(5));
      expect(fts.length, equals(539));

      final tgtCustCount = Sqflite.firstIntValue(await eTgtDb.rawQuery('SELECT COUNT(*) FROM customers'));
      final tgtProdCount = Sqflite.firstIntValue(await eTgtDb.rawQuery('SELECT COUNT(*) FROM products'));
      final tgtSaleCount = Sqflite.firstIntValue(await eTgtDb.rawQuery('SELECT COUNT(*) FROM sales'));
      final tgtLedgerCount = Sqflite.firstIntValue(await eTgtDb.rawQuery('SELECT COUNT(*) FROM ledger_entries'));

      expect(tgtCustCount, equals(401));
      expect(tgtProdCount, equals(26));
      expect(tgtSaleCount, equals(5));
      expect(tgtLedgerCount, equals(539));
    });

    test('Erkul Çeyiz: Finansal Semantik (381 Aktif Caride 3.787.125 TL Alacak, 20 Silinmiş Caride 0 TL)', () async {
      final activeBalCents = Sqflite.firstIntValue(
        await eTgtDb.rawQuery('SELECT SUM(balance_cents) FROM customers WHERE is_deleted = 0'),
      );
      final deletedBalCents = Sqflite.firstIntValue(
        await eTgtDb.rawQuery('SELECT SUM(balance_cents) FROM customers WHERE is_deleted = 1'),
      );

      // 381 Aktif Cari: -378,712,500 kuruş (-3,787,125.00 TL net alacak)
      expect(activeBalCents, equals(-378712500));
      // 20 Silinmiş/Kapanmış Cari: Borç ve tahsilat birbirini kapattığı için bakiye sıfırdır
      expect(deletedBalCents, equals(0));
    });
  });

  group('STAGE 10.12.67: 5. Nutopia Fındık Değirmeni Kapsamlı Mutabakatı', () {
    late Database nSrcDb;
    late Database nTgtDb;

    setUpAll(() async {
      nSrcDb = await openReadOnlyDatabase(nutopiaSrcPath);
      nTgtDb = await openReadOnlyDatabase(nutopiaTgtPath);
    });

    tearDownAll(() async {
      await nSrcDb.close();
      await nTgtDb.close();
    });

    test('Nutopia: 37,682 Ürün, 584 Müşteri, 52 Satış, 1,424 Hareket ve Kuruş Bakiye Mutabakatı', () async {
      final pCount = Sqflite.firstIntValue(await nTgtDb.rawQuery('SELECT COUNT(*) FROM products'));
      final cCount = Sqflite.firstIntValue(await nTgtDb.rawQuery('SELECT COUNT(*) FROM customers'));
      final sCount = Sqflite.firstIntValue(await nTgtDb.rawQuery('SELECT COUNT(*) FROM sales'));
      final lCount = Sqflite.firstIntValue(await nTgtDb.rawQuery('SELECT COUNT(*) FROM ledger_entries'));
      final cashCount = Sqflite.firstIntValue(await nTgtDb.rawQuery('SELECT COUNT(*) FROM cash_transactions'));

      expect(pCount, equals(37682));
      expect(cCount, equals(584));
      expect(sCount, equals(52));
      expect(lCount, equals(1403));
      expect(cashCount, equals(21));
      expect(lCount! + cashCount!, equals(1424));

      // Bakiye Mutabakatı: -134,500.68 TL
      final balCents = Sqflite.firstIntValue(await nTgtDb.rawQuery('SELECT SUM(balance_cents) FROM customers'));
      expect(balCents, equals(-13450068));
    });

    test('Nutopia: 54 Manuel Borç, 2 Taksit Planı, 9 Taksit ve 8 Tahsilat Tam Eşleşmesi', () async {
      final manualDebtCount = Sqflite.firstIntValue(
        await nTgtDb.rawQuery("SELECT COUNT(*) FROM ledger_entries WHERE entry_type = 'MANUAL_DEBT'"),
      );
      final manualDebtSum = Sqflite.firstIntValue(
        await nTgtDb.rawQuery("SELECT SUM(amount_cents) FROM ledger_entries WHERE entry_type = 'MANUAL_DEBT'"),
      );
      expect(manualDebtCount, equals(54));
      expect(manualDebtSum, equals(10335100)); // 103,351.00 TL

      final planCount = Sqflite.firstIntValue(await nTgtDb.rawQuery('SELECT COUNT(*) FROM customer_installment_plans'));
      final instCount = Sqflite.firstIntValue(await nTgtDb.rawQuery('SELECT COUNT(*) FROM customer_installments'));
      expect(planCount, equals(2));
      expect(instCount, equals(9));

      final colInstCount = Sqflite.firstIntValue(
        await nTgtDb.rawQuery(
          "SELECT COUNT(*) FROM ledger_entries WHERE entry_type = 'COLLECTION' AND (description LIKE '%Taksit%' OR description LIKE '%taksit%')",
        ),
      );
      final colInstSum = Sqflite.firstIntValue(
        await nTgtDb.rawQuery(
          "SELECT SUM(amount_cents) FROM ledger_entries WHERE entry_type = 'COLLECTION' AND (description LIKE '%Taksit%' OR description LIKE '%taksit%')",
        ),
      );
      expect(colInstCount, equals(8));
      expect(colInstSum, equals(975332)); // 9,753.32 TL
    });
  });
}
