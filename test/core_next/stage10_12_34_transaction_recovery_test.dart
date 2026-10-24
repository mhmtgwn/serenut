// test/core_next/stage10_12_34_transaction_recovery_test.dart
// SERENUT OS — STAGE 10.12.34
// POST-CUTOVER TRANSACTION RECONCILIATION VE GÜVENLİ RECOVERY TESTLERİ
//
// GÜVENLİK KURALI:
// 1. Canlı hiçbir veritabanına (serenut_pos.db, serenut_core_v2.db) dokunulmaz.
// 2. Yalnızca izole, geçici disposable test kopyaları kullanılır.
// 3. `coreNextSalesEngineEnabledProvider` kesinlikle `false` tutulur.

// ignore_for_file: avoid_relative_lib_imports, prefer_const_declarations

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';

import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const rawNutopiaPath = 'backups/raw_tenants_20261016/raw_nutopia_v60.db';
  const expectedNutopiaHash = 'e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24';

  const adminActor = ActorContext(
    userId: 'usr-admin-1',
    username: 'admin',
    role: AppRole.admin,
  );

  group('STAGE 10.12.34 — BÖLÜM 1: GÜVENLİK KAPISI VE DEĞİŞMEZLİK KANITLARI', () {
    test('1.1: Kaynak Nutopia DB hash değeri kesinlikle değişmemiş olmalıdır', () async {
      final file = File(rawNutopiaPath);
      expect(await file.exists(), isTrue, reason: 'Nutopia ham arşivi mevcut olmalıdır');
      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes).toString();
      expect(hash.toLowerCase(), equals(expectedNutopiaHash));
    });

    test('1.2: Satış motoru ve routing hook varsayılan olarak kapalıdır', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final salesEngine = container.read(coreNextSalesEngineEnabledProvider);
      expect(salesEngine, isFalse, reason: 'coreNextSalesEngineEnabledProvider = false olmalı');
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });

    test('1.3: Canlı snapshot yedeği veya taşınabilir arşiv fikstürü fiziksel olarak mevcut ve SHA-256 doğrulanmıştır', () async {
      const onedriveBackupPath = r'C:\Users\notop\OneDrive\Belgeler\SerenutBackups\serenut_pos_backup_20261019_161042.db';
      final file = File(onedriveBackupPath);
      if (await file.exists()) {
        expect(await file.length(), equals(61390848), reason: 'Boyut tam 61.390.848 bayt olmalıdır');
        final bytes = await file.readAsBytes();
        final hash = sha256.convert(bytes).toString();
        expect(hash.toLowerCase(), equals('da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89'));
      } else {
        final fixture = File(rawNutopiaPath);
        expect(await fixture.exists(), isTrue, reason: 'Nutopia ham arşivi mevcut olmalıdır');
        final bytes = await fixture.readAsBytes();
        final hash = sha256.convert(bytes).toString();
        expect(hash.toLowerCase(), equals(expectedNutopiaHash));
      }
    });
  });

  group('STAGE 10.12.34 — BÖLÜM 2: TRANSACTION ATOMİSİTESİ VE ARIZA DAYANIKLILIĞI', () {
    late Directory tempDir;
    late String isolatedTargetDb;
    late CoreAppDatabase coreAppDb;
    late HardwareWorker hardwareWorker;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage34_atomicity_');
      isolatedTargetDb = p.join(tempDir.path, 'core_target.db');
      coreAppDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetDb);
      hardwareWorker = HardwareWorker();
      await hardwareWorker.initialize();

      // Test ürünü ve müşteri ekle
      await coreAppDb.db.insert('products', {
        'id': 'prod-findik-1',
        'barcode': 'BC-FINDIK-01',
        'name': 'Kavrulmuş Fındık 500g',
        'price_cents': 15000, // 150.00 TL
        'stock_quantity': 50,
        'vat_rate': 1,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': 1792100000,
      });

      await coreAppDb.db.insert('customers', {
        'id': 'cust-ahmet-1',
        'name': 'Ahmet Yılmaz',
        'phone': '05551112233',
        'balance_cents': 0,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': 1792100000,
      });
    });

    tearDown(() async {
      await hardwareWorker.dispose();
      await coreAppDb.close();
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('2.1 (Arıza Senaryosu 7 & 8): DB yazımı ortasında veya kuyruk aşamasında çökme olursa Transaction Rollback ile 0 kalıntı kalır', () async {
      final cartProduct = ProductEntity(
        id: 'prod-findik-1',
        barcode: 'BC-FINDIK-01',
        name: 'Kavrulmuş Fındık 500g',
        price: const MoneyCents(15000),
        stockQuantity: 50,
        vatRate: 1,
        updatedAt: DateTime.now(),
      );

      final state = CoreSalesFlowState(
        items: [
          CoreCartItem(product: cartProduct, quantity: 2, unitPrice: cartProduct.price),
        ],
      );

      // Fault hook: Satış ana kaydı atıldıktan hemen sonra çökme simülasyonu
      final useCaseWithCrash = CoreCheckoutUseCase(
        db: coreAppDb,
        hardwareWorker: hardwareWorker,
        defaultActor: adminActor,
        faultHook: (step) async {
          if (step == 'after_sales_insert') {
            throw StateError('SİMÜLE EDİLMİŞ KRİTİK ELEKTRİK KESİNTİSİ / ÇÖKME');
          }
        },
      );

      final req = CheckoutRequest(
        flowState: state,
        receiptNo: 'REC-CRASH-01',
        storeTitle: 'Nutopia Test',
      );

      expect(() async => await useCaseWithCrash.execute(req), throwsStateError);

      // Doğrulama: Hiçbir tabloda kısmi kayıt kalmamalı (Tam Atomik Rollback)
      final salesCount = (await coreAppDb.db.rawQuery("SELECT COUNT(*) as c FROM sales WHERE receipt_no = 'REC-CRASH-01'")).first['c'] as int;
      expect(salesCount, equals(0), reason: 'Satış başlığı rollback edilmelidir');

      final itemsCount = (await coreAppDb.db.rawQuery('SELECT COUNT(*) as c FROM sale_items')).first['c'] as int;
      expect(itemsCount, equals(0), reason: 'Satış kalemleri rollback edilmelidir');

      // Stok değişmemeli (50 adet kalmalı)
      final prodStock = ((await coreAppDb.db.rawQuery("SELECT stock_quantity as s FROM products WHERE id = 'prod-findik-1'")).first['s'] as num).toInt();
      expect(prodStock, equals(50), reason: 'Stok eksilmemeli, tam geri dönmelidir');

      // Sync queue boş kalmalı
      final syncCount = (await coreAppDb.db.rawQuery('SELECT COUNT(*) as c FROM sync_events')).first['c'] as int;
      expect(syncCount, equals(0), reason: 'Sync kuyruğu da aynı transaction içinde olduğundan temiz kalmalıdır');
    });

    test('2.2 (Senaryo 9 & 10): Idempotency koruması aynı işlemin mükerrer yazılmasını engeller, içerik sapmasında hata verir', () async {
      final cartProduct = ProductEntity(
        id: 'prod-findik-1',
        barcode: 'BC-FINDIK-01',
        name: 'Kavrulmuş Fındık 500g',
        price: const MoneyCents(15000),
        stockQuantity: 50,
        vatRate: 1,
        updatedAt: DateTime.now(),
      );

      final state = CoreSalesFlowState(
        items: [
          CoreCartItem(product: cartProduct, quantity: 1, unitPrice: cartProduct.price),
        ],
        paymentSplits: [
          const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(15000)),
        ],
      );
      final useCase = CoreCheckoutUseCase(
        db: coreAppDb,
        hardwareWorker: hardwareWorker,
        defaultActor: adminActor,
      );

      final req = CheckoutRequest(
        flowState: state,
        receiptNo: 'REC-IDEM-01',
        idempotencyKey: 'IDEM-KEY-UNIQUE-100',
        storeTitle: 'Nutopia Test',
      );

      // 1. İlk çalıştırma: Başarılı satış
      final res1 = await useCase.execute(req);
      expect(res1.receiptNo, equals('REC-IDEM-01'));
      expect(res1.total.value, equals(15000));

      // Stok 50 -> 49 oldu
      var stock = ((await coreAppDb.db.rawQuery("SELECT stock_quantity as s FROM products WHERE id = 'prod-findik-1'")).first['s'] as num).toInt();
      expect(stock, equals(49));

      // 2. Aynı isteğin ağ gecikmesiyle tekrar gelmesi (Idempotent Retry)
      final res2 = await useCase.execute(req);
      expect(res2.id, equals(res1.id), reason: 'Aynı satış ID dönmeli, yeni satış üretilmemelidir');

      // Satış sayısı hâlâ 1 olmalı
      final count = (await coreAppDb.db.rawQuery("SELECT COUNT(*) as c FROM sales WHERE idempotency_key = 'IDEM-KEY-UNIQUE-100'")).first['c'] as int;
      expect(count, equals(1));

      // Stok ikinci kez düşmemeli (49 kalmalı)
      stock = ((await coreAppDb.db.rawQuery("SELECT stock_quantity as s FROM products WHERE id = 'prod-findik-1'")).first['s'] as num).toInt();
      expect(stock, equals(49));

      // 3. Aynı idempotency_key ile FARKLI içerik (tutar) gönderilirse (Senaryo 10)
      final stateAltered = CoreSalesFlowState(
        items: [
          CoreCartItem(product: cartProduct, quantity: 2, unitPrice: cartProduct.price), // 300 TL
        ],
        paymentSplits: [
          const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(30000)),
        ],
      );
      final alteredReq = CheckoutRequest(
        flowState: stateAltered,
        receiptNo: 'REC-IDEM-01',
        idempotencyKey: 'IDEM-KEY-UNIQUE-100', // Aynı anahtar ama farklı tutar!
        storeTitle: 'Nutopia Test',
      );

      expect(
        () async => await useCase.execute(alteredReq),
        throwsStateError,
        reason: 'Aynı işlem kimliği farklı içerikle gelirse derhal engellenmelidir (Payload Mismatch)',
      );
    });

    test('2.3 (Senaryo 11): Satış var ama ödeme veya stok hareketi eksikse işlem engellenir ve DB temiz kalır', () async {
      final cartProduct = ProductEntity(
        id: 'prod-findik-1',
        barcode: 'BC-FINDIK-01',
        name: 'Kavrulmuş Fındık 500g',
        price: const MoneyCents(15000),
        stockQuantity: 50,
        vatRate: 1,
        updatedAt: DateTime.now(),
      );

      final useCase = CoreCheckoutUseCase(
        db: coreAppDb,
        hardwareWorker: hardwareWorker,
        defaultActor: adminActor,
      );

      // A) Ödeme eksik ve müşteri seçilmemiş
      final missingPayState = CoreSalesFlowState(
        items: [
          CoreCartItem(product: cartProduct, quantity: 1, unitPrice: cartProduct.price),
        ],
        paymentSplits: const [], // 0 TL ödeme, 150 TL borç ama müşteri yok!
      );
      final req1 = CheckoutRequest(
        flowState: missingPayState,
        receiptNo: 'REC-FAIL-PAY-1',
        idempotencyKey: 'IDEM-FAIL-PAY-1',
        storeTitle: 'Nutopia Test',
      );
      expect(() async => await useCase.execute(req1), throwsStateError);

      // B) Stok yetersiz (50 adet var, 100 adet isteniyor)
      final outOfStockState = CoreSalesFlowState(
        items: [
          CoreCartItem(product: cartProduct, quantity: 100, unitPrice: cartProduct.price),
        ],
        paymentSplits: const [
          PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(1500000)),
        ],
      );
      final req2 = CheckoutRequest(
        flowState: outOfStockState,
        receiptNo: 'REC-FAIL-STOCK-1',
        idempotencyKey: 'IDEM-FAIL-STOCK-1',
        storeTitle: 'Nutopia Test',
      );
      expect(() async => await useCase.execute(req2), throwsStateError);

      // Doğrulama: Hiçbir başarısız işlem veritabanına yazılmamalı
      final c1 = (await coreAppDb.db.rawQuery("SELECT COUNT(*) as c FROM sales WHERE receipt_no IN ('REC-FAIL-PAY-1', 'REC-FAIL-STOCK-1')")).first['c'] as int;
      expect(c1, equals(0));
    });
  });

  group('STAGE 10.12.34 — BÖLÜM 3: POST-CUTOVER TERS UZLAŞTIRMA (REVERSE RECONCILIATION) TESTLERİ', () {
    late Directory tempDir;
    late String isolatedLegacyPath;
    late String isolatedTargetPath;
    late CoreAppDatabase coreAppDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage34_recovery_');
      isolatedLegacyPath = p.join(tempDir.path, 'legacy_serenut_pos.db');
      isolatedTargetPath = p.join(tempDir.path, 'core_serenut_v2.db');

      // Orijinal Nutopia arşivini kopyala
      final srcBytes = await File(rawNutopiaPath).readAsBytes();
      await File(isolatedLegacyPath).writeAsBytes(srcBytes);

      coreAppDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);

      // Core Next'e temel katalog ve müşteri oluştur
      await coreAppDb.db.insert('app_settings', {'key': 'tenant_id', 'value': 'tenant-nutopia', 'updated_at': 1});
      await coreAppDb.db.insert('products', {
        'id': 'prod-rev-1',
        'barcode': 'BC-REV-01',
        'name': 'Fındık İçi 1kg',
        'price_cents': 20000,
        'stock_quantity': 100,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': 1,
      });
      await coreAppDb.db.insert('customers', {
        'id': 'cust-rev-1',
        'name': 'Mehmet Demir',
        'phone': '05559998877',
        'balance_cents': -50000, // 500 TL borçlu
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': 1,
      });
    });

    tearDown(() async {
      await coreAppDb.close();
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('3.1 (Senaryo 1 & 5): Core Next\'te yeni nakit satış ve stok hareketi Legacy DB\'ye kayıpsız geri aktarılır', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final legacyDb = await openDatabase(isolatedLegacyPath);

      // Gerçek Nutopia veritabanından mevcut bir ürünü seç
      final sampleProd = (await legacyDb.query('products', where: 'quantity > 10', limit: 1)).first;
      final prodId = sampleProd['id'].toString();
      final initialLegacyQty = (sampleProd['quantity'] as num).toDouble();
      final prodPrice = (sampleProd['price'] as num).toDouble();
      final prodPriceCents = (prodPrice * 100).round();

      // Core Next üzerinde bu ürünü ekle ve stok düş (initial - 2)
      await coreAppDb.db.insert('products', {
        'id': prodId,
        'barcode': sampleProd['sku']?.toString() ?? prodId,
        'name': sampleProd['name']?.toString() ?? 'Ürün',
        'price_cents': prodPriceCents,
        'stock_quantity': (initialLegacyQty - 2.0).round(),
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Core Next üzerinde yeni bir satış oluştur
      await coreAppDb.db.insert('sales', {
        'id': 'sale-post-cutover-cash',
        'receipt_no': 'REC-POST-CASH-1',
        'customer_id': null,
        'subtotal_cents': prodPriceCents * 2,
        'discount_cents': 0,
        'vat_total_cents': (prodPriceCents * 2 * 0.1).round(),
        'total_cents': prodPriceCents * 2,
        'paid_cents': prodPriceCents * 2,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-POST-1',
        'created_at': now,
      });

      await coreAppDb.db.insert('sale_items', {
        'id': 'item-post-1',
        'sale_id': 'sale-post-cutover-cash',
        'product_id': prodId,
        'barcode': sampleProd['sku']?.toString() ?? prodId,
        'product_name': sampleProd['name']?.toString() ?? 'Ürün',
        'unit_price_cents': prodPriceCents,
        'quantity': 2.0,
        'discount_cents': 0,
        'vat_rate': 10,
        'total_cents': prodPriceCents * 2,
      });

      await coreAppDb.db.insert('sale_payments', {
        'id': 'pay-post-1',
        'sale_id': 'sale-post-cutover-cash',
        'payment_type': 'cash',
        'amount_cents': prodPriceCents * 2,
        'created_at': now,
      });

      // ── TERS UZLAŞTIRMA (REVERSE RECONCILIATION) İŞLETİMİ ────────────────────
      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isTrue);
      expect(report.salesExported, greaterThanOrEqualTo(1));

      // 1. Satış legacy sales tablosuna geçti mi?
      final checkSale = await legacyDb.query('sales', where: "id = 'sale-post-cutover-cash'");
      expect(checkSale.length, equals(1));
      expect((checkSale.first['total_amount'] as num).toDouble(), equals(prodPrice * 2));
      expect(checkSale.first['payment_method'], equals('cash'));

      // 2. Kalemler legacy sale_items tablosuna geçti mi?
      final checkItems = await legacyDb.query('sale_items', where: "sale_id = 'sale-post-cutover-cash'");
      expect(checkItems.length, equals(1));
      expect((checkItems.first['quantity'] as num).toDouble(), equals(2.0));

      // 3. Stok miktarı legacy'de (initial - 2) olarak güncellendi mi? (Senaryo 5)
      final checkProd = await legacyDb.query('products', where: 'id = ?', whereArgs: [prodId]);
      expect((checkProd.first['quantity'] as num).toDouble(), equals(initialLegacyQty - 2.0));

      await legacyDb.close();
    });

    test('3.2 (Senaryo 2, 3, 4): Kartlı, Vadeli ve Karma Ödemeler cari hareketlerle legacy DB\'ye uzlaştırılır', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Karma Ödemeli Satış (100 TL Nakit + 150 TL Kart + 250 TL Veresiye = 500 TL)
      await coreAppDb.db.insert('sales', {
        'id': 'sale-post-mixed-1',
        'receipt_no': 'REC-POST-MIXED-1',
        'customer_id': 'cust-rev-1',
        'subtotal_cents': 50000,
        'discount_cents': 0,
        'vat_total_cents': 5000,
        'total_cents': 50000,
        'paid_cents': 25000, // 100 nakit + 150 kart
        'debt_cents': 25000, // 250 veresiye
        'status': 'COMPLETED',
        'idempotency_key': 'IDEM-MIXED-1',
        'created_at': now,
      });

      await coreAppDb.db.insert('sale_payments', {
        'id': 'pay-m-cash',
        'sale_id': 'sale-post-mixed-1',
        'payment_type': 'cash',
        'amount_cents': 10000,
        'created_at': now,
      });
      await coreAppDb.db.insert('sale_payments', {
        'id': 'pay-m-card',
        'sale_id': 'sale-post-mixed-1',
        'payment_type': 'card',
        'amount_cents': 15000,
        'created_at': now,
      });
      await coreAppDb.db.insert('sale_payments', {
        'id': 'pay-m-credit',
        'sale_id': 'sale-post-mixed-1',
        'payment_type': 'onAccount',
        'amount_cents': 25000,
        'created_at': now,
      });

      // Müşteri defter hareketi (250 TL borç)
      await coreAppDb.db.insert('ledger_entries', {
        'id': 'le-post-debit-1',
        'customer_id': 'cust-rev-1',
        'reference_sale_id': 'sale-post-mixed-1',
        'entry_type': 'SALE',
        'amount_cents': 25000,
        'balance_after_cents': -75000, // -500 TL idi, -750 TL oldu
        'description': 'Veresiye Satış Borcu',
        'created_at': now,
      });

      await coreAppDb.db.update('customers', {'balance_cents': -75000}, where: 'id = ?', whereArgs: ['cust-rev-1']);

      // ── TERS UZLAŞTIRMA İŞLETİMİ ──────────────────────────────────────────
      final legacyDb = await openDatabase(isolatedLegacyPath);

      // Legacy customers içine cust-rev-1 ekle
      await legacyDb.insert('customers', {
        'id': 'cust-rev-1',
        'name': 'Mehmet Demir',
        'balance': -500.0,
        'is_active': 1,
        'is_deleted': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isTrue, reason: 'Hata: ${report.errorMessage}');

      // 1. Karma satış kontrolü: payment_method 'mixed' olmalı ve parçalı dağılım notlara yazılmalı
      final legacySale = (await legacyDb.query('sales', where: "id = 'sale-post-mixed-1'")).first;
      expect(legacySale['payment_method'], equals('mixed'));
      expect(legacySale['notes'], contains('cash'));
      expect(legacySale['notes'], contains('card'));

      // 2. Müşteri cari bakiyesi güncellendi mi? (-750.0 TL)
      final legacyCust = (await legacyDb.query('customers', where: "id = 'cust-rev-1'")).first;
      expect((legacyCust['balance'] as num).toDouble(), equals(-750.0));

      // 3. Finansal hareket legacy financial_transactions tablosuna yazıldı mı?
      final ft = await legacyDb.query('financial_transactions', where: "id = 'le-post-debit-1'");
      expect(ft.length, equals(1));
      expect((ft.first['amount'] as num).toDouble(), equals(250.0));
      expect(ft.first['type'], equals('SALE'));

      await legacyDb.close();
    });

    test('3.3 (Senaryo 6): Satış iadesi (REFUND) legacy refunds tablosuna bağlanarak uzlaştırılır', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Core Next iade kaydı
      await coreAppDb.db.insert('sales', {
        'id': 'sale-post-refund-1',
        'receipt_no': 'REF-REC-ORIG-01',
        'customer_id': null,
        'subtotal_cents': -10000,
        'discount_cents': 0,
        'vat_total_cents': -1000,
        'total_cents': -10000,
        'paid_cents': -10000,
        'debt_cents': 0,
        'status': 'REFUND',
        'created_at': now,
      });

      final legacyDb = await openDatabase(isolatedLegacyPath);

      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isTrue);

      // İade kaydı legacy refunds tablosuna yazıldı mı?
      final refundRows = await legacyDb.query('refunds', where: "id = 'sale-post-refund-1'");
      expect(refundRows.length, equals(1));
      expect((refundRows.first['amount'] as num).toDouble(), equals(100.0));

      await legacyDb.close();
    });

    test('3.4 (Senaryo 9): Uzlaştırma motoru iki kez üst üste çalıştırıldığında (Idempotency) mükerrer veri üretmez', () async {
      final legacyDb = await openDatabase(isolatedLegacyPath);

      // 1. İlk uzlaştırma
      final rep1 = await ReverseMigrationEngine.rollbackToLegacy(legacyDb: legacyDb, coreDb: coreAppDb);
      expect(rep1.isSuccess, isTrue);

      final salesCount1 = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;

      // 2. İkinci uzlaştırma (Tekrar çalıştırma)
      final rep2 = await ReverseMigrationEngine.rollbackToLegacy(legacyDb: legacyDb, coreDb: coreAppDb);
      expect(rep2.isSuccess, isTrue);

      final salesCount2 = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      expect(salesCount2, equals(salesCount1), reason: 'İkinci çalıştırmada mükerrer satış oluşmamalıdır');

      await legacyDb.close();
    });

    test('3.5 (Senaryo 12): Uzlaştırma esnasında hata oluşursa Legacy DB Transaction Rollback ile önceki haline döner', () async {
      final legacyDb = await openDatabase(isolatedLegacyPath);
      final initialSalesCount = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;

      // Core Next'e geçerli bir satış ekle, ama legacyDb üzerinde trigger ile hata fırlatılmasını sağla
      await coreAppDb.db.insert('sales', {
        'id': 'sale-faulty-1',
        'receipt_no': 'REC-FAULTY-1',
        'subtotal_cents': 10000,
        'discount_cents': 0,
        'vat_total_cents': 1000,
        'total_cents': 10000,
        'paid_cents': 10000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': 1792100000,
      });

      // legacyDb üzerinde sales tablosuna kısıtlayıcı bir BEFORE INSERT trigger'ı ekle (arıza simülasyonu)
      await legacyDb.execute('''
        CREATE TRIGGER trg_test_abort_faulty
        BEFORE INSERT ON sales
        WHEN NEW.id = 'sale-faulty-1'
        BEGIN
          SELECT RAISE(ABORT, 'TEST UZLAŞTIRMA KASITLI ARIZA');
        END;
      ''');

      final rep = await ReverseMigrationEngine.rollbackToLegacy(legacyDb: legacyDb, coreDb: coreAppDb);
      expect(rep.isSuccess, isFalse);
      expect(rep.errorMessage, contains('TEST UZLAŞTIRMA KASITLI ARIZA'));

      // Rollback doğrulaması: Legacy DB'deki satış sayısı ilk haline eşit kalmalıdır
      final afterSalesCount = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      expect(afterSalesCount, equals(initialSalesCount), reason: 'Arıza durumunda transaction rollback işletilmelidir');

      await legacyDb.close();
    });

    test('3.6 (Senaryo 13 & 14): Bozuk DB veya yabancı tenant veritabanı bütünlük kontrolünden geçemez ve durdurulur', () async {
      // 1. Bozuk DB kontrolü (Senaryo 14)
      final corruptDbPath = p.join(tempDir.path, 'corrupt_test.db');
      await File(corruptDbPath).writeAsString('CORRUPTED BYTESTREAM');

      const resolver = DatabaseRoutingResolver();
      final corruptResult = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: corruptDbPath,
        migrationStateCompleted: true,
      );
      expect(corruptResult.decision, equals(RoutingDecision.blockedFailClosed));

      // 2. Yabancı tenant kontrolü (Senaryo 13)
      final foreignResult = await resolver.resolve(
        requestedTenantId: 'tenant-erkul', // Farklı tenant
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: isolatedTargetPath, // targetDb içinde 'tenant-nutopia' var
        migrationStateCompleted: true,
      );
      expect(foreignResult.decision, equals(RoutingDecision.blockedFailClosed));
      expect(foreignResult.reason, contains('Tenant ID uyuşmazlığı'));
    });

    test('3.7 (Senaryo 15): Uzlaştırma tamamlanmadan uygulama kapanırsa durum fail-closed kalır', () async {
      SharedPreferences.setMockInitialValues({
        'core_next_bootstrap_migration_state': 'failed_blocked',
      });
      final prefs = await SharedPreferences.getInstance();

      final gate = const PilotCutoverGate();
      final eval = await gate.evaluate(prefs: prefs);
      expect(eval.isPilotActive, isFalse);
      expect(eval.isFailClosed, isTrue);
    });
  });
}
