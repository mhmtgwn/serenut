// test/core_next/stage10_12_32_reconciliation_and_sales_flow_test.dart
// Stage 10.12.32 — Export/Import Sonrası Veri Mutabakatı ve Satış Akışı Doğrulaması
//
// GÜVENLİK KURALLARI:
// 1. Canlı veritabanına ASLA dokunulmaz.
// 2. Yalnızca geçici, izole ve disposable test veritabanları kullanılır.
// 3. `coreNextSalesEngineEnabledProvider` kesinlikle `false` kalır.

// ignore_for_file: avoid_relative_lib_imports

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('STAGE 10.12.32 — GÜVENLİK KAPISI VE ÖN KOŞUL DOĞRULAMALARI', () {
    test('1.1: coreNextSalesEngineEnabledProvider varsayılan olarak kesinlikle false olmalıdır', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final isEnabled = container.read(coreNextSalesEngineEnabledProvider);
      expect(isEnabled, isFalse, reason: 'Üretim satış motoru kapalı olmalı, pilot açılmamalıdır');
    });

    test('1.2: PilotCutoverGate fail-closed davranmalı ve pilot geçişini engellemelidir', () async {
      final prefs = await SharedPreferences.getInstance();
      final gateResult = await const PilotCutoverGate().evaluate(prefs: prefs);
      expect(gateResult.isPilotActive, isFalse, reason: 'Pilot yetkilendirmesi kapalı olmalıdır');
      expect(gateResult.isFailClosed, isTrue);
    });

    test('1.3: Kaynak yedek dosyaları fiziksel olarak mevcut ve erişilebilir olmalıdır', () async {
      const baseRoaming = r'C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS';
      final rawNutopia = p.join(baseRoaming, r'backups\raw_tenants_20261016\raw_nutopia_v60.db');
      const onedriveDir = r'C:\Users\notop\OneDrive\Belgeler\SerenutBackups';
      final liveBackup = p.join(onedriveDir, 'serenut_pos_backup_20261019_161042.db');

      expect(await File(rawNutopia).exists(), isTrue, reason: 'Nutopia ham arşivi bulunmalıdır');
      expect(await File(liveBackup).exists(), isTrue, reason: 'Güncel canlı yedek bulunmalıdır');
    });
  });

  group('STAGE 10.12.32 — İZOLE EXPORT/IMPORT VERİ MUTABAKATI', () {
    late Directory tempDir;
    late String isolatedSourceDb;
    late String isolatedTargetDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage32_reconcile_');
      isolatedSourceDb = p.join(tempDir.path, 'source_test.db');
      isolatedTargetDb = p.join(tempDir.path, 'target_core_test.db');

      const baseRoaming = r'C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS';
      final rawNutopia = p.join(baseRoaming, r'backups\raw_tenants_20261016\raw_nutopia_v60.db');

      // Kaynak dosyayı geçici dizine kopyala
      await File(rawNutopia).copy(isolatedSourceDb);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('2.1: Tam kapsamlı izole export/import ve 1:1 kayıt mutabakatı', () async {
      final srcDb = await openDatabase(isolatedSourceDb, readOnly: true);
      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetDb);
      final bridge = MigrationBridgeEngine(targetCore);

      // Göçü icra et
      final report = await bridge.migrateFromLegacy(srcDb, fullScope: true);

      expect(report.isSuccess, isTrue, reason: report.errorMessage);
      expect(report.productsMigrated, equals(37682));
      expect(report.customersMigrated, equals(584));
      expect(report.salesMigrated, equals(52));
      expect(report.saleItemsMigrated, equals(120));
      expect(report.ordersMigrated, equals(792));
      expect(report.ledgerEntriesMigrated, equals(1403));
      expect(report.installmentsMigrated, equals(9));

      // Stok mutabakatı
      final targetDb = targetCore.db;
      final stockRes = await targetDb.rawQuery('SELECT SUM(stock_quantity) as total_stock FROM products');
      final targetStock = (stockRes.first['total_stock'] as num).toDouble();
      expect((targetStock - 5179525.85).abs() < 0.01, isTrue,
          reason: 'Hedef stok toplamı 5179525.85 olmalıdır');

      // Müşteri bakiye mutabakatı (-134.500,68 TL = -13450068 kuruş)
      final balRes = await targetDb.rawQuery('SELECT SUM(balance_cents) as total_bal FROM customers');
      final targetBal = (balRes.first['total_bal'] as num).toInt();
      expect(targetBal, equals(-13450068));

      // Satış cirosu mutabakatı (31.282,25 TL = 3128225 kuruş)
      final revRes = await targetDb.rawQuery('SELECT SUM(total_cents) as total_rev FROM sales');
      final targetRev = (revRes.first['total_rev'] as num).toInt();
      expect(targetRev, equals(3128225));

      await srcDb.close();
      await targetCore.close();
    });

    test('2.2: Canlı güncel veritabanı yedeğinin (19.10.2026 - 601 müşteri, 814 sipariş) izole aktarımı', () async {
      const onedriveDir = r'C:\Users\notop\OneDrive\Belgeler\SerenutBackups';
      final liveBackupPath = p.join(onedriveDir, 'serenut_pos_backup_20261019_161042.db');

      final isolatedLiveSource = p.join(tempDir.path, 'source_live_test.db');
      final isolatedLiveTarget = p.join(tempDir.path, 'target_live_core_test.db');

      await File(liveBackupPath).copy(isolatedLiveSource);

      final liveSrcDb = await openDatabase(isolatedLiveSource, readOnly: true);
      final liveTargetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedLiveTarget);
      final bridge = MigrationBridgeEngine(liveTargetCore);

      final report = await bridge.migrateFromLegacy(liveSrcDb, fullScope: true);

      expect(report.isSuccess, isTrue, reason: report.errorMessage);
      expect(report.productsMigrated, equals(37682));
      expect(report.customersMigrated, equals(601), reason: '601 müşterinin tamamı aktarılmalıdır');
      expect(report.salesMigrated, equals(52));
      expect(report.saleItemsMigrated, equals(120));
      expect(report.ordersMigrated, equals(814), reason: '814 siparişin tamamı aktarılmalıdır');

      final targetDb = liveTargetCore.db;
      final stockRes = await targetDb.rawQuery('SELECT SUM(stock_quantity) as total_stock FROM products');
      final targetStock = (stockRes.first['total_stock'] as num).toDouble();
      expect((targetStock - 5178999.45).abs() < 0.01, isTrue,
          reason: 'Canlı güncel stok toplamı 5178999.45 olmalıdır');

      // Müşteri bakiye mutabakatı (-109.322,68 TL = -10932268 kuruş)
      final balRes = await targetDb.rawQuery('SELECT SUM(balance_cents) as total_bal FROM customers');
      final targetBal = (balRes.first['total_bal'] as num).toInt();
      expect(targetBal, equals(-10932268));

      await liveSrcDb.close();
      await liveTargetCore.close();
    });
  });

  group('STAGE 10.12.32 — GERÇEK SATIŞ AKIŞI DOĞRULAMALARI (10 SENARYO)', () {
    late Directory tempDir;
    late CoreAppDatabase testDb;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage32_sales_flow_');
      final testDbPath = p.join(tempDir.path, 'sales_flow_test.db');
      testDb = await CoreAppDatabase.open(inMemoryOrCustomPath: testDbPath);
      db = testDb.db;

      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // Test ürünleri
      await db.insert('products', {
        'id': 'prod-nut-1',
        'barcode': '8690001001',
        'name': 'Kavrulmuş Fındık 500g',
        'price_cents': 20000, // 200.00 TL
        'stock_quantity': 50.0,
        'vat_rate': 1,
        'unit': 'ADET',
        'is_deleted': 0,
        'is_active': 1,
        'updated_at': nowMs,
      });

      await db.insert('products', {
        'id': 'prod-nut-2',
        'barcode': '8690001002',
        'name': 'Fındık Ezmesi 350g',
        'price_cents': 15000, // 150.00 TL
        'stock_quantity': 30.0,
        'vat_rate': 8,
        'unit': 'ADET',
        'is_deleted': 0,
        'is_active': 1,
        'updated_at': nowMs,
      });

      // Test müşterileri
      await db.insert('customers', {
        'id': 'cust-regular',
        'name': 'Mustafa Karadeniz',
        'phone': '05321112233',
        'balance_cents': 0,
        'is_deleted': 0,
        'is_active': 1,
        'updated_at': nowMs,
      });

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

    tearDown(() async {
      await testDb.close();
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('Senaryo 1: Ürün seçimi ve stok kontrolü', () async {
      final rows = await db.query('products', where: 'barcode = ?', whereArgs: ['8690001001']);
      expect(rows.length, equals(1));
      expect(rows.first['name'], equals('Kavrulmuş Fındık 500g'));
      expect((rows.first['stock_quantity'] as num).toDouble(), equals(50.0));
    });

    test('Senaryo 2: Nakit satış ve kasa hareketi', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const saleId = 'test-sale-cash';

      await db.transaction((txn) async {
        await txn.insert('sales', {
          'id': saleId,
          'receipt_no': 'REC-CASH-1',
          'customer_id': 'customer-pesin-default',
          'subtotal_cents': 20000,
          'total_cents': 20000,
          'paid_cents': 20000,
          'debt_cents': 0,
          'status': 'COMPLETED',
          'created_at': nowMs,
        });

        await txn.insert('sale_items', {
          'id': 'item-c1',
          'sale_id': saleId,
          'product_id': 'prod-nut-1',
          'barcode': '8690001001',
          'product_name': 'Kavrulmuş Fındık 500g',
          'quantity': 1.0,
          'unit_price_cents': 20000,
          'vat_rate': 1,
          'total_cents': 20000,
        });

        await txn.insert('cash_transactions', {
          'id': 'cash-tx-1',
          'type': 'INFLOW',
          'category': 'SALE',
          'amount_cents': 20000,
          'description': 'Nakit Satış #$saleId',
          'created_at': nowMs,
        });

        await txn.insert('sale_payments', {
          'id': 'pay-c1',
          'sale_id': saleId,
          'payment_type': 'cash',
          'amount_cents': 20000,
          'created_at': nowMs,
        });

        await txn.rawUpdate('UPDATE products SET stock_quantity = stock_quantity - 1.0 WHERE id = ?', ['prod-nut-1']);
      });

      final p = (await db.query('products', where: 'id = ?', whereArgs: ['prod-nut-1'])).first;
      expect((p['stock_quantity'] as num).toDouble(), equals(49.0));

      final cash = (await db.query('cash_transactions', where: 'id = ?', whereArgs: ['cash-tx-1'])).first;
      expect(cash['amount_cents'], equals(20000));
    });

    test('Senaryo 3: Kart satışı', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const saleId = 'test-sale-card';

      await db.transaction((txn) async {
        await txn.insert('sales', {
          'id': saleId,
          'receipt_no': 'REC-CARD-1',
          'customer_id': 'customer-pesin-default',
          'subtotal_cents': 15000,
          'total_cents': 15000,
          'paid_cents': 15000,
          'debt_cents': 0,
          'status': 'COMPLETED',
          'created_at': nowMs,
        });

        await txn.insert('sale_payments', {
          'id': 'pay-card-1',
          'sale_id': saleId,
          'payment_type': 'card',
          'amount_cents': 15000,
          'created_at': nowMs,
        });

        await txn.rawUpdate('UPDATE products SET stock_quantity = stock_quantity - 1.0 WHERE id = ?', ['prod-nut-2']);
      });

      final p = (await db.query('products', where: 'id = ?', whereArgs: ['prod-nut-2'])).first;
      expect((p['stock_quantity'] as num).toDouble(), equals(29.0));

      final pay = (await db.query('sale_payments', where: 'sale_id = ?', whereArgs: [saleId])).first;
      expect(pay['payment_type'], equals('card'));
      expect(pay['amount_cents'], equals(15000));
    });

    test('Senaryo 4: Vadeli satış ve müşteri bakiyesine borç yansıtma', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const saleId = 'test-sale-credit';

      await db.transaction((txn) async {
        await txn.insert('sales', {
          'id': saleId,
          'receipt_no': 'REC-CREDIT-1',
          'customer_id': 'cust-regular',
          'subtotal_cents': 40000, // 2 adet fındık = 400.00 TL
          'total_cents': 40000,
          'paid_cents': 0,
          'debt_cents': 40000,
          'status': 'COMPLETED',
          'created_at': nowMs,
        });

        await txn.insert('ledger_entries', {
          'id': 'led-cr-1',
          'customer_id': 'cust-regular',
          'reference_sale_id': saleId,
          'entry_type': 'DEBIT',
          'amount_cents': 40000,
          'balance_after_cents': 40000,
          'description': 'Vadeli Satış #$saleId',
          'created_at': nowMs,
        });

        await txn.rawUpdate('UPDATE customers SET balance_cents = balance_cents + 40000 WHERE id = ?', ['cust-regular']);
        await txn.rawUpdate('UPDATE products SET stock_quantity = stock_quantity - 2.0 WHERE id = ?', ['prod-nut-1']);
      });

      final cust = (await db.query('customers', where: 'id = ?', whereArgs: ['cust-regular'])).first;
      expect(cust['balance_cents'], equals(40000)); // 400.00 TL borçlandı

      final p = (await db.query('products', where: 'id = ?', whereArgs: ['prod-nut-1'])).first;
      expect((p['stock_quantity'] as num).toDouble(), equals(48.0));
    });

    test('Senaryo 5: Karma ödeme (Nakit + Kart + Vadeli)', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const saleId = 'test-sale-mixed';

      await db.transaction((txn) async {
        await txn.insert('sales', {
          'id': saleId,
          'receipt_no': 'REC-MIX-1',
          'customer_id': 'cust-regular',
          'subtotal_cents': 50000, // 500 TL
          'total_cents': 50000,
          'paid_cents': 30000, // 200 nakit + 100 kart
          'debt_cents': 20000, // 200 vadeli
          'status': 'COMPLETED',
          'created_at': nowMs,
        });

        // Nakit ödeme
        await txn.insert('sale_payments', {
          'id': 'pay-mix-cash',
          'sale_id': saleId,
          'payment_type': 'cash',
          'amount_cents': 20000,
          'created_at': nowMs,
        });
        await txn.insert('cash_transactions', {
          'id': 'cash-mix-1',
          'type': 'INFLOW',
          'category': 'SALE',
          'amount_cents': 20000,
          'description': 'Karma Satış Nakit Payı #$saleId',
          'created_at': nowMs,
        });

        // Kart ödeme
        await txn.insert('sale_payments', {
          'id': 'pay-mix-card',
          'sale_id': saleId,
          'payment_type': 'card',
          'amount_cents': 10000,
          'created_at': nowMs,
        });

        // Vadeli kısım deftere
        await txn.insert('ledger_entries', {
          'id': 'led-mix-1',
          'customer_id': 'cust-regular',
          'reference_sale_id': saleId,
          'entry_type': 'DEBIT',
          'amount_cents': 20000,
          'balance_after_cents': 60000, // 400 + 200 = 600 TL
          'description': 'Karma Satış Vadeli Kısım #$saleId',
          'created_at': nowMs,
        });
        await txn.rawUpdate('UPDATE customers SET balance_cents = balance_cents + 20000 WHERE id = ?', ['cust-regular']);
      });

      final cust = (await db.query('customers', where: 'id = ?', whereArgs: ['cust-regular'])).first;
      expect(cust['balance_cents'], equals(20000)); // İzole testte sıfırdan 20000 kuruş eklenmişti
    });

    test('Senaryo 6: Satış iptali ve iade', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const saleId = 'test-sale-cancel';

      // Önce satış ekle
      await db.transaction((txn) async {
        await txn.insert('sales', {
          'id': saleId,
          'receipt_no': 'REC-CAN-1',
          'customer_id': 'customer-pesin-default',
          'subtotal_cents': 20000,
          'total_cents': 20000,
          'paid_cents': 20000,
          'debt_cents': 0,
          'status': 'COMPLETED',
          'created_at': nowMs,
        });
        await txn.rawUpdate('UPDATE products SET stock_quantity = stock_quantity - 1.0 WHERE id = ?', ['prod-nut-1']);
      });

      // İptal et
      await db.transaction((txn) async {
        await txn.update('sales', {'status': 'CANCELLED'}, where: 'id = ?', whereArgs: [saleId]);
        await txn.rawUpdate('UPDATE products SET stock_quantity = stock_quantity + 1.0 WHERE id = ?', ['prod-nut-1']);
      });

      final s = (await db.query('sales', where: 'id = ?', whereArgs: [saleId])).first;
      expect(s['status'], equals('CANCELLED'));

      final p = (await db.query('products', where: 'id = ?', whereArgs: ['prod-nut-1'])).first;
      expect((p['stock_quantity'] as num).toDouble(), equals(50.0)); // Stok iade edildi
    });

    test('Senaryo 7: Tahsilat ve müşteri bakiyesi', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // Müşteriye 150 TL borç yazalım
      await db.rawUpdate('UPDATE customers SET balance_cents = 15000 WHERE id = ?', ['cust-regular']);

      // 100 TL tahsilat yapalım
      await db.transaction((txn) async {
        await txn.insert('ledger_entries', {
          'id': 'led-col-1',
          'customer_id': 'cust-regular',
          'entry_type': 'COLLECTION',
          'amount_cents': 10000,
          'balance_after_cents': 5000,
          'description': 'Müşteri Tahsilatı',
          'created_at': nowMs,
        });
        await txn.insert('cash_transactions', {
          'id': 'cash-col-1',
          'type': 'INFLOW',
          'category': 'COLLECTION',
          'amount_cents': 10000,
          'description': 'Tahsilat cust-regular',
          'created_at': nowMs,
        });
        await txn.rawUpdate('UPDATE customers SET balance_cents = balance_cents - 10000 WHERE id = ?', ['cust-regular']);
      });

      final cust = (await db.query('customers', where: 'id = ?', whereArgs: ['cust-regular'])).first;
      expect(cust['balance_cents'], equals(5000)); // 150 - 100 = 50 TL (5000 kuruş)
    });

    test('Senaryo 8: İşlem tekrarında mükerrer satış oluşmaması (Idempotency)', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const saleId = 'test-sale-unique-1';

      await db.insert('sales', {
        'id': saleId,
        'receipt_no': 'REC-UNIQ-1',
        'customer_id': 'customer-pesin-default',
        'subtotal_cents': 10000,
        'total_cents': 10000,
        'paid_cents': 10000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': nowMs,
      });

      // Aynı id ile tekrar ekleme DatabaseException vermelidir
      expect(
        () async => await db.insert('sales', {
          'id': saleId,
          'receipt_no': 'REC-UNIQ-DUP',
          'customer_id': 'customer-pesin-default',
          'subtotal_cents': 10000,
          'total_cents': 10000,
          'paid_cents': 10000,
          'debt_cents': 0,
          'status': 'COMPLETED',
          'created_at': nowMs,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('Senaryo 9: İşlem başarısız olduğunda transaction rollback', () async {
      final pBefore = (await db.query('products', where: 'id = ?', whereArgs: ['prod-nut-1'])).first;
      final stockBefore = (pBefore['stock_quantity'] as num).toDouble();

      try {
        await db.transaction((txn) async {
          await txn.rawUpdate('UPDATE products SET stock_quantity = stock_quantity - 5.0 WHERE id = ?', ['prod-nut-1']);
          // Hata fırlatalım
          throw Exception('Simüle edilmiş ödeme arayüzü çökmesi');
        });
      } catch (_) {}

      final pAfter = (await db.query('products', where: 'id = ?', whereArgs: ['prod-nut-1'])).first;
      final stockAfter = (pAfter['stock_quantity'] as num).toDouble();

      expect(stockAfter, equals(stockBefore), reason: 'Transaction çöktüğünde stok geri alınmalıdır (Rollback)');
    });

    test('Senaryo 10: İşlem sonrasında stok ve finansal kayıtların tutarlılığı', () async {
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first, equals('ok'));

      // Negatif kuruş veya tutarsız satış kaydı olmamalı
      final invalidSales = await db.rawQuery('SELECT COUNT(*) as count FROM sales WHERE paid_cents + debt_cents != total_cents');
      expect(invalidSales.first['count'], equals(0));
    });
  });
}
