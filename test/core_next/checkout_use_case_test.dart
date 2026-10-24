// test/core_next/checkout_use_case_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_state.dart';


void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late CoreAppDatabase coreDb;
  late SqliteLedgerRepository ledgerRepo;
  late LedgerService ledgerService;
  late HardwareWorker hardwareWorker;
  late CoreCheckoutUseCase checkoutUseCase;
  late CoreSalesFlowNotifier salesNotifier;

  setUp(() async {
    // 1. Temiz veritabanı aç
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

    salesNotifier = CoreSalesFlowNotifier(checkoutUseCase);

    // 2. Test Ürünlerini Veritabanına Ekle
    await coreDb.db.insert('products', {
      'id': 'p-ekmek',
      'barcode': '111',
      'name': 'Köy Ekmeği',
      'price_cents': 1500, // 15 TL
      'vat_rate': 1,
      'unit': 'piece',
      'stock_quantity': 50,
      'is_active': 1,
      'is_deleted': 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    await coreDb.db.insert('products', {
      'id': 'p-peynir',
      'barcode': '222',
      'name': 'Köy Peyniri (Tartılı)',
      'price_cents': 20000, // 200 TL/kg
      'vat_rate': 10,
      'unit': 'kg',
      'stock_quantity': 10000, // 10 kg
      'is_active': 1,
      'is_deleted': 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    // 3. Test Müşterisi Ekle
    await coreDb.db.insert('customers', {
      'id': 'c-ali',
      'name': 'Ali Usta',
      'phone': '05551112233',
      'balance_cents': 0,
      'credit_limit_cents': 50000, // 500 TL limit
      'is_active': 1,
      'is_deleted': 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  });

  tearDown(() async {
    await hardwareWorker.dispose();
    await coreDb.close();
  });

  group('Kasa Satış ve Checkout Akışı (CoreCheckoutUseCase & Notifier) Tests', () {
    test('Senaryo 1: Standart Nakit Satışta stoklar düşmeli ve satış kaydedilmelidir', () async {
      final pEkmek = ProductEntity(
        id: 'p-ekmek',
        barcode: '111',
        name: 'Köy Ekmeği',
        price: MoneyCents(1500),
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      // 2 adet ekmek sepete ekle
      salesNotifier.addProduct(pEkmek, quantity: 2);
      expect(salesNotifier.state.subtotal.value, 3000); // 30 TL
      expect(salesNotifier.state.total.value, 3000);

      // 30 TL nakit ödeme
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(3000)),
      ]);

      // Satışı tamamla
      final saleOrder = await salesNotifier.completeCheckout(
        receiptNo: '2026-0001',
        storeTitle: 'Test Bakkal',
      );

      expect(saleOrder.receiptNo, '2026-0001');
      expect(saleOrder.total.value, 3000);
      expect(salesNotifier.state.items.isEmpty, true); // Sepet sıfırlandı

      // Stok kontrolü: 50 - 2 = 48 kalmalı
      final productRows = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-ekmek']);
      expect(productRows.first['stock_quantity'], 48);

      // Satış tablosu kontrolü
      final saleRows = await coreDb.db.query('sales', where: 'receipt_no = ?', whereArgs: ['2026-0001']);
      expect(saleRows.length, 1);
      expect(saleRows.first['paid_cents'], 3000);
    });

    test('Senaryo 2: Tartılı Teraziden gelen 450 gram peynir kuruşu kuruşuna doğru hesaplanmalıdır', () async {
      final pPeynir = ProductEntity(
        id: 'p-peynir',
        barcode: '222',
        name: 'Köy Peyniri (Tartılı)',
        price: MoneyCents(20000), // 200 TL/kg
        stockQuantity: 10000,
        updatedAt: DateTime.now(),
      );

      // 450 gram sepete ekle (200 TL * 0.450 = 90.00 TL = 9000 kuruş)
      salesNotifier.addWeighedProduct(pPeynir, 450);
      expect(salesNotifier.state.total.value, 9000);
      expect(salesNotifier.state.total.formatTL(), '90,00 ₺');

      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.creditCard, amount: MoneyCents(9000)),
      ]);

      final saleOrder = await salesNotifier.completeCheckout(
        receiptNo: '2026-0002',
        storeTitle: 'Test Bakkal',
      );

      expect(saleOrder.total.value, 9000);
      // Stoktan 450 gram düşmeli: 10000 - 450 = 9550
      final productRows = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-peynir']);
      expect(productRows.first['stock_quantity'], 9550);
    });

    test('Senaryo 2B: Tartılı Terazi ticari yarım-yukarı yuvarlama sınır testleri (1g, 10g, 100g, 300g, 500g, 999g, 1000g)', () {
      // Birim fiyat: 33,33 TL/kg = 3333 kuruş/kg
      final pTartili = ProductEntity(
        id: 'p-scale-test',
        barcode: '333',
        name: 'Dökme Zeytin',
        price: const MoneyCents(3333),
        stockQuantity: 50000,
        updatedAt: DateTime.now(),
      );

      final weightsAndExpected = {
        1: 3,       // 3.333 kuruş -> 3 kuruş
        10: 33,     // 33.33 kuruş -> 33 kuruş
        100: 333,   // 333.3 kuruş -> 333 kuruş
        300: 1000,  // 999.9 kuruş -> 1000 kuruş (10,00 TL - 1 kuruş kayıp yok!)
        500: 1667,  // 1666.5 kuruş -> 1667 kuruş (16,67 TL)
        999: 3330,  // 3329.667 kuruş -> 3330 kuruş (33,30 TL)
        1000: 3333, // 3333.0 kuruş -> 3333 kuruş (33,33 TL)
      };

      for (final entry in weightsAndExpected.entries) {
        final gram = entry.key;
        final expectedCents = entry.value;

        final item = CoreCartItem(
          product: pTartili,
          quantity: gram,
          unitPrice: pTartili.price,
          isWeighed: true,
        );

        expect(item.lineTotal.value, expectedCents,
            reason: '$gram gram için ticari yarım yukarı yuvarlama sonucu $expectedCents kuruş olmalıdır!');
      }

      // İndirimli tartılı satış testi: 300 gram (1000 kuruş) - 150 kuruş indirim = 850 kuruş
      final discountedItem = CoreCartItem(
        product: pTartili,
        quantity: 300,
        unitPrice: pTartili.price,
        discount: const MoneyCents(150),
        isWeighed: true,
      );
      expect(discountedItem.lineTotal.value, 850);
    });

    test('Senaryo 3: Veresiye Satışta LedgerService cariye borç yazmalı ve bakiye düşmelidir', () async {
      final pEkmek = ProductEntity(
        id: 'p-ekmek',
        barcode: '111',
        name: 'Köy Ekmeği',
        price: MoneyCents(1500),
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      // Müşteri seç (Ali Usta)
      final customer = CustomerEntity(
        id: 'c-ali',
        name: 'Ali Usta',
        balance: MoneyCents.zero,
        creditLimit: MoneyCents(50000),
        updatedAt: DateTime.now(),
      );
      salesNotifier.selectCustomer(customer);

      // 4 ekmek sepete at = 60 TL (6000 kuruş)
      salesNotifier.addProduct(pEkmek, quantity: 4);

      // 20 TL Nakit verdi, 40 TL'si Veresiye kaldı
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(2000)),
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(4000)),
      ]);

      expect(salesNotifier.state.paidTotal.value, 2000);
      expect(salesNotifier.state.debtTotal.value, 4000);

      await salesNotifier.completeCheckout(
        receiptNo: '2026-0003',
        storeTitle: 'Test Bakkal',
      );

      // Müşteri bakiyesi -40 TL (-4000 kuruş) olmalı
      final updatedCust = await ledgerRepo.getCustomer('c-ali');
      expect(updatedCust!.balance.value, -4000);
      expect(updatedCust.balance.formatTL(), '-40,00 ₺');

      // Defterde kayıt oluşmalı
      final ledgerEntries = await ledgerRepo.getCustomerLedgerHistory('c-ali');
      expect(ledgerEntries.length, 1);
      expect(ledgerEntries.first.amount.value, 4000);
      expect(ledgerEntries.first.entryType, LedgerEntryType.debitSale);
    });

    test('Senaryo 4: Veresiye borç varken müşteri seçilmemişse işlem reddedilmelidir', () async {
      final pEkmek = ProductEntity(
        id: 'p-ekmek',
        barcode: '111',
        name: 'Köy Ekmeği',
        price: MoneyCents(1500),
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      salesNotifier.addProduct(pEkmek, quantity: 2); // 30 TL
      // Ödeme yapılmadı (30 TL borç kaldı ama müşteri seçilmedi)

      expect(
        () => salesNotifier.completeCheckout(
          receiptNo: '2026-FAIL',
          storeTitle: 'Test Bakkal',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Senaryo 5: Karma Ödeme (Nakit + Kredi Kartı + Veresiye) sale_payments ve cash_transactions tablolarına eksiksiz yazılmalıdır', () async {
      final pPeynir = ProductEntity(
        id: 'p-peynir',
        barcode: '222',
        name: 'Köy Peyniri (Tartılı)',
        price: const MoneyCents(20000), // 200 TL
        stockQuantity: 10000,
        updatedAt: DateTime.now(),
      );

      final customer = CustomerEntity(
        id: 'c-ali',
        name: 'Ali Usta',
        balance: MoneyCents.zero,
        creditLimit: const MoneyCents(50000),
        updatedAt: DateTime.now(),
      );
      salesNotifier.selectCustomer(customer);
      salesNotifier.addProduct(pPeynir, quantity: 1); // 200 TL (20000 kuruş)

      // 50 TL Nakit, 100 TL Kredi Kartı, Kalan 50 TL Veresiye
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(5000)),
        const PaymentSplitEntity(type: PaymentType.creditCard, amount: MoneyCents(10000)),
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(5000)),
      ]);

      expect(salesNotifier.state.paidTotal.value, 15000);
      expect(salesNotifier.state.debtTotal.value, 5000);

      final completedSale = await salesNotifier.completeCheckout(
        receiptNo: '2026-KARMA-01',
        storeTitle: 'Test Bakkal',
      );

      expect(completedSale.total.value, 20000);
      expect(completedSale.paid.value, 15000);
      expect(completedSale.debt.value, 5000);

      // 1. sale_payments tablosunda 3 satır bulunmalıdır
      final paymentRows = await coreDb.db.query(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: [completedSale.id],
        orderBy: 'created_at ASC',
      );
      expect(paymentRows.length, 3);
      final paymentTypes = paymentRows.map((r) => r['payment_type']).toSet();
      expect(paymentTypes, containsAll(['cash', 'creditCard', 'onAccount']));

      // 2. cash_transactions tablosunda yalnızca nakit kısım (5000 kuruş) yer almalıdır
      final cashRows = await coreDb.db.query(
        'cash_transactions',
        where: 'description LIKE ?',
        whereArgs: ['%2026-KARMA-01%'],
      );
      expect(cashRows.length, 1);
      expect(cashRows.first['amount_cents'], 5000);
      expect(cashRows.first['type'], 'INFLOW');

      // 3. sync_events kuyruğunda PENDING satış eventi olmalıdır
      final syncRows = await coreDb.db.query(
        'sync_events',
        where: 'entity_id = ?',
        whereArgs: [completedSale.id],
      );
      expect(syncRows.length, 1);
      expect(syncRows.first['sync_state'], 'PENDING');

      // 4. Müşteri cari bakiyesi -50 TL (-5000 kuruş) olmalıdır
      final updatedCust = await ledgerRepo.getCustomer('c-ali');
      expect(updatedCust!.balance.value, -5000);
    });

    test('Senaryo 6: İdempotency Koruması — Birebir aynı satışta tekrar tahsilat yapılmaz, farklı sepette çakışma hatası verilir', () async {
      final pEkmek = ProductEntity(
        id: 'p-ekmek',
        barcode: '111',
        name: 'Köy Ekmeği',
        price: const MoneyCents(1500), // 15 TL
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      salesNotifier.addProduct(pEkmek, quantity: 1);
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(1500)),
      ]);

      final firstSale = await salesNotifier.completeCheckout(
        receiptNo: '2026-IDEMP-01',
        storeTitle: 'Test Bakkal',
      );
      expect(firstSale.receiptNo, '2026-IDEMP-01');

      // 6.1 Birebir aynı satış tekrarlandığında (REPLAY):
      // İkinci kez tahsilat yapılmaz, aynı satış güvenle döner
      salesNotifier.addProduct(pEkmek, quantity: 1);
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(1500)),
      ]);

      final replaySale = await salesNotifier.completeCheckout(
        receiptNo: '2026-IDEMP-01',
        storeTitle: 'Test Bakkal',
      );
      expect(replaySale.id, firstSale.id);

      // Stok sadece 1 kez düşmüş olmalıdır (50 - 1 = 49)
      final prodRows = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-ekmek']);
      expect(prodRows.first['stock_quantity'], 49);

      // 6.2 Aynı fiş no ile FARKLI bir sepet gönderilirse: ÇAKIŞMA HATASI
      salesNotifier.addProduct(pEkmek, quantity: 2); // 30 TL
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(3000)),
      ]);

      expect(
        () => salesNotifier.completeCheckout(
          receiptNo: '2026-IDEMP-01',
          storeTitle: 'Test Bakkal',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
