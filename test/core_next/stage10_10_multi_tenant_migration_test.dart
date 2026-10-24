import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const nutopiaDbPath = r'C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db';
  const serenutDbPath = r'C:\Users\notop\AppData\Roaming\com.example\Serenut OS\databases\serenut_pos.db';
  const erkulJsonPath = r'C:\Users\notop\AppData\Local\Temp\sandbox_erkul_source.json';

  late Directory tempDir;

  int count(List<Map<String, Object?>> rows) => (rows.first.values.first as num).toInt();

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('stage10_10_multi_tenant_');
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('STAGE 10.10 — 3 İşletmenin Bağımsız ve Kayıpsız Core Next Göçü', () {
    test('1. Tenant 1 ("Nutopia Fındık Değirmeni") tam kapsamlı ve kayıpsız taşınmalıdır', () async {
      expect(File(nutopiaDbPath).existsSync(), isTrue, reason: 'Nutopia DB bulunamadı');

      final targetDbPath = '${tempDir.path}\\sandbox_nutopia_target.db';
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      final bridge = MigrationBridgeEngine(coreDb);

      final legacyDb = await openDatabase(nutopiaDbPath, readOnly: true);

      final legacyStockRow = await legacyDb.rawQuery('SELECT ROUND(SUM(CAST(quantity AS REAL)), 2) as total_stock FROM products');
      final legacyStockTotal = (legacyStockRow.first['total_stock'] as num).toDouble();

      final legacyBalRow = await legacyDb.rawQuery('SELECT SUM(ROUND(balance * 100)) as total_bal FROM customers');
      final legacyBalTotal = (legacyBalRow.first['total_bal'] as num).toInt();

      // Göçü çalıştır
      final report = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      await legacyDb.close();

      expect(report.isSuccess, isTrue, reason: report.errorMessage);
      expect(report.productsMigrated, equals(37682));
      expect(report.customersMigrated, equals(584));
      expect(report.salesMigrated, equals(52));
      expect(report.saleItemsMigrated, equals(120));
      expect(report.ledgerEntriesMigrated, equals(1403));
      expect(report.ordersMigrated, equals(792));
      expect(report.installmentsMigrated, equals(9));
      expect(report.auditEventsMigrated, equals(3972));
      expect(report.cashCountsMigrated, equals(0));

      // Veritabanı doğrudan sorgu mutabakatı
      final target = coreDb.db;

      // 1. Ürün ve Stok Mutabakatı (Ondalıklı ürünler dahil)
      final prodCount = count(await target.rawQuery('SELECT COUNT(*) FROM products'));
      expect(prodCount, equals(37682));

      final stockRow = await target.rawQuery('SELECT ROUND(SUM(stock_quantity), 2) as total_stock FROM products');
      final stockTotal = (stockRow.first['total_stock'] as num).toDouble();
      expect(stockTotal, equals(legacyStockTotal), reason: 'Stok toplamı kaynak veritabanı ile birebir aynı olmalıdır');
      expect((stockTotal - 5179525.85).abs() < 0.01, isTrue, reason: 'Stok toplamı 5179525.85 olmalıdır: $stockTotal');

      // Ondalıklı ürün örneği kontrolü (Tartılı / kesirli stoklar kayıpsız korunmalıdır)
      final decimalProds = await target.rawQuery('SELECT name, stock_quantity FROM products WHERE stock_quantity != CAST(stock_quantity AS INTEGER) LIMIT 5');
      expect(decimalProds.isNotEmpty, isTrue, reason: 'Ondalıklı/tartılı ürünler kayıpsız korunmalıdır');
      expect((decimalProds.first['stock_quantity'] as num).toDouble() % 1 != 0, isTrue);

      // 2. Müşteri ve Bakiye Mutabakatı
      final custCount = count(await target.rawQuery('SELECT COUNT(*) FROM customers'));
      expect(custCount, equals(584));

      final balRow = await target.rawQuery('SELECT SUM(balance_cents) as total_bal FROM customers');
      final totalBalCents = (balRow.first['total_bal'] as num).toInt();
      expect(totalBalCents, equals(legacyBalTotal), reason: 'Nutopia müşteri bakiyesi kaynak ile kuruşu kuruşuna aynı olmalıdır');
      expect(totalBalCents, equals(-13450068), reason: 'Nutopia müşteri bakiyesi -134,500.68 TL (-13,450,068 kuruş) olmalıdır');

      // 3. Sipariş ve Taksit Mutabakatı
      final orderCount = count(await target.rawQuery('SELECT COUNT(*) FROM orders'));
      expect(orderCount, equals(792));
      final orderItemCount = count(await target.rawQuery('SELECT COUNT(*) FROM order_items'));
      expect(orderItemCount, equals(1068));

      final planCount = count(await target.rawQuery('SELECT COUNT(*) FROM customer_installment_plans'));
      expect(planCount, equals(2));
      final instCount = count(await target.rawQuery('SELECT COUNT(*) FROM customer_installments'));
      expect(instCount, equals(9));

      // 4. Denetim İzi (Audit) ve Kasa
      final auditCount = count(await target.rawQuery('SELECT COUNT(*) FROM audit_events'));
      expect(auditCount, equals(3972));
      final cashCount = count(await target.rawQuery('SELECT COUNT(*) FROM cash_counts'));
      expect(cashCount, equals(0));
      final expCount = count(await target.rawQuery('SELECT COUNT(*) FROM cash_expenses'));
      expect(expCount, equals(0));

      await coreDb.close();
    });

    test('2. Tenant 2 ("serenut") şema v44 uyumluluğuyla bağımsız ve kayıpsız taşınmalıdır', () async {
      expect(File(serenutDbPath).existsSync(), isTrue, reason: 'Serenut DB bulunamadı');

      final targetDbPath = '${tempDir.path}\\sandbox_serenut_target.db';
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      final bridge = MigrationBridgeEngine(coreDb);

      final legacyDb = await openDatabase(serenutDbPath, readOnly: true);

      // Göçü çalıştır (Şema v44 desteği ile)
      final report = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      await legacyDb.close();

      expect(report.isSuccess, isTrue, reason: report.errorMessage);
      expect(report.productsMigrated, equals(6377));
      expect(report.customersMigrated, equals(7));
      expect(report.salesMigrated, equals(15));
      expect(report.saleItemsMigrated, equals(19));
      expect(report.ledgerEntriesMigrated, equals(12));
      expect(report.ordersMigrated, equals(5));

      // Hedef veritabanı doğrudan sorguları
      final target = coreDb.db;

      final prodCount = count(await target.rawQuery('SELECT COUNT(*) FROM products'));
      expect(prodCount, equals(6377));

      final stockRow = await target.rawQuery('SELECT ROUND(SUM(stock_quantity), 2) as total_stock FROM products');
      final stockTotal = (stockRow.first['total_stock'] as num).toDouble();
      expect((stockTotal - 637445.0).abs() < 0.01, isTrue);

      final custCount = count(await target.rawQuery('SELECT COUNT(*) FROM customers'));
      expect(custCount, equals(7));

      final balRow = await target.rawQuery('SELECT SUM(balance_cents) as total_bal FROM customers');
      final totalBalCents = (balRow.first['total_bal'] as num).toInt();
      expect(totalBalCents, equals(-267300), reason: 'Serenut müşteri bakiyesi -2,673.00 TL olmalıdır');

      final orderCount = count(await target.rawQuery('SELECT COUNT(*) FROM orders'));
      expect(orderCount, equals(5));
      final orderItemCount = count(await target.rawQuery('SELECT COUNT(*) FROM order_items'));
      expect(orderItemCount, equals(5));

      await coreDb.close();
    });

    test('3. Tenant 3 ("ERKUL ÇEYİZ") PostgreSQL verisinden 401 müşterisi ve tüm cari bakiyeleriyle kayıpsız taşınmalıdır', () async {
      expect(File(erkulJsonPath).existsSync(), isTrue, reason: 'Erkul JSON export bulunamadı');

      final rawContent = await File(erkulJsonPath).readAsString();
      final jsonMap = jsonDecode(rawContent) as Map<String, dynamic>;

      final targetDbPath = '${tempDir.path}\\sandbox_erkul_target.db';
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // Göçü çalıştır
      final report = await bridge.migrateFromErkulJson(jsonMap);

      if (!report.isSuccess) {
        print('=== ERKUL MIGRATION ERROR: ${report.errorMessage} ===');
      }

      // Rapor doğrulaması
      expect(report.isSuccess, isTrue, reason: 'Erkul hatası: ${report.errorMessage}');
      expect(report.customersMigrated, equals(401), reason: '401 müşterinin tamamı korunmalıdır!');
      expect(report.productsMigrated, equals(26));
      expect(report.salesMigrated, equals(5));
      expect(report.saleItemsMigrated, equals(5));
      expect(report.ledgerEntriesMigrated, equals(539));
      expect(report.ordersMigrated, equals(1));

      // Hedef veritabanı doğrudan sorguları
      final target = coreDb.db;

      // 1. Müşteri Bütünlüğü ve Alacak Mutabakatı (523,620.00 TL)
      final custCount = count(await target.rawQuery('SELECT COUNT(*) FROM customers'));
      expect(custCount, equals(401), reason: 'Kesinlikle 401 müşteri olmalıdır, tek bir müşteri dahi kaybedilemez!');

      final balRow = await target.rawQuery('SELECT SUM(balance_cents) as total_bal FROM customers');
      final totalBalCents = (balRow.first['total_bal'] as num).toInt();
      // Erkul Çeyiz toplam cari alacağı -523,620.00 TL = -52,362,000 kuruş
      expect(totalBalCents, equals(-52362000), reason: 'Erkul müşteri alacağı kuruşu kuruşuna -52,362,000 cents olmalıdır');

      // 2. Ürün ve Satış Mutabakatı
      final prodCount = count(await target.rawQuery('SELECT COUNT(*) FROM products'));
      expect(prodCount, equals(26));

      final salesCount = count(await target.rawQuery('SELECT COUNT(*) FROM sales'));
      expect(salesCount, equals(5));

      final ledgerCount = count(await target.rawQuery('SELECT COUNT(*) FROM ledger_entries'));
      expect(ledgerCount, equals(539));

      final orderCount = count(await target.rawQuery('SELECT COUNT(*) FROM orders'));
      expect(orderCount, equals(1));

      // 3. Kullanıcı Yetki Mutabakatı
      final userRow = await target.rawQuery("SELECT * FROM users WHERE display_name = 'tunahan erkul' OR username = 'erkultunahan7@gmail.com'");
      expect(userRow.isNotEmpty, isTrue);

      await coreDb.close();
    });

    test('4. Tenant İzolasyonu (Çapraz Veri Sızıntısı Sıfır Olmalıdır)', () async {
      final nutopiaDb = await openDatabase('${tempDir.path}\\sandbox_nutopia_target.db', readOnly: true, singleInstance: false);
      final serenutDb = await openDatabase('${tempDir.path}\\sandbox_serenut_target.db', readOnly: true, singleInstance: false);
      final erkulDb = await openDatabase('${tempDir.path}\\sandbox_erkul_target.db', readOnly: true, singleInstance: false);

      // Erkul müşterilerinden biri Nutopia veya Serenut veritabanında olamaz (Tam İzolasyon)
      final erkulCustIds = (await erkulDb.query('customers', columns: ['id'])).map((r) => r['id'].toString()).toSet();
      final nutopiaCustIds = (await nutopiaDb.query('customers', columns: ['id'])).map((r) => r['id'].toString()).toSet();
      final serenutCustIds = (await serenutDb.query('customers', columns: ['id'])).map((r) => r['id'].toString()).toSet();

      // Erkul'un 401 müşterisinin hiçbiri diğer tenant'lara sızamaz
      expect(erkulCustIds.intersection(nutopiaCustIds).isEmpty, isTrue, reason: 'Erkul ve Nutopia müşterileri kesinlikle kesişemez!');
      expect(erkulCustIds.intersection(serenutCustIds).isEmpty, isTrue, reason: 'Erkul ve Serenut müşterileri kesinlikle kesişemez!');

      // Her 3 veritabanı tamamen bağımsız dosyalarda ve bağımsız kayıtlara sahiptir
      expect(nutopiaCustIds.length, equals(584));
      expect(serenutCustIds.length, equals(7));
      expect(erkulCustIds.length, equals(401));

      // Erkul kullanıcısı Tunahan Erkul Nutopia veya Serenut'ta olamaz
      final nutopiaErkulUser = await nutopiaDb.rawQuery("SELECT COUNT(*) FROM users WHERE username = 'tunahan erkul' OR username = 'erkultunahan7@gmail.com'");
      expect(count(nutopiaErkulUser), equals(0));

      final serenutErkulUser = await serenutDb.rawQuery("SELECT COUNT(*) FROM users WHERE username = 'tunahan erkul' OR username = 'erkultunahan7@gmail.com'");
      expect(count(serenutErkulUser), equals(0));

      await nutopiaDb.close();
      await serenutDb.close();
      await erkulDb.close();
    });

    test('5. İdempotency (Tekrar Çalıştırmada Sıfır Çift Kayıt ve Sıfır Bakiye Değişimi)', () async {
      final targetDbPath = '${tempDir.path}\\sandbox_erkul_target.db';
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      final bridge = MigrationBridgeEngine(coreDb);

      final rawContent = await File(erkulJsonPath).readAsString();
      final jsonMap = jsonDecode(rawContent) as Map<String, dynamic>;

      // 2. kez göçü çalıştır
      final report2 = await bridge.migrateFromErkulJson(jsonMap);
      expect(report2.isSuccess, isTrue, reason: report2.errorMessage);
      expect(report2.customersMigrated, equals(401));

      final target = coreDb.db;
      final custCount = count(await target.rawQuery('SELECT COUNT(*) FROM customers'));
      expect(custCount, equals(401), reason: 'İkinci çalıştırmada müşteri sayısı çoğalmamalıdır');

      final balRow = await target.rawQuery('SELECT SUM(balance_cents) as total_bal FROM customers');
      final totalBalCents = (balRow.first['total_bal'] as num).toInt();
      expect(totalBalCents, equals(-52362000), reason: 'İkinci çalıştırmada bakiye mutasyonu olamaz');

      await coreDb.close();
    });
  });
}
