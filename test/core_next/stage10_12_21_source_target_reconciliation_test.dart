// test/core_next/stage10_12_21_source_target_reconciliation_test.dart
// SERENUT OS — STAGE 10.12.21
// KAYNAK-HEDEF VERİ TUTARSIZLIKLARINI ÇÖZME VE BAĞIMSIZ MUTABAKAT TEST PAKETİ

@Timeout(Duration(minutes: 5))
library;

// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const String expectedNutopiaSha =
      'e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24';
  final String nutopiaSourcePath = p.normalize(
    p.join(Directory.current.path, 'backups', 'raw_tenants_20261016', 'raw_nutopia_v60.db'),
  );

  String calculateFileSha256(String filePath) {
    final bytes = File(filePath).readAsBytesSync();
    return sha256.convert(bytes).toString();
  }

  group('STAGE 10.12.21: KAYNAK-HEDEF DERİN ADLİ MUTABAKAT VE ÇELİŞKİ ÇÖZÜMÜ', () {
    late Directory tempDir;
    late String isolatedNutopiaPath;
    late String isolatedTargetPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stg10_12_21_reconciliation_');
      isolatedNutopiaPath = p.join(tempDir.path, 'nutopia_source_copy.db');
      isolatedTargetPath = p.join(tempDir.path, 'target_core_app.db');

      final rawBackup = File(nutopiaSourcePath);
      expect(rawBackup.existsSync(), isTrue, reason: 'Kaynak Nutopia yedeği bulunamadı');
      final currentSha = calculateFileSha256(nutopiaSourcePath);
      expect(
        currentSha,
        equals(expectedNutopiaSha),
        reason: 'Kaynak DB SHA-256 imzası bozulmuş olamaz!',
      );

      // Yalnızca izole geçici kopyayı kullan
      await rawBackup.copy(isolatedNutopiaPath);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('1. Kaynak DB SHA-256 hash doğrulaması ve dokunulmazlık', () async {
      final sha = calculateFileSha256(nutopiaSourcePath);
      expect(sha, equals(expectedNutopiaSha));
    });

    test('2. Ürün sayısı çelişkisinin çözümü ve ID/alan bazlı karşılaştırma', () async {
      final legacyDb = await openDatabase(isolatedNutopiaPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // Kaynak incelemesi
      final srcTotal = (await legacyDb.rawQuery('SELECT count(*) as c FROM products')).first['c'] as int;
      final srcActive = (await legacyDb.rawQuery('SELECT count(*) as c FROM products WHERE is_deleted = 0')).first['c'] as int;
      final srcDeleted = (await legacyDb.rawQuery('SELECT count(*) as c FROM products WHERE is_deleted = 1')).first['c'] as int;
      final srcIsActive1 = (await legacyDb.rawQuery('SELECT count(*) as c FROM products WHERE is_active = 1')).first['c'] as int;
      final srcIsActive0 = (await legacyDb.rawQuery('SELECT count(*) as c FROM products WHERE is_active = 0')).first['c'] as int;

      // Çelişkinin çözümü: Kaynakta 37.682 ürünün 17 adedi aktif, 37.665 adedi silinmiştir!
      expect(srcTotal, equals(37682));
      expect(srcActive, equals(17));
      expect(srcDeleted, equals(37665));
      expect(srcIsActive1, equals(17));
      expect(srcIsActive0, equals(37665));

      // Göçü çalıştır
      final rep = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep.isSuccess, isTrue);

      final target = coreDb.db;
      final tgtTotal = (await target.rawQuery('SELECT count(*) as c FROM products')).first['c'] as int;
      final tgtActive = (await target.rawQuery('SELECT count(*) as c FROM products WHERE is_deleted = 0')).first['c'] as int;
      final tgtDeleted = (await target.rawQuery('SELECT count(*) as c FROM products WHERE is_deleted = 1')).first['c'] as int;
      final tgtIsActive1 = (await target.rawQuery('SELECT count(*) as c FROM products WHERE is_active = 1')).first['c'] as int;
      final tgtIsActive0 = (await target.rawQuery('SELECT count(*) as c FROM products WHERE is_active = 0')).first['c'] as int;

      expect(tgtTotal, equals(37682));
      expect(tgtActive, equals(17));
      expect(tgtDeleted, equals(37665));
      expect(tgtIsActive1, equals(17));
      expect(tgtIsActive0, equals(37665));

      // ID kümesi karşılaştırması
      final srcRows = await legacyDb.rawQuery('SELECT id, name, sku, quantity, price, price_minor FROM products');
      final tgtRows = await target.rawQuery('SELECT id, name, barcode, stock_quantity, price_cents FROM products');

      final srcIds = srcRows.map((r) => r['id'].toString()).toSet();
      final tgtIds = tgtRows.map((r) => r['id'].toString()).toSet();

      expect(srcIds.difference(tgtIds), isEmpty, reason: 'Hedefte eksik ürün ID bulunmamalı');
      expect(tgtIds.difference(srcIds), isEmpty, reason: 'Hedefte fazladan ürün ID bulunmamalı');

      // 17 aktif ürünün isim, barkod/sku, stok ve fiyat alanlarının bire bir denkliği
      final srcActiveList = await legacyDb.rawQuery('SELECT id, name, sku, quantity, price, price_minor FROM products WHERE is_deleted = 0');
      for (final sRow in srcActiveList) {
        final id = sRow['id'].toString();
        final tRow = tgtRows.firstWhere((r) => r['id'].toString() == id);

        expect(tRow['name'], equals(sRow['name']));
        final expectedBarcode = (sRow['sku'] ?? id).toString().trim();
        expect(tRow['barcode'], equals(expectedBarcode));

        final num srcStock = (sRow['quantity'] as num?) ?? 0;
        final num tgtStock = (tRow['stock_quantity'] as num?) ?? 0;
        expect((srcStock - tgtStock).abs() < 0.001, isTrue);

        final int expectedCents = (sRow['price_minor'] != null)
            ? (sRow['price_minor'] as num).toInt()
            : (((sRow['price'] as num?)?.toDouble() ?? 0.0) * 100).round();
        expect(tRow['price_cents'], equals(expectedCents));
      }

      await legacyDb.close();
      await coreDb.close();
    });

    test('3. Satış ve satış kalemi (120 adet) ID eşlemesi ve parasal toplamlar', () async {
      final legacyDb = await openDatabase(isolatedNutopiaPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // Kaynak: 52 satış ve 120 satış kalemi
      final srcSales = await legacyDb.rawQuery('SELECT id, total_amount, total_amount_minor FROM sales');
      final srcItems = await legacyDb.rawQuery('SELECT id, sale_id, product_id, quantity, subtotal, subtotal_minor FROM sale_items');

      expect(srcSales.length, equals(52));
      expect(srcItems.length, equals(120), reason: 'Kaynakta tam olarak 120 satış kalemi bulunmalıdır');

      int srcSalesTotalCents = 0;
      for (final s in srcSales) {
        if (s['total_amount_minor'] != null) {
          srcSalesTotalCents += (s['total_amount_minor'] as num).toInt();
        } else {
          srcSalesTotalCents += (((s['total_amount'] as num?)?.toDouble() ?? 0.0) * 100).round();
        }
      }
      expect(srcSalesTotalCents, equals(3128225)); // 31.282,25 TL

      int srcItemsSubtotalCents = 0;
      for (final it in srcItems) {
        if (it['subtotal_minor'] != null) {
          srcItemsSubtotalCents += (it['subtotal_minor'] as num).toInt();
        } else {
          srcItemsSubtotalCents += (((it['subtotal'] as num?)?.toDouble() ?? 0.0) * 100).round();
        }
      }
      expect(srcItemsSubtotalCents, equals(3130725)); // 31.307,25 TL

      await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      final target = coreDb.db;

      final tgtSales = await target.rawQuery('SELECT id, total_cents FROM sales');
      final tgtItems = await target.rawQuery('SELECT id, sale_id, product_id, total_cents FROM sale_items');

      expect(tgtSales.length, equals(52));
      expect(tgtItems.length, equals(120), reason: 'Hedefte tam olarak 120 satış kalemi bulunmalıdır');

      final tgtSalesTotalCents = (await target.rawQuery('SELECT SUM(total_cents) as s FROM sales')).first['s'] as int;
      expect(tgtSalesTotalCents, equals(3128225));

      final tgtItemsTotalCents = (await target.rawQuery('SELECT SUM(total_cents) as s FROM sale_items')).first['s'] as int;
      expect(tgtItemsTotalCents, equals(3130725));

      // ID kümeleri bire bir eşleşmeli
      final srcSaleIds = srcSales.map((r) => r['id'].toString()).toSet();
      final tgtSaleIds = tgtSales.map((r) => r['id'].toString()).toSet();
      expect(srcSaleIds.difference(tgtSaleIds), isEmpty);
      expect(tgtSaleIds.difference(srcSaleIds), isEmpty);

      final srcItemIds = srcItems.map((r) => r['id'].toString()).toSet();
      final tgtItemIds = tgtItems.map((r) => r['id'].toString()).toSet();
      expect(srcItemIds.difference(tgtItemIds), isEmpty);
      expect(tgtItemIds.difference(srcItemIds), isEmpty);

      await legacyDb.close();
      await coreDb.close();
    });

    test('4. Sipariş ve sipariş kalemi eşlemesi (792 sipariş / 1068 kalem)', () async {
      final legacyDb = await openDatabase(isolatedNutopiaPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      final srcOrders = await legacyDb.rawQuery('SELECT id, total_amount FROM orders');
      final srcOrderItems = await legacyDb.rawQuery('SELECT id, order_id FROM order_items');

      expect(srcOrders.length, equals(792));
      expect(srcOrderItems.length, equals(1068));

      await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      final target = coreDb.db;

      final tgtOrders = await target.rawQuery('SELECT id, total_amount_cents FROM orders');
      final tgtOrderItems = await target.rawQuery('SELECT id, order_id FROM order_items');

      expect(tgtOrders.length, equals(792));
      expect(tgtOrderItems.length, equals(1068));

      final srcOrderIds = srcOrders.map((r) => r['id'].toString()).toSet();
      final tgtOrderIds = tgtOrders.map((r) => r['id'].toString()).toSet();
      expect(srcOrderIds.difference(tgtOrderIds), isEmpty);
      expect(tgtOrderIds.difference(srcOrderIds), isEmpty);

      final srcOrderItemIds = srcOrderItems.map((r) => r['id'].toString()).toSet();
      final tgtOrderItemIds = tgtOrderItems.map((r) => r['id'].toString()).toSet();
      expect(srcOrderItemIds.difference(tgtOrderItemIds), isEmpty);
      expect(tgtOrderItemIds.difference(srcOrderItemIds), isEmpty);

      await legacyDb.close();
      await coreDb.close();
    });

    test('5. Müşteri bakiyeleri ve finans hareketleri (584 müşteri / 1403 defter kaydı)', () async {
      final legacyDb = await openDatabase(isolatedNutopiaPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      final srcCustRows = await legacyDb.rawQuery('SELECT id, balance, balance_minor FROM customers');
      expect(srcCustRows.length, equals(584));

      int srcBalSumCents = 0;
      for (final r in srcCustRows) {
        final rawBal = (r['balance'] as num?)?.toDouble() ?? 0.0;
        srcBalSumCents += (rawBal * 100).round();
      }
      expect(srcBalSumCents, equals(-13450068)); // -134.500,68 TL

      final srcCustTxs = await legacyDb.rawQuery('''
        SELECT * FROM financial_transactions 
        WHERE customer_id IS NOT NULL 
          AND customer_id != '' 
          AND customer_id IN (SELECT id FROM customers)
      ''');
      expect(srcCustTxs.length, equals(1403));

      await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      final target = coreDb.db;

      final tgtCustRows = await target.rawQuery('SELECT id, balance_cents FROM customers');
      expect(tgtCustRows.length, equals(584));

      final tgtBalSumCents = (await target.rawQuery('SELECT SUM(balance_cents) as s FROM customers')).first['s'] as int;
      expect(tgtBalSumCents, equals(-13450068));

      final tgtLedgerRows = await target.rawQuery('SELECT id, customer_id, amount_cents, entry_type FROM ledger_entries');
      expect(tgtLedgerRows.length, equals(1403));

      // ID kümesi karşılaştırması
      final srcCustIds = srcCustRows.map((r) {
        final id = r['id'].toString();
        return id.isEmpty ? 'customer-pesin-default' : id;
      }).toSet();
      final tgtCustIds = tgtCustRows.map((r) => r['id'].toString()).toSet();
      expect(srcCustIds.difference(tgtCustIds), isEmpty);
      expect(tgtCustIds.difference(srcCustIds), isEmpty);

      await legacyDb.close();
      await coreDb.close();
    });

    test('6. Müşterisiz nakit satışların (21 adet) doğrudan cash_transactions tablosuna aktarılması', () async {
      final legacyDb = await openDatabase(isolatedNutopiaPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // Kaynakta müşterisiz nakit işlemler
      final srcAnonTxs = await legacyDb.rawQuery('''
        SELECT id, amount, amount_minor, type, reference_id, description FROM financial_transactions 
        WHERE (customer_id IS NULL OR customer_id = '' OR customer_id NOT IN (SELECT id FROM customers))
          AND type = 'sale'
      ''');
      expect(srcAnonTxs.length, equals(21));

      int srcAnonTotalCents = 0;
      for (final r in srcAnonTxs) {
        if (r['amount_minor'] != null) {
          srcAnonTotalCents += (r['amount_minor'] as num).toInt();
        } else {
          srcAnonTotalCents += (((r['amount'] as num?)?.toDouble() ?? 0.0) * 100).round();
        }
      }
      expect(srcAnonTotalCents, equals(1219700)); // 12.197,00 TL

      await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      final target = coreDb.db;

      // Hedefte gerçek cash_transactions tablosunun incelenmesi (outbox değil)
      final tgtCashTxs = await target.rawQuery('''
        SELECT id, type, category, amount_cents, description 
        FROM cash_transactions 
        WHERE category = 'SALE'
      ''');

      expect(tgtCashTxs.length, equals(21));
      for (final ct in tgtCashTxs) {
        expect(ct['type'], equals('INFLOW'));
        expect(ct['category'], equals('SALE'));
      }

      final tgtCashTotalCents = (await target.rawQuery('''
        SELECT SUM(amount_cents) as s FROM cash_transactions WHERE category = 'SALE'
      ''')).first['s'] as int;
      expect(tgtCashTotalCents, equals(1219700));

      // ID kümesi eşleşmesi
      final srcAnonIds = srcAnonTxs.map((r) => r['id'].toString()).toSet();
      final tgtAnonIds = tgtCashTxs.map((r) => r['id'].toString()).toSet();
      expect(srcAnonIds.difference(tgtAnonIds), isEmpty);
      expect(tgtAnonIds.difference(srcAnonIds), isEmpty);

      await legacyDb.close();
      await coreDb.close();
    });

    test('7. Taksit planları (2 plan) ve taksit dilimleri (9 dilim) mutabakatı', () async {
      final legacyDb = await openDatabase(isolatedNutopiaPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      final srcPlans = await legacyDb.rawQuery('SELECT id, customer_id, total_amount FROM customer_installment_plans');
      final srcInsts = await legacyDb.rawQuery('SELECT id, plan_id, customer_id, amount, paid_amount FROM customer_installments');

      expect(srcPlans.length, equals(2));
      expect(srcInsts.length, equals(9));

      await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      final target = coreDb.db;

      final tgtPlans = await target.rawQuery('SELECT id, customer_id, total_amount_cents FROM customer_installment_plans');
      final tgtInsts = await target.rawQuery('SELECT id, plan_id, customer_id, amount_cents, paid_amount_cents FROM customer_installments');

      expect(tgtPlans.length, equals(2));
      expect(tgtInsts.length, equals(9));

      final srcPlanIds = srcPlans.map((r) => r['id'].toString()).toSet();
      final tgtPlanIds = tgtPlans.map((r) => r['id'].toString()).toSet();
      expect(srcPlanIds.difference(tgtPlanIds), isEmpty);
      expect(tgtPlanIds.difference(srcPlanIds), isEmpty);

      final srcInstIds = srcInsts.map((r) => r['id'].toString()).toSet();
      final tgtInstIds = tgtInsts.map((r) => r['id'].toString()).toSet();
      expect(srcInstIds.difference(tgtInstIds), isEmpty);
      expect(tgtInstIds.difference(srcInstIds), isEmpty);

      await legacyDb.close();
      await coreDb.close();
    });

    test('8. Yetim kayıt (orphan) ve yinelenen kayıt (duplicate) mutabakatı', () async {
      final legacyDb = await openDatabase(isolatedNutopiaPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      final target = coreDb.db;

      // 1. Yetim Satış Kalemi Kontrolü
      final orphanSaleItems = await target.rawQuery('''
        SELECT count(*) as c FROM sale_items si 
        LEFT JOIN sales s ON si.sale_id = s.id 
        WHERE s.id IS NULL
      ''');
      expect(orphanSaleItems.first['c'], equals(0));

      // 2. Yetim Sipariş Kalemi Kontrolü
      final orphanOrderItems = await target.rawQuery('''
        SELECT count(*) as c FROM order_items oi 
        LEFT JOIN orders o ON oi.order_id = o.id 
        WHERE o.id IS NULL
      ''');
      expect(orphanOrderItems.first['c'], equals(0));

      // 3. Yetim Defter Hareketi Kontrolü
      final orphanLedger = await target.rawQuery('''
        SELECT count(*) as c FROM ledger_entries le 
        LEFT JOIN customers c ON le.customer_id = c.id 
        WHERE c.id IS NULL
      ''');
      expect(orphanLedger.first['c'], equals(0));

      // 4. Yetim Taksit Kontrolü
      final orphanInsts = await target.rawQuery('''
        SELECT count(*) as c FROM customer_installments ci 
        LEFT JOIN customer_installment_plans cp ON ci.plan_id = cp.id 
        WHERE cp.id IS NULL
      ''');
      expect(orphanInsts.first['c'], equals(0));

      // 5. Duplicate ID kontrolü
      for (final table in ['products', 'customers', 'sales', 'sale_items', 'orders', 'order_items', 'ledger_entries', 'cash_transactions', 'customer_installment_plans', 'customer_installments']) {
        final dups = await target.rawQuery('SELECT id, count(*) as c FROM $table GROUP BY id HAVING c > 1');
        expect(dups, isEmpty, reason: '$table tablosunda yinelenen ID tespit edildi!');
      }

      await legacyDb.close();
      await coreDb.close();
    });

    test('9. İdempotency: Aynı mutabakat sorgularının 2. çalıştırmada bire bir aynı kalması', () async {
      final legacyDb = await openDatabase(isolatedNutopiaPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // İlk çalıştırma
      final rep1 = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep1.isSuccess, isTrue);

      final target = coreDb.db;
      final p1 = (await target.rawQuery('SELECT count(*) as c FROM products')).first['c'] as int;
      final c1 = (await target.rawQuery('SELECT count(*) as c FROM customers')).first['c'] as int;
      final s1 = (await target.rawQuery('SELECT count(*) as c FROM sales')).first['c'] as int;
      final si1 = (await target.rawQuery('SELECT count(*) as c FROM sale_items')).first['c'] as int;
      final o1 = (await target.rawQuery('SELECT count(*) as c FROM orders')).first['c'] as int;
      final oi1 = (await target.rawQuery('SELECT count(*) as c FROM order_items')).first['c'] as int;
      final l1 = (await target.rawQuery('SELECT count(*) as c FROM ledger_entries')).first['c'] as int;
      final ct1 = (await target.rawQuery('SELECT count(*) as c FROM cash_transactions')).first['c'] as int;

      // İkinci çalıştırma
      final rep2 = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep2.isSuccess, isTrue);

      final p2 = (await target.rawQuery('SELECT count(*) as c FROM products')).first['c'] as int;
      final c2 = (await target.rawQuery('SELECT count(*) as c FROM customers')).first['c'] as int;
      final s2 = (await target.rawQuery('SELECT count(*) as c FROM sales')).first['c'] as int;
      final si2 = (await target.rawQuery('SELECT count(*) as c FROM sale_items')).first['c'] as int;
      final o2 = (await target.rawQuery('SELECT count(*) as c FROM orders')).first['c'] as int;
      final oi2 = (await target.rawQuery('SELECT count(*) as c FROM order_items')).first['c'] as int;
      final l2 = (await target.rawQuery('SELECT count(*) as c FROM ledger_entries')).first['c'] as int;
      final ct2 = (await target.rawQuery('SELECT count(*) as c FROM cash_transactions')).first['c'] as int;

      expect(p2, equals(p1));
      expect(c2, equals(c1));
      expect(s2, equals(s1));
      expect(si2, equals(si1));
      expect(o2, equals(o1));
      expect(oi2, equals(oi1));
      expect(l2, equals(l1));
      expect(ct2, equals(ct1));

      await legacyDb.close();
      await coreDb.close();
    });

    test('10. Kaynak ve hedef ID fark analizi (Missing and Extra ID lists)', () async {
      final legacyDb = await openDatabase(isolatedNutopiaPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      final target = coreDb.db;

      Future<void> assertIdParity(String srcTable, String tgtTable) async {
        final srcList = (await legacyDb.rawQuery('SELECT id FROM $srcTable')).map((r) {
          final id = r['id'].toString();
          if (srcTable == 'customers' && id.isEmpty) {
            return 'customer-pesin-default';
          }
          return id;
        }).toSet();
        final tgtList = (await target.rawQuery('SELECT id FROM $tgtTable')).map((r) => r['id'].toString()).toSet();

        final missingInTarget = srcList.difference(tgtList).toList();
        final extraInTarget = tgtList.difference(srcList).toList();

        expect(missingInTarget, isEmpty, reason: '$srcTable -> $tgtTable eksik kayıtlar: $missingInTarget');
        expect(extraInTarget, isEmpty, reason: '$srcTable -> $tgtTable fazladan kayıtlar: $extraInTarget');
      }

      await assertIdParity('products', 'products');
      await assertIdParity('customers', 'customers');
      await assertIdParity('sales', 'sales');
      await assertIdParity('sale_items', 'sale_items');
      await assertIdParity('orders', 'orders');
      await assertIdParity('order_items', 'order_items');
      await assertIdParity('customer_installment_plans', 'customer_installment_plans');
      await assertIdParity('customer_installments', 'customer_installments');

      await legacyDb.close();
      await coreDb.close();
    });
  });
}
