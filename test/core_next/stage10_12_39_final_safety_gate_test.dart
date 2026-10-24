// test/core_next/stage10_12_39_final_safety_gate_test.dart
// SERENUT OS — STAGE 10.12.39
// ÜRETİM KODUNA BAĞLI SON GÜVENLİK KAPISI VE VERİ GEÇİŞİ HAZIRLIK DEĞERLENDİRMESİ
//
// GÜVENLİK SINIRLARI:
// 1. Canlı veritabanlarına dokunulmaz.
// 2. Yalnızca geçici, izole SQLite test kopyaları kullanılır.
// 3. `coreNextSalesEngineEnabledProvider = false` ve `databaseRoutingHook = null` korunur.
// 4. Testler doğrudan üretim fonksiyonu `ReverseMigrationEngine.rollbackToLegacy()` ve
//    `DatabaseRoutingResolver.resolve()` / `assertSafeRollback()` çağırır.

// ignore_for_file: avoid_relative_lib_imports, prefer_const_declarations

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const rawNutopiaPath = 'backups/raw_tenants_20261016/raw_nutopia_v60.db';

  group('STAGE 10.12.39 — BÖLÜM 1: GÜVENLİK SINIRLARI VE SABİTLER', () {
    test('1.1: coreNextSalesEngineEnabledProvider = false ve databaseRoutingHook = null korunur', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final salesEngine = container.read(coreNextSalesEngineEnabledProvider);
      expect(salesEngine, isFalse, reason: 'coreNextSalesEngineEnabledProvider kesinlikle false kalmalıdır');
      expect(DatabaseManager.databaseRoutingHook, isNull, reason: 'databaseRoutingHook kesinlikle null kalmalıdır');
    });

    test('1.2: Kaynak arşiv Nutopia v60 dosyası mevcuttur', () async {
      final file = File(rawNutopiaPath);
      expect(await file.exists(), isTrue, reason: 'Nutopia ham arşiv dosyası diskte olmalıdır');
    });
  });

  group('STAGE 10.12.39 — BÖLÜM 2: 8 KRİTİK İADE, FİNANSAL VE İÇERİK BÜTÜNLÜĞÜ SENARYOSU', () {
    late Directory tempDir;
    late String legacyPath;
    late String corePath;
    late Database legacyDb;
    late CoreAppDatabase coreAppDb;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('stage39_gate_');
      legacyPath = p.join(tempDir.path, 'legacy_nutopia.db');
      corePath = p.join(tempDir.path, 'core_serenut_v2.db');

      await File(rawNutopiaPath).copy(legacyPath);
      legacyDb = await databaseFactoryFfi.openDatabase(legacyPath);
      coreAppDb = await CoreAppDatabase.open(inMemoryOrCustomPath: corePath);
    });

    tearDown(() async {
      await legacyDb.close();
      await coreAppDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    // Senaryo 1: İade tutarı aynı, ancak iade kalemleri farklı
    test('Senaryo 1: İade tutarı aynı (-50 TL), ancak iade kalemleri farklı olduğunda aktarım durdurulur', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const collisionRefundId = 'ref-diff-items-1';

      // 1. Legacy'de orijinal satış oluştur (Legacy v60 sales tablosunda receipt_no sütunu yoktur)
      await legacyDb.insert('sales', {
        'id': 'sale-orig-101',
        'customer_id': 'customer-pesin-default',
        'total_amount': 100.0,
        'total_amount_minor': 10000,
        'paid_amount': 100.0,
        'payment_method': 'cash',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('sale_items', {
        'id': 'si-orig-1',
        'sale_id': 'sale-orig-101',
        'product_id': 'prod-A',
        'quantity': 1.0,
        'unit_price': 50.0,
        'subtotal': 50.0,
        'created_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('sale_items', {
        'id': 'si-orig-2',
        'sale_id': 'sale-orig-101',
        'product_id': 'prod-B',
        'quantity': 1.0,
        'unit_price': 50.0,
        'subtotal': 50.0,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Legacy'de mevcut iade: 50 TL -> Kalem: Ürün A (1 adet)
      await legacyDb.insert('refunds', {
        'id': collisionRefundId,
        'sale_id': 'sale-orig-101',
        'amount': 50.0,
        'refund_method': 'cash',
        'reason': 'İade',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('refund_items', {
        'id': 'ri-leg-1',
        'refund_id': collisionRefundId,
        'sale_item_id': 'si-orig-1',
        'product_id': 'prod-A',
        'quantity': 1,
        'unit_refund_amount': 50.0,
        'subtotal': 50.0,
      });

      // Core Next'te AYNI İade ID, AYNI Tutar (-5000 sent) -> Kalem: Ürün B (1 adet)
      await coreAppDb.db.insert('products', {
        'id': 'prod-B',
        'barcode': 'prod-B',
        'name': 'Ürün B',
        'price_cents': 5000,
        'stock_quantity': 10,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      });
      await coreAppDb.db.insert('sales', {
        'id': collisionRefundId,
        'receipt_no': 'REF-sale-orig-101',
        'subtotal_cents': -5000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': -5000,
        'paid_cents': -5000,
        'debt_cents': 0,
        'status': 'REFUND',
        'idempotency_key': 'IDEM-REF-DIFF-ITEMS',
        'created_at': now,
      });
      await coreAppDb.db.insert('sale_items', {
        'id': 'item-core-ref-1',
        'sale_id': collisionRefundId,
        'product_id': 'prod-B',
        'barcode': 'prod-B',
        'product_name': 'Ürün B',
        'unit_price_cents': 5000,
        'quantity': 1.0,
        'discount_cents': 0,
        'vat_rate': 0,
        'total_cents': -5000,
      });

      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isFalse);
      expect(report.errorMessage, contains('İADE KALEM DETAY ÇAKIŞMASI TESPİT EDİLDİ'));
      expect(report.errorMessage, contains('prod-B'));
    });

    // Senaryo 2: İade aynı, ancak ilişkili satış ID'si farklı
    test('Senaryo 2: İade aynı, ancak ilişkili satış ID\'si farklı olduğunda aktarım durdurulur', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const collisionRefundId = 'ref-diff-sale-id-1';

      // Legacy'de iki ayrı satış
      await legacyDb.insert('sales', {
        'id': 'sale-orig-201',
        'customer_id': 'customer-pesin-default',
        'total_amount': 50.0,
        'total_amount_minor': 5000,
        'paid_amount': 50.0,
        'payment_method': 'cash',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('sales', {
        'id': 'sale-orig-202',
        'customer_id': 'customer-pesin-default',
        'total_amount': 50.0,
        'total_amount_minor': 5000,
        'paid_amount': 50.0,
        'payment_method': 'cash',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Legacy'de mevcut iade: sale-orig-201'e bağlı
      await legacyDb.insert('refunds', {
        'id': collisionRefundId,
        'sale_id': 'sale-orig-201',
        'amount': 30.0,
        'refund_method': 'cash',
        'reason': 'İade',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
      });

      // Core Next'te AYNI İade ID, AYNI Tutar (-3000 sent) -> AMA REF-sale-orig-202 (sale-orig-202) referanslı
      await coreAppDb.db.insert('sales', {
        'id': collisionRefundId,
        'receipt_no': 'REF-sale-orig-202', // sale-orig-202'ye bağlanmak istiyor
        'subtotal_cents': -3000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': -3000,
        'paid_cents': -3000,
        'debt_cents': 0,
        'status': 'REFUND',
        'idempotency_key': 'IDEM-REF-DIFF-SALE',
        'created_at': now,
      });

      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isFalse);
      expect(report.errorMessage, contains('İADE İLİŞKİLİ SATIŞ ÇAKIŞMASI TESPİT EDİLDİ'));
      expect(report.errorMessage, contains('sale-orig-201'));
      expect(report.errorMessage, contains('sale-orig-202'));
    });

    // Senaryo 3: İade aynı, ancak stok etkisi veya müşteri bakiyesi baseline farklı
    test('Senaryo 3: İade aynı, ancak stok etkisi baseline legacy ile çakıştığında aktarım durdurulur', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const refundSaleId = 'ref-stock-conflict-1';
      final sampleProd = (await legacyDb.query('products', limit: 1)).first;
      final prodId = sampleProd['id'].toString();
      final initialLegacyQty = (sampleProd['quantity'] as num).toDouble();
      final priceCents = 2000;

      // Core Next: 1 adet iade edildi -> Core stok = initialLegacyQty + 1
      await coreAppDb.db.insert('products', {
        'id': prodId,
        'barcode': sampleProd['sku']?.toString() ?? prodId,
        'name': sampleProd['name']?.toString() ?? 'Ürün',
        'price_cents': priceCents,
        'stock_quantity': (initialLegacyQty + 1.0).round(),
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await coreAppDb.db.insert('sales', {
        'id': refundSaleId,
        'receipt_no': 'REF-REC-STK',
        'subtotal_cents': -priceCents,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': -priceCents,
        'paid_cents': -priceCents,
        'debt_cents': 0,
        'status': 'REFUND',
        'idempotency_key': 'IDEM-REF-STK',
        'created_at': now,
      });

      await coreAppDb.db.insert('sale_items', {
        'id': 'item-ref-stk-1',
        'sale_id': refundSaleId,
        'product_id': prodId,
        'barcode': prodId,
        'product_name': 'Ürün',
        'unit_price_cents': priceCents,
        'quantity': 1.0,
        'discount_cents': 0,
        'vat_rate': 0,
        'total_cents': -priceCents,
      });

      // Legacy DB'de beklenmeyen stok sapması (ör. manuel sayım ile stok değişmiş)
      await legacyDb.update('products', {'quantity': initialLegacyQty + 5.0}, where: 'id = ?', whereArgs: [prodId]);

      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isFalse);
      expect(report.errorMessage, contains('STOK ÇAKIŞMASI TESPİT EDİLDİ'));
      expect(report.errorMessage, contains(prodId));
    });

    // Senaryo 4: Finansal işlem tutarı aynı, ancak kaynak satış (reference_id) farklı
    test('Senaryo 4: Finansal işlem tutarı aynı, ancak kaynak satış (reference_id) farklı olduğunda aktarım durdurulur', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const collisionFtId = 'ft-diff-ref-1';

      await legacyDb.insert('customers', {
        'id': 'cust-ft-1',
        'name': 'Test Cust',
        'balance': 0.0,
        'balance_minor': 0,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Legacy DB: 40 TL hareket -> reference_id = 'sale-ref-AAA'
      await legacyDb.insert('financial_transactions', {
        'id': collisionFtId,
        'customer_id': 'cust-ft-1',
        'type': 'SALE',
        'amount': 40.0,
        'reference_id': 'sale-ref-AAA',
        'created_at': DateTime.now().toIso8601String(),
      });

      // Core Next DB: AYNI ID, AYNI 4000 sent -> AMA reference_sale_id = 'sale-ref-BBB'
      await coreAppDb.db.insert('customers', {
        'id': 'cust-ft-1',
        'name': 'Test Cust',
        'balance_cents': 0,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      });

      await coreAppDb.db.insert('sales', {
        'id': 'sale-ref-BBB',
        'receipt_no': 'REC-BBB',
        'customer_id': 'cust-ft-1',
        'subtotal_cents': 4000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 4000,
        'paid_cents': 0,
        'debt_cents': 4000,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-BBB',
        'created_at': now,
      });

      await coreAppDb.db.insert('ledger_entries', {
        'id': collisionFtId,
        'customer_id': 'cust-ft-1',
        'entry_type': 'SALE',
        'amount_cents': 4000,
        'balance_after_cents': -4000,
        'reference_sale_id': 'sale-ref-BBB', // Farklı kaynak satış!
        'description': 'Borç Dekontu',
        'created_at': now,
      });

      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isFalse);
      expect(report.errorMessage, contains('FİNANSAL HAREKET KAYNAK SATIŞ ÇAKIŞMASI TESPİT EDİLDİ'));
      expect(report.errorMessage, contains('sale-ref-AAA'));
      expect(report.errorMessage, contains('sale-ref-BBB'));
    });

    // Senaryo 5: Satış tutarı aynı, ancak ürün fiyatı, miktar veya indirim farklı
    test('Senaryo 5: Satış tutarı aynı (100 TL), ancak ürün miktar ve birim fiyat dağılımı farklı olduğunda durdurulur', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const collisionSaleId = 'sale-same-total-diff-unit-price';
      final existingCust = (await legacyDb.query('customers', limit: 1)).first;
      final custId = existingCust['id'].toString();

      // Legacy DB: 100 TL -> Ürün X, 1 adet x 100 TL
      await legacyDb.insert('sales', {
        'id': collisionSaleId,
        'customer_id': custId,
        'total_amount': 100.0,
        'total_amount_minor': 10000,
        'paid_amount': 100.0,
        'payment_method': 'cash',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('sale_items', {
        'id': 'si-diff-price-1',
        'sale_id': collisionSaleId,
        'product_id': 'prod-same-id',
        'quantity': 1.0,
        'unit_price': 100.0,
        'subtotal': 100.0,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Core Next DB: AYNI Satış ID, AYNI Toplam (10000 sent) -> AMA Ürün X, 2 adet x 50 TL
      await coreAppDb.db.insert('customers', {
        'id': custId,
        'name': 'Cust Sample',
        'balance_cents': 0,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      });
      await coreAppDb.db.insert('products', {
        'id': 'prod-same-id',
        'barcode': 'prod-same-id',
        'name': 'Ürün',
        'price_cents': 5000,
        'stock_quantity': 50,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      });
      await coreAppDb.db.insert('sales', {
        'id': collisionSaleId,
        'receipt_no': 'REC-DIFF-PRICE',
        'customer_id': custId,
        'subtotal_cents': 10000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 10000,
        'paid_cents': 10000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-DIFF-PRICE',
        'created_at': now,
      });
      await coreAppDb.db.insert('sale_items', {
        'id': 'item-core-diff-price',
        'sale_id': collisionSaleId,
        'product_id': 'prod-same-id',
        'barcode': 'prod-same-id',
        'product_name': 'Ürün',
        'unit_price_cents': 5000,
        'quantity': 2.0, // 2 adet!
        'discount_cents': 0,
        'vat_rate': 0,
        'total_cents': 10000,
      });

      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isFalse);
      expect(report.errorMessage, contains('SATIŞ KALEM DETAY ÇAKIŞMASI TESPİT EDİLDİ'));
      expect(report.errorMessage, contains('prod-same-id'));
    });

    // Senaryo 6: Aynı ID ile içerik sapması varsa aktarım duruyor ve hiçbir kısmi değişiklik kalmıyor
    test('Senaryo 6: İçerik sapması anında aktarım durur ve Legacy veritabanında hiçbir kısmi değişiklik kalmaz', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const collisionSaleId = 'sale-divergence-rollback-test';

      final initialSaleCount = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      final initialItemCount = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sale_items')).first['c'] as int;
      final initialProdCount = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM products')).first['c'] as int;

      // Legacy'de satış: 80 TL
      await legacyDb.insert('sales', {
        'id': collisionSaleId,
        'customer_id': 'customer-pesin-default',
        'total_amount': 80.0,
        'total_amount_minor': 8000,
        'paid_amount': 80.0,
        'payment_method': 'cash',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Core Next'te AYNI Satış ID ama 120 TL (12000 sent)
      await coreAppDb.db.insert('sales', {
        'id': collisionSaleId,
        'receipt_no': 'REC-DIV-FAIL',
        'subtotal_cents': 12000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 12000,
        'paid_cents': 12000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-DIV-FAIL',
        'created_at': now,
      });

      // Bir de fazladan yeni satış ekleyelim; çakışma durumunda bu yeni satış da geri alınmalıdır!
      await coreAppDb.db.insert('sales', {
        'id': 'sale-should-not-be-committed',
        'receipt_no': 'REC-UNCOMMITTED',
        'subtotal_cents': 3000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 3000,
        'paid_cents': 3000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-UNCOMMITTED',
        'created_at': now,
      });

      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isFalse);

      // Kısmi değişiklik kalmadı mı doğrula:
      final afterSaleCount = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      final afterItemCount = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sale_items')).first['c'] as int;
      final afterProdCount = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM products')).first['c'] as int;
      expect(afterSaleCount, equals(initialSaleCount + 1), reason: 'Yalnızca test öncesi legacy satışı mevcut olmalı, Core Next satışları committed edilmemelidir');
      expect(afterItemCount, equals(initialItemCount), reason: 'Sale items tablosuna kalıntı yazılmamış olmalıdır');
      expect(afterProdCount, equals(initialProdCount), reason: 'Products tablosu değişmemiş olmalıdır');

      final uncommittedCheck = await legacyDb.query('sales', where: "id = 'sale-should-not-be-committed'");
      expect(uncommittedCheck.isEmpty, isTrue, reason: 'Kısmi aktarım atomik olarak geri alınmış olmalıdır');

      // Orijinal satışın tutarı (80 TL) korunmalı, 120 TL ile ezilmemelidir
      final origCheck = await legacyDb.query('sales', where: 'id = ?', whereArgs: [collisionSaleId]);
      expect((origCheck.first['total_amount'] as num).toDouble(), equals(80.0));
    });

    // Senaryo 7: Transaction ortasında hata oluşuyor; tüm tablolar birlikte geri alınıyor
    test('Senaryo 7: Transaction ortasında beklenmedik hata oluştuğunda tüm tablolar birlikte atomik geri alınır', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      final initialSales = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      final initialProducts = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM products')).first['c'] as int;

      // 1 geçerli yeni satış ekle
      await coreAppDb.db.insert('sales', {
        'id': 'sale-atomic-ok-1',
        'receipt_no': 'REC-ATOMIC-1',
        'subtotal_cents': 5000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 5000,
        'paid_cents': 5000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-ATOMIC-1',
        'created_at': now,
      });

      // Ancak stok çakışması yaratan bir durum oluştur (stok baseline hatası)
      final sampleProd = (await legacyDb.query('products', limit: 1)).first;
      final prodId = sampleProd['id'].toString();
      final initialLegacyQty = (sampleProd['quantity'] as num).toDouble();

      await coreAppDb.db.insert('products', {
        'id': prodId,
        'barcode': prodId,
        'name': 'Ürün',
        'price_cents': 5000,
        'stock_quantity': (initialLegacyQty - 1.0).round(),
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await coreAppDb.db.insert('sale_items', {
        'id': 'item-atomic-stk-1',
        'sale_id': 'sale-atomic-ok-1',
        'product_id': prodId,
        'barcode': prodId,
        'product_name': 'Ürün',
        'unit_price_cents': 5000,
        'quantity': 1.0,
        'discount_cents': 0,
        'vat_rate': 0,
        'total_cents': 5000,
      });

      // Legacy stoku dışarıdan bağımsız değiştirerek stok uzlaştırmasında hata tetikle
      await legacyDb.update('products', {'quantity': initialLegacyQty + 20.0}, where: 'id = ?', whereArgs: [prodId]);

      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isFalse);
      expect(report.errorMessage, contains('STOK ÇAKIŞMASI'));

      // Satış eklenmişti ama stok hatasında transaction rollback edildi; sales tablosunda sale-atomic-ok-1 kalmamalı!
      final checkSale = await legacyDb.query('sales', where: "id = 'sale-atomic-ok-1'");
      expect(checkSale.isEmpty, isTrue, reason: 'Transaction abort anında satış kaydı da geri alınmalıdır');

      final finalSales = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      expect(finalSales, equals(initialSales));

      final finalProducts = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM products')).first['c'] as int;
      expect(finalProducts, equals(initialProducts));
    });

    // Senaryo 8: Aynı aktarım tekrar çalıştırılıyor; kayıtlar ikinci kez uygulanmıyor (Tam İdempotency)
    test('Senaryo 8: Aynı aktarım iki kez çalıştırıldığında satış, ödeme, stok, bakiye, iade ve finansal kayıtlar mükerrer uygulanmaz', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sampleProd = (await legacyDb.query('products', limit: 1)).first;
      final prodId = sampleProd['id'].toString();
      final initialLegacyQty = (sampleProd['quantity'] as num).toDouble();
      final priceCents = 3500;

      // 1. Yeni Satış (Nakit)
      await coreAppDb.db.insert('products', {
        'id': prodId,
        'barcode': prodId,
        'name': 'Ürün',
        'price_cents': priceCents,
        'stock_quantity': (initialLegacyQty - 1.0).round(),
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await coreAppDb.db.insert('sales', {
        'id': 'sale-idem-full-1',
        'receipt_no': 'REC-IDEM-FULL-1',
        'subtotal_cents': priceCents,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': priceCents,
        'paid_cents': priceCents,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-FULL-1',
        'created_at': now,
      });

      await coreAppDb.db.insert('sale_items', {
        'id': 'item-idem-full-1',
        'sale_id': 'sale-idem-full-1',
        'product_id': prodId,
        'barcode': prodId,
        'product_name': 'Ürün',
        'unit_price_cents': priceCents,
        'quantity': 1.0,
        'discount_cents': 0,
        'vat_rate': 0,
        'total_cents': priceCents,
      });

      await coreAppDb.db.insert('sale_payments', {
        'id': 'pay-idem-full-1',
        'sale_id': 'sale-idem-full-1',
        'payment_type': 'cash',
        'amount_cents': priceCents,
        'created_at': now,
      });

      // BİRİNCİ ÇALIŞTIRMA
      final rep1 = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );
      expect(rep1.isSuccess, isTrue);
      expect(rep1.salesExported, equals(1));
      expect(rep1.productsUpdated, equals(1));

      // Stok: initialLegacyQty - 1.0 oldu
      final stockAfter1 = ((await legacyDb.query('products', where: 'id = ?', whereArgs: [prodId])).first['quantity'] as num).toDouble();
      expect(stockAfter1, closeTo(initialLegacyQty - 1.0, 0.001));

      // İKİNCİ ÇALIŞTIRMA (Aynı veritabanlarıyla tekrar çağır)
      final rep2 = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );
      expect(rep2.isSuccess, isTrue);
      expect(rep2.salesExported, equals(0), reason: 'İkinci çalıştırmada yeni satış bulunmamalıdır');
      expect(rep2.productsUpdated, equals(0), reason: 'İkinci çalıştırmada stok tekrar düşürülmemelidir');

      // Stok HÂLÂ initialLegacyQty - 1.0 olmalı (ikinci kez düşmemeli!)
      final stockAfter2 = ((await legacyDb.query('products', where: 'id = ?', whereArgs: [prodId])).first['quantity'] as num).toDouble();
      expect(stockAfter2, closeTo(initialLegacyQty - 1.0, 0.001));

      // Satış ve ödeme tablolarında tek bir kayıt olmalıdır
      final salesRows = await legacyDb.query('sales', where: "id = 'sale-idem-full-1'");
      expect(salesRows.length, equals(1));

      final itemRows = await legacyDb.query('sale_items', where: "sale_id = 'sale-idem-full-1'");
      expect(itemRows.length, equals(1));

      final payRows = await legacyDb.query('sale_payments', where: "sale_id = 'sale-idem-full-1'");
      expect(payRows.length, equals(1));
    });
  });
}
