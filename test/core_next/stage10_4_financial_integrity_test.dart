// test/core_next/stage10_4_financial_integrity_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  group('Stage 10.4 — İade Bütünlüğü, Özgün Ödeme Mutabakatı ve Idempotency Testleri', () {
    late CoreAppDatabase coreDb;
    late HardwareWorker hardwareWorker;
    late SqliteLedgerRepository ledgerRepo;
    late LedgerService ledgerService;
    late CoreCheckoutUseCase checkoutUseCase;
    late CoreRefundUseCase refundUseCase;

    const manager = ActorContext(userId: 'm-104', username: 'yonetici_104', role: AppRole.manager);

    final pBal = ProductEntity(
      id: 'p-bal',
      barcode: '869104001',
      name: 'Karakovan Balı',
      price: const MoneyCents(10000),
      stockQuantity: 20,
      updatedAt: DateTime.now(),
    );

    final pCeviz = ProductEntity(
      id: 'p-ceviz',
      barcode: '869104002',
      name: 'Yerli Ceviz 1kg',
      price: const MoneyCents(5000),
      stockQuantity: 30,
      updatedAt: DateTime.now(),
    );

    setUp(() async {
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: inMemoryDatabasePath);
      hardwareWorker = HardwareWorker();
      await hardwareWorker.initialize();
      ledgerRepo = SqliteLedgerRepository(coreDb.db);
      ledgerService = LedgerService(ledgerRepo);

      checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        hardwareWorker: hardwareWorker,
        ledgerService: ledgerService,
      );

      refundUseCase = CoreRefundUseCase(
        db: coreDb,
        ledgerService: ledgerService,
      );

      // Başlangıç test müşterisi oluştur (0 TL bakiye)
      await coreDb.db.insert('customers', {
        'id': 'c-104',
        'name': 'Ahmet Yılmaz',
        'phone': '5551040000',
        'balance_cents': 0,
        'credit_limit_cents': 500000,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Başlangıç test ürünleri ekle
      await coreDb.db.insert('products', {
        'id': 'p-bal',
        'barcode': '869104001',
        'name': 'Karakovan Balı',
        'price_cents': 10000, // 100 TL
        'stock_quantity': 20,
        'vat_rate': 20,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('products', {
        'id': 'p-ceviz',
        'barcode': '869104002',
        'name': 'Yerli Ceviz 1kg',
        'price_cents': 5000, // 50 TL
        'stock_quantity': 30,
        'vat_rate': 20,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      await coreDb.close();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 1. KARMA ÖDEME İADESİ: ÖZGÜN ÖDEMEYLE MUTABAKAT VE NAKİT SINIRI
    // ─────────────────────────────────────────────────────────────────────────

    test('10.4.1: 10 TL nakit + 90 TL vadeli satıştan 50 TL nakit iadesi talebi reddedilir ve yan etki bırakmaz', () async {
      final cust = await ledgerRepo.getCustomer('c-104');

      // 2 Adet Ceviz sat (100 TL): 10 TL nakit + 90 TL veresiye
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pCeviz, quantity: 2);
      notifier.selectCustomer(cust);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(1000)), // 10 TL
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(9000)), // 90 TL
      ]);

      final sale = await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: notifier.state,
          receiptNo: 'REC-104-MIX-1',
          storeTitle: 'Serenut',
          actor: manager,
        ),
      );

      // Satış sonrası durum kontrolü
      var cRow = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-104'])).first;
      expect(cRow['balance_cents'], -9000); // 90 TL borç
      var pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-ceviz'])).first;
      expect(pRow['stock_quantity'], 28);

      // Kasa nakit defterindeki mevcut giriş sayısı
      final initialCashTxCount = Sqflite.firstIntValue(
        await coreDb.db.rawQuery('SELECT COUNT(*) FROM cash_transactions WHERE type = "OUTFLOW"'),
      )!;
      expect(initialCashTxCount, 0);

      // 1 Adet Ceviz (50 TL) için 50 TL nakit iadesi iste! (Orijinal nakit yalnızca 10 TL)
      expect(
        () => refundUseCase.execute(
          RefundRequest(
            originalSaleId: sale.id,
            actor: manager,
            items: [const RefundItemRequest(productId: 'p-ceviz', quantity: 1)],
            reason: 'Yetkisiz 50 TL Nakit İade',
            paymentDistributions: const [
              RefundPaymentSplit(type: PaymentType.cash, amount: MoneyCents(5000)), // 50 TL nakit (YASAK!)
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('orijinal satışta kalan iade edilebilir nakit tutarını (1000 kuruş) aşamaz'),
          ),
        ),
      );

      // Adli SQLite Doğrulaması: İşlem tamamen atomik olarak geri alınmış olmalıdır
      final afterOutflows = await coreDb.db.query('cash_transactions', where: 'type = "OUTFLOW"');
      expect(afterOutflows, isEmpty, reason: 'Reddedilen iade kasadan nakit çıkışı yapamaz');

      final refundSales = await coreDb.db.query('sales', where: "status = 'REFUND'");
      expect(refundSales, isEmpty, reason: 'Reddedilen iade sales tablosunda kayıt bırakamaz');

      cRow = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-104'])).first;
      expect(cRow['balance_cents'], -9000, reason: 'Müşteri borcu değişmemelidir');

      pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-ceviz'])).first;
      expect(pRow['stock_quantity'], 28, reason: 'Stok iade edilmemelidir');
    });

    test('10.4.2: Özgün ödeme dağılımına uygun izinli iade doğru nakit ve ledger kayıtlarını üretir', () async {
      final cust = await ledgerRepo.getCustomer('c-104');

      // 1 Adet Bal sat (100 TL): 10 TL nakit + 90 TL veresiye
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pBal, quantity: 1);
      notifier.selectCustomer(cust);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(1000)),
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(9000)),
      ]);

      final sale = await checkoutUseCase.execute(
        CheckoutRequest(flowState: notifier.state, receiptNo: 'REC-104-MIX-2', storeTitle: 'Serenut', actor: manager),
      );

      // İzinli dağılım: 10 TL nakit + 90 TL veresiye borç silimi (Tam iade)
      final result = await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          reason: 'Tam ve Kurallara Uygun İade',
          paymentDistributions: const [
            RefundPaymentSplit(type: PaymentType.cash, amount: MoneyCents(1000)),
            RefundPaymentSplit(type: PaymentType.onAccount, amount: MoneyCents(9000)),
          ],
        ),
      );

      expect(result.refundTotal.value, 10000);

      // 1. Kasa defterinde yalnızca 10 TL OUTFLOW bulunmalıdır
      final cashOutflows = await coreDb.db.query('cash_transactions', where: 'type = "OUTFLOW"');
      expect(cashOutflows.length, 1);
      expect(cashOutflows.first['amount_cents'], 1000);
      expect(cashOutflows.first['category'], 'REFUND');

      // 2. Müşteri carisinde borç 0 TL olmalıdır (90 TL borç silinmiş)
      final cRow = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-104'])).first;
      expect(cRow['balance_cents'], 0);

      // 3. Ledger tablosunda creditRefund kaydı bulunmalıdır
      final ledgerEntries = await coreDb.db.query('ledger_entries', where: 'customer_id = "c-104"');
      expect(ledgerEntries.length, 2); // 1 DEBIT (satış), 1 creditRefund (iade)
      final refundEntry = ledgerEntries.firstWhere((e) => e['entry_type'] == 'creditRefund');
      expect(refundEntry['amount_cents'], 9000);
      expect(refundEntry['balance_after_cents'], 0);

      // 4. Stok geri yüklenmiş olmalıdır (19 -> 20)
      final pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-bal'])).first;
      expect(pRow['stock_quantity'], 20);

      // 5. sync_events tablosunda finansal refund mutasyonu bulunmalıdır
      final syncEvents = await coreDb.db.query('sync_events', where: 'group_id = ?', whereArgs: [result.refundId]);
      expect(syncEvents.length, 1);
      expect(syncEvents.first['entity_type'], 'financial_transaction');
    });

    test('10.4.3: Daha önce kısmen iade edilmiş satışta toplam iade sınırı ve kanal limitleri aşılamaz', () async {
      final cust = await ledgerRepo.getCustomer('c-104');

      // 2 Adet Ceviz sat (100 TL): 20 TL nakit + 80 TL veresiye
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pCeviz, quantity: 2);
      notifier.selectCustomer(cust);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(2000)),
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(8000)),
      ]);

      final sale = await checkoutUseCase.execute(
        CheckoutRequest(flowState: notifier.state, receiptNo: 'REC-104-PARTIAL', storeTitle: 'Serenut', actor: manager),
      );

      // 1. Kısmi İade: 1 Adet Ceviz (50 TL) -> 20 TL nakit + 30 TL veresiye silimi
      await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          items: [const RefundItemRequest(productId: 'p-ceviz', quantity: 1)],
          reason: 'Kısmi İade 1',
          paymentDistributions: const [
            RefundPaymentSplit(type: PaymentType.cash, amount: MoneyCents(2000)),
            RefundPaymentSplit(type: PaymentType.onAccount, amount: MoneyCents(3000)),
          ],
        ),
      );

      // Kalan limitler: Nakit = 0 TL, Vadeli = 50 TL, Kalan ürün = 1 adet
      // 2. Kısmi İade Denemesi (Hatalı): Nakit bittiği halde 10 TL nakit istemeyi dene
      expect(
        () => refundUseCase.execute(
          RefundRequest(
            originalSaleId: sale.id,
            actor: manager,
            items: [const RefundItemRequest(productId: 'p-ceviz', quantity: 1)],
            reason: 'Hatalı Nakit İsteği',
            paymentDistributions: const [
              RefundPaymentSplit(type: PaymentType.cash, amount: MoneyCents(1000)),
              RefundPaymentSplit(type: PaymentType.onAccount, amount: MoneyCents(4000)),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('kalan iade edilebilir nakit tutarını (0 kuruş) aşamaz'),
          ),
        ),
      );

      // 3. Kısmi İade Denemesi (Hatalı): Kalan 1 adetten fazla (2 adet) iade etmeyi dene
      expect(
        () => refundUseCase.execute(
          RefundRequest(
            originalSaleId: sale.id,
            actor: manager,
            items: [const RefundItemRequest(productId: 'p-ceviz', quantity: 2)],
            reason: 'Aşırı Miktar İsteği',
            paymentDistributions: const [
              RefundPaymentSplit(type: PaymentType.onAccount, amount: MoneyCents(10000)),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('kalan iade edilebilir miktarı (1) aşamaz'),
          ),
        ),
      );

      // 4. Kısmi İade Denemesi (Başarılı): Kalan 1 adet ceviz için 50 TL vadeli borç silimi
      final res2 = await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          items: [const RefundItemRequest(productId: 'p-ceviz', quantity: 1)],
          reason: 'Kalan Kalemin İadesi',
          paymentDistributions: const [
            RefundPaymentSplit(type: PaymentType.onAccount, amount: MoneyCents(5000)),
          ],
        ),
      );

      expect(res2.refundTotal.value, 5000);

      // Müşteri borcu tamamen sıfırlanmış olmalıdır (80 TL borç vardı, 30 TL + 50 TL silindi)
      final cRow = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-104'])).first;
      expect(cRow['balance_cents'], 0);

      // Stok başlangıç seviyesine dönmüş olmalıdır (30 adet)
      final pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-ceviz'])).first;
      expect(pRow['stock_quantity'], 30);
    });

    test('10.4.4: Kartlı veya belirsiz dağılımlı karma iade güvenle reddedilir ve veritabanı kirlenmez', () async {
      // 1. Kredi kartlı satış yap
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pBal, quantity: 1);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.creditCard, amount: MoneyCents(10000)),
      ]);

      final cardSale = await checkoutUseCase.execute(
        CheckoutRequest(flowState: notifier.state, receiptNo: 'REC-104-CARD', storeTitle: 'Serenut', actor: manager),
      );

      // Kart iadesi -> UnsupportedError
      expect(
        () => refundUseCase.execute(
          RefundRequest(originalSaleId: cardSale.id, actor: manager, reason: 'Kart İadesi'),
        ),
        throwsA(isA<UnsupportedError>()),
      );

      // 2. Karma satış yap ve dağılım vermeden iade dene
      final cust = await ledgerRepo.getCustomer('c-104');
      final mixedNotifier = CoreSalesFlowNotifier(checkoutUseCase);
      mixedNotifier.addProduct(pBal, quantity: 1);
      mixedNotifier.selectCustomer(cust);
      mixedNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(5000)),
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(5000)),
      ]);

      final mixedSale = await checkoutUseCase.execute(
        CheckoutRequest(flowState: mixedNotifier.state, receiptNo: 'REC-104-MIX-AMBIGUOUS', storeTitle: 'Serenut', actor: manager),
      );

      // Dağılım yok -> StateError
      expect(
        () => refundUseCase.execute(
          RefundRequest(originalSaleId: mixedSale.id, actor: manager, reason: 'Belirsiz İade'),
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('paymentDistributions'))),
      );
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 2. İADE İDEMPOTENCY: TAM VE KARARLI PAYLOAD DOĞRULAMASI
    // ─────────────────────────────────────────────────────────────────────────

    test('10.4.5: Aynı anahtar + aynı tam payload önceki sonucu deterministik döner ve stok mükerrer artmaz', () async {
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pBal, quantity: 1);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(10000)),
      ]);

      final sale = await checkoutUseCase.execute(
        CheckoutRequest(flowState: notifier.state, receiptNo: 'REC-104-IDEMP-1', storeTitle: 'Serenut', actor: manager),
      );

      const idempKey = 'idemp-exact-match-key';

      // İlk İade
      final res1 = await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          reason: 'Birebir İade Testi',
          idempotencyKey: idempKey,
        ),
      );

      final stockAfterFirst = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-bal'])).first['stock_quantity'];
      expect(stockAfterFirst, 20); // Satışta 19'a düşmüştü, iadede 20 oldu

      // İkinci İade (Birebir aynı payload ve aynı anahtar)
      final res2 = await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          reason: 'Birebir İade Testi',
          idempotencyKey: idempKey,
        ),
      );

      // Sonuçlar deterministik olarak birebir aynı olmalıdır
      expect(res2.refundId, res1.refundId);
      expect(res2.refundTotal.value, res1.refundTotal.value);
      expect(res2.receiptNo, res1.receiptNo);

      // Stok ikinci kez artmamalıdır!
      final stockAfterSecond = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-bal'])).first['stock_quantity'];
      expect(stockAfterSecond, 20);

      // Kasa nakit çıkışı ikinci kez yazılmamalıdır!
      final cashOutflows = await coreDb.db.query('cash_transactions', where: 'type = "OUTFLOW"');
      expect(cashOutflows.length, 1);
    });

    test('10.4.6: Aynı anahtar + farklı ödeme dağılımı çatışma (conflict) hatası fırlatır ve yan etki bırakmaz', () async {
      final cust = await ledgerRepo.getCustomer('c-104');

      // 100 TL satış: 50 TL nakit + 50 TL veresiye
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pBal, quantity: 1);
      notifier.selectCustomer(cust);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(5000)),
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(5000)),
      ]);

      final sale = await checkoutUseCase.execute(
        CheckoutRequest(flowState: notifier.state, receiptNo: 'REC-104-IDEMP-SPLIT', storeTitle: 'Serenut', actor: manager),
      );

      const idempKey = 'idemp-split-conflict-key';

      // 1. İade: 50 TL nakit + 50 TL veresiye ile başarılı oluşturuldu
      await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          reason: 'Orijinal Dağılım',
          idempotencyKey: idempKey,
          paymentDistributions: const [
            RefundPaymentSplit(type: PaymentType.cash, amount: MoneyCents(5000)),
            RefundPaymentSplit(type: PaymentType.onAccount, amount: MoneyCents(5000)),
          ],
        ),
      );

      final refundsCountBefore = Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM sales WHERE status = "REFUND"'))!;
      final outflowsCountBefore = Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM cash_transactions WHERE type = "OUTFLOW"'))!;

      // 2. İade: AYNI anahtar ile FARKLI dağılım (ör. 0 TL nakit, 100 TL veresiye) gönder
      expect(
        () => refundUseCase.execute(
          RefundRequest(
            originalSaleId: sale.id,
            actor: manager,
            reason: 'Farklı Dağılım Talebi',
            idempotencyKey: idempKey,
            paymentDistributions: const [
              RefundPaymentSplit(type: PaymentType.cash, amount: MoneyCents(0)),
              RefundPaymentSplit(type: PaymentType.onAccount, amount: MoneyCents(10000)),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('İdempotency Çakışması'),
          ),
        ),
      );

      // Veritabanı tablolarında ek bir kayıt oluşmadığı doğrulanır
      final refundsCountAfter = Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM sales WHERE status = "REFUND"'))!;
      final outflowsCountAfter = Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM cash_transactions WHERE type = "OUTFLOW"'))!;

      expect(refundsCountAfter, refundsCountBefore);
      expect(outflowsCountAfter, outflowsCountBefore);
    });

    test('10.4.7: Farklı anahtar ile yeni iade yalnızca kalan limitler izin veriyorsa kabul edilir', () async {
      // 2 adet Bal satışı (200 TL nakit)
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pBal, quantity: 2);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(20000)),
      ]);

      final sale = await checkoutUseCase.execute(
        CheckoutRequest(flowState: notifier.state, receiptNo: 'REC-104-TWO-KEYS', storeTitle: 'Serenut', actor: manager),
      );

      // Key 1: 1 adet iade et (Kalan: 1 adet, 100 TL nakit)
      final res1 = await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          items: [const RefundItemRequest(productId: 'p-bal', quantity: 1)],
          idempotencyKey: 'key-part-1',
        ),
      );
      expect(res1.refundTotal.value, 10000);

      // Key 2: Kalan 1 adedi iade et (Kabul edilmeli)
      final res2 = await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          items: [const RefundItemRequest(productId: 'p-bal', quantity: 1)],
          idempotencyKey: 'key-part-2',
        ),
      );
      expect(res2.refundTotal.value, 10000);

      // Key 3: Artık iade edilecek ürün kalmadı -> StateError
      expect(
        () => refundUseCase.execute(
          RefundRequest(
            originalSaleId: sale.id,
            actor: manager,
            items: [const RefundItemRequest(productId: 'p-bal', quantity: 1)],
            idempotencyKey: 'key-part-3',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
