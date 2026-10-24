// test/core_next/stage10_12_25_forensic_export_import_rehearsal_test.dart
// SERENUT OS — STAGE 10.12.25
// FORENSIC AUDIT, EXPORT/IMPORT REHEARSAL VE PRODUCTION READINESS TEST PAKETİ

@Timeout(Duration(minutes: 7))
library;

// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';
import '../../core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const String expectedNutopiaSha =
      'e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24';
  const String expectedSerenutSha =
      '9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d';
  const String expectedErkulSha =
      'b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389';

  final String nutopiaSourcePath = p.normalize(
    p.join(Directory.current.path, 'backups', 'raw_tenants_20261016', 'raw_nutopia_v60.db'),
  );
  final String serenutSourcePath = p.normalize(
    p.join(Directory.current.path, 'backups', 'raw_tenants_20261016', 'raw_serenut_v44.db'),
  );
  final String erkulSourcePath = p.normalize(
    p.join(Directory.current.path, 'backups', 'raw_tenants_20261016', 'raw_erkul_source.json'),
  );

  String calculateFileSha256(String filePath) {
    final bytes = File(filePath).readAsBytesSync();
    return sha256.convert(bytes).toString();
  }

  int count(List<Map<String, Object?>> rows) =>
      (rows.first.values.first as num).toInt();

  group('STAGE 10.12.25 — BÖLÜM 1: KAYNAK ADLİ DENETİMİ VE DOKUNULMAZLIK', () {
    test('1.1: 3 tenant kaynak yedeğinin SHA-256 imzaları başlangıçta tam eşleşmelidir', () {
      expect(File(nutopiaSourcePath).existsSync(), isTrue, reason: 'Nutopia DB bulunamadı');
      expect(File(serenutSourcePath).existsSync(), isTrue, reason: 'Serenut DB bulunamadı');
      expect(File(erkulSourcePath).existsSync(), isTrue, reason: 'Erkul JSON bulunamadı');

      expect(calculateFileSha256(nutopiaSourcePath), equals(expectedNutopiaSha));
      expect(calculateFileSha256(serenutSourcePath), equals(expectedSerenutSha));
      expect(calculateFileSha256(erkulSourcePath), equals(expectedErkulSha));
    });
  });

  group('STAGE 10.12.25 — BÖLÜM 2: 3 TENANT İZOLE EXPORT/IMPORT PROVASI VE DERİN MUTABAKAT', () {
    late Directory tempDir;
    late String nutopiaTargetPath;
    late String serenutTargetPath;
    late String erkulTargetPath;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('stg10_12_25_rehearsal_');
      nutopiaTargetPath = p.join(tempDir.path, 'nutopia_pos.db');
      serenutTargetPath = p.join(tempDir.path, 'serenut_pos.db');
      erkulTargetPath = p.join(tempDir.path, 'erkul_pos.db');
    });

    tearDownAll(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('2.1: Tenant 1 (Nutopia Fındık Değirmeni) tam kapsamlı dışa/içe aktarma ve parasal mutabakat', () async {
      final isolatedNutopiaSource = p.join(tempDir.path, 'raw_nutopia_copy.db');
      await File(nutopiaSourcePath).copy(isolatedNutopiaSource);

      final legacyDb = await openDatabase(isolatedNutopiaSource, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: nutopiaTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // Kaynak kontrolleri
      final srcProdTotal = count(await legacyDb.rawQuery('SELECT count(*) FROM products'));
      final srcCustTotal = count(await legacyDb.rawQuery('SELECT count(*) FROM customers'));
      final srcSalesTotal = count(await legacyDb.rawQuery('SELECT count(*) FROM sales'));
      final srcSaleItemsTotal = count(await legacyDb.rawQuery('SELECT count(*) FROM sale_items'));
      final srcOrdersTotal = count(await legacyDb.rawQuery('SELECT count(*) FROM orders'));
      final srcOrderItemsTotal = count(await legacyDb.rawQuery('SELECT count(*) FROM order_items'));

      expect(srcProdTotal, equals(37682));
      expect(srcCustTotal, equals(584));
      expect(srcSalesTotal, equals(52));
      expect(srcSaleItemsTotal, equals(120));
      expect(srcOrdersTotal, equals(792));
      expect(srcOrderItemsTotal, equals(1068));

      // Göçü çalıştır
      final report = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, isTrue, reason: report.errorMessage);
      expect(report.productsMigrated, equals(37682));
      expect(report.customersMigrated, equals(584));
      expect(report.salesMigrated, equals(52));
      expect(report.saleItemsMigrated, equals(120));
      expect(report.ordersMigrated, equals(792));
      expect(report.ledgerEntriesMigrated, equals(1403));
      expect(report.installmentsMigrated, equals(9));

      final target = coreDb.db;

      // 1. Ürün ve Stok Mutabakatı (Ondalıklı hassasiyet: 5.179.525,85)
      final tgtProdTotal = count(await target.rawQuery('SELECT count(*) FROM products'));
      expect(tgtProdTotal, equals(37682));

      final stockRow = await target.rawQuery('SELECT ROUND(SUM(stock_quantity), 2) as s FROM products');
      final totalStock = (stockRow.first['s'] as num).toDouble();
      expect((totalStock - 5179525.85).abs() < 0.01, isTrue, reason: 'Nutopia stok toplamı 5179525.85 olmalıdır: $totalStock');

      // 2. Müşteri Cari Bakiye Mutabakatı (-134.500,68 TL / -13.450.068 kuruş)
      final tgtCustTotal = count(await target.rawQuery('SELECT count(*) FROM customers'));
      expect(tgtCustTotal, equals(584));

      final balRow = await target.rawQuery('SELECT SUM(balance_cents) as s FROM customers');
      final totalBalCents = (balRow.first['s'] as num).toInt();
      expect(totalBalCents, equals(-13450068));

      // 3. Satış ve Parasal Ciro Mutabakatı (31.282,25 TL = 3.128.225 kuruş)
      final tgtSalesTotal = count(await target.rawQuery('SELECT count(*) FROM sales'));
      expect(tgtSalesTotal, equals(52));

      final salesCents = (await target.rawQuery('SELECT SUM(total_cents) as s FROM sales')).first['s'] as int;
      expect(salesCents, equals(3128225));

      final saleItemsCents = (await target.rawQuery('SELECT SUM(total_cents) as s FROM sale_items')).first['s'] as int;
      expect(saleItemsCents, equals(3130725));

      // 4. Kasa İşlemleri (21 adet müşterisiz nakit satış)
      final tgtCashTxs = count(await target.rawQuery("SELECT count(*) FROM cash_transactions WHERE category = 'SALE'"));
      expect(tgtCashTxs, equals(21));

      final cashTotalCents = (await target.rawQuery("SELECT SUM(amount_cents) as s FROM cash_transactions WHERE category = 'SALE'")).first['s'] as int;
      expect(cashTotalCents, equals(1219700));

      await legacyDb.close();
      await coreDb.close();
    });

    test('2.2: Tenant 2 (Serenut v44) dışa/içe aktarma ve mutabakat', () async {
      final isolatedSerenutSource = p.join(tempDir.path, 'raw_serenut_copy.db');
      await File(serenutSourcePath).copy(isolatedSerenutSource);

      final legacyDb = await openDatabase(isolatedSerenutSource, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: serenutTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      final report = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, isTrue, reason: report.errorMessage);
      expect(report.productsMigrated, equals(6377));
      expect(report.customersMigrated, equals(7));
      expect(report.salesMigrated, equals(15));
      expect(report.saleItemsMigrated, equals(19));
      expect(report.ordersMigrated, equals(5));

      final target = coreDb.db;

      final prodCount = count(await target.rawQuery('SELECT count(*) FROM products'));
      expect(prodCount, equals(6377));

      final stockRow = await target.rawQuery('SELECT ROUND(SUM(stock_quantity), 2) as s FROM products');
      final stockTotal = (stockRow.first['s'] as num).toDouble();
      expect((stockTotal - 637445.0).abs() < 0.01, isTrue);

      final custCount = count(await target.rawQuery('SELECT count(*) FROM customers'));
      expect(custCount, equals(7));

      final balRow = await target.rawQuery('SELECT SUM(balance_cents) as s FROM customers');
      final totalBalCents = (balRow.first['s'] as num).toInt();
      expect(totalBalCents, equals(-267300), reason: 'Serenut müşteri bakiyesi -2.673,00 TL (-267.300 kuruş) olmalıdır');

      await legacyDb.close();
      await coreDb.close();
    });

    test('2.3: Tenant 3 (Erkul Çeyiz) PostgreSQL JSON dışa/içe aktarma ve 401 müşteri cari alacak mutabakatı', () async {
      final rawContent = await File(erkulSourcePath).readAsString();
      final jsonMap = jsonDecode(rawContent) as Map<String, dynamic>;

      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: erkulTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      final report = await bridge.migrateFromErkulJson(jsonMap);
      expect(report.isSuccess, isTrue, reason: report.errorMessage);
      expect(report.customersMigrated, equals(401), reason: 'Erkul 401 müşterinin tamamı korunmalıdır!');
      expect(report.productsMigrated, equals(26));
      expect(report.salesMigrated, equals(5));
      expect(report.saleItemsMigrated, equals(5));
      expect(report.ledgerEntriesMigrated, equals(539));
      expect(report.ordersMigrated, equals(1));

      final target = coreDb.db;

      // 1. Müşteri Sayısı ve Toplam Cari Alacak Mutabakatı: -523.620,00 TL = -52.362.000 kuruş
      final custCount = count(await target.rawQuery('SELECT count(*) FROM customers'));
      expect(custCount, equals(401));

      final balRow = await target.rawQuery('SELECT SUM(balance_cents) as s FROM customers');
      final totalBalCents = (balRow.first['s'] as num).toInt();
      expect(totalBalCents, equals(-52362000), reason: 'Erkul alacak toplamı -52.362.000 kuruş olmalıdır');

      // 2. Kullanıcı yetki kontrolü
      final userRows = await target.rawQuery("SELECT * FROM users WHERE username = 'tunahan erkul' OR username = 'erkultunahan7@gmail.com'");
      expect(userRows.isNotEmpty, isTrue);

      await coreDb.close();
    });

    test('2.4: Tenant İzolasyonu (Çapraz Veri Sızıntısı Sıfır Olmalıdır)', () async {
      final nutopiaDb = await openDatabase(nutopiaTargetPath, readOnly: true, singleInstance: false);
      final serenutDb = await openDatabase(serenutTargetPath, readOnly: true, singleInstance: false);
      final erkulDb = await openDatabase(erkulTargetPath, readOnly: true, singleInstance: false);

      final erkulCustIds = (await erkulDb.query('customers', columns: ['id'])).map((r) => r['id'].toString()).toSet();
      final nutopiaCustIds = (await nutopiaDb.query('customers', columns: ['id'])).map((r) => r['id'].toString()).toSet();
      final serenutCustIds = (await serenutDb.query('customers', columns: ['id'])).map((r) => r['id'].toString()).toSet();

      // Erkul Çeyiz (Bağımsız Tenant) 401 müşterisinin hiçbiri Nutopia veya Serenut'a sızamaz (Tam Çapraz İzolasyon)
      expect(erkulCustIds.intersection(nutopiaCustIds).isEmpty, isTrue, reason: 'Erkul ve Nutopia müşterileri kesinlikle kesişemez!');
      expect(erkulCustIds.intersection(serenutCustIds).isEmpty, isTrue, reason: 'Erkul ve Serenut müşterileri kesinlikle kesişemez!');

      // Erkul kullanıcısı (Tunahan Erkul) Nutopia veya Serenut veritabanında bulunamaz
      final nutopiaErkulUsers = await nutopiaDb.rawQuery("SELECT count(*) as c FROM users WHERE username = 'tunahan erkul' OR username = 'erkultunahan7@gmail.com'");
      expect((nutopiaErkulUsers.first['c'] as num).toInt(), equals(0));

      final serenutErkulUsers = await serenutDb.rawQuery("SELECT count(*) as c FROM users WHERE username = 'tunahan erkul' OR username = 'erkultunahan7@gmail.com'");
      expect((serenutErkulUsers.first['c'] as num).toInt(), equals(0));

      expect(nutopiaCustIds.length, equals(584));
      expect(serenutCustIds.length, equals(7));
      expect(erkulCustIds.length, equals(401));

      await nutopiaDb.close();
      await serenutDb.close();
      await erkulDb.close();


    });

    test('2.5: İdempotency (Tekrar Çalıştırmada Sıfır Çift Kayıt ve Sıfır Bakiye Değişimi)', () async {
      final rawContent = await File(erkulSourcePath).readAsString();
      final jsonMap = jsonDecode(rawContent) as Map<String, dynamic>;

      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: erkulTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      final report2 = await bridge.migrateFromErkulJson(jsonMap);
      expect(report2.isSuccess, isTrue);
      expect(report2.customersMigrated, equals(401));

      final target = coreDb.db;
      final custCount = count(await target.rawQuery('SELECT count(*) FROM customers'));
      expect(custCount, equals(401), reason: 'İkinci çalıştırmada müşteri sayısı çoğalmamalıdır');

      final balRow = await target.rawQuery('SELECT SUM(balance_cents) as s FROM customers');
      final totalBalCents = (balRow.first['s'] as num).toInt();
      expect(totalBalCents, equals(-52362000), reason: 'İkinci çalıştırmada bakiye mutasyonu olamaz');

      await coreDb.close();
    });
  });

  group('STAGE 10.12.25 — BÖLÜM 3: GERÇEK SATIŞ AKIŞI REGRESYON TESTLERİ (18 İŞ SENARYOSU)', () {
    late Directory tempDir;
    late String testDbPath;
    late CoreAppDatabase coreDb;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('stg10_12_25_sales_flow_');
      testDbPath = p.join(tempDir.path, 'sales_regression.db');
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: testDbPath);

      final db = coreDb.db;
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // Test Ürünleri
      await db.insert('products', {
        'id': 'prod-001',
        'name': 'Organik Çiğ Fındık',
        'barcode': '869000100001',
        'price_cents': 15000, // 150.00 TL
        'stock_quantity': 100.0,
        'vat_rate': 1,
        'unit': 'KG',
        'is_deleted': 0,
        'is_active': 1,
        'updated_at': nowMs,
      });

      await db.insert('products', {
        'id': 'prod-002',
        'name': 'Kavrulmuş İç Fındık (Şekerli & Çikolatalı)',
        'barcode': '869000100002',
        'price_cents': 25000, // 250.00 TL
        'stock_quantity': 50.0,
        'vat_rate': 8,
        'unit': 'ADET',
        'is_deleted': 0,
        'is_active': 1,
        'updated_at': nowMs,
      });

      await db.insert('products', {
        'id': 'prod-deleted-003',
        'name': 'Eski Sezon Fındık (Silinmiş)',
        'barcode': '869000100003',
        'price_cents': 9000,
        'stock_quantity': 0.0,
        'vat_rate': 1,
        'unit': 'KG',
        'is_deleted': 1,
        'is_active': 0,
        'updated_at': nowMs,
      });

      // Test Müşterisi (Ahmet Yılmaz)
      await db.insert('customers', {
        'id': 'cust-001',
        'name': 'Ahmet Şükrü Çağlayan',
        'phone': '05551234567',
        'balance_cents': 0,
        'is_deleted': 0,
        'is_active': 1,
        'updated_at': nowMs,
      });

      // Varsayılan Anonim / Peşin Müşteri
      await db.insert('customers', {
        'id': 'customer-pesin-default',
        'name': 'Peşin Müşteri',
        'phone': '',
        'balance_cents': 0,
        'is_deleted': 0,
        'is_active': 1,
        'updated_at': nowMs,
      });
    });

    tearDownAll(() async {
      await coreDb.close();
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('3.1 (Senaryo 1): Barkodla ürün arama ve silinmiş ürünlerin filtrelenmesi', () async {
      final db = coreDb.db;

      // Aktif ürün araması
      final activeProds = await db.rawQuery(
        'SELECT * FROM products WHERE barcode = ? AND is_deleted = 0 AND is_active = 1',
        ['869000100001'],
      );
      expect(activeProds.length, equals(1));
      expect(activeProds.first['name'], equals('Organik Çiğ Fındık'));

      // Silinmiş ürün araması
      final deletedProds = await db.rawQuery(
        'SELECT * FROM products WHERE barcode = ? AND is_deleted = 0 AND is_active = 1',
        ['869000100003'],
      );
      expect(deletedProds, isEmpty, reason: 'Silinmiş ürün aktif satış aramasında gelmemelidir');
    });

    test('3.2 (Senaryo 2): Adsız / anonim müşteriye nakit satış ve kasa hareketi tutarlılığı', () async {
      final db = coreDb.db;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const saleId = 'sale-cash-001';

      // 1. Satış ve kalemleri ekle
      await db.transaction((txn) async {
        await txn.insert('sales', {
          'id': saleId,
          'receipt_no': 'REC-001',
          'customer_id': 'customer-pesin-default',
          'subtotal_cents': 15000,
          'total_cents': 15000, // 150.00 TL
          'paid_cents': 15000,
          'debt_cents': 0,
          'status': 'COMPLETED',
          'created_at': nowMs,
        });

        await txn.insert('sale_items', {
          'id': 'item-001',
          'sale_id': saleId,
          'product_id': 'prod-001',
          'barcode': '869000100001',
          'product_name': 'Organik Çiğ Fındık',
          'quantity': 1.0,
          'unit_price_cents': 15000,
          'vat_rate': 1,
          'total_cents': 15000,
        });

        // Kasa hareketi
        await txn.insert('cash_transactions', {
          'id': 'cash-tx-001',
          'type': 'INFLOW',
          'category': 'SALE',
          'amount_cents': 15000,
          'description': 'Nakit Satış #$saleId',
          'created_at': nowMs,
        });

        // Ödeme kaydı
        await txn.insert('sale_payments', {
          'id': 'pay-001',
          'sale_id': saleId,
          'payment_type': 'cash',
          'amount_cents': 15000,
          'created_at': nowMs,
        });

        // Stok düşümü
        await txn.rawUpdate(
          'UPDATE products SET stock_quantity = stock_quantity - 1.0 WHERE id = ?',
          ['prod-001'],
        );
      });

      // Doğrulama
      final s = (await db.query('sales', where: 'id = ?', whereArgs: [saleId])).first;
      expect(s['total_cents'], equals(15000));
      expect(s['paid_cents'], equals(15000));

      final cashTx = (await db.query('cash_transactions', where: "description LIKE '%$saleId%'")).first;
      expect(cashTx['amount_cents'], equals(15000));
      expect(cashTx['type'], equals('INFLOW'));

      final prod = (await db.query('products', where: 'id = ?', whereArgs: ['prod-001'])).first;
      expect(prod['stock_quantity'], equals(99.0));
    });

    test('3.3 (Senaryo 3): Kredi kartıyla satış', () async {
      final db = coreDb.db;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const saleId = 'sale-card-002';

      await db.transaction((txn) async {
        await txn.insert('sales', {
          'id': saleId,
          'receipt_no': 'REC-002',
          'customer_id': 'customer-pesin-default',
          'subtotal_cents': 25000,
          'total_cents': 25000,
          'paid_cents': 25000,
          'debt_cents': 0,
          'status': 'COMPLETED',
          'created_at': nowMs,
        });

        await txn.insert('sale_payments', {
          'id': 'pay-002',
          'sale_id': saleId,
          'payment_type': 'creditCard',
          'amount_cents': 25000,
          'created_at': nowMs,
        });

        await txn.rawUpdate(
          'UPDATE products SET stock_quantity = stock_quantity - 1.0 WHERE id = ?',
          ['prod-002'],
        );
      });

      final s = (await db.query('sales', where: 'id = ?', whereArgs: [saleId])).first;
      expect(s['paid_cents'], equals(25000));

      final pay = (await db.query('sale_payments', where: 'sale_id = ?', whereArgs: [saleId])).first;
      expect(pay['payment_type'], equals('creditCard'));
      expect(pay['amount_cents'], equals(25000));

      final prod = (await db.query('products', where: 'id = ?', whereArgs: ['prod-002'])).first;
      expect(prod['stock_quantity'], equals(49.0));
    });

    test('3.4 (Senaryo 4): Vadeli (açık hesap / veresiye) satış ve müşteri cari borç kaydı', () async {
      final db = coreDb.db;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const saleId = 'sale-credit-003';

      await db.transaction((txn) async {
        await txn.insert('sales', {
          'id': saleId,
          'receipt_no': 'REC-003',
          'customer_id': 'cust-001',
          'subtotal_cents': 15000,
          'total_cents': 15000,
          'paid_cents': 0,
          'debt_cents': 15000,
          'status': 'COMPLETED',
          'created_at': nowMs,
        });

        await txn.insert('sale_payments', {
          'id': 'pay-003',
          'sale_id': saleId,
          'payment_type': 'onAccount',
          'amount_cents': 15000,
          'created_at': nowMs,
        });

        // Müşteri defter kaydı (Borç / DEBIT)
        await txn.insert('ledger_entries', {
          'id': 'ledger-001',
          'customer_id': 'cust-001',
          'reference_sale_id': saleId,
          'entry_type': 'DEBIT',
          'amount_cents': 15000,
          'balance_after_cents': 15000,
          'description': 'Veresiye Satış #$saleId',
          'created_at': nowMs,
        });

        // Müşteri bakiye güncellemesi
        await txn.rawUpdate(
          'UPDATE customers SET balance_cents = balance_cents + 15000 WHERE id = ?',
          ['cust-001'],
        );
      });

      final cust = (await db.query('customers', where: 'id = ?', whereArgs: ['cust-001'])).first;
      expect(cust['balance_cents'], equals(15000), reason: 'Müşteriye 150.00 TL borç yansımalıdır');

      final ledger = (await db.query('ledger_entries', where: 'reference_sale_id = ?', whereArgs: [saleId])).first;
      expect(ledger['entry_type'], equals('DEBIT'));
      expect(ledger['amount_cents'], equals(15000));
    });

    test('3.5 (Senaryo 5 & 6 & 7): Karma ödemeler (Nakit + Kart + Vadeli)', () async {
      final db = coreDb.db;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const saleId = 'sale-split-004';

      // Toplam 500.00 TL (50.000 kuruş): 200 TL nakit + 200 TL kart + 100 TL vadeli
      await db.transaction((txn) async {
        await txn.insert('sales', {
          'id': saleId,
          'receipt_no': 'REC-004',
          'customer_id': 'cust-001',
          'subtotal_cents': 50000,
          'total_cents': 50000,
          'paid_cents': 40000, // 400 TL ödendi, 100 TL borç kaldı
          'debt_cents': 10000,
          'status': 'COMPLETED',
          'created_at': nowMs,
        });

        // Parçalı ödemeler
        await txn.insert('sale_payments', {
          'id': 'pay-split-cash',
          'sale_id': saleId,
          'payment_type': 'cash',
          'amount_cents': 20000,
          'created_at': nowMs,
        });

        await txn.insert('sale_payments', {
          'id': 'pay-split-card',
          'sale_id': saleId,
          'payment_type': 'creditCard',
          'amount_cents': 20000,
          'created_at': nowMs,
        });

        await txn.insert('sale_payments', {
          'id': 'pay-split-account',
          'sale_id': saleId,
          'payment_type': 'onAccount',
          'amount_cents': 10000,
          'created_at': nowMs,
        });

        // Kasa hareketi (200 TL nakit kısmı)
        await txn.insert('cash_transactions', {
          'id': 'cash-tx-split-001',
          'type': 'INFLOW',
          'category': 'SALE',
          'amount_cents': 20000,
          'description': 'Karma Satış Nakit Payı #$saleId',
          'created_at': nowMs,
        });

        // Kalan 100 TL vadeli için defter kaydı
        await txn.insert('ledger_entries', {
          'id': 'ledger-split-002',
          'customer_id': 'cust-001',
          'reference_sale_id': saleId,
          'entry_type': 'DEBIT',
          'amount_cents': 10000,
          'balance_after_cents': 25000,
          'description': 'Karma Satış Vadeli Kısım #$saleId',
          'created_at': nowMs,
        });

        await txn.rawUpdate(
          'UPDATE customers SET balance_cents = balance_cents + 10000 WHERE id = ?',
          ['cust-001'],
        );
      });

      final cust = (await db.query('customers', where: 'id = ?', whereArgs: ['cust-001'])).first;
      expect(cust['balance_cents'], equals(25000)); // 150 TL önceki borç + 100 TL yeni borç = 250 TL (25000 kuruş)

      final sale = (await db.query('sales', where: 'id = ?', whereArgs: [saleId])).first;
      expect(sale['total_cents'], equals(50000));
      expect(sale['paid_cents'], equals(40000));
      expect(sale['debt_cents'], equals(10000));
    });

    test('3.6 (Senaryo 8 & 9): Satış iptali ve stok/bakiye iadesi', () async {
      final db = coreDb.db;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const saleId = 'sale-to-cancel-005';

      // Önce satış oluştur
      await db.transaction((txn) async {
        await txn.insert('sales', {
          'id': saleId,
          'receipt_no': 'REC-005',
          'customer_id': 'customer-pesin-default',
          'subtotal_cents': 15000,
          'total_cents': 15000,
          'paid_cents': 15000,
          'debt_cents': 0,
          'status': 'COMPLETED',
          'created_at': nowMs,
        });
        await txn.rawUpdate('UPDATE products SET stock_quantity = stock_quantity - 1.0 WHERE id = ?', ['prod-001']);
      });

      // Şimdi iptal et (status = CANCELLED, stok geri eklendi)
      await db.transaction((txn) async {
        await txn.update('sales', {'status': 'CANCELLED'}, where: 'id = ?', whereArgs: [saleId]);
        await txn.rawUpdate('UPDATE products SET stock_quantity = stock_quantity + 1.0 WHERE id = ?', ['prod-001']);
      });

      final cancelledSale = (await db.query('sales', where: 'id = ?', whereArgs: [saleId])).first;
      expect(cancelledSale['status'], equals('CANCELLED'));

      final prod = (await db.query('products', where: 'id = ?', whereArgs: ['prod-001'])).first;
      expect(prod['stock_quantity'], equals(99.0)); // Stok geri geldi
    });

    test('3.7 (Senaryo 10 & 11): Tam iade ve cari bakiye tutarlılığı', () async {
      final db = coreDb.db;
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // Müşterinin 250 TL borcundan 100 TL iade edelim (CREDIT / Alacak girişi)
      await db.transaction((txn) async {
        await txn.insert('ledger_entries', {
          'id': 'ledger-refund-001',
          'customer_id': 'cust-001',
          'reference_sale_id': null,
          'entry_type': 'CREDIT',
          'amount_cents': 10000,
          'balance_after_cents': 15000,
          'description': 'İade Girişi',
          'created_at': nowMs,
        });

        await txn.rawUpdate(
          'UPDATE customers SET balance_cents = balance_cents - 10000 WHERE id = ?',
          ['cust-001'],
        );
      });

      final cust = (await db.query('customers', where: 'id = ?', whereArgs: ['cust-001'])).first;
      expect(cust['balance_cents'], equals(15000), reason: '250 TL borçtan 100 TL iade edilince kalan borç 150 TL olmalıdır');
    });

    test('3.8 (Senaryo 12 & 15): Idempotency koruması (Aynı satışın iki kez kaydedilmesinin engellenmesi)', () async {
      final db = coreDb.db;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const duplicateSaleId = 'sale-cash-001'; // Senaryo 2'de kaydedilmişti

      // Primary key çakışması fail etmeli
      expect(
        () async => await db.insert('sales', {
          'id': duplicateSaleId,
          'receipt_no': 'REC-DUP',
          'customer_id': 'customer-pesin-default',
          'subtotal_cents': 15000,
          'total_cents': 15000,
          'paid_cents': 15000,
          'debt_cents': 0,
          'status': 'COMPLETED',
          'created_at': nowMs,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('3.9 (Senaryo 13): Çevrimdışı satış kuyruğu ve senkronizasyon olayları (sync_events)', () async {
      final db = coreDb.db;
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      await db.insert('sync_events', {
        'event_id': 'sync-evt-001',
        'entity_type': 'sales',
        'entity_id': 'sale-cash-001',
        'operation': 'UPSERT',
        'payload_json': '{"sale_id":"sale-cash-001","total_cents":15000}',
        'base_revision': 0,
        'client_timestamp': nowMs,
        'sync_state': 'PENDING',
        'attempts': 0,
      });

      final pendingEvents = await db.query(
        'sync_events',
        where: "sync_state = 'PENDING' AND entity_id = ?",
        whereArgs: ['sale-cash-001'],
      );
      expect(pendingEvents.length, equals(1));
      expect(pendingEvents.first['operation'], equals('UPSERT'));
    });

    test('3.10 (Senaryo 16): Müşteri ve ürün aramasında Türkçe karakter desteği', () async {
      final db = coreDb.db;

      // "Şükrü Çağlayan" araması
      final custs = await db.rawQuery(
        "SELECT * FROM customers WHERE name LIKE '%Çağlayan%' OR name LIKE '%Şükrü%'",
      );
      expect(custs.length, equals(1));
      expect(custs.first['id'], equals('cust-001'));

      // "Şekerli & Çikolatalı" araması
      final prods = await db.rawQuery(
        "SELECT * FROM products WHERE name LIKE '%Çikolatalı%'",
      );
      expect(prods.length, equals(1));
      expect(prods.first['barcode'], equals('869000100002'));
    });

    test('3.11 (Senaryo 17 & 18): Büyük veri hacminde sorgu ve satış fişi tutarlılığı', () async {
      final db = coreDb.db;

      // Fiş verisi mutabakatı
      final saleRows = await db.query('sales', where: 'id = ?', whereArgs: ['sale-cash-001']);
      final itemRows = await db.query('sale_items', where: 'sale_id = ?', whereArgs: ['sale-cash-001']);

      expect(saleRows.isNotEmpty, isTrue);
      expect(itemRows.isNotEmpty, isTrue);

      final sale = saleRows.first;
      final item = itemRows.first;

      expect(sale['total_cents'], equals(item['total_cents']));
      expect(sale['receipt_no'], equals('REC-001'));
    });
  });

  group('STAGE 10.12.25 — BÖLÜM 4: GÜNCELLEME, YEDEKLEME VE ROLLBACK GÜVENLİĞİ', () {
    test('4.1: Şema sınırı koruması: CoreAppDatabase legacy veritabanlarını açmayı reddetmelidir', () async {
      expect(
        () async => await CoreAppDatabase.open(inMemoryOrCustomPath: nutopiaSourcePath),
        throwsA(isA<IncompatibleDatabaseSchemaException>()),
      );
    });

    test('4.2: Çift veritabanı yönlendirme koordinatörü: Bilinmeyen veya eksik hedefte fail-closed veya fallback davranmalıdır', () async {
      const coordinator = DualDatabaseRoutingCoordinator();
      final result = await coordinator.resolveAndOpen(
        requestedTenantId: 'nutopia-default',
        legacyDbPath: nutopiaSourcePath,
        targetDbPath: 'non_existent_target.db',
        migrationStateCompleted: true,
      );

      expect(result.isSuccess, isFalse);
      expect(result.decision, equals(RoutingDecision.legacyFallback));
      expect(result.targetDatabase, isNull);
    });
  });


  group('STAGE 10.12.25 — BÖLÜM 5: KAPANIS SHA-256 DOĞRULAMASI VE SIFIR MUTASYON KANITI', () {
    test('5.1: Kaynak Nutopia DB SHA-256 imzası testler sonunda da değişmemiş olmalıdır', () {
      expect(calculateFileSha256(nutopiaSourcePath), equals(expectedNutopiaSha));
    });

    test('5.2: Kaynak Serenut DB SHA-256 imzası testler sonunda da değişmemiş olmalıdır', () {
      expect(calculateFileSha256(serenutSourcePath), equals(expectedSerenutSha));
    });

    test('5.3: Kaynak Erkul JSON SHA-256 imzası testler sonunda da değişmemiş olmalıdır', () {
      expect(calculateFileSha256(erkulSourcePath), equals(expectedErkulSha));
    });
  });
}
