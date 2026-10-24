// test/core_next/stage10_12_36_conflict_safe_reconciliation_test.dart
// SERENUT OS — STAGE 10.12.36
// REVERSE MIGRATION ÇAKIŞMA GÜVENLİĞİ, FİNANSAL MUTABAKAT VE VERİ KORUMA TESTLERİ
//
// GÜVENLİK KURALI:
// 1. Canlı hiçbir veritabanına (serenut_pos.db, serenut_core_v2.db) dokunulmaz.
// 2. Yalnızca izole, geçici disposable test kopyaları kullanılır.
// 3. `coreNextSalesEngineEnabledProvider` kesinlikle `false` tutulur.

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
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const rawNutopiaPath = 'backups/raw_tenants_20261016/raw_nutopia_v60.db';

  group('STAGE 10.12.36 — BÖLÜM 1: GÜVENLİK KAPISI VE DEĞİŞMEZLİK', () {
    test('1.1: Satış motoru ve routing hook varsayılan olarak kapalıdır', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final salesEngine = container.read(coreNextSalesEngineEnabledProvider);
      expect(salesEngine, isFalse, reason: 'coreNextSalesEngineEnabledProvider = false olmalıdır');
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });

    test('1.2: Kaynak arşiv fixture dosyası mevcuttur', () async {
      final file = File(rawNutopiaPath);
      expect(await file.exists(), isTrue, reason: 'Nutopia ham arşivi mevcut olmalıdır');
    });
  });

  group('STAGE 10.12.36 — BÖLÜM 2: STOK VE BAKİYE ÇAKIŞMASI DENETİMİ (EN KRİTİK SENARYOLAR)', () {
    late Directory tempDir;
    late String isolatedLegacyPath;
    late String isolatedTargetPath;
    late CoreAppDatabase coreAppDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage36_conflict_');
      isolatedLegacyPath = p.join(tempDir.path, 'legacy_serenut_pos.db');
      isolatedTargetPath = p.join(tempDir.path, 'core_serenut_v2.db');

      // Orijinal Nutopia arşivini izole geçici klasöre kopyala
      final srcBytes = await File(rawNutopiaPath).readAsBytes();
      await File(isolatedLegacyPath).writeAsBytes(srcBytes);

      coreAppDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      await coreAppDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia',
        'updated_at': 1,
      });
    });

    tearDown(() async {
      await coreAppDb.close();
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('2.1 (En Kritik Stok Çakışması): Legacy stok bağımsız değişmişse (100 -> 98), 5 adet satan Core Next (95) körlemesine üzerine yazamaz, durdurulur', () async {
      final legacyDb = await openDatabase(isolatedLegacyPath);
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Legacy DB'de ürünün başlangıç stoku: 100
      final sampleProd = (await legacyDb.query('products', where: 'quantity > 10', limit: 1)).first;
      final prodId = sampleProd['id'].toString();
      await legacyDb.update('products', {'quantity': 100.0}, where: 'id = ?', whereArgs: [prodId]);

      // 2. Core Next'te aynı ürün 100'den başladı ve 5 adet satıldı -> Core Next güncel stok: 95
      final prodPrice = (sampleProd['price'] as num).toDouble();
      final prodPriceCents = (prodPrice * 100).round();

      await coreAppDb.db.insert('products', {
        'id': prodId,
        'barcode': sampleProd['sku']?.toString() ?? prodId,
        'name': sampleProd['name']?.toString() ?? 'Ürün',
        'price_cents': prodPriceCents,
        'stock_quantity': 95, // 100 - 5 = 95
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await coreAppDb.db.insert('sales', {
        'id': 'sale-conflict-stock-1',
        'receipt_no': 'REC-CONF-STK-1',
        'customer_id': null,
        'subtotal_cents': prodPriceCents * 5,
        'discount_cents': 0,
        'vat_total_cents': (prodPriceCents * 5 * 0.1).round(),
        'total_cents': prodPriceCents * 5,
        'paid_cents': prodPriceCents * 5,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-CONF-STK-1',
        'created_at': now,
      });

      await coreAppDb.db.insert('sale_items', {
        'id': 'item-conf-stk-1',
        'sale_id': 'sale-conflict-stock-1',
        'product_id': prodId,
        'barcode': sampleProd['sku']?.toString() ?? prodId,
        'product_name': sampleProd['name']?.toString() ?? 'Ürün',
        'unit_price_cents': prodPriceCents,
        'quantity': 5.0, // 5 adet satıldı
        'discount_cents': 0,
        'vat_rate': 10,
        'total_cents': prodPriceCents * 5,
      });

      await coreAppDb.db.insert('sale_payments', {
        'id': 'pay-conf-stk-1',
        'sale_id': 'sale-conflict-stock-1',
        'payment_type': 'cash',
        'amount_cents': prodPriceCents * 5,
        'created_at': now,
      });

      // 3. KRİTİK ÇAKIŞMA DURUMU: Legacy DB'de, Core Next satışından bağımsız bir değişiklik meydana gelmiş gibi stok 98 yapıldı!
      await legacyDb.update('products', {'quantity': 98.0}, where: 'id = ?', whereArgs: [prodId]);

      // 4. Ters uzlaştırma işletimi
      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      // BEKLENEN DAVRANIŞ:
      // Sistem 95 veya 98 değerini körlemesine yazmamalı!
      // Çakışmayı tespit etmeli ve işlemi güvenli biçimde DURDURMALIDIR.
      expect(report.isSuccess, isFalse, reason: 'Bağımsız stok farkında otomatik aktarım durdurulmalıdır');
      expect(report.errorMessage, contains('STOK ÇAKIŞMASI TESPİT EDİLDİ'));
      expect(report.errorMessage, contains(prodId));

      // DOĞRULAMA: Legacy DB'deki 98 değeri ASLA ezilmemeli, ilk haliyle korunmalıdır!
      final checkProd = await legacyDb.query('products', where: 'id = ?', whereArgs: [prodId]);
      expect((checkProd.first['quantity'] as num).toDouble(), equals(98.0), reason: 'Legacy stok 98 olarak korunmalı, 95 ile ezilmemelidir');

      // Satış da aktarılmamalı (Atomik Rollback)
      final checkSale = await legacyDb.query('sales', where: "id = 'sale-conflict-stock-1'");
      expect(checkSale.isEmpty, isTrue, reason: 'Çakışma anında hiçbir satış aktarılmamalıdır');

      await legacyDb.close();
    });

    test('2.2 (En Kritik Müşteri Bakiye Çakışması): Legacy carisine bağımsız tahsilat girilmişse (-500 -> -400), vadeli Core Next satışı (-750) bakiye farkını ezemez', () async {
      final legacyDb = await openDatabase(isolatedLegacyPath);
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Legacy DB'de müşteri bakiyesi: -500 TL (500 TL borç)
      await legacyDb.insert('customers', {
        'id': 'cust-conf-1',
        'name': 'Ali Vural',
        'balance': -500.0,
        'is_active': 1,
        'is_deleted': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // 2. Core Next'te müşteriye 250 TL veresiye satış yapıldı (-500 -> -750 TL oldu)
      await coreAppDb.db.insert('customers', {
        'id': 'cust-conf-1',
        'name': 'Ali Vural',
        'balance_cents': -75000, // -750.00 TL
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await coreAppDb.db.insert('sales', {
        'id': 'sale-conflict-bal-1',
        'receipt_no': 'REC-CONF-BAL-1',
        'customer_id': 'cust-conf-1',
        'subtotal_cents': 25000,
        'discount_cents': 0,
        'vat_total_cents': 2500,
        'total_cents': 25000,
        'paid_cents': 0,
        'debt_cents': 25000, // 250 TL veresiye
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-CONF-BAL-1',
        'created_at': now,
      });

      await coreAppDb.db.insert('ledger_entries', {
        'id': 'le-conf-bal-1',
        'customer_id': 'cust-conf-1',
        'reference_sale_id': 'sale-conflict-bal-1',
        'entry_type': 'SALE',
        'amount_cents': 25000,
        'balance_after_cents': -75000,
        'description': 'Veresiye Satış Borcu',
        'created_at': now,
      });

      // 3. KRİTİK ÇAKIŞMA DURUMU: Legacy DB'de Core Next'ten bağımsız 100 TL tahsilat girildi -> Bakiye -400 TL oldu!
      await legacyDb.update('customers', {'balance': -400.0}, where: "id = 'cust-conf-1'");

      // 4. Ters uzlaştırma işletimi
      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      // BEKLENEN DAVRANIŞ:
      expect(report.isSuccess, isFalse, reason: 'Bağımsız cari bakiye farkında aktarım durdurulmalıdır');
      expect(report.errorMessage, contains('MÜŞTERİ BAKİYE ÇAKIŞMASI TESPİT EDİLDİ'));
      expect(report.errorMessage, contains('cust-conf-1'));

      // DOĞRULAMA: Legacy DB'deki -400 TL tahsilatlı bakiye ASLA -750 TL ile ezilmemelidir!
      final checkCust = await legacyDb.query('customers', where: "id = 'cust-conf-1'");
      expect((checkCust.first['balance'] as num).toDouble(), equals(-400.0), reason: 'Legacy bakiye -400.0 TL olarak korunmalıdır');

      await legacyDb.close();
    });

    test('2.3 (Çakışma Olmayan Normal Akış): Legacy DB değişmemişse Core Next satış etkisi (100 -> 95) kayıpsız uygulanır', () async {
      final legacyDb = await openDatabase(isolatedLegacyPath);
      final now = DateTime.now().millisecondsSinceEpoch;

      final sampleProd = (await legacyDb.query('products', where: 'quantity > 10', limit: 1)).first;
      final prodId = sampleProd['id'].toString();
      await legacyDb.update('products', {'quantity': 100.0}, where: 'id = ?', whereArgs: [prodId]);

      final prodPrice = (sampleProd['price'] as num).toDouble();
      final prodPriceCents = (prodPrice * 100).round();

      await coreAppDb.db.insert('products', {
        'id': prodId,
        'barcode': sampleProd['sku']?.toString() ?? prodId,
        'name': sampleProd['name']?.toString() ?? 'Ürün',
        'price_cents': prodPriceCents,
        'stock_quantity': 95, // 100 - 5 = 95
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await coreAppDb.db.insert('sales', {
        'id': 'sale-safe-stk-1',
        'receipt_no': 'REC-SAFE-STK-1',
        'customer_id': null,
        'subtotal_cents': prodPriceCents * 5,
        'discount_cents': 0,
        'vat_total_cents': (prodPriceCents * 5 * 0.1).round(),
        'total_cents': prodPriceCents * 5,
        'paid_cents': prodPriceCents * 5,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-SAFE-STK-1',
        'created_at': now,
      });

      await coreAppDb.db.insert('sale_items', {
        'id': 'item-safe-stk-1',
        'sale_id': 'sale-safe-stk-1',
        'product_id': prodId,
        'barcode': sampleProd['sku']?.toString() ?? prodId,
        'product_name': sampleProd['name']?.toString() ?? 'Ürün',
        'unit_price_cents': prodPriceCents,
        'quantity': 5.0,
        'discount_cents': 0,
        'vat_rate': 10,
        'total_cents': prodPriceCents * 5,
      });

      await coreAppDb.db.insert('sale_payments', {
        'id': 'pay-safe-stk-1',
        'sale_id': 'sale-safe-stk-1',
        'payment_type': 'cash',
        'amount_cents': prodPriceCents * 5,
        'created_at': now,
      });

      // Legacy DB dokunulmadı (hâlâ 100)
      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isTrue);
      expect(report.productsUpdated, equals(1));

      // Stok 100 -> 95 oldu mu?
      final checkProd = await legacyDb.query('products', where: 'id = ?', whereArgs: [prodId]);
      expect((checkProd.first['quantity'] as num).toDouble(), equals(95.0));

      await legacyDb.close();
    });

    test('2.4 (Dokunulmamış Ürün Koruması): Core Next satışında yer almayan legacy ürünlerin stoku asla değiştirilmez', () async {
      final legacyDb = await openDatabase(isolatedLegacyPath);

      // Core Next'te hiç satılmamış iki ürün seç
      final otherProds = await legacyDb.query('products', limit: 2);
      final initialStocks = {for (final p in otherProds) p['id'].toString(): (p['quantity'] as num).toDouble()};

      // Ters uzlaştırma işlet (başka bir satış olsun veya olmasın)
      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isTrue);

      // Bu ürünlerin stokları birebir aynı kalmalıdır
      for (final pid in initialStocks.keys) {
        final row = (await legacyDb.query('products', where: 'id = ?', whereArgs: [pid])).first;
        expect((row['quantity'] as num).toDouble(), equals(initialStocks[pid]), reason: 'Dokunulmamış ürün stoku değişmemelidir');
      }

      await legacyDb.close();
    });
  });

  group('STAGE 10.12.36 — BÖLÜM 3: İLİŞKİSEL BÜTÜNLÜK VE İDEMPOTENCY', () {
    late Directory tempDir;
    late String isolatedLegacyPath;
    late String isolatedTargetPath;
    late CoreAppDatabase coreAppDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage36_integrity_');
      isolatedLegacyPath = p.join(tempDir.path, 'legacy_serenut_pos.db');
      isolatedTargetPath = p.join(tempDir.path, 'core_serenut_v2.db');

      final srcBytes = await File(rawNutopiaPath).readAsBytes();
      await File(isolatedLegacyPath).writeAsBytes(srcBytes);

      coreAppDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      await coreAppDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia',
        'updated_at': 1,
      });
    });

    tearDown(() async {
      await coreAppDb.close();
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('3.1 (İdempotency): Başarılı ters uzlaştırma ikinci kez çalıştırıldığında hiçbir tabloda mükerrer satır oluşmaz', () async {
      final legacyDb = await openDatabase(isolatedLegacyPath);
      final now = DateTime.now().millisecondsSinceEpoch;

      final sampleProd = (await legacyDb.query('products', where: 'quantity > 10', limit: 1)).first;
      final prodId = sampleProd['id'].toString();
      final initialLegacyQty = (sampleProd['quantity'] as num).toDouble();
      final prodPrice = (sampleProd['price'] as num).toDouble();
      final prodPriceCents = (prodPrice * 100).round();

      await coreAppDb.db.insert('products', {
        'id': prodId,
        'barcode': sampleProd['sku']?.toString() ?? prodId,
        'name': sampleProd['name']?.toString() ?? 'Ürün',
        'price_cents': prodPriceCents,
        'stock_quantity': (initialLegacyQty - 1.0).round(),
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await coreAppDb.db.insert('sales', {
        'id': 'sale-idem-stk-1',
        'receipt_no': 'REC-IDEM-STK-1',
        'customer_id': null,
        'subtotal_cents': prodPriceCents,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': prodPriceCents,
        'paid_cents': prodPriceCents,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-KEY-STK-1',
        'created_at': now,
      });

      await coreAppDb.db.insert('sale_items', {
        'id': 'item-idem-stk-1',
        'sale_id': 'sale-idem-stk-1',
        'product_id': prodId,
        'barcode': sampleProd['sku']?.toString() ?? prodId,
        'product_name': sampleProd['name']?.toString() ?? 'Ürün',
        'unit_price_cents': prodPriceCents,
        'quantity': 1.0,
        'discount_cents': 0,
        'vat_rate': 0,
        'total_cents': prodPriceCents,
      });

      await coreAppDb.db.insert('sale_payments', {
        'id': 'pay-idem-stk-1',
        'sale_id': 'sale-idem-stk-1',
        'payment_type': 'cash',
        'amount_cents': prodPriceCents,
        'created_at': now,
      });

      // 1. Çalıştırma
      final rep1 = await ReverseMigrationEngine.rollbackToLegacy(legacyDb: legacyDb, coreDb: coreAppDb);
      expect(rep1.isSuccess, isTrue);
      expect(rep1.salesExported, equals(1));
      expect(rep1.productsUpdated, equals(1));

      final salesCount1 = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      final itemsCount1 = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sale_items')).first['c'] as int;
      final paymentsCount1 = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sale_payments')).first['c'] as int;
      final stock1 = ((await legacyDb.query('products', where: 'id = ?', whereArgs: [prodId])).first['quantity'] as num).toDouble();
      expect(stock1, equals(initialLegacyQty - 1.0));

      // 2. Çalıştırma (Tekrar Deneme)
      final rep2 = await ReverseMigrationEngine.rollbackToLegacy(legacyDb: legacyDb, coreDb: coreAppDb);
      expect(rep2.isSuccess, isTrue);
      expect(rep2.salesExported, equals(0), reason: 'İkinci çalıştırmada 0 yeni satış aktarılmalı');
      expect(rep2.productsUpdated, equals(0), reason: 'İkinci çalıştırmada stok tekrar düşmemeli');

      final salesCount2 = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      final itemsCount2 = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sale_items')).first['c'] as int;
      final paymentsCount2 = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sale_payments')).first['c'] as int;
      final stock2 = ((await legacyDb.query('products', where: 'id = ?', whereArgs: [prodId])).first['quantity'] as num).toDouble();

      expect(salesCount2, equals(salesCount1), reason: 'Mükerrer satış oluşmamalıdır');
      expect(itemsCount2, equals(itemsCount1), reason: 'Mükerrer kalem oluşmamalıdır');
      expect(paymentsCount2, equals(paymentsCount1), reason: 'Mükerrer ödeme oluşmamalıdır');
      expect(stock2, equals(stock1), reason: 'Stok ikinci kez düşmemelidir');

      await legacyDb.close();
    });

    test('3.2 (Routing Rollback Güvenliği): Aktarım tamamlanmadan (legacy_migration_completed rolled_back olmadan) routing legacyye çevrilemez', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await coreAppDb.db.insert('sales', {
        'id': 'sale-blocker-1',
        'receipt_no': 'REC-BLK-1',
        'subtotal_cents': 10000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 10000,
        'paid_cents': 10000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-BLK-1',
        'created_at': now,
      });

      const resolver = DatabaseRoutingResolver();
      expect(
        () async => await resolver.assertSafeRollback(
          targetDb: coreAppDb.db,
          initialMigrationCutoffTimestamp: now - 10000,
        ),
        throwsA(isA<UnsafeRollbackException>()),
        reason: 'Hedefte yeni işlem varken ters uzlaştırma yapılmadan routing değiştirilemez',
      );
    });
  });
}
