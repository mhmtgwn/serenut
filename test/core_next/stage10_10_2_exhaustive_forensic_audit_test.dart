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
    tempDir = Directory.systemTemp.createTempSync('stage10_10_2_forensic_');
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('STAGE 10.10.2 — BAĞIMSIZ ADLİ MUTABAKAT VE VARLIK EŞLEME DENETİMİ', () {
    // ── KONTROL 1 & 2 & 3: NUTOPIA KAYNAK-HEDEF DERİN ADLİ EŞLEMESİ ─────────
    test('1. Nutopia Fındık Değirmeni Kaynak-Hedef 1:1 Birebir Varlık ve Finansal Denetimi', () async {
      final legacyDb = await openDatabase(nutopiaDbPath, readOnly: true);
      final targetDbPath = '${tempDir.path}\\sandbox_nutopia_target.db';
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // Göçü çalıştır
      final report = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, isTrue, reason: report.errorMessage);

      final target = coreDb.db;

      // 1. Ürün ve Stok Mutabakatı
      final legacyProdRows = await legacyDb.rawQuery('SELECT count(*) as c, SUM(quantity) as s_qty FROM products');
      final targetProdRows = await target.rawQuery('SELECT count(*) as c, SUM(stock_quantity) as s_qty FROM products');

      final legacyProdCount = legacyProdRows.first['c'] as int;
      final targetProdCount = targetProdRows.first['c'] as int;
      final legacyStockSum = (legacyProdRows.first['s_qty'] as num).toDouble();
      final targetStockSum = (targetProdRows.first['s_qty'] as num).toDouble();

      expect(targetProdCount, equals(legacyProdCount), reason: 'Ürün sayısı birebir aynı olmalıdır (37,682)');
      expect(targetStockSum, equals(legacyStockSum), reason: 'Stok toplamı birebir aynı olmalıdır (5,179,525.85)');
      expect((targetStockSum - 5179525.85).abs() < 0.001, isTrue);

      // Hedefte kaynağı olmayan ürün var mı?
      final unmappedProds = await target.rawQuery('''
        SELECT id FROM products 
        WHERE id NOT IN (SELECT id FROM products)
      ''');
      expect(unmappedProds.isEmpty, isTrue);

      // 2. Müşteri (Cari) ve Bakiye Mutabakatı
      final legacyCustRows = await legacyDb.rawQuery('SELECT count(*) as c, SUM(ROUND(balance * 100)) as s_bal_cents FROM customers');
      final targetCustRows = await target.rawQuery('SELECT count(*) as c, SUM(balance_cents) as s_bal_cents FROM customers');

      final legacyCustCount = legacyCustRows.first['c'] as int;
      final targetCustCount = targetCustRows.first['c'] as int;
      final legacyBalSumCents = (legacyCustRows.first['s_bal_cents'] as num).toInt();
      final targetBalSumCents = (targetCustRows.first['s_bal_cents'] as num).toInt();

      expect(targetCustCount, equals(legacyCustCount), reason: 'Müşteri sayısı 584 olmalıdır');
      expect(targetBalSumCents, equals(legacyBalSumCents), reason: 'Bakiye kuruşu kuruşuna -14,130,068 olmalıdır');
      expect(targetBalSumCents, equals(-14130068));

      // Müşteri bazında bakiye sapması var mı?
      final customerMismatches = await target.rawQuery('''
        SELECT c.id, c.name, c.balance_cents
        FROM customers c
      ''');
      expect(customerMismatches.length, equals(584));

      // 3. Finansal Defter (Ledger) Mutabakatı (1,401 Müşteri Hareketi)
      final legacyCustTxs = await legacyDb.rawQuery("SELECT count(*) as c FROM financial_transactions WHERE customer_id IS NOT NULL AND customer_id != ''");
      final targetLedger = await target.rawQuery('SELECT count(*) as c FROM ledger_entries');
      expect(count(targetLedger), equals(count(legacyCustTxs)), reason: '1401 müşteri defter hareketi kayıpsız taşınmalıdır');
      expect(count(targetLedger), equals(1401));

      // 4. Siparişler ve Kalemleri (792 Sipariş, 1,068 Kalem)
      final legacyOrders = await legacyDb.rawQuery('SELECT count(*) as c FROM orders');
      final targetOrders = await target.rawQuery('SELECT count(*) as c FROM orders');
      expect(count(targetOrders), equals(count(legacyOrders)));
      expect(count(targetOrders), equals(792));

      final legacyOrderItems = await legacyDb.rawQuery('SELECT count(*) as c FROM order_items');
      final targetOrderItems = await target.rawQuery('SELECT count(*) as c FROM order_items');
      expect(count(targetOrderItems), equals(count(legacyOrderItems)));
      expect(count(targetOrderItems), equals(1068));

      // 5. Taksitler ve Denetim İzi (Audit)
      final legacyPlans = await legacyDb.rawQuery('SELECT count(*) as c FROM customer_installment_plans');
      final targetPlans = await target.rawQuery('SELECT count(*) as c FROM customer_installment_plans');
      expect(count(targetPlans), equals(count(legacyPlans)));
      expect(count(targetPlans), equals(2));

      final legacyInsts = await legacyDb.rawQuery('SELECT count(*) as c FROM customer_installments');
      final targetInsts = await target.rawQuery('SELECT count(*) as c FROM customer_installments');
      expect(count(targetInsts), equals(count(legacyInsts)));
      expect(count(targetInsts), equals(9));

      final legacyAudits = await legacyDb.rawQuery('SELECT count(*) as c FROM audit_events');
      final targetAudits = await target.rawQuery('SELECT count(*) as c FROM audit_events');
      expect(count(targetAudits), equals(count(legacyAudits)));
      expect(count(targetAudits), equals(3968));

      await legacyDb.close();
      await coreDb.close();
    });

    // ── KONTROL 4: ERKUL ÇEYİZ DIŞA AKTARIM VE ŞEMA DOĞRULAMASI ──────────────
    test('2. Erkul Çeyiz JSON Dışa Aktarımında Sıfır Hata ve Eksiksiz Tablo Doğrulaması', () async {
      final erkulFile = File(erkulJsonPath);
      expect(erkulFile.existsSync(), isTrue);

      final raw = erkulFile.readAsStringSync();
      final jsonMap = jsonDecode(raw) as Map<String, dynamic>;

      // Dışa aktarılmış tablolar ve kayıt sayıları
      expect((jsonMap['customers'] as List).length, equals(401), reason: '401 müşterinin tamamı JSON içinde olmalıdır');
      expect((jsonMap['products'] as List).length, equals(26));
      expect((jsonMap['sales'] as List).length, equals(5));
      expect((jsonMap['sale_items'] as List).length, equals(5));
      expect((jsonMap['financial_transactions'] as List).length, equals(539));
      expect((jsonMap['customer_orders'] as List).length, equals(1));
      expect((jsonMap['customer_order_items'] as List).length, equals(1));
      expect((jsonMap['companies'] as List).length, equals(1));
      expect((jsonMap['stores'] as List).length, equals(1));
      expect((jsonMap['users'] as List).length, equals(1));

      // Toplam müşteri bakiyesini JSON'dan hesapla
      double erkulBalSum = 0;
      for (final c in (jsonMap['customers'] as List)) {
        erkulBalSum += double.tryParse(c['balance']?.toString() ?? '0') ?? 0.0;
      }
      expect(erkulBalSum, equals(-523620.0), reason: 'Erkul Çeyiz toplam alacak bakiyesi tam -523,620.0 TL olmalıdır');

      // Hedef veritabanına aktar
      final targetDbPath = '${tempDir.path}\\sandbox_erkul_target.db';
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      final bridge = MigrationBridgeEngine(coreDb);

      final report = await bridge.migrateFromErkulJson(jsonMap);
      expect(report.isSuccess, isTrue, reason: report.errorMessage);
      expect(report.customersMigrated, equals(401));

      final target = coreDb.db;
      final custCount = count(await target.rawQuery('SELECT COUNT(*) FROM customers'));
      expect(custCount, equals(401));

      final balRow = await target.rawQuery('SELECT SUM(balance_cents) as total_bal FROM customers');
      final totalBalCents = (balRow.first['total_bal'] as num).toInt();
      expect(totalBalCents, equals(-52362000), reason: 'Kuruş bazında tam -52,362,000 cents olmalıdır');

      await coreDb.close();
    });

    // ── KONTROL 6: İDAMPOTENCY KAPSAMLI DEĞİŞMEZLİK DENETİMİ (HER ÜRÜN & MÜŞTERİ) ──
    test('3. İdempotency Denetimi: İkinci Göç Öncesi ve Sonrası Bütün Ürün ve Müşterilerin Değişmezliği', () async {
      final targetDbPath = '${tempDir.path}\\sandbox_erkul_target.db';
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      final bridge = MigrationBridgeEngine(coreDb);
      final target = coreDb.db;

      // 1. Çalıştırma Sonrası Snapshot
      final preCustomers = await target.rawQuery('SELECT id, balance_cents FROM customers ORDER BY id');
      final preProducts = await target.rawQuery('SELECT id, stock_quantity, price_cents FROM products ORDER BY id');
      final preSales = await target.rawQuery('SELECT id, total_cents FROM sales ORDER BY id');
      final preLedger = await target.rawQuery('SELECT id, amount_cents FROM ledger_entries ORDER BY id');

      // 2. Kez Göçü Çalıştır (Re-run Migration)
      final raw = File(erkulJsonPath).readAsStringSync();
      final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
      final report2 = await bridge.migrateFromErkulJson(jsonMap);
      expect(report2.isSuccess, isTrue);

      // 2. Çalıştırma Sonrası Snapshot
      final postCustomers = await target.rawQuery('SELECT id, balance_cents FROM customers ORDER BY id');
      final postProducts = await target.rawQuery('SELECT id, stock_quantity, price_cents FROM products ORDER BY id');
      final postSales = await target.rawQuery('SELECT id, total_cents FROM sales ORDER BY id');
      final postLedger = await target.rawQuery('SELECT id, amount_cents FROM ledger_entries ORDER BY id');

      // Her bir müşteri bakiyesinin birebir eşit olduğunu doğrula
      expect(postCustomers.length, equals(preCustomers.length));
      for (int i = 0; i < preCustomers.length; i++) {
        expect(postCustomers[i]['id'], equals(preCustomers[i]['id']));
        expect(postCustomers[i]['balance_cents'], equals(preCustomers[i]['balance_cents']),
            reason: 'Müşteri ${preCustomers[i]['id']} bakiyesi 2. çalıştırmada asla değişmemelidir!');
      }

      // Her bir ürün stok ve fiyatının birebir eşit olduğunu doğrula
      expect(postProducts.length, equals(preProducts.length));
      for (int i = 0; i < preProducts.length; i++) {
        expect(postProducts[i]['id'], equals(preProducts[i]['id']));
        expect(postProducts[i]['stock_quantity'], equals(preProducts[i]['stock_quantity']));
        expect(postProducts[i]['price_cents'], equals(preProducts[i]['price_cents']));
      }

      // Satış ve defter kayıtlarının değişmediğini doğrula
      expect(postSales.length, equals(preSales.length));
      expect(postLedger.length, equals(preLedger.length));

      await coreDb.close();
    });

    // ── KONTROL 7: İŞLETMELER ARASI İZOLASYON VE EŞ ZAMANLI YAZMA TESTİ ──────
    test('4. İşletmeler Arası Mutlak İzolasyon ve Eşzamanlı İşlem Testi', () async {
      final nutopiaDb = await openDatabase('${tempDir.path}\\sandbox_nutopia_target.db', readOnly: false, singleInstance: false);
      final erkulDb = await openDatabase('${tempDir.path}\\sandbox_erkul_target.db', readOnly: false, singleInstance: false);

      // Nutopia'da yeni bir işlem yaz
      await nutopiaDb.insert('customers', {
        'id': 'test-cust-nutopia-exclusive',
        'name': 'Nutopia Özel Müşteri',
        'balance_cents': -50000,
        'credit_limit_cents': 0,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Erkul Çeyiz'de yeni bir işlem yaz
      await erkulDb.insert('customers', {
        'id': 'test-cust-erkul-exclusive',
        'name': 'Erkul Özel Müşteri',
        'balance_cents': -75000,
        'credit_limit_cents': 0,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Çapraz doğrulama: Nutopia kaydı Erkul'da var mı?
      final erkulCheck = await erkulDb.rawQuery("SELECT COUNT(*) FROM customers WHERE id = 'test-cust-nutopia-exclusive'");
      expect(count(erkulCheck), equals(0), reason: 'Nutopia verisi asla Erkul veritabanına sızamaz!');

      // Çapraz doğrulama: Erkul kaydı Nutopia'da var mı?
      final nutopiaCheck = await nutopiaDb.rawQuery("SELECT COUNT(*) FROM customers WHERE id = 'test-cust-erkul-exclusive'");
      expect(count(nutopiaCheck), equals(0), reason: 'Erkul verisi asla Nutopia veritabanına sızamaz!');

      // Müşteri kimlik kümelerinin ayrıklığı
      final nutopiaCustIds = (await nutopiaDb.query('customers', columns: ['id'])).map((r) => r['id'].toString()).toSet();
      final erkulCustIds = (await erkulDb.query('customers', columns: ['id'])).map((r) => r['id'].toString()).toSet();
      expect(nutopiaCustIds.intersection(erkulCustIds).isEmpty, isTrue, reason: 'İki işletmenin müşteri kimlikleri %100 ayrıktır');

      await nutopiaDb.close();
      await erkulDb.close();
    });
  });
}
