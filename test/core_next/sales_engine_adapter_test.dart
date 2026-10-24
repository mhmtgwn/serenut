// test/core_next/sales_engine_adapter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart';
import '../../core_next/client_core/lib/presentation/sales/sales_engine_adapter.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SalesEngineAdapter (Özellik Bayrağı ve Güvenli Çift Motor) Tests', () {
    late CoreAppDatabase coreDb;
    late SqliteLedgerRepository ledgerRepo;
    late LedgerService ledgerService;
    late HardwareWorker hardwareWorker;
    late CoreCheckoutUseCase checkoutUseCase;
    late CoreSalesFlowNotifier salesNotifier;

    final testProduct = ProductEntity(
      id: 'p-adapter-1',
      barcode: '123456',
      name: 'Adaptör Test Ekmeği',
      price: const MoneyCents(1000), // 10 TL
      stockQuantity: 20,
      updatedAt: DateTime.now(),
    );

    final testCustomer = CustomerEntity(
      id: 'c-adapter-1',
      name: 'Denetim Müşterisi',
      balance: MoneyCents.zero,
      creditLimit: const MoneyCents(100000), // 1.000 TL
      updatedAt: DateTime.now(),
    );

    setUp(() async {
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: inMemoryDatabasePath);
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
      salesNotifier = CoreSalesFlowNotifier(
        checkoutUseCase,
        defaultActor: ActorContext.testManager,
      );

      await coreDb.db.insert('products', {
        'id': testProduct.id,
        'barcode': testProduct.barcode,
        'name': testProduct.name,
        'price_cents': testProduct.price.value,
        'vat_rate': 1,
        'unit': 'piece',
        'stock_quantity': testProduct.stockQuantity,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('customers', {
        'id': testCustomer.id,
        'name': testCustomer.name,
        'balance_cents': testCustomer.balance.value,
        'credit_limit_cents': testCustomer.creditLimit.value,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      await hardwareWorker.dispose();
      await coreDb.close();
    });

    test('1. Varsayılan Motor: Feature flag kapalıdır ve legacy motor çalışır', () async {
      final adapter = SalesEngineAdapter(coreNotifier: salesNotifier);
      expect(adapter.isCoreNextActive, false);

      bool legacyCalled = false;
      final result = await adapter.executeCheckout(
        receiptNo: 'REC-LEGACY-01',
        storeTitle: 'Test Bakkal',
        legacyExecute: () async {
          legacyCalled = true;
          return {'id': 'legacy-sale-1', 'total': 50.0};
        },
      );

      expect(legacyCalled, true);
      expect(result.isSuccess, true);
      expect(result.executedEngine, SalesEngineType.legacy);
      expect(result.coreSaleOrder, isNull);
      expect(result.legacySale, isNotNull);
    });

    test('2. Yeni Motor Aktifleştirildiğinde: CoreNext nakit satışını sözleşmeye uygun yürütür', () async {
      final adapter = SalesEngineAdapter(coreNotifier: salesNotifier, initialUseCoreNext: true);
      expect(adapter.isCoreNextActive, true);

      // Sepete 2 adet ekmek ve 20 TL nakit ekle
      salesNotifier.addProduct(testProduct, quantity: 2);
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(2000)),
      ]);

      final result = await adapter.executeCheckout(
        receiptNo: 'REC-CORENEXT-01',
        storeTitle: 'Test Bakkal',
        idempotencyKey: 'idemp-cash-01',
      );

      expect(result.isSuccess, true);
      expect(result.executedEngine, SalesEngineType.coreNext);
      expect(result.saleId, isNotNull);
      expect(result.receiptNo, 'REC-CORENEXT-01');
      expect(result.total?.value, 2000);
      expect(result.paid?.value, 2000);
      expect(result.debt?.value, 0);
      expect(result.stockMovementsCount, 1);
      expect(result.hasLedgerDebit, false);
      expect(result.isOutboxEnqueued, true);

      // Veritabanı teyidi: Stok 20 - 2 = 18 kalmalı
      final pRows = await coreDb.db.query('products', where: 'id = ?', whereArgs: [testProduct.id]);
      expect(pRows.first['stock_quantity'], 18);
    });

    test('3. Kart Satışı: PaymentType.creditCard ile tam ödeme sözleşmesi doğrulanır', () async {
      final adapter = SalesEngineAdapter(coreNotifier: salesNotifier, initialUseCoreNext: true);

      salesNotifier.addProduct(testProduct, quantity: 1);
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.creditCard, amount: MoneyCents(1000)),
      ]);

      final result = await adapter.executeCheckout(
        receiptNo: 'REC-CARD-01',
        storeTitle: 'Test Bakkal',
      );

      expect(result.isSuccess, true);
      expect(result.executedEngine, SalesEngineType.coreNext);
      expect(result.payments.first.type, PaymentType.creditCard);
      expect(result.payments.first.amount.value, 1000);
      expect(result.paid?.value, 1000);
      expect(result.debt?.value, 0);
    });

    test('4. Vadeli Satış: Müşteri seçimi ile deftere borç işlenir ve bakiye güncellenir', () async {
      final adapter = SalesEngineAdapter(coreNotifier: salesNotifier, initialUseCoreNext: true);

      salesNotifier.selectCustomer(testCustomer);
      salesNotifier.addProduct(testProduct, quantity: 3); // 30 TL
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(3000)),
      ]);

      final result = await adapter.executeCheckout(
        receiptNo: 'REC-DEBT-01',
        storeTitle: 'Test Bakkal',
      );

      expect(result.isSuccess, true);
      expect(result.debt?.value, 3000);
      expect(result.hasLedgerDebit, true);
      expect(result.customerId, testCustomer.id);

      // Defter teyidi: Müşterinin bakiyesi -30 TL (-3000 kuruş) olmalı
      final cust = await ledgerRepo.getCustomer(testCustomer.id);
      expect(cust?.balance.value, -3000);
    });

    test('5. Karma Ödeme (Split Payment): Nakit + Kart + Vadeli kuruş hassasiyeti', () async {
      final adapter = SalesEngineAdapter(coreNotifier: salesNotifier, initialUseCoreNext: true);

      salesNotifier.selectCustomer(testCustomer);
      salesNotifier.addProduct(testProduct, quantity: 5); // 50 TL (5000 kuruş)
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(2000)),
        const PaymentSplitEntity(type: PaymentType.creditCard, amount: MoneyCents(1500)),
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(1500)),
      ]);

      final result = await adapter.executeCheckout(
        receiptNo: 'REC-KARMA-01',
        storeTitle: 'Test Bakkal',
      );

      expect(result.isSuccess, true);
      expect(result.total?.value, 5000);
      expect(result.paid?.value, 3500); // 20 TL + 15 TL
      expect(result.debt?.value, 1500); // 15 TL borç
      expect(result.hasLedgerDebit, true);

      // Müşteri defteri -15 TL olmalı
      final cust = await ledgerRepo.getCustomer(testCustomer.id);
      expect(cust?.balance.value, -1500);
    });

    test('6. Hata Durumunda Güvenlik: Hata olunca otomatik fallback yapılmaz, hata döner', () async {
      final adapter = SalesEngineAdapter(coreNotifier: salesNotifier, initialUseCoreNext: true);

      // Sepet boş
      final result = await adapter.executeCheckout(
        receiptNo: 'REC-ERROR-01',
        storeTitle: 'Test Bakkal',
      );

      expect(result.isSuccess, false);
      expect(result.executedEngine, SalesEngineType.coreNext);
      expect(result.errorMessage, contains('Sepet boş'));
    });

    test('7. İdempotency Replay: Aynı idempotencyKey ile tekrar çağrıldığında var olan satış döner', () async {
      final adapter = SalesEngineAdapter(coreNotifier: salesNotifier, initialUseCoreNext: true);

      salesNotifier.addProduct(testProduct, quantity: 1);
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(1000)),
      ]);

      final firstResult = await adapter.executeCheckout(
        receiptNo: 'REC-IDEMP-01',
        storeTitle: 'Test Bakkal',
        idempotencyKey: 'idemp-key-99',
      );
      expect(firstResult.isSuccess, true);

      // Sepete tekrar ekle ve aynı idempotencyKey ile çağır
      salesNotifier.addProduct(testProduct, quantity: 1);
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(1000)),
      ]);

      final secondResult = await adapter.executeCheckout(
        receiptNo: 'REC-IDEMP-01',
        storeTitle: 'Test Bakkal',
        idempotencyKey: 'idemp-key-99',
      );

      expect(secondResult.isSuccess, true);
      expect(secondResult.saleId, firstResult.saleId);

      // Stok sadece 1 kez düşmüş olmalı (20 - 1 = 19)
      final pRows = await coreDb.db.query('products', where: 'id = ?', whereArgs: [testProduct.id]);
      expect(pRows.first['stock_quantity'], 19);
    });

    test('8. syncFromCart: Sepet durumunu deterministik aktarır', () async {
      final adapter = SalesEngineAdapter(coreNotifier: salesNotifier, initialUseCoreNext: true);

      adapter.syncFromCart(
        products: [testProduct],
        quantities: {testProduct.id: 4},
        customer: testCustomer,
        discount: const MoneyCents(500), // 5 TL indirim
        paymentSplits: [
          const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(3500)),
        ],
      );

      expect(salesNotifier.state.items.length, 1);
      expect(salesNotifier.state.items.first.quantity, 4);
      expect(salesNotifier.state.generalDiscount.value, 500);
      expect(salesNotifier.state.subtotal.value, 4000);
      expect(salesNotifier.state.total.value, 3500);
      expect(salesNotifier.state.selectedCustomer?.id, testCustomer.id);
    });

    test('9. Koruma: Devam eden işlem varken setFeatureFlag StateError fırlatır', () async {
      final adapter = SalesEngineAdapter(coreNotifier: salesNotifier, initialUseCoreNext: false);
      expect(adapter.isOperationInProgress, false);

      adapter.setFeatureFlag(true);
      expect(adapter.isCoreNextActive, true);
    });
  });
}

