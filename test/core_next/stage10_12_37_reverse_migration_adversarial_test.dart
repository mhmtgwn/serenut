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

  group('STAGE 10.12.37 — BÖLÜM 1: GÜVENLİK KAPISI VE DEĞİŞMEZLİK', () {
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

  group('STAGE 10.12.37 — BÖLÜM 2: DELTA MATEMATİĞİ VE KARŞIT (ADVERSARIAL) SENARYOLAR', () {
    late Directory tempDir;
    late String legacyPath;
    late String corePath;
    late Database legacyDb;
    late CoreAppDatabase coreAppDb;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('stage37_adv_');
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

    test('2.1 (Senaryo 3 - Net Delta): Aynı ürün için birden fazla satış ve iade net delta olarak doğru toplanır', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sampleProd = (await legacyDb.query('products', limit: 1)).first;
      final prodId = sampleProd['id'].toString();
      final initialLegacyQty = (sampleProd['quantity'] as num).toDouble();
      final priceCents = 1000;

      // Core Next'e ürünü ekle: 3 adet satıldı, 1 adet iade edildi -> Net Delta = -2.0
      await coreAppDb.db.insert('products', {
        'id': prodId,
        'barcode': sampleProd['sku']?.toString() ?? prodId,
        'name': sampleProd['name']?.toString() ?? 'Ürün',
        'price_cents': priceCents,
        'stock_quantity': (initialLegacyQty - 2.0).round(),
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Satış 1: 1 adet
      await coreAppDb.db.insert('sales', {
        'id': 'sale-multi-1',
        'receipt_no': 'REC-M-1',
        'subtotal_cents': priceCents,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': priceCents,
        'paid_cents': priceCents,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-M-1',
        'created_at': now,
      });
      await coreAppDb.db.insert('sale_items', {
        'id': 'item-m-1',
        'sale_id': 'sale-multi-1',
        'product_id': prodId,
        'barcode': prodId,
        'product_name': 'Ürün',
        'unit_price_cents': priceCents,
        'quantity': 1.0,
        'discount_cents': 0,
        'vat_rate': 0,
        'total_cents': priceCents,
      });

      // Satış 2: 2 adet
      await coreAppDb.db.insert('sales', {
        'id': 'sale-multi-2',
        'receipt_no': 'REC-M-2',
        'subtotal_cents': priceCents * 2,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': priceCents * 2,
        'paid_cents': priceCents * 2,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-M-2',
        'created_at': now + 1,
      });
      await coreAppDb.db.insert('sale_items', {
        'id': 'item-m-2',
        'sale_id': 'sale-multi-2',
        'product_id': prodId,
        'barcode': prodId,
        'product_name': 'Ürün',
        'unit_price_cents': priceCents,
        'quantity': 2.0,
        'discount_cents': 0,
        'vat_rate': 0,
        'total_cents': priceCents * 2,
      });

      // İade 1: 1 adet geri (REFUND status)
      await coreAppDb.db.insert('sales', {
        'id': 'refund-multi-1',
        'receipt_no': 'REF-REC-M-1',
        'subtotal_cents': -priceCents,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': -priceCents,
        'paid_cents': -priceCents,
        'debt_cents': 0,
        'status': 'REFUND',
        'idempotency_key': 'IDEM-REF-1',
        'created_at': now + 2,
      });
      await coreAppDb.db.insert('sale_items', {
        'id': 'item-ref-1',
        'sale_id': 'refund-multi-1',
        'product_id': prodId,
        'barcode': prodId,
        'product_name': 'Ürün',
        'unit_price_cents': priceCents,
        'quantity': 1.0,
        'discount_cents': 0,
        'vat_rate': 0,
        'total_cents': -priceCents,
      });

      // Ters taşıma çalıştır
      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isTrue);
      expect(report.salesExported, equals(3));
      expect(report.productsUpdated, equals(1));

      // Net stok kontrolü: Başlangıç - 2
      final updatedLegacy = await legacyDb.query('products', where: 'id = ?', whereArgs: [prodId]);
      final finalQty = (updatedLegacy.first['quantity'] as num).toDouble();
      expect(finalQty, closeTo(initialLegacyQty - 2.0, 0.001));
    });

    test('2.2 (Senaryo 5 - İçerik Çakışması): Aynı Satış ID iki tarafta farklı tutarla varsa sessizce atlanamaz, durdurulur', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const collisionSaleId = 'sale-collision-divergence-1';
      final existingCust = (await legacyDb.query('customers', limit: 1)).first;
      final existingCustId = existingCust['id'].toString();

      // Legacy DB'ye satış yaz: 100.00 TL (10000 sent)
      await legacyDb.insert('sales', {
        'id': collisionSaleId,
        'customer_id': existingCustId,
        'total_amount': 100.0,
        'total_amount_minor': 10000,
        'paid_amount': 100.0,
        'paid_amount_minor': 10000,
        'payment_method': 'cash',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Core Next DB'ye AYNI ID ile ama FARKLI tutarla (150.00 TL / 15000 sent) yaz
      await coreAppDb.db.insert('sales', {
        'id': collisionSaleId,
        'receipt_no': 'REC-DIV-1',
        'subtotal_cents': 15000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 15000,
        'paid_cents': 15000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-DIV-1',
        'created_at': now,
      });

      // Ters taşıma bu içerik sapmasını algılamalı ve fail-closed durdurmalıdır!
      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isFalse);
      expect(report.errorMessage, contains('SATIŞ İÇERİK ÇAKIŞMASI TESPİT EDİLDİ'));
      expect(report.errorMessage, contains(collisionSaleId));

      // Legacy DB'deki orijinal tutar (100.00 TL) asla ezilmemiştir
      final legCheck = await legacyDb.query('sales', where: 'id = ?', whereArgs: [collisionSaleId]);
      expect(legCheck.first['total_amount'], equals(100.0));
      expect(legCheck.first['total_amount_minor'], equals(10000));
    });

    test('2.3 (Senaryo 6 & 9 - Atomik Rollback): Hata anında (Transaction Abort) hiçbir ara tablo kısmi kayıt barındırmaz', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1 geçerli satış
      await coreAppDb.db.insert('sales', {
        'id': 'sale-valid-half-1',
        'receipt_no': 'REC-VH-1',
        'subtotal_cents': 5000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 5000,
        'paid_cents': 5000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-VH-1',
        'created_at': now,
      });

      // Gerçek legacy ürününü alıp bağımsız stok değişikliği simüle et
      final existingProd = (await legacyDb.query('products', limit: 1)).first;
      final fakeProdId = existingProd['id'].toString();
      final initialLegacyQty = (existingProd['quantity'] as num).toDouble();

      // Legacy stok bağımsız 98 oldu diyelim
      await legacyDb.update(
        'products',
        {'quantity': initialLegacyQty - 2.0},
        where: 'id = ?',
        whereArgs: [fakeProdId],
      );

      await coreAppDb.db.insert('products', {
        'id': fakeProdId,
        'barcode': existingProd['sku']?.toString() ?? fakeProdId,
        'name': existingProd['name']?.toString() ?? 'Ürün',
        'price_cents': 5000,
        'stock_quantity': (initialLegacyQty - 5.0).round(), // Core Next 5 satmış, beklenen baseline initial, ama legacy -2!
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      });

      await coreAppDb.db.insert('sale_items', {
        'id': 'item-abort-1',
        'sale_id': 'sale-valid-half-1',
        'product_id': fakeProdId,
        'barcode': fakeProdId,
        'product_name': 'Ürün',
        'unit_price_cents': 1000,
        'quantity': 5.0,
        'discount_cents': 0,
        'vat_rate': 0,
        'total_cents': 5000,
      });

      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isFalse);
      expect(report.errorMessage, contains('STOK ÇAKIŞMASI TESPİT EDİLDİ'));

      // Atomik Transaction Kanıtı: Satış başlığı legacy'ye YAZILMAMIŞ olmalıdır (Rollback oldu!)
      final checkSale = await legacyDb.query('sales', where: 'id = ?', whereArgs: ['sale-valid-half-1']);
      expect(checkSale, isEmpty, reason: 'Transaction abort edildiğinde satış silinmeli/yazılmamalıdır');

      // Ürün stoku (initial - 2.0) olarak el değmeden kalmalıdır
      final checkProd = await legacyDb.query('products', where: 'id = ?', whereArgs: [fakeProdId]);
      expect((checkProd.first['quantity'] as num).toDouble(), closeTo(initialLegacyQty - 2.0, 0.001));
    });

    test('2.4 (Senaryo 10 - Kuruş Hassasiyeti): balance_minor integer sütunu kuruşu kuruşuna güncellenir', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const custId = 'cust-cents-precision-1';

      // Legacy müşterisi: -150.75 TL (-15075 sent)
      await legacyDb.insert('customers', {
        'id': custId,
        'name': 'Kuruş Test Müşterisi',
        'balance': -150.75,
        'balance_minor': -15075,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Core Next'te 49.25 TL (4925 sent) vadeli satış yapıldı -> Yeni Bakiye: -200.00 TL (-20000 sent)
      await coreAppDb.db.insert('customers', {
        'id': custId,
        'name': 'Kuruş Test Müşterisi',
        'balance_cents': -20000,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      });

      await coreAppDb.db.insert('ledger_entries', {
        'id': 'ledger-cents-1',
        'customer_id': custId,
        'entry_type': 'DEBT',
        'amount_cents': 4925,
        'balance_after_cents': -20000,
        'description': 'Vadeli Satış',
        'created_at': now,
      });

      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isTrue);
      expect(report.customersUpdated, equals(1));

      // Legacy DB kontrolü: hem balance (-200.0) hem balance_minor (-20000) tam eşleşmelidir
      final custRows = await legacyDb.query('customers', where: 'id = ?', whereArgs: [custId]);
      expect((custRows.first['balance'] as num).toDouble(), equals(-200.0));
      expect((custRows.first['balance_minor'] as num).toInt(), equals(-20000));
    });
  });
}
