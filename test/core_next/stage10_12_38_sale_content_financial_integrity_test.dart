// ignore_for_file: avoid_relative_lib_imports, prefer_const_declarations

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

  group('STAGE 10.12.38 — BÖLÜM 1: GÜVENLİK KAPISI VE DEĞİŞMEZLİK', () {
    test('1.1: Satış motoru ve routing hook varsayılan olarak kesinlikle kapalıdır', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final salesEngine = container.read(coreNextSalesEngineEnabledProvider);
      expect(salesEngine, isFalse, reason: 'coreNextSalesEngineEnabledProvider = false kalmalıdır');
      expect(DatabaseManager.databaseRoutingHook, isNull, reason: 'databaseRoutingHook = null kalmalıdır');
    });

    test('1.2: Kaynak arşiv fixture dosyası mevcuttur ve okunabilir durumdadır', () async {
      final file = File(rawNutopiaPath);
      expect(await file.exists(), isTrue, reason: 'Nutopia ham arşiv dosyası diskte olmalıdır');
    });
  });

  group('STAGE 10.12.38 — BÖLÜM 2: SATIŞ İÇERİĞİ VE DERİN ÇOK BOYUTLU ÇAKIŞMA TESTLERİ', () {
    late Directory tempDir;
    late String legacyPath;
    late String corePath;
    late Database legacyDb;
    late CoreAppDatabase coreAppDb;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('stage38_integrity_');
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

    test('2.1 (Aynı Satış ID, Aynı Tutar, FARKLI Kalemler): Satış toplamı eşit olsa dahi farklı ürünler çakışma olarak yakalanır', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const collisionSaleId = 'sale-same-total-diff-items';
      final existingCust = (await legacyDb.query('customers', limit: 1)).first;
      final custId = existingCust['id'].toString();

      // Legacy DB: Satış 100 TL (10000 sent) -> Kalem: Ürün X, 1 adet, 100 TL
      await legacyDb.insert('sales', {
        'id': collisionSaleId,
        'customer_id': custId,
        'total_amount': 100.0,
        'total_amount_minor': 10000,
        'paid_amount': 100.0,
        'paid_amount_minor': 10000,
        'payment_method': 'cash',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('sale_items', {
        'id': 'item-leg-diff-1',
        'sale_id': collisionSaleId,
        'product_id': 'prod-leg-X',
        'quantity': 1.0,
        'unit_price': 100.0,
        'subtotal': 100.0,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Core Next DB: AYNI Satış ID, AYNI Toplam (10000 sent) -> AMA Kalem: Ürün Y, 2 adet, 50 TL
      await coreAppDb.db.insert('customers', {
        'id': custId,
        'name': 'Sample Cust',
        'balance_cents': 0,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      });

      await coreAppDb.db.insert('sales', {
        'id': collisionSaleId,
        'receipt_no': 'REC-DIFF-ITEMS',
        'customer_id': custId,
        'subtotal_cents': 10000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 10000,
        'paid_cents': 10000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-DIFF-ITEMS',
        'created_at': now,
      });

      await coreAppDb.db.insert('products', {
        'id': 'prod-core-Y',
        'barcode': 'prod-core-Y',
        'name': 'Ürün Y',
        'price_cents': 5000,
        'stock_quantity': 100,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      });

      await coreAppDb.db.insert('sale_items', {
        'id': 'item-core-diff-1',
        'sale_id': collisionSaleId,
        'product_id': 'prod-core-Y',
        'barcode': 'prod-core-Y',
        'product_name': 'Ürün Y',
        'unit_price_cents': 5000,
        'quantity': 2.0,
        'discount_cents': 0,
        'vat_rate': 0,
        'total_cents': 10000,
      });

      // Ters taşıma: Toplam aynı olmasına rağmen kalem içerik farkını tespit etmeli ve durdurmalıdır!
      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isFalse);
      expect(report.errorMessage, contains('SATIŞ KALEM DETAY ÇAKIŞMASI TESPİT EDİLDİ'));
      expect(report.errorMessage, contains('prod-core-Y'));
    });

    test('2.2 (Aynı Satış ID, Aynı Tutar, FARKLI Ödeme Dağılımı): Nakit vs Kart/Karma ödeme sapması çakışma olarak durdurulur', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const collisionSaleId = 'sale-same-total-diff-payments';
      final existingCust = (await legacyDb.query('customers', limit: 1)).first;
      final custId = existingCust['id'].toString();

      // Legacy DB: Satış 100 TL -> Ödeme: 100 TL Nakit
      await legacyDb.insert('sales', {
        'id': collisionSaleId,
        'customer_id': custId,
        'total_amount': 100.0,
        'total_amount_minor': 10000,
        'paid_amount': 100.0,
        'paid_amount_minor': 10000,
        'payment_method': 'cash',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.execute('''
        CREATE TABLE IF NOT EXISTS sale_payments (
          id TEXT PRIMARY KEY NOT NULL,
          sale_id TEXT NOT NULL,
          payment_type TEXT NOT NULL,
          amount REAL NOT NULL,
          amount_minor INTEGER NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await legacyDb.insert('sale_payments', {
        'id': 'pay-leg-cash',
        'sale_id': collisionSaleId,
        'payment_type': 'cash',
        'amount': 100.0,
        'amount_minor': 10000,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Core Next DB: AYNI Satış ID, AYNI Toplam (10000 sent) -> AMA Ödeme: 100 TL Kredi Kartı
      await coreAppDb.db.insert('customers', {
        'id': custId,
        'name': 'Sample Cust',
        'balance_cents': 0,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      });

      await coreAppDb.db.insert('sales', {
        'id': collisionSaleId,
        'receipt_no': 'REC-DIFF-PAY',
        'customer_id': custId,
        'subtotal_cents': 10000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 10000,
        'paid_cents': 10000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-DIFF-PAY',
        'created_at': now,
      });
      await coreAppDb.db.insert('sale_payments', {
        'id': 'pay-core-card',
        'sale_id': collisionSaleId,
        'payment_type': 'card',
        'amount_cents': 10000,
        'created_at': now,
      });

      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isFalse);
      expect(report.errorMessage, contains('SATIŞ ÖDEME DAĞILIM ÇAKIŞMASI TESPİT EDİLDİ'));
      expect(report.errorMessage, contains('card'));
    });

    test('2.3 (Aynı Satış ID, FARKLI Müşteri): Satışın farklı cariye atanmış olması çakışma olarak durdurulur', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const collisionSaleId = 'sale-same-total-diff-cust';

      // 2 farklı müşteri
      await legacyDb.insert('customers', {
        'id': 'cust-alpha-1',
        'name': 'Müşteri Alpha',
        'balance': 0.0,
        'balance_minor': 0,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('customers', {
        'id': 'cust-beta-2',
        'name': 'Müşteri Beta',
        'balance': 0.0,
        'balance_minor': 0,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      await coreAppDb.db.insert('customers', {
        'id': 'cust-alpha-1',
        'name': 'Müşteri Alpha',
        'balance_cents': 0,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      });
      await coreAppDb.db.insert('customers', {
        'id': 'cust-beta-2',
        'name': 'Müşteri Beta',
        'balance_cents': 0,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      });

      // Legacy: cust-alpha-1
      await legacyDb.insert('sales', {
        'id': collisionSaleId,
        'customer_id': 'cust-alpha-1',
        'total_amount': 75.0,
        'total_amount_minor': 7500,
        'paid_amount': 75.0,
        'paid_amount_minor': 7500,
        'payment_method': 'cash',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Core Next: AYNI satış, AYNI 7500 sent, AMA cust-beta-2
      await coreAppDb.db.insert('sales', {
        'id': collisionSaleId,
        'receipt_no': 'REC-DIFF-CUST',
        'customer_id': 'cust-beta-2',
        'subtotal_cents': 7500,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 7500,
        'paid_cents': 7500,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-DIFF-CUST',
        'created_at': now,
      });

      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isFalse);
      expect(report.errorMessage, contains('SATIŞ MÜŞTERİ ÇAKIŞMASI TESPİT EDİLDİ'));
      expect(report.errorMessage, contains('cust-alpha-1'));
      expect(report.errorMessage, contains('cust-beta-2'));
    });

    test('2.4 (Aynı Finansal İşlem ID, FARKLI İşlem Türü veya Müşteri): Defter sapması fail-closed durdurulur', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const collisionFtId = 'ft-collision-type-1';

      // Legacy DB: PAYMENT türünde 50 TL tahsilat
      await legacyDb.insert('customers', {
        'id': 'cust-sample',
        'name': 'Sample Cust',
        'balance': 0.0,
        'balance_minor': 0,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      await legacyDb.insert('financial_transactions', {
        'id': collisionFtId,
        'customer_id': 'cust-sample',
        'type': 'PAYMENT',
        'amount': 50.0,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Core Next DB: AYNI ID ile DEBT (borç) türünde hareket
      await coreAppDb.db.insert('customers', {
        'id': 'cust-sample',
        'name': 'Sample Cust',
        'balance_cents': 0,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      });

      await coreAppDb.db.insert('ledger_entries', {
        'id': collisionFtId,
        'customer_id': 'cust-sample',
        'entry_type': 'DEBT',
        'amount_cents': 5000,
        'balance_after_cents': -5000,
        'description': 'Borç Dekontu',
        'created_at': now,
      });

      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isFalse);
      expect(report.errorMessage, contains('FİNANSAL HAREKET TÜR ÇAKIŞMASI TESPİT EDİLDİ'));
      expect(report.errorMessage, contains(collisionFtId));
    });

    test('2.5 (Aynı İade ID, FARKLI Tutar): İade tutarı uyuşmazlığı tespit edilir ve durdurulur', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const collisionRefundId = 'ref-collision-amt-1';

      // Legacy DB: 20 TL iade
      await legacyDb.insert('refunds', {
        'id': collisionRefundId,
        'sale_id': 'sale-orig-1',
        'amount': 20.0,
        'refund_method': 'cash',
        'reason': 'Test İadesi',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
      });

      // Core Next DB: AYNI iade ID ama -30 TL (-3000 sent)
      await coreAppDb.db.insert('sales', {
        'id': collisionRefundId,
        'receipt_no': 'REF-REC-1',
        'subtotal_cents': -3000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': -3000,
        'paid_cents': -3000,
        'debt_cents': 0,
        'status': 'REFUND',
        'idempotency_key': 'IDEM-REF-COLL',
        'created_at': now,
      });

      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isFalse);
      expect(report.errorMessage, contains('İADE TUTAR ÇAKIŞMASI TESPİT EDİLDİ'));
      expect(report.errorMessage, contains(collisionRefundId));
    });

    test('2.6 (Kusursuz İdempotency): Bütün alanları birebir eşleşen satış tekrarında tek bir mükerrer satır oluşmaz', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const safeIdemSaleId = 'sale-safe-idempotent-match';
      final sampleProd = (await legacyDb.query('products', limit: 1)).first;
      final prodId = sampleProd['id'].toString();
      final initialLegacyQty = (sampleProd['quantity'] as num).toDouble();
      final priceCents = 2500;

      // Core Next: 1 adet satış
      await coreAppDb.db.insert('products', {
        'id': prodId,
        'barcode': sampleProd['sku']?.toString() ?? prodId,
        'name': sampleProd['name']?.toString() ?? 'Ürün',
        'price_cents': priceCents,
        'stock_quantity': (initialLegacyQty - 1.0).round(),
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await coreAppDb.db.insert('sales', {
        'id': safeIdemSaleId,
        'receipt_no': 'REC-IDEM-SAFE',
        'subtotal_cents': priceCents,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': priceCents,
        'paid_cents': priceCents,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-SAFE-1',
        'created_at': now,
      });

      await coreAppDb.db.insert('sale_items', {
        'id': 'item-safe-idem-1',
        'sale_id': safeIdemSaleId,
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
        'id': 'pay-safe-idem-1',
        'sale_id': safeIdemSaleId,
        'payment_type': 'cash',
        'amount_cents': priceCents,
        'created_at': now,
      });

      // 1. Çalıştırma -> Aktarılmalı
      final rep1 = await ReverseMigrationEngine.rollbackToLegacy(legacyDb: legacyDb, coreDb: coreAppDb);
      expect(rep1.isSuccess, isTrue);
      expect(rep1.salesExported, equals(1));
      expect(rep1.productsUpdated, equals(1));

      // 2. Çalıştırma -> Bütün alanlar (tutar, kalem, ödeme) birebir eşleştiği için güvenle atlanmalı
      final rep2 = await ReverseMigrationEngine.rollbackToLegacy(legacyDb: legacyDb, coreDb: coreAppDb);
      expect(rep2.isSuccess, isTrue);
      expect(rep2.salesExported, equals(0));
      expect(rep2.productsUpdated, equals(0));

      // Satış ve kalem sayısı tam 1 olarak kalmalı
      final salesCheck = await legacyDb.query('sales', where: 'id = ?', whereArgs: [safeIdemSaleId]);
      expect(salesCheck.length, equals(1));
      final itemsCheck = await legacyDb.query('sale_items', where: 'sale_id = ?', whereArgs: [safeIdemSaleId]);
      expect(itemsCheck.length, equals(1));
      final payCheck = await legacyDb.query('sale_payments', where: 'sale_id = ?', whereArgs: [safeIdemSaleId]);
      expect(payCheck.length, equals(1));

      // Stok tekrar düşürülmemiş olmalı
      final prodCheck = await legacyDb.query('products', where: 'id = ?', whereArgs: [prodId]);
      expect((prodCheck.first['quantity'] as num).toDouble(), closeTo(initialLegacyQty - 1.0, 0.001));
    });
  });
}
