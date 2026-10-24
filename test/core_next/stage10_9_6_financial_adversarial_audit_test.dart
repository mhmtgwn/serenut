// test/core_next/stage10_9_6_financial_adversarial_audit_test.dart
// SERENUT OS — STAGE 10.9.6
// Adversarial Financial Integrity, Refund, Ledger, Stock & Outbox Atomicity Audit

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/domain/usecases/refund_use_case.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late CoreAppDatabase coreDb;
  late SqliteLedgerRepository ledgerRepo;
  late LedgerService ledgerService;
  late HardwareWorker hardwareWorker;
  final uuid = const Uuid();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stage10_9_6_adv_test_');
    dbPath = p.join(tempDir.path, 'serenut_core_test.db');
    coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: dbPath);
    ledgerRepo = SqliteLedgerRepository(coreDb.db);
    ledgerService = LedgerService(ledgerRepo);
    hardwareWorker = HardwareWorker();
    await hardwareWorker.initialize();
  });

  tearDown(() async {
    await hardwareWorker.dispose();
    await coreDb.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> seedInitialData({
    int initialStock = 100,
    int initialBalanceCents = 0,
    int creditLimitCents = 50000,
  }) async {
    await coreDb.db.insert('categories', {
      'id': 'cat-icecek',
      'name': 'İçecekler',
      'color_hex': '#00FF00',
      'sort_order': 1,
      'is_active': 1,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    await coreDb.db.insert('products', {
      'id': 'prod-kahve',
      'barcode': '8690001001',
      'name': 'Filtre Kahve',
      'category_id': 'cat-icecek',
      'price_cents': 10000, // 100.00 TL
      'cost_price_cents': 6000,
      'vat_rate': 20,
      'unit': 'piece',
      'stock_quantity': initialStock,
      'critical_threshold': 5,
      'is_active': 1,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    await coreDb.db.insert('products', {
      'id': 'prod-su',
      'barcode': '8690001002',
      'name': 'Su 500ml',
      'category_id': 'cat-icecek',
      'price_cents': 1000, // 10.00 TL
      'cost_price_cents': 500,
      'vat_rate': 10,
      'unit': 'piece',
      'stock_quantity': 50,
      'critical_threshold': 5,
      'is_active': 1,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    await coreDb.db.insert('customers', {
      'id': 'cust-veli',
      'name': 'Veli Can',
      'phone': '05551112233',
      'balance_cents': initialBalanceCents,
      'credit_limit_cents': creditLimitCents,
      'is_active': 1,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  group('STAGE 10.9.6 — B1 & B2: Satış ve Karma Ödeme Bütünlüğü Testleri', () {
    test('1. Karma Ödeme (33.33 Nakit + 33.33 Kart + 33.34 İkinci Kart = 100.00 TL) Kuruşu Kuruşuna Eşleşir', () async {
      await seedInitialData(initialStock: 10);

      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        hardwareWorker: hardwareWorker,
        ledgerService: ledgerService,
        defaultActor: ActorContext.testManager,
      );

      final salesNotifier = CoreSalesFlowNotifier(checkoutUseCase);

      final pKahve = ProductEntity(
        id: 'prod-kahve',
        name: 'Filtre Kahve',
        barcode: '8690001001',
        price: const MoneyCents(10000), // 100.00 TL
        costPrice: const MoneyCents(6000),
        vatRate: 20,
        stockQuantity: 10,
        updatedAt: DateTime.now(),
      );

      // 1 adet 100.00 TL kahve ekle
      salesNotifier.addProduct(pKahve);

      // Karma Ödeme Dağılımı: 3333 + 3333 + 3334 = 10000 kuruş
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(3333)),
        const PaymentSplitEntity(type: PaymentType.creditCard, amount: MoneyCents(3333)),
        const PaymentSplitEntity(type: PaymentType.creditCard, amount: MoneyCents(3334)),
      ]);

      expect(salesNotifier.state.paidTotal.value, 10000);
      expect(salesNotifier.state.total.value, 10000);
      expect(salesNotifier.state.debtTotal.value, 0);

      final receiptNo = 'REC-ADV-1001';
      final order = await salesNotifier.completeCheckout(
        receiptNo: receiptNo,
        storeTitle: 'Serenut Test Store',
      );

      expect(order.total.value, 10000);
      expect(order.paid.value, 10000);
      expect(order.debt.value, 0);

      // Veritabanı doğrulaması
      final saleRows = await coreDb.db.query('sales', where: 'id = ?', whereArgs: [order.id]);
      expect(saleRows.first['total_cents'], 10000);
      expect(saleRows.first['paid_cents'], 10000);

      // sale_payments toplamı tam 10000 kuruş olmalı
      final payments = await coreDb.db.query('sale_payments', where: 'sale_id = ?', whereArgs: [order.id]);
      expect(payments.length, 3);
      final sumPayments = payments.fold<int>(0, (s, p) => s + (p['amount_cents'] as num).toInt());
      expect(sumPayments, 10000);

      // Nakit kasa girişi tam 3333 kuruş olmalı
      final cashTxs = await coreDb.db.query('cash_transactions', where: 'description LIKE ?', whereArgs: ['%$receiptNo%']);
      expect(cashTxs.length, 1);
      expect(cashTxs.first['amount_cents'], 3333);

      // Stok 10'dan 9'a düşmeli
      final prodRows = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve']);
      expect(prodRows.first['stock_quantity'], 9);

      // sync_events outbox kuyruğuna 1 adet sale mutasyonu yazılmalı
      final syncEvents = await coreDb.db.query('sync_events', where: 'group_id = ?', whereArgs: [order.id]);
      expect(syncEvents.length, 1);
      expect(syncEvents.first['entity_type'], 'sale');
    });

    test('2. Eksik Ödeme, Fazla Ödeme veya Negatif Parça Anında Reddedilir (Fail-Closed Invariant)', () async {
      await seedInitialData(initialStock: 10);

      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        hardwareWorker: hardwareWorker,
        ledgerService: ledgerService,
        defaultActor: ActorContext.testManager,
      );

      final salesNotifier = CoreSalesFlowNotifier(checkoutUseCase);

      final pKahve = ProductEntity(
        id: 'prod-kahve',
        name: 'Filtre Kahve',
        barcode: '8690001001',
        price: const MoneyCents(10000),
        costPrice: const MoneyCents(6000),
        vatRate: 20,
        stockQuantity: 10,
        updatedAt: DateTime.now(),
      );

      salesNotifier.addProduct(pKahve);

      // A) Negatif ödeme parçası
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(-500)),
      ]);
      expect(
        () => salesNotifier.completeCheckout(
          receiptNo: 'REC-NEG',
          storeTitle: 'Store',
        ),
        throwsA(isA<StateError>()),
      );

      // B) Eksik ödeme parçası toplamı (9999 kuruş != 10000 kuruş)
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(9999)),
      ]);
      expect(
        () => salesNotifier.completeCheckout(
          receiptNo: 'REC-UNDER',
          storeTitle: 'Store',
        ),
        throwsA(isA<StateError>()),
      );

      // C) Fazla ödeme (10001 kuruş > 10000 kuruş)
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(10001)),
      ]);
      expect(
        () => salesNotifier.completeCheckout(
          receiptNo: 'REC-OVER',
          storeTitle: 'Store',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('3. Stok Yetersizliğinde Satış Tamamen İptal Edilir ve Sıfır Sızıntı (Zero Partial Insert) Olur', () async {
      await seedInitialData(initialStock: 2); // Sadece 2 adet stok var

      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        hardwareWorker: hardwareWorker,
        ledgerService: ledgerService,
        defaultActor: ActorContext.testManager,
      );

      final salesNotifier = CoreSalesFlowNotifier(checkoutUseCase);

      final pKahve = ProductEntity(
        id: 'prod-kahve',
        name: 'Filtre Kahve',
        barcode: '8690001001',
        price: const MoneyCents(10000),
        costPrice: const MoneyCents(6000),
        vatRate: 20,
        stockQuantity: 2,
        updatedAt: DateTime.now(),
      );

      // Sepete 5 adet ekle (stok 2)
      salesNotifier.addProduct(pKahve, quantity: 5);

      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(50000)),
      ]);

      expect(
        () => salesNotifier.completeCheckout(
          receiptNo: 'REC-FAIL-STOCK',
          storeTitle: 'Store',
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'msg', contains('Yetersiz stok'))),
      );

      // Veritabanında hiçbir satış veya ödeme kalmamalıdır (ACID Rollback)
      final sales = await coreDb.db.query('sales');
      expect(sales.isEmpty, true);
      final payments = await coreDb.db.query('sale_payments');
      expect(payments.isEmpty, true);
      final syncEvents = await coreDb.db.query('sync_events');
      expect(syncEvents.isEmpty, true);

      // Stok 2 olarak korunmalıdır
      final prods = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve']);
      expect(prods.first['stock_quantity'], 2);
    });

    test('4. İdempotency Koruması: Aynı İstek Tekrarlanırsa Mükerrer Satış ve Stok Düşüşü Yapılmaz', () async {
      await seedInitialData(initialStock: 10);

      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        hardwareWorker: hardwareWorker,
        ledgerService: ledgerService,
        defaultActor: ActorContext.testManager,
      );

      final salesNotifier = CoreSalesFlowNotifier(checkoutUseCase);

      final pKahve = ProductEntity(
        id: 'prod-kahve',
        name: 'Filtre Kahve',
        barcode: '8690001001',
        price: const MoneyCents(10000),
        costPrice: const MoneyCents(6000),
        vatRate: 20,
        stockQuantity: 10,
        updatedAt: DateTime.now(),
      );

      salesNotifier.addProduct(pKahve);
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(10000)),
      ]);

      // 1. Çağrı
      final order1 = await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: salesNotifier.state,
          receiptNo: 'REC-IDEMP-1',
          storeTitle: 'Store',
          idempotencyKey: 'key-idemp-unique-123',
          actor: ActorContext.testManager,
        ),
      );
      expect(order1.receiptNo, 'REC-IDEMP-1');

      // 2. Çağrı (Birebir aynı istek ve aynı idempotency key)
      final order2 = await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: salesNotifier.state,
          receiptNo: 'REC-IDEMP-1',
          storeTitle: 'Store',
          idempotencyKey: 'key-idemp-unique-123',
          actor: ActorContext.testManager,
        ),
      );
      expect(order2.id, order1.id);
      expect(order2.receiptNo, order1.receiptNo);

      // Satışlar tek kayıt olmalıdır
      final sales = await coreDb.db.query('sales');
      expect(sales.length, 1);

      // Stok 10'dan yalnızca 1 kez düşmüş olup 9 kalmalıdır
      final prods = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve']);
      expect(prods.first['stock_quantity'], 9);

      // C) Aynı idempotency anahtarıyla farklı sepette istek gönderilirse CONFLICT fırlatılır
      salesNotifier.addProduct(pKahve); // 2 adet oldu
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(20000)),
      ]);

      expect(
        () => checkoutUseCase.execute(
          CheckoutRequest(
            flowState: salesNotifier.state,
            receiptNo: 'REC-IDEMP-1',
            idempotencyKey: 'key-idemp-unique-123',
            storeTitle: 'Store',
            actor: ActorContext.testManager,
          ),
        ),
        throwsA(isA<StateError>().having((e) => e.message.toLowerCase(), 'msg', contains('çakışma'))),
      );
    });
  });

  group('STAGE 10.9.6 — C: İade ve Stok Güvenliği Testleri', () {
    test('5. Kısmi İade Stoğu Tam Geri Ekler ve Satılan Miktar Aşılamaz', () async {
      await seedInitialData(initialStock: 10);

      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        hardwareWorker: hardwareWorker,
        ledgerService: ledgerService,
        defaultActor: ActorContext.testManager,
      );

      final salesNotifier = CoreSalesFlowNotifier(checkoutUseCase);

      final pKahve = ProductEntity(
        id: 'prod-kahve',
        name: 'Filtre Kahve',
        barcode: '8690001001',
        price: const MoneyCents(10000),
        costPrice: const MoneyCents(6000),
        vatRate: 20,
        stockQuantity: 10,
        updatedAt: DateTime.now(),
      );

      // 5 adet sat: Stok 10 -> 5
      salesNotifier.addProduct(pKahve, quantity: 5);
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(50000)),
      ]);

      final sale = await salesNotifier.completeCheckout(
        receiptNo: 'REC-REFUND-SALE',
        storeTitle: 'Store',
      );

      final prodAfterSale = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve']);
      expect(prodAfterSale.first['stock_quantity'], 5);

      final refundUseCase = CoreRefundUseCase(db: coreDb, ledgerService: ledgerService);

      // 1. Kısmi İade: 2 adet iade et (Kalan iade edilebilir: 3)
      final ref1 = await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: ActorContext.testManager,
          idempotencyKey: 'ref-idemp-1',
          items: [
            const RefundItemRequest(productId: 'prod-kahve', quantity: 2),
          ],
        ),
      );
      expect(ref1.refundTotal.value, 20000); // 2 * 100.00 TL = 200.00 TL

      // Stok 5 + 2 = 7 olmalıdır
      final prodAfterRef1 = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve']);
      expect(prodAfterRef1.first['stock_quantity'], 7);

      // 2. Kalan miktardan fazlasını (4 adet) iade etmeye kalkışırsak patlamalıdır
      expect(
        () => refundUseCase.execute(
          RefundRequest(
            originalSaleId: sale.id,
            actor: ActorContext.testManager,
            idempotencyKey: 'ref-idemp-excess',
            items: [
              const RefundItemRequest(productId: 'prod-kahve', quantity: 4),
            ],
          ),
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'msg', contains('kalan iade edilebilir miktarı (3) aşamaz'))),
      );

      // Stok 7 kalmaya devam etmelidir (Hiçbir sızıntı yok)
      final prodAfterExcess = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve']);
      expect(prodAfterExcess.first['stock_quantity'], 7);

      // 3. Kalan tam 3 adedi iade et (İade tamamlanır)
      final ref2 = await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: ActorContext.testManager,
          idempotencyKey: 'ref-idemp-2',
          items: [
            const RefundItemRequest(productId: 'prod-kahve', quantity: 3),
          ],
        ),
      );
      expect(ref2.refundTotal.value, 30000);

      // Stok tam orijinal değerine (10) dönmelidir
      final prodFinal = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve']);
      expect(prodFinal.first['stock_quantity'], 10);
    });
  });

  group('STAGE 10.9.6 — D: Ledger ve Müşteri Bakiyesi Mutabakatı', () {
    test('6. Vadeli Satış, Tahsilat ve İade Defter Hareketleri ile customers.balance_cents Kuruşu Kuruşuna Eşleşir', () async {
      await seedInitialData(initialStock: 10, initialBalanceCents: 0, creditLimitCents: 50000);

      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        hardwareWorker: hardwareWorker,
        ledgerService: ledgerService,
        defaultActor: ActorContext.testManager,
      );

      final salesNotifier = CoreSalesFlowNotifier(checkoutUseCase);

      final customer = CustomerEntity(
        id: 'cust-veli',
        name: 'Veli Can',
        phone: '05551112233',
        balance: const MoneyCents(0),
        creditLimit: const MoneyCents(50000),
        updatedAt: DateTime.now(),
      );

      final pKahve = ProductEntity(
        id: 'prod-kahve',
        name: 'Filtre Kahve',
        barcode: '8690001001',
        price: const MoneyCents(10000), // 100.00 TL
        costPrice: const MoneyCents(6000),
        vatRate: 20,
        stockQuantity: 10,
        updatedAt: DateTime.now(),
      );

      // 1. Adım: 100.00 TL'lik Veresiye (Vadeli) Satış
      salesNotifier.addProduct(pKahve);
      salesNotifier.selectCustomer(customer);
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(10000)),
      ]);

      expect(salesNotifier.state.debtTotal.value, 10000);
      expect(salesNotifier.state.paidTotal.value, 0);

      final sale = await salesNotifier.completeCheckout(
        receiptNo: 'REC-DEBT-1',
        storeTitle: 'Store',
      );

      // Müşterinin bakiyesi -10000 kuruş (100.00 TL borç) olmalı
      final custRows1 = await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['cust-veli']);
      expect(custRows1.first['balance_cents'], -10000);

      // Defterde 1 adet debitSale kaydı olmalı
      final ledger1 = await coreDb.db.query('ledger_entries', where: 'customer_id = ?', whereArgs: ['cust-veli']);
      expect(ledger1.length, 1);
      expect(ledger1.first['entry_type'], 'debitSale');
      expect(ledger1.first['amount_cents'], 10000);
      expect(ledger1.first['balance_after_cents'], -10000);

      // 2. Adım: 40.00 TL Tahsilat (postCollection)
      await ledgerService.postCollection(
        entryId: uuid.v4(),
        customerId: 'cust-veli',
        collectionAmount: const MoneyCents(4000),
        description: 'Nakit Kısmi Tahsilat',
        timestamp: DateTime.now(),
      );

      // Bakiye -10000 + 4000 = -6000 kuruş (60.00 TL borç) olmalı
      final custRows2 = await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['cust-veli']);
      expect(custRows2.first['balance_cents'], -6000);

      // 3. Adım: Veresiye Satışın İadesi (postRefund)
      final refundUseCase = CoreRefundUseCase(db: coreDb, ledgerService: ledgerService);
      await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: ActorContext.testManager,
          idempotencyKey: 'ref-on-account-1',
          paymentDistributions: [
            const RefundPaymentSplit(type: PaymentType.onAccount, amount: MoneyCents(10000)),
          ],
        ),
      );

      // İade sonrası müşteri bakiyesi ve defter kontrolü
      final custRows3 = await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['cust-veli']);
      // 100 TL borçlanmıştı, 40 TL ödemişti (-60 TL idi). 100 TL veresiye borcu iptal/iade edildiğinde
      // müşterinin bakiyesi 4000 kuruş (+40.00 TL alacaklı) olur.
      expect(custRows3.first['balance_cents'], 4000);

      // Defterdeki tüm hareketlerin sonuncusu customers.balance_cents ile birebir eşleşmeli
      final allLedger = await coreDb.db.query('ledger_entries', where: 'customer_id = ?', whereArgs: ['cust-veli'], orderBy: 'created_at ASC');
      expect(allLedger.last['balance_after_cents'], 4000);
    });
  });

  group('STAGE 10.9.6 — E: Outbox ve Transaction Atomikliği Testi', () {
    test('7. Outbox Kaydında veya İşlem Ortasında Hata Meydana Gelirse Sıfır Veri Sızıntısı ile Geri Alınır', () async {
      await seedInitialData(initialStock: 10);

      // faultHook ile 'after_sales_insert' adımından sonra kasıtlı hata fırlatalım
      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        hardwareWorker: hardwareWorker,
        ledgerService: ledgerService,
        defaultActor: ActorContext.testManager,
        faultHook: (step) async {
          if (step == 'after_sales_insert') {
            throw const SocketException('Simulated Crash during checkout transaction');
          }
        },
      );

      final salesNotifier = CoreSalesFlowNotifier(checkoutUseCase);

      final pKahve = ProductEntity(
        id: 'prod-kahve',
        name: 'Filtre Kahve',
        barcode: '8690001001',
        price: const MoneyCents(10000),
        costPrice: const MoneyCents(6000),
        vatRate: 20,
        stockQuantity: 10,
        updatedAt: DateTime.now(),
      );

      salesNotifier.addProduct(pKahve);
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(10000)),
      ]);

      expect(
        () => salesNotifier.completeCheckout(
          receiptNo: 'REC-CRASH-TEST',
          storeTitle: 'Store',
        ),
        throwsA(isA<SocketException>()),
      );

      // Transaction tamamen geri alınmış (Rollback) olmalı:
      final sales = await coreDb.db.query('sales');
      expect(sales.isEmpty, true, reason: 'Satış başlığı silinmelidir.');

      final items = await coreDb.db.query('sale_items');
      expect(items.isEmpty, true, reason: 'Satış kalemleri silinmelidir.');

      final syncEvents = await coreDb.db.query('sync_events');
      expect(syncEvents.isEmpty, true, reason: 'Outbox kuyruğuna yetim kayıt kalmamalıdır.');

      final prods = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-kahve']);
      expect(prods.first['stock_quantity'], 10, reason: 'Stok düşümü geri alınmalıdır.');
    });
  });
}
