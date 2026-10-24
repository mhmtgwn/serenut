// test/core_next/financial_resilience_and_atomicity_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_state.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Stage 7 — Finansal Dayanıklılık, Idempotency ve Atomiklik Testleri', () {
    late CoreAppDatabase coreDb;
    late SqliteLedgerRepository ledgerRepo;
    late LedgerService ledgerService;
    late HardwareWorker hardwareWorker;

    final testProduct = ProductEntity(
      id: 'p-resilience-1',
      barcode: '8690001',
      name: 'Test Dayanıklılık Ürünü',
      price: const MoneyCents(5000), // 50,00 TL
      stockQuantity: 100,
      updatedAt: DateTime.now(),
    );

    final testCustomer = CustomerEntity(
      id: 'c-resilience-1',
      name: 'Ahmet Dayanıklı',
      balance: MoneyCents.zero,
      creditLimit: const MoneyCents(200000), // 2.000 TL
      updatedAt: DateTime.now(),
    );

    setUp(() async {
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: inMemoryDatabasePath);
      ledgerRepo = SqliteLedgerRepository(coreDb.db);
      ledgerService = LedgerService(ledgerRepo);
      hardwareWorker = HardwareWorker();
      await hardwareWorker.initialize();

      // Ürün ve Müşteri Ekle
      await coreDb.db.insert('products', {
        'id': testProduct.id,
        'barcode': testProduct.barcode,
        'name': testProduct.name,
        'price_cents': testProduct.price.value,
        'vat_rate': 20,
        'unit': 'piece',
        'stock_quantity': testProduct.stockQuantity,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('customers', {
        'id': testCustomer.id,
        'name': testCustomer.name,
        'phone': '05550001122',
        'balance_cents': 0,
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

    test('1. Sıfır Tutar, Negatif Tutar ve Fazla Ödeme Koruması', () async {
      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        hardwareWorker: hardwareWorker,
        defaultActor: ActorContext.testManager,
      );

      // 1.1 Boş Sepet
      final emptyState = const CoreSalesFlowState();
      expect(
        () => checkoutUseCase.execute(CheckoutRequest(
          flowState: emptyState,
          receiptNo: 'REC-ZERO-1',
          storeTitle: 'Test Bakkal',
        )),
        throwsA(isA<StateError>()),
      );

      // 1.2 Negatif Ödeme Parçası (Örn: -10 TL)
      final negativeSplitState = CoreSalesFlowState(
        items: [CoreCartItem(product: testProduct, quantity: 1, unitPrice: testProduct.price)],
        paymentSplits: const [
          PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(-1000)),
        ],
      );
      expect(
        () => checkoutUseCase.execute(CheckoutRequest(
          flowState: negativeSplitState,
          receiptNo: 'REC-NEG-1',
          storeTitle: 'Test Bakkal',
        )),
        throwsA(isA<StateError>()),
      );

      // 1.3 Fazla Ödeme (Satış 50 TL, tahsilat 60 TL bildirilmiş)
      final overpaidState = CoreSalesFlowState(
        items: [CoreCartItem(product: testProduct, quantity: 1, unitPrice: testProduct.price)],
        paymentSplits: const [
          PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(6000)),
        ],
      );
      expect(
        () => checkoutUseCase.execute(CheckoutRequest(
          flowState: overpaidState,
          receiptNo: 'REC-OVER-1',
          storeTitle: 'Test Bakkal',
        )),
        throwsA(isA<StateError>()),
      );
    });

    test('2. Idempotency Ayrımı: Birebir Aynı İstek (Replay) vs Farklı İstek (Çakışma Hatası)', () async {
      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        hardwareWorker: hardwareWorker,
        defaultActor: ActorContext.testManager,
      );

      final validState = CoreSalesFlowState(
        items: [CoreCartItem(product: testProduct, quantity: 1, unitPrice: testProduct.price)],
        paymentSplits: const [
          PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(5000)),
        ],
      );

      // İlk satış başarılı olmalı
      final firstSale = await checkoutUseCase.execute(CheckoutRequest(
        flowState: validState,
        receiptNo: 'REC-IDEMP-EXACT',
        idempotencyKey: 'idemp-uuid-1001',
        storeTitle: 'Test Bakkal',
      ));
      expect(firstSale.receiptNo, 'REC-IDEMP-EXACT');
      expect(firstSale.total.value, 5000);

      // Stok 100 -> 99'a düşmeli
      var pRow = await coreDb.db.query('products', where: 'id = ?', whereArgs: [testProduct.id]);
      expect(pRow.first['stock_quantity'], 99);

      // 2.1 Birebir Aynı İstek Yeniden Geldiğinde (REPLAY):
      // İkinci kez stok düşmemeli, aynı satış dönmeli
      final replaySale = await checkoutUseCase.execute(CheckoutRequest(
        flowState: validState,
        receiptNo: 'REC-IDEMP-EXACT',
        idempotencyKey: 'idemp-uuid-1001',
        storeTitle: 'Test Bakkal',
      ));
      expect(replaySale.id, firstSale.id);
      expect(replaySale.receiptNo, firstSale.receiptNo);

      // Stok hâlâ 99 kalmalı (mükerrer düşüm yok!)
      pRow = await coreDb.db.query('products', where: 'id = ?', whereArgs: [testProduct.id]);
      expect(pRow.first['stock_quantity'], 99);

      // Kasa hareketi 1 adet kalmalı (mükerrer tahsilat yok!)
      final cashRows = await coreDb.db.query('cash_transactions', where: 'description LIKE ?', whereArgs: ['%REC-IDEMP-EXACT%']);
      expect(cashRows.length, 1);

      // 2.2 Aynı Idempotency Key ile FARKLI bir sepet/tutar gelirse: ÇAKIŞMA HATASI
      final differentState = CoreSalesFlowState(
        items: [CoreCartItem(product: testProduct, quantity: 2, unitPrice: testProduct.price)], // 100 TL
        paymentSplits: const [
          PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(10000)),
        ],
      );
      expect(
        () => checkoutUseCase.execute(CheckoutRequest(
          flowState: differentState,
          receiptNo: 'REC-IDEMP-DIFFERENT',
          idempotencyKey: 'idemp-uuid-1001', // Aynı anahtar ama farklı sepet
          storeTitle: 'Test Bakkal',
        )),
        throwsA(isA<StateError>()),
      );
    });

    test('3. Atomiklik & Fault Injection: Transactionın Her Adımında Kısmi Kayıt Kalmadığının Kanıtı', () async {
      final faultSteps = [
        'after_sales_insert',
        'after_items_insert',
        'after_payments_insert',
        'after_ledger_insert',
        'after_sync_events_insert',
      ];

      final stateWithCredit = CoreSalesFlowState(
        items: [CoreCartItem(product: testProduct, quantity: 1, unitPrice: testProduct.price)],
        selectedCustomer: testCustomer,
        paymentSplits: const [
          PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(2000)),
          PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(3000)),
        ],
      );

      for (var i = 0; i < faultSteps.length; i++) {
        final targetFaultStep = faultSteps[i];
        final receiptNo = 'REC-FAULT-$i';

        final faultyUseCase = CoreCheckoutUseCase(
          db: coreDb,
          hardwareWorker: hardwareWorker,
          defaultActor: ActorContext.testManager,
          faultHook: (step) async {
            if (step == targetFaultStep) {
              throw Exception('SİMÜLE EDİLMİŞ KRİTİK ÇÖKME: Adım=$step');
            }
          },
        );

        // Satış çağrısı hata vermeli
        expect(
          () => faultyUseCase.execute(CheckoutRequest(
            flowState: stateWithCredit,
            receiptNo: receiptNo,
            idempotencyKey: 'fault-key-$i',
            storeTitle: 'Test Bakkal',
          )),
          throwsA(isA<Exception>()),
        );

        // ATOMİKLİK DENETİMİ: Veritabanında hiçbir artık kayıt kalmamış olmalı!
        final sales = await coreDb.db.query('sales', where: 'receipt_no = ?', whereArgs: [receiptNo]);
        expect(sales.isEmpty, true, reason: '$targetFaultStep sonrasında sales tablosu temizlenmiş olmalıdır!');

        final payments = await coreDb.db.query('sale_payments', where: 'reference_note = ?', whereArgs: [testCustomer.name]);
        expect(payments.isEmpty, true, reason: '$targetFaultStep sonrasında sale_payments temizlenmiş olmalıdır!');

        final cash = await coreDb.db.query('cash_transactions', where: 'description LIKE ?', whereArgs: ['%$receiptNo%']);
        expect(cash.isEmpty, true, reason: '$targetFaultStep sonrasında cash_transactions temizlenmiş olmalıdır!');

        final ledger = await coreDb.db.query('ledger_entries', where: 'customer_id = ?', whereArgs: [testCustomer.id]);
        expect(ledger.isEmpty, true, reason: '$targetFaultStep sonrasında ledger_entries temizlenmiş olmalıdır!');

        final sync = await coreDb.db.query('sync_events', where: 'payload_json LIKE ?', whereArgs: ['%$receiptNo%']);
        expect(sync.isEmpty, true, reason: '$targetFaultStep sonrasında sync_events temizlenmiş olmalıdır!');

        // Müşteri bakiyesi sıfır kalmalıdır
        final cust = await ledgerRepo.getCustomer(testCustomer.id);
        expect(cust!.balance.value, 0, reason: 'Müşteri bakiyesi bozulmamış olmalıdır!');

        // Stok 100 olarak kalmalıdır
        final prod = await coreDb.db.query('products', where: 'id = ?', whereArgs: [testProduct.id]);
        expect(prod.first['stock_quantity'], 100, reason: 'Stok düşümü rollback edilmiş olmalıdır!');
      }
    });

    test('4. Eşzamanlı (Concurrent) Checkout: İki Eşzamanlı Çağrıda Tek Satış ve Sıfır Mükerrer Finansal Yan Etki', () async {
      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        hardwareWorker: hardwareWorker,
        defaultActor: ActorContext.testManager,
      );

      final concurrentState = CoreSalesFlowState(
        items: [CoreCartItem(product: testProduct, quantity: 1, unitPrice: testProduct.price)],
        selectedCustomer: testCustomer,
        paymentSplits: const [
          PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(2000)),
          PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(3000)),
        ],
      );

      final req1 = CheckoutRequest(
        flowState: concurrentState,
        receiptNo: 'REC-CONCUR-001',
        idempotencyKey: 'idemp-concurrent-key',
        storeTitle: 'Test Bakkal',
      );
      final req2 = CheckoutRequest(
        flowState: concurrentState,
        receiptNo: 'REC-CONCUR-001',
        idempotencyKey: 'idemp-concurrent-key',
        storeTitle: 'Test Bakkal',
      );

      // İki çağrıyı AYNI ANDA eşzamanlı olarak ateşle
      final results = await Future.wait([
        checkoutUseCase.execute(req1),
        checkoutUseCase.execute(req2),
      ]);

      // 1. Her iki çağrı da geçerli sonuç almalı ve aynı satış ID'sine işaret etmeli
      expect(results[0].id, results[1].id);
      expect(results[0].receiptNo, 'REC-CONCUR-001');
      expect(results[1].receiptNo, 'REC-CONCUR-001');

      // 2. Altı Kritik Finansal Tabloda Mükerrer Kayıt Oluşmadığını Doğrula:
      // a. sales tablosunda tam olarak 1 kayıt olmalıdır
      final sales = await coreDb.db.query('sales', where: 'receipt_no = ?', whereArgs: ['REC-CONCUR-001']);
      expect(sales.length, 1, reason: 'Eşzamanlı çağrıda sales tablosunda yalnızca 1 kayıt olmalıdır!');

      // b. sale_items tablosunda tam olarak 1 kayıt olmalıdır
      final items = await coreDb.db.query('sale_items', where: 'sale_id = ?', whereArgs: [results[0].id]);
      expect(items.length, 1, reason: 'sale_items tablosunda mükerrer kayıt olmamalıdır!');

      // c. sale_payments tablosunda tam olarak 2 kayıt (1 cash, 1 onAccount) olmalıdır
      final payments = await coreDb.db.query('sale_payments', where: 'sale_id = ?', whereArgs: [results[0].id]);
      expect(payments.length, 2, reason: 'sale_payments tablosunda mükerrer split olmamalıdır!');

      // d. cash_transactions tablosunda tam olarak 1 nakit hareketi olmalıdır
      final cash = await coreDb.db.query('cash_transactions', where: 'description LIKE ?', whereArgs: ['%REC-CONCUR-001%']);
      expect(cash.length, 1, reason: 'cash_transactions tablosunda mükerrer kasa hareketi olmamalıdır!');

      // e. ledger_entries tablosunda tam olarak 1 defter kaydı olmalıdır
      final ledger = await coreDb.db.query('ledger_entries', where: 'reference_sale_id = ?', whereArgs: [results[0].id]);
      expect(ledger.length, 1, reason: 'ledger_entries tablosunda mükerrer borç kaydı olmamalıdır!');

      // f. sync_events tablosunda tam olarak 1 senkronizasyon olayı olmalıdır
      final sync = await coreDb.db.query('sync_events', where: 'entity_id = ?', whereArgs: [results[0].id]);
      expect(sync.length, 1, reason: 'sync_events tablosunda mükerrer olay olmamalıdır!');

      // 3. Stok ve Müşteri Bakiyesinde Çift Düşüş Olmadığını Doğrula:
      // Stok 100 -> 99'a düşmeli (98 olmamalı!)
      final prod = await coreDb.db.query('products', where: 'id = ?', whereArgs: [testProduct.id]);
      expect(prod.first['stock_quantity'], 99, reason: 'Stok yalnızca 1 adet düşmüş olmalıdır!');

      // Müşteri bakiyesi 0 -> -3000 kuruş olmalı (-6000 olmamalı!)
      final cust = await ledgerRepo.getCustomer(testCustomer.id);
      expect(cust!.balance.value, -3000, reason: 'Müşteri bakiyesi yalnızca 1 kez borçlandırılmış olmalıdır!');
    });

    test('5. Eşzamanlı Farklı Sepet Çakışması: Aynı Anahtarla Farklı Tutar Yarıştığında Biri Başarılı, Diğeri Açık Hata Almalıdır', () async {
      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        hardwareWorker: hardwareWorker,
        defaultActor: ActorContext.testManager,
      );

      final stateA = CoreSalesFlowState(
        items: [CoreCartItem(product: testProduct, quantity: 1, unitPrice: testProduct.price)], // 50 TL
        paymentSplits: const [
          PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(5000)),
        ],
      );

      final stateB = CoreSalesFlowState(
        items: [CoreCartItem(product: testProduct, quantity: 2, unitPrice: testProduct.price)], // 100 TL
        paymentSplits: const [
          PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(10000)),
        ],
      );

      final reqA = CheckoutRequest(
        flowState: stateA,
        receiptNo: 'REC-CONCUR-CONFLICT-A',
        idempotencyKey: 'idemp-conflict-key',
        storeTitle: 'Test Bakkal',
      );
      final reqB = CheckoutRequest(
        flowState: stateB,
        receiptNo: 'REC-CONCUR-CONFLICT-B',
        idempotencyKey: 'idemp-conflict-key', // Aynı anahtar ama farklı sepet
        storeTitle: 'Test Bakkal',
      );

      var successCount = 0;
      var conflictCount = 0;

      final futures = [
        checkoutUseCase.execute(reqA).then((val) {
          successCount++;
        }).catchError((err) {
          if (err is StateError && err.message.contains('İdempotency çakışması')) {
            conflictCount++;
          } else {
            throw err;
          }
        }),
        checkoutUseCase.execute(reqB).then((val) {
          successCount++;
        }).catchError((err) {
          if (err is StateError && err.message.contains('İdempotency çakışması')) {
            conflictCount++;
          } else {
            throw err;
          }
        }),
      ];

      await Future.wait(futures);

      expect(successCount, 1, reason: 'Yalnızca 1 satış başarıyla tamamlanmalıdır!');
      expect(conflictCount, 1, reason: 'Diğer yarışan istek açık çakışma hatası almalıdır!');

      // Veritabanında tek bir satış olmalı
      final sales = await coreDb.db.query('sales', where: 'idempotency_key = ?', whereArgs: ['idemp-conflict-key']);
      expect(sales.length, 1);
    });
  });
}
