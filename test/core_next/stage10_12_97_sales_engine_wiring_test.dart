// test/core_next/stage10_12_97_sales_engine_wiring_test.dart
// SERENUT OS — STAGE 10.12.97
// Core Next Satış Motoru Bağlantıları ve Entegrasyon Test Paketi
// ignore_for_file: avoid_relative_lib_imports

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/sales_service.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/repository_providers.dart';

import '../../core_next/client_core/lib/domain/models/core_entities.dart' as core;
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/domain/usecases/refund_use_case.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_sale_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_product_repository.dart';
import '../../core_next/client_core/lib/infrastructure/sales/core_next_sales_bridge.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart';
import '../../core_next/client_core/lib/presentation/sales/sales_engine_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('STAGE 10.12.97 — Core Next Satış Motoru Bağlantıları Test Paketi', () {
    late Directory tempDir;
    late CoreAppDatabase coreDb;
    late SqliteLedgerRepository ledgerRepo;
    late LedgerService ledgerService;
    late HardwareWorker hardwareWorker;
    late CoreCheckoutUseCase checkoutUseCase;
    late CoreRefundUseCase refundUseCase;
    late CoreSalesFlowNotifier salesFlowNotifier;
    late SalesEngineAdapter adapter;
    late SqliteProductRepository productRepo;
    late CoreNextSaleExecutor saleExecutor;
    late CoreNextRefundExecutor refundExecutor;

    const testProductId = 'prod-test-nut-01';
    const testCustomerId = 'cust-test-ali-01';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('stage10_12_97_test_');
      final dbPath = p.join(tempDir.path, 'isolated_test_core.db');

      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: dbPath);
      ledgerRepo = SqliteLedgerRepository(coreDb.db);
      ledgerService = LedgerService(ledgerRepo);
      hardwareWorker = HardwareWorker();
      await hardwareWorker.initialize();

      checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        ledgerService: ledgerService,
        hardwareWorker: hardwareWorker,
        defaultActor: ActorContext.testManager,
      );

      refundUseCase = CoreRefundUseCase(
        db: coreDb,
        ledgerService: ledgerService,
      );

      salesFlowNotifier = CoreSalesFlowNotifier(
        checkoutUseCase,
        defaultActor: ActorContext.testManager,
      );

      adapter = SalesEngineAdapter(
        coreNotifier: salesFlowNotifier,
        initialUseCoreNext: true,
      );

      productRepo = SqliteProductRepository(coreDb.db);

      saleExecutor = CoreNextSalesBridge.createSaleExecutor(
        checkoutUseCase: checkoutUseCase,
        productRepo: productRepo,
        adapter: adapter,
        coreDb: coreDb,
      );

      refundExecutor = CoreNextSalesBridge.createRefundExecutor(
        refundUseCase: refundUseCase,
      );

      // Test Ürünü Ekle (Fındık Ezmesi 100 TL = 10.000 kuruş, Stok: 50)
      await coreDb.db.insert('products', {
        'id': testProductId,
        'barcode': '8690001001',
        'name': 'Organik Fındık Ezmesi',
        'price_cents': 10000,
        'vat_rate': 1,
        'unit': 'piece',
        'stock_quantity': 50,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Test Müşterisi Ekle (Ali Yılmaz, Bakiye: 0, Limit: 10.000 TL)
      await coreDb.db.insert('customers', {
        'id': testCustomerId,
        'name': 'Ali Yılmaz',
        'balance_cents': 0,
        'credit_limit_cents': 1000000,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      await hardwareWorker.dispose();
      await coreDb.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('1. Nakit Satış: Stok düşmeli, nakit ödeme Core Next satış kaydına işlenmeli', () async {
      final sale = await saleExecutor(
        customerId: '',
        items: [
          SaleItemInput(
            productId: testProductId,
            productName: 'Organik Fındık Ezmesi',
            quantity: 2,
            unitPrice: 100.0,
          ),
        ],
        paymentMethod: 'cash',
        paidAmount: 200.0,
        cashierName: 'Test Kasiyer',
        userId: 'usr-kasiyer-1',
        userRole: 'cashier',
      );

      expect(sale, isNotNull);
      expect(sale!.totalAmount, equals(200.0));
      expect(sale.paymentMethod, equals('cash'));

      // Stok Kontrolü: 50 - 2 = 48
      final prod = await productRepo.getById(testProductId);
      expect(prod?.stockQuantity, equals(48));

      // Veritabanı satış kaydı
      final salesRows = await coreDb.query('sales');
      expect(salesRows.length, equals(1));
      expect(salesRows.first['total_cents'], equals(20000));
      expect(salesRows.first['status'], equals('COMPLETED'));

      // Ödeme tablosu kontrolü
      final paymentRows = await coreDb.query('sale_payments');
      expect(paymentRows.length, equals(1));
      expect(paymentRows.first['payment_type'], equals('cash'));
      expect(paymentRows.first['amount_cents'], equals(20000));
    });

    test('2. Kart Satışı: Kredi kartı ödemesi ve stok hareketi başarıyla işlenmeli', () async {
      final sale = await saleExecutor(
        customerId: '',
        items: [
          SaleItemInput(
            productId: testProductId,
            productName: 'Organik Fındık Ezmesi',
            quantity: 1,
            unitPrice: 100.0,
          ),
        ],
        paymentMethod: 'credit_card',
        paidAmount: 100.0,
        cashierName: 'Kasiyer 2',
      );

      expect(sale, isNotNull);
      expect(sale!.totalAmount, equals(100.0));

      final prod = await productRepo.getById(testProductId);
      expect(prod?.stockQuantity, equals(49));

      final paymentRows = await coreDb.query('sale_payments');
      expect(paymentRows.first['payment_type'], equals('creditCard'));
      expect(paymentRows.first['amount_cents'], equals(10000));
    });

    test('3. Vadeli / Açık Hesap Satış: Müşteri bakiyesi artmalı ve defter kaydı oluşmalı', () async {
      final sale = await saleExecutor(
        customerId: testCustomerId,
        items: [
          SaleItemInput(
            productId: testProductId,
            productName: 'Organik Fındık Ezmesi',
            quantity: 3,
            unitPrice: 100.0,
          ),
        ],
        paymentMethod: 'on_account',
        paidAmount: 0.0,
        cashierName: 'Kasiyer 1',
      );

      expect(sale, isNotNull);
      expect(sale!.totalAmount, equals(300.0));

      // Müşteri Bakiyesi Kontrolü (0 - 300 TL = -30.000 kuruş borç)
      final custRows = await coreDb.query('customers', where: 'id = ?', whereArgs: [testCustomerId]);
      expect(custRows.first['balance_cents'], equals(-30000));

      // Defter Kaydı Kontrolü (Veresiye için müşteri hesabı borçlandırılmalı)
      final ledgerRows = await coreDb.query(
        'ledger_entries',
        where: 'customer_id = ?',
        whereArgs: [testCustomerId],
      );
      expect(ledgerRows.isNotEmpty, isTrue);
      expect(ledgerRows.first['amount_cents'], equals(30000));
      expect(ledgerRows.first['entry_type'], equals('debitSale'));
    });

    test('4. Karma Ödeme (Split): Nakit + Kart + Açık Hesap doğru oranlarda dağıtılmalı', () async {
      final sale = await saleExecutor(
        customerId: testCustomerId,
        items: [
          SaleItemInput(
            productId: testProductId,
            productName: 'Organik Fındık Ezmesi',
            quantity: 3,
            unitPrice: 100.0,
          ),
        ],
        paymentMethod: 'mixed',
        terminalMetadata: {
          'splits': [
            {'type': 'cash', 'amount': 100.0},
            {'type': 'card', 'amount': 100.0},
            {'type': 'on_account', 'amount': 100.0, 'note': 'Kalan vadeli'},
          ]
        },
      );

      expect(sale, isNotNull);

      // Ödeme parçaları kontrolü
      final paymentRows = await coreDb.query('sale_payments', orderBy: 'id ASC');
      expect(paymentRows.length, equals(3));
      expect(paymentRows.any((r) => r['payment_type'] == 'cash' && r['amount_cents'] == 10000), isTrue);
      expect(paymentRows.any((r) => r['payment_type'] == 'creditCard' && r['amount_cents'] == 10000), isTrue);
      expect(paymentRows.any((r) => r['payment_type'] == 'onAccount' && r['amount_cents'] == 10000), isTrue);

      // Yalnızca 100 TL açık hesap kısmı müşteriye borç yazılmalı (-10.000 kuruş)
      final custRows = await coreDb.query('customers', where: 'id = ?', whereArgs: [testCustomerId]);
      expect(custRows.first['balance_cents'], equals(-10000));
    });

    test('5. İskonto Hesabı: Tutar kuruş hassasiyetinde doğru düşülmeli', () async {
      final sale = await saleExecutor(
        customerId: '',
        items: [
          SaleItemInput(
            productId: testProductId,
            productName: 'Organik Fındık Ezmesi',
            quantity: 1,
            unitPrice: 100.0,
          ),
        ],
        paymentMethod: 'cash',
        discountAmount: 15.0, // 15 TL indirim
        paidAmount: 85.0,
        userRole: 'manager',
      );

      expect(sale, isNotNull);
      expect(sale!.totalAmount, equals(85.0));

      final orderRows = await coreDb.query('sales');
      expect(orderRows.first['subtotal_cents'], equals(10000));
      expect(orderRows.first['discount_cents'], equals(1500));
      expect(orderRows.first['total_cents'], equals(8500));
    });

    test('6. İade Akışı: Satış iade edildiğinde stok stoğa geri girmeli ve kayıt oluşmalı', () async {
      // 1. Önce 2 adet nakit satış yap
      final sale = await saleExecutor(
        customerId: '',
        items: [
          SaleItemInput(
            productId: testProductId,
            productName: 'Organik Fındık Ezmesi',
            quantity: 2,
            unitPrice: 100.0,
          ),
        ],
        paymentMethod: 'cash',
        paidAmount: 200.0,
      );
      expect(sale, isNotNull);

      // Stok 50 - 2 = 48 oldu
      var prod = await productRepo.getById(testProductId);
      expect(prod?.stockQuantity, equals(48));

      // 2. 1 adedini iade et
      await refundExecutor(
        saleId: sale!.id,
        itemsToReturn: [
          SaleItemInput(
            productId: testProductId,
            quantity: 1,
            unitPrice: 100.0,
          ),
        ],
        refundMethod: 'cash',
        reason: 'Ambalaj hasarlı',
        userId: 'usr-mgr-1',
        userRole: 'manager',
      );

      // Stok 48 + 1 = 49 olmalı
      prod = await productRepo.getById(testProductId);
      expect(prod?.stockQuantity, equals(49));

      // İade kaydı oluşmalı (Core Next ters kayıt - compensating reversal mimarisi)
      final refundRows = await coreDb.query('sales', where: "status = 'REFUND'");
      expect(refundRows.length, equals(1));
      expect(refundRows.first['total_cents'], equals(-10000));
    });

    test('7. Stok Mutabakatı ve Defter Tutarlılığı: Satış ve iadelerde bakiye tam tutmalı', () async {
      // Başlangıç: Stok 50
      // 1. Satış: 5 adet (Stok -> 45)
      final sale = await saleExecutor(
        customerId: '',
        items: [
          SaleItemInput(
            productId: testProductId,
            quantity: 5,
            unitPrice: 100.0,
          ),
        ],
        paymentMethod: 'cash',
      );

      var prod = await productRepo.getById(testProductId);
      expect(prod?.stockQuantity, equals(45));

      // 2. İade: 2 adet (Stok -> 47)
      await refundExecutor(
        saleId: sale!.id,
        itemsToReturn: [
          SaleItemInput(
            productId: testProductId,
            quantity: 2,
            unitPrice: 100.0,
          ),
        ],
        refundMethod: 'cash',
        reason: 'Fazla alındı',
      );

      prod = await productRepo.getById(testProductId);
      expect(prod?.stockQuantity, equals(47));

      // Kasa nakit mutabakatı (Nakit kasaya net 300 TL = 30.000 kuruş girmiş olmalı)
      final cashRows = await coreDb.query('cash_transactions');
      expect(cashRows.isNotEmpty, isTrue);
      final inflow = cashRows.where((r) => r['type'] == 'INFLOW').fold<int>(0, (sum, r) => sum + (r['amount_cents'] as int));
      final outflow = cashRows.where((r) => r['type'] == 'OUTFLOW').fold<int>(0, (sum, r) => sum + (r['amount_cents'] as int));
      expect(inflow - outflow, equals(30000));
    });

    test('8. Desteklenmeyen Kısmi Ödeme: Core Next modunda açık UnsupportedError fırlatılmalı', () async {
      final container = ProviderContainer(
        overrides: [
          saleRepositoryProvider.overrideWith(
            (ref) => Future.value(CoreNextSaleRepository.fromCoreAppDatabase(coreDb)),
          ),
          coreNextSalesEngineEnabledProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(salesControllerProvider.notifier);
      expect(
        () => controller.recordPartialPayment(saleId: 'sale-dummy-id', amount: 50.0, method: 'cash'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('9. Eksik Executor Koruması: Motor aktifken executor null ise StateError ile durdurulmalı', () async {
      final container = ProviderContainer(
        overrides: [
          saleRepositoryProvider.overrideWith(
            (ref) => Future.value(CoreNextSaleRepository.fromCoreAppDatabase(coreDb)),
          ),
          salesServiceProvider.overrideWith((ref) => Future.value(_FakeSalesService())),
          currentUserProvider.overrideWithValue(null),
          coreNextSalesEngineEnabledProvider.overrideWith((ref) => true),
          coreNextSaleExecutorProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(salesControllerProvider.notifier);
      await expectLater(
        controller.createSale(
          customerId: '',
          items: [
            SaleItemInput(productId: testProductId, quantity: 1, unitPrice: 100.0),
          ],
          paymentMethod: 'cash',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('10. DualDatabaseRoutingCoordinator ve Erkul Çeyiz Tenant İzolasyonu', () async {
      // 10.1: Varsayılan (enableSalesEngine: false) durumda satış sağlayıcıları override EDİLMEZ
      final normalOverrides = DualDatabaseRoutingCoordinator.createRepositoryOverrides(
        coreDb: coreDb,
        enableSalesEngine: false,
      );

      final hasSaleRepo = normalOverrides.any((o) => o.toString().contains('coreNextSaleRepositoryProvider'));
      final hasSalesEngine = normalOverrides.any((o) => o.toString().contains('coreNextSalesEngineEnabledProvider'));
      expect(hasSaleRepo, isFalse);
      expect(hasSalesEngine, isFalse);

      // 10.2: enableSalesEngine: true olduğunda 4 bağlantı da atomik olarak enjekte edilir
      final fullOverrides = DualDatabaseRoutingCoordinator.createRepositoryOverrides(
        coreDb: coreDb,
        enableSalesEngine: true,
      );
      final container = ProviderContainer(overrides: fullOverrides);
      addTearDown(container.dispose);

      expect(container.read(coreNextSalesEngineEnabledProvider), isTrue);
      expect(container.read(coreNextSaleExecutorProvider), isNotNull);
      expect(container.read(coreNextRefundExecutorProvider), isNotNull);
      expect(container.read(coreNextSaleRepositoryProvider), isA<CoreNextSaleRepository>());

      // 10.3: Erkul Çeyiz tenant'ı ile Nutopia DB'ye erişilmek istendiğinde tenantMismatchBlocked dönmeli
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'comp-nutopia-01',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      const resolver = DatabaseRoutingResolver();
      final resolution = await resolver.resolve(
        requestedTenantId: 'comp-1791194455402-bdc6d8d1', // Erkul Çeyiz
        legacyDbPath: p.join(tempDir.path, 'erkul_legacy.db'),
        targetDbPath: coreDb.db.path,
        migrationStateCompleted: true,
      );

      expect(resolution.decision, equals(RoutingDecision.blockedFailClosed));
      expect(resolution.isTargetSelected, isFalse);
    });
  });
}

class _FakeSalesService extends Fake implements SalesService {}
