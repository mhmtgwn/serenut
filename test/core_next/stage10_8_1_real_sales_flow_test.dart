// test/core_next/stage10_8_1_real_sales_flow_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/domain/usecases/refund_use_case.dart';
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

  group('Stage 10.8.1 — Gerçek Satış Akışı, SQLite Atomik Transaction ve Ticari Kurallar', () {
    late CoreAppDatabase coreDb;
    late SqliteLedgerRepository ledgerRepo;
    late LedgerService ledgerService;
    late HardwareWorker hardwareWorker;
    late CoreCheckoutUseCase checkoutUseCase;
    late CoreSalesFlowNotifier salesNotifier;
    late SalesEngineAdapter adapter;

    final productEkmek = ProductEntity(
      id: 'prod-ekmek',
      barcode: '8690001',
      name: 'Tam Buğday Ekmeği',
      price: const MoneyCents(1500), // 15,00 TL
      stockQuantity: 100,
      updatedAt: DateTime.now(),
    );

    final productZeytin = ProductEntity(
      id: 'prod-zeytin',
      barcode: '8690002',
      name: 'Gemlik Zeytini (kg)',
      price: const MoneyCents(24000), // 240,00 TL / kg
      stockQuantity: 50000, // 50 kg
      updatedAt: DateTime.now(),
    );

    final customerAhmet = CustomerEntity(
      id: 'cust-ahmet',
      name: 'Ahmet Yılmaz',
      balance: MoneyCents.zero,
      creditLimit: const MoneyCents(200000), // 2.000,00 TL
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

      adapter = SalesEngineAdapter(
        coreNotifier: salesNotifier,
        initialUseCoreNext: true,
        defaultActor: ActorContext.testManager,
      );

      // Ürünleri gerçek SQLite veritabanına ekle
      await coreDb.db.insert('products', {
        'id': productEkmek.id,
        'barcode': productEkmek.barcode,
        'name': productEkmek.name,
        'price_cents': productEkmek.price.value,
        'vat_rate': 1,
        'unit': 'piece',
        'stock_quantity': productEkmek.stockQuantity,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('products', {
        'id': productZeytin.id,
        'barcode': productZeytin.barcode,
        'name': productZeytin.name,
        'price_cents': productZeytin.price.value,
        'vat_rate': 10,
        'unit': 'kg',
        'stock_quantity': productZeytin.stockQuantity,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Müşteriyi gerçek SQLite veritabanına ekle
      await coreDb.db.insert('customers', {
        'id': customerAhmet.id,
        'name': customerAhmet.name,
        'balance_cents': customerAhmet.balance.value,
        'credit_limit_cents': customerAhmet.creditLimit.value,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      await hardwareWorker.dispose();
      await coreDb.close();
    });

    test('1. Tam Nakit Satış: Satış, Kalem, Kasa ve Outbox atomik olarak oluşturulur', () async {
      salesNotifier.addProduct(productEkmek, quantity: 2); // 30,00 TL
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(3000)),
      ]);

      final result = await adapter.executeCheckout(
        receiptNo: 'REC-CASH-001',
        storeTitle: 'Test Bakkaliye',
      );

      expect(result.isSuccess, true);
      expect(result.total?.value, 3000);
      expect(result.paid?.value, 3000);
      expect(result.debt?.value, 0);

      // SQLite Tablo Kontrolleri:
      final sales = await coreDb.db.query('sales', where: 'id = ?', whereArgs: [result.saleId]);
      expect(sales.length, 1);
      expect(sales.first['total_cents'], 3000);
      expect(sales.first['paid_cents'], 3000);
      expect(sales.first['debt_cents'], 0);

      final items = await coreDb.db.query('sale_items', where: 'sale_id = ?', whereArgs: [result.saleId]);
      expect(items.length, 1);
      expect(items.first['quantity'], 2);

      final payments = await coreDb.db.query('sale_payments', where: 'sale_id = ?', whereArgs: [result.saleId]);
      expect(payments.length, 1);
      expect(payments.first['payment_type'], 'cash');
      expect(payments.first['amount_cents'], 3000);

      final cashTx = await coreDb.db.query('cash_transactions', where: 'category = ?', whereArgs: ['SALE']);
      expect(cashTx.length, 1);
      expect(cashTx.first['amount_cents'], 3000);

      final syncEvents = await coreDb.db.query('sync_events', where: 'entity_id = ?', whereArgs: [result.saleId]);
      expect(syncEvents.length, 1);

      // Stok: 100 - 2 = 98
      final prod = await coreDb.db.query('products', where: 'id = ?', whereArgs: [productEkmek.id]);
      expect(prod.first['stock_quantity'], 98);
    });

    test('2. Tam Kart Satışı: Kredi kartı tahsilatı ve sıfır kasa nakit hareketi', () async {
      salesNotifier.addProduct(productEkmek, quantity: 1); // 15,00 TL
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.creditCard, amount: MoneyCents(1500)),
      ]);

      final result = await adapter.executeCheckout(
        receiptNo: 'REC-CARD-001',
        storeTitle: 'Test Bakkaliye',
      );

      expect(result.isSuccess, true);
      expect(result.payments.first.type, PaymentType.creditCard);

      // Kart satışında nakit kasa girişi olmamalı
      final cashTx = await coreDb.db.query('cash_transactions', where: 'category = ?', whereArgs: ['SALE']);
      expect(cashTx.isEmpty, true);
    });

    test('3. Tam Vadeli Satış: Müşteri seçimi ile çift taraflı defter (customer_ledger) kaydı', () async {
      salesNotifier.selectCustomer(customerAhmet);
      salesNotifier.addProduct(productEkmek, quantity: 4); // 60,00 TL
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(6000)),
      ]);

      final result = await adapter.executeCheckout(
        receiptNo: 'REC-DEBT-001',
        storeTitle: 'Test Bakkaliye',
      );

      expect(result.isSuccess, true);
      expect(result.debt?.value, 6000);
      expect(result.hasLedgerDebit, true);

      // Müşteri bakiyesi -60,00 TL (-6000 kuruş) olmalı
      final cust = await ledgerRepo.getCustomer(customerAhmet.id);
      expect(cust?.balance.value, -6000);

      // Defterde satır oluşmalı
      final ledgerHistory = await ledgerRepo.getCustomerLedgerHistory(customerAhmet.id);
      expect(ledgerHistory.length, 1);
      expect(ledgerHistory.first.entryType, LedgerEntryType.debitSale);
      expect(ledgerHistory.first.amount.value, 6000);
      expect(ledgerHistory.first.balanceAfter.value, -6000);
    });

    test('4. Karma Ödeme (Nakit + Kart + Vadeli): Kuruş denkliği ve çoklu ödeme kaydı', () async {
      salesNotifier.selectCustomer(customerAhmet);
      salesNotifier.addProduct(productEkmek, quantity: 10); // 150,00 TL (15.000 kuruş)
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(5000)),       // 50 TL
        const PaymentSplitEntity(type: PaymentType.creditCard, amount: MoneyCents(6000)), // 60 TL
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(4000)),  // 40 TL
      ]);

      final result = await adapter.executeCheckout(
        receiptNo: 'REC-SPLIT-001',
        storeTitle: 'Test Bakkaliye',
      );

      expect(result.isSuccess, true);
      expect(result.total?.value, 15000);
      expect(result.paid?.value, 11000);
      expect(result.debt?.value, 4000);

      final payments = await coreDb.db.query('sale_payments', where: 'sale_id = ?', whereArgs: [result.saleId]);
      expect(payments.length, 3);

      final cust = await ledgerRepo.getCustomer(customerAhmet.id);
      expect(cust?.balance.value, -4000);
    });

    test('5. Hata Enjeksiyonu ve SQLite Rollback: Transaction kesildiğinde veritabanı kirlenmez', () async {
      final faultDb = await CoreAppDatabase.open(inMemoryOrCustomPath: inMemoryDatabasePath);
      final faultLedgerRepo = SqliteLedgerRepository(faultDb.db);
      final faultLedgerService = LedgerService(faultLedgerRepo);

      // Kalemler eklendikten sonra hata fırlatan hook
      final faultCheckoutUseCase = CoreCheckoutUseCase(
        db: faultDb,
        ledgerService: faultLedgerService,
        hardwareWorker: hardwareWorker,
        defaultActor: ActorContext.testManager,
        faultHook: (step) async {
          if (step == 'after_items_insert') {
            throw Exception('SIMULATED_POWER_FAILURE_MID_TRANSACTION');
          }
        },
      );

      final faultNotifier = CoreSalesFlowNotifier(faultCheckoutUseCase, defaultActor: ActorContext.testManager);
      final faultAdapter = SalesEngineAdapter(coreNotifier: faultNotifier, initialUseCoreNext: true);

      // Veritabanına test ürünü koy
      await faultDb.db.insert('products', {
        'id': 'p-fault',
        'barcode': '999',
        'name': 'Hata Testi',
        'price_cents': 1000,
        'vat_rate': 1,
        'unit': 'piece',
        'stock_quantity': 50,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      faultNotifier.addProduct(
        ProductEntity(id: 'p-fault', barcode: '999', name: 'Hata Testi', price: const MoneyCents(1000), updatedAt: DateTime.now()),
        quantity: 2,
      );
      faultNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(2000)),
      ]);

      final result = await faultAdapter.executeCheckout(
        receiptNo: 'REC-FAULT-001',
        storeTitle: 'Test',
      );

      expect(result.isSuccess, false);
      expect(result.errorMessage, contains('SIMULATED_POWER_FAILURE'));

      // ROLLBACK TEYİDİ: Veritabanında 0 kirli kayıt kalmalıdır
      final sales = await faultDb.db.query('sales');
      expect(sales.isEmpty, true);

      final items = await faultDb.db.query('sale_items');
      expect(items.isEmpty, true);

      final payments = await faultDb.db.query('sale_payments');
      expect(payments.isEmpty, true);

      final events = await faultDb.db.query('sync_events');
      expect(events.isEmpty, true);

      // Stok değişmemeli (50 olarak kalmalı)
      final prod = await faultDb.db.query('products', where: 'id = ?', whereArgs: ['p-fault']);
      expect(prod.first['stock_quantity'], 50);

      await faultDb.close();
    });

    test('6. İdempotency Koruması: Aynı anahtarla tekrar istek tek satış ve tek stok düşümü üretir', () async {
      salesNotifier.addProduct(productEkmek, quantity: 3); // 45,00 TL
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(4500)),
      ]);

      final call1 = await adapter.executeCheckout(
        receiptNo: 'REC-REPLAY-001',
        storeTitle: 'Test Bakkaliye',
        idempotencyKey: 'idemp-replay-token-42',
      );
      expect(call1.isSuccess, true);

      // Tekrar sepete ekle ve aynı anahtarla ikinci kez submit et
      salesNotifier.addProduct(productEkmek, quantity: 3);
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(4500)),
      ]);

      final call2 = await adapter.executeCheckout(
        receiptNo: 'REC-REPLAY-001',
        storeTitle: 'Test Bakkaliye',
        idempotencyKey: 'idemp-replay-token-42',
      );

      expect(call2.isSuccess, true);
      expect(call2.saleId, call1.saleId);

      // Stok sadece bir kez 3 adet düşmüş olmalı (100 - 3 = 97)
      final prod = await coreDb.db.query('products', where: 'id = ?', whereArgs: [productEkmek.id]);
      expect(prod.first['stock_quantity'], 97);

      // Toplam satış sayısı tam 1 olmalı
      final allSales = await coreDb.db.query('sales');
      expect(allSales.length, 1);
    });

    test('7. İade Use-Case (CoreRefundUseCase): Satış iade edildiğinde stok geri yüklenir ve deftere alacak işlenir', () async {
      // 1. Önce vadeli bir satış yap
      salesNotifier.selectCustomer(customerAhmet);
      salesNotifier.addProduct(productEkmek, quantity: 2); // 30,00 TL
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(3000)),
      ]);

      final saleResult = await adapter.executeCheckout(
        receiptNo: 'REC-REFUND-001',
        storeTitle: 'Test Bakkaliye',
      );
      expect(saleResult.isSuccess, true);

      // Stok 98 oldu, müşteri -30,00 TL oldu
      var prod = await coreDb.db.query('products', where: 'id = ?', whereArgs: [productEkmek.id]);
      expect(prod.first['stock_quantity'], 98);

      var cust = await ledgerRepo.getCustomer(customerAhmet.id);
      expect(cust?.balance.value, -3000);

      // 2. Satışı İade Et (CoreRefundUseCase)
      final refundUseCase = CoreRefundUseCase(
        db: coreDb,
        ledgerService: ledgerService,
      );

      final refundResult = await refundUseCase.execute(
        RefundRequest(
          originalSaleId: saleResult.saleId!,
          reason: 'Müşteri vazgeçti',
          actor: ActorContext.testManager,
          paymentDistributions: [
            const RefundPaymentSplit(type: PaymentType.onAccount, amount: MoneyCents(3000)),
          ],
        ),
      );

      expect(refundResult.refundedItems.length, 1);
      expect(refundResult.refundTotal.value, 3000);

      // Stok geri yüklendi mi: 98 + 2 = 100 olmalı
      prod = await coreDb.db.query('products', where: 'id = ?', whereArgs: [productEkmek.id]);
      expect(prod.first['stock_quantity'], 100);

      // Müşteri borcu sıfırlandı mı: -30 + 30 = 0 olmalı
      cust = await ledgerRepo.getCustomer(customerAhmet.id);
      expect(cust?.balance.value, 0);
    });

    test('8. Geçersiz Satış Kuralları: Boş sepet, negatif tutar, müşterisiz vadeli işlem reddedilir', () async {
      // A. Boş sepet
      var res = await adapter.executeCheckout(receiptNo: 'ERR-1', storeTitle: 'Test');
      expect(res.isSuccess, false);
      expect(res.errorMessage, contains('Sepet boş'));

      // B. Müşterisiz vadeli satış
      salesNotifier.addProduct(productEkmek, quantity: 1);
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(1500)),
      ]);
      res = await adapter.executeCheckout(receiptNo: 'ERR-2', storeTitle: 'Test');
      expect(res.isSuccess, false);
      expect(res.errorMessage, contains('müşteri seçilmelidir'));
    });
  });
}
