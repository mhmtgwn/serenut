// test/core_next/stage10_3_fixes_test.dart

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/domain/models/sync_dtos.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/domain/usecases/refund_use_case.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Stage 10.3 — Beş Kritik Açığın Giderilmesi ve Kanıtlı Doğrulama Testleri', () {
    late CoreAppDatabase coreDb;
    late HardwareWorker hardwareWorker;
    late SqliteLedgerRepository ledgerRepo;
    late LedgerService ledgerService;
    late CoreCheckoutUseCase checkoutUseCase;
    late CoreRefundUseCase refundUseCase;
    late SyncV4PullIngestionService ingestionService;

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

      ingestionService = SyncV4PullIngestionService(coreDb);

      // Başlangıç Fixture Verileri
      await coreDb.db.insert('products', {
        'id': 'p-103',
        'barcode': '8690103',
        'name': 'Organik Zeytinyağı',
        'price_cents': 20000, // 200 TL
        'stock_quantity': 10,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('customers', {
        'id': 'c-103',
        'name': 'Mehmet Demir',
        'phone': '05551234567',
        'balance_cents': 0,
        'credit_limit_cents': 500000,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      await hardwareWorker.dispose();
      await coreDb.close();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 1. RBAC: GÜVENİLİR ACTOR, SYSTEM ACTOR ENGELİ VE MANAGER APPROVAL
    // ─────────────────────────────────────────────────────────────────────────
    test('1. RBAC: ActorContext.system ile satış yapılması kesinlikle reddedilir', () async {
      final p = ProductEntity(
        id: 'p-103',
        barcode: '8690103',
        name: 'Organik Zeytinyağı',
        price: const MoneyCents(20000),
        stockQuantity: 10,
        updatedAt: DateTime.now(),
      );

      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(p, quantity: 1);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(20000)),
      ]);

      // Sistem dahili aktörü ile satış denenir
      expect(
        () => checkoutUseCase.execute(
          CheckoutRequest(
            flowState: notifier.state,
            receiptNo: 'REC-SYS-ACTOR',
            storeTitle: 'Store',
            actor: ActorContext.system, // SİSTEM AKTÖRÜ
          ),
        ),
        throwsA(isA<AuthorizationException>()),
      );

      // Tabloların değişmediğini doğrula
      final sales = await coreDb.db.query('sales');
      expect(sales.isEmpty, true);
    });

    test('1. RBAC: Sahte veya yetkisiz yönetici onayı (ManagerApproval) ile indirim yapılamaz', () async {
      final p = ProductEntity(
        id: 'p-103',
        barcode: '8690103',
        name: 'Organik Zeytinyağı',
        price: const MoneyCents(20000),
        stockQuantity: 10,
        updatedAt: DateTime.now(),
      );

      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(p, quantity: 1);
      notifier.setGeneralDiscount(const MoneyCents(5000)); // 50 TL İndirim
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(15000)),
      ]);

      // Personel, geçersiz bir personel onayı (staff role) ekleyerek iskonto yapmaya çalışır
      const fakeApproval = ManagerApproval(
        managerId: 'fake-mgr-1',
        managerUsername: 'sahte_yonetici',
        managerRole: AppRole.staff, // STAFF YÖNETİCİ SAYILAMAZ
      );

      const staffWithFakeApproval = ActorContext(
        userId: 'stf-1',
        username: 'personel',
        role: AppRole.staff,
        managerApproval: fakeApproval,
      );

      expect(
        () => checkoutUseCase.execute(
          CheckoutRequest(
            flowState: notifier.state,
            receiptNo: 'REC-FAKE-APPROVAL',
            storeTitle: 'Store',
            actor: staffWithFakeApproval,
          ),
        ),
        throwsA(isA<AuthorizationException>()),
      );

      // Doğru ManagerApproval (manager role) ile başarılı olur
      const validApproval = ManagerApproval(
        managerId: 'real-mgr-1',
        managerUsername: 'gercek_yonetici',
        managerRole: AppRole.manager,
      );

      const cashierWithValidApproval = ActorContext(
        userId: 'cashier-1',
        username: 'kasiyer',
        role: AppRole.cashier,
        managerApproval: validApproval,
      );

      final successSale = await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: notifier.state,
          receiptNo: 'REC-VALID-APPROVAL',
          storeTitle: 'Store',
          actor: cashierWithValidApproval,
        ),
      );

      expect(successSale.receiptNo, 'REC-VALID-APPROVAL');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 2. SYNC V4: TAMAMLANMIŞ SATIŞ, ESKİ SNAPSHOT VE YENİ SNAPSHOT SIRASI
    // ─────────────────────────────────────────────────────────────────────────
    test('2. Sync V4: Çevrimdışı satış push edildikten sonra gelen eski snapshot stoku ezmez, yeni snapshot ikinci kez düşmez', () async {
      final p = ProductEntity(
        id: 'p-103',
        barcode: '8690103',
        name: 'Organik Zeytinyağı',
        price: const MoneyCents(20000),
        stockQuantity: 10,
        updatedAt: DateTime.now(),
      );

      const cashier = ActorContext(userId: 'c-1', username: 'kasiyer', role: AppRole.cashier);

      // 1. Çevrimdışı Satış: 2 adet satıldı (Stok: 10 -> 8)
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(p, quantity: 2);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(40000)),
      ]);
      await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: notifier.state,
          receiptNo: 'REC-SYNC-TEST-1',
          storeTitle: 'Store',
          actor: cashier,
        ),
      );

      var pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-103'])).first;
      expect(pRow['stock_quantity'], 8);

      // 2. Satış sunucuya gönderildi ve onaylandı (SYNCED, revizyon 105)
      await coreDb.db.update(
        'sync_events',
        {
          'sync_state': 'SYNCED',
          'base_revision': 105,
        },
        where: "entity_type = 'sale'",
      );

      // 3. Sunucudan, satış henüz yansıtılmadan önceki eski snapshot geldi (revizyon 100 < 105, stok 10)
      final oldPullDto = SyncPullResponseDto(
        changes: [
          const SyncPullChange(
            revision: 100, // 105'ten küçük!
            mutationId: 'mut-old-p',
            deviceId: 'server',
            entityType: 'product',
            entityId: 'p-103',
            operation: 'UPSERT',
            payload: {
              'barcode': '8690103',
              'name': 'Organik Zeytinyağı',
              'price_cents': 20000,
              'stock_quantity': 10, // Eski stok
            },
            createdAt: '2026-10-13T12:00:00Z',
          ),
        ],
        nextCursor: 101,
      );

      await ingestionService.ingestPull(oldPullDto);

      // Doğrulama: Eski snapshot stoku 10'a çıkaramadı, 8 olarak korundu!
      pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-103'])).first;
      expect(pRow['stock_quantity'], 8, reason: 'Eski sunucu snapshotı yerel stoku 8den 10a çıkaramaz');

      // 4. Sunucunun satışı yansıttığı yeni snapshot geldi (revizyon 106 >= 105, stok 8)
      final newPullDto = SyncPullResponseDto(
        changes: [
          const SyncPullChange(
            revision: 106, // 105'ten büyük!
            mutationId: 'mut-new-p',
            deviceId: 'server',
            entityType: 'product',
            entityId: 'p-103',
            operation: 'UPSERT',
            payload: {
              'barcode': '8690103',
              'name': 'Organik Zeytinyağı',
              'price_cents': 20000,
              'stock_quantity': 8, // Satış sunucuda da işlenmiş
            },
            createdAt: '2026-10-13T12:05:00Z',
          ),
        ],
        nextCursor: 107,
      );

      await ingestionService.ingestPull(newPullDto);

      // Doğrulama: Satış ikinci kez düşülmemeli (8 - 2 = 6 olmamalı, 8 kalmalıdır!)
      pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-103'])).first;
      expect(pRow['stock_quantity'], 8, reason: 'Satış sunucuya yansıdıktan sonra ikinci kez düşülemez');
    });

    test('2. Sync V4: Bekleyen vadeli satış varken uzaktaki tahsilat kaybolmaz ve bakiye birleşir', () async {
      final p = ProductEntity(
        id: 'p-103',
        barcode: '8690103',
        name: 'Organik Zeytinyağı',
        price: const MoneyCents(20000),
        stockQuantity: 10,
        updatedAt: DateTime.now(),
      );

      const manager = ActorContext(userId: 'm-1', username: 'yonetici', role: AppRole.manager);
      final cust = await ledgerRepo.getCustomer('c-103');

      // 1. Çevrimdışı 200 TL vadeli satış yapıldı (Bakiye: 0 -> -200 TL / -20000 kuruş)
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(p, quantity: 1);
      notifier.selectCustomer(cust);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(20000)),
      ]);
      await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: notifier.state,
          receiptNo: 'REC-DEBT-PULL-1',
          storeTitle: 'Store',
          actor: manager,
        ),
      );

      var cRow = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-103'])).first;
      expect(cRow['balance_cents'], -20000);

      // 2. Başka bir kasadan müşteriye 50 TL tahsilat/ödeme yapılmış olsun (Uzak bakiye: +5000 kuruş)
      final pullDto = SyncPullResponseDto(
        changes: [
          const SyncPullChange(
            revision: 50,
            mutationId: 'mut-cust-remote',
            deviceId: 'server',
            entityType: 'customer',
            entityId: 'c-103',
            operation: 'UPSERT',
            payload: {
              'name': 'Mehmet Demir',
              'balance_cents': 5000, // Uzak tahsilat sonucu bakiye
            },
            createdAt: '2026-10-13T12:00:00Z',
          ),
        ],
        nextCursor: 51,
      );

      await ingestionService.ingestPull(pullDto);

      // Doğrulama: Uzak tahsilat (+50 TL) ile yerel bekleyen borç (-200 TL) birleşmelidir (-150 TL)
      cRow = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-103'])).first;
      expect(cRow['balance_cents'], -15000, reason: 'Uzak tahsilat (+50 TL) ile yerel borç (-200 TL) birleşmeli (-150 TL kalmalı)');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 3. İADELER: GERÇEK NAKİT ÇIKIŞI (CASH_TRANSACTIONS) VE KART/KARMA KONTROLÜ
    // ─────────────────────────────────────────────────────────────────────────
    test('3. İade: Nakit iadede cash_transactions tablosuna atomik OUTFLOW kaydı yazılır', () async {
      final p = ProductEntity(
        id: 'p-103',
        barcode: '8690103',
        name: 'Organik Zeytinyağı',
        price: const MoneyCents(20000),
        stockQuantity: 10,
        updatedAt: DateTime.now(),
      );

      const manager = ActorContext(userId: 'm-1', username: 'yonetici', role: AppRole.manager);

      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(p, quantity: 1);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(20000)),
      ]);
      final sale = await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: notifier.state,
          receiptNo: 'REC-CASH-OUTFLOW',
          storeTitle: 'Store',
          actor: manager,
        ),
      );

      // İade et
      await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          reason: 'Nakit İade',
        ),
      );

      // Kasa nakit defterinde OUTFLOW kaydı bulunmalıdır
      final outflows = await coreDb.db.query('cash_transactions', where: "type = 'OUTFLOW'");
      expect(outflows.length, 1);
      expect(outflows.first['amount_cents'], 20000);
      expect(outflows.first['category'], 'REFUND');
    });

    test('3. İade: Kredi kartlı satışın doğrudan iadesi harici terminal olmadığı için reddedilir', () async {
      final p = ProductEntity(
        id: 'p-103',
        barcode: '8690103',
        name: 'Organik Zeytinyağı',
        price: const MoneyCents(20000),
        stockQuantity: 10,
        updatedAt: DateTime.now(),
      );

      const manager = ActorContext(userId: 'm-1', username: 'yonetici', role: AppRole.manager);

      // %100 Kredi Kartı ile satış yap
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(p, quantity: 1);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.creditCard, amount: MoneyCents(20000)),
      ]);
      final sale = await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: notifier.state,
          receiptNo: 'REC-CARD-SALE',
          storeTitle: 'Store',
          actor: manager,
        ),
      );

      // Kartlı satışın iadesini dene -> UnsupportedError
      expect(
        () => refundUseCase.execute(
          RefundRequest(
            originalSaleId: sale.id,
            actor: manager,
            reason: 'Kart İade Talebi',
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('3. İade: Karma ödemeli satışta iade dağılımı belirtilmezse işlem güvenle reddedilir', () async {
      final p = ProductEntity(
        id: 'p-103',
        barcode: '8690103',
        name: 'Organik Zeytinyağı',
        price: const MoneyCents(20000),
        stockQuantity: 10,
        updatedAt: DateTime.now(),
      );

      const manager = ActorContext(userId: 'm-1', username: 'yonetici', role: AppRole.manager);
      final cust = await ledgerRepo.getCustomer('c-103');

      // Karma ödeme: 100 TL nakit, 100 TL veresiye
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(p, quantity: 1);
      notifier.selectCustomer(cust);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(10000)),
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(10000)),
      ]);
      final sale = await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: notifier.state,
          receiptNo: 'REC-MIXED-SALE',
          storeTitle: 'Store',
          actor: manager,
        ),
      );

      // Dağılım belirtmeden iade dene -> StateError
      expect(
        () => refundUseCase.execute(
          RefundRequest(
            originalSaleId: sale.id,
            actor: manager,
            reason: 'Karma İade',
          ),
        ),
        throwsA(isA<StateError>()),
      );

      // Doğru paymentDistributions ile iade dene -> Başarılı
      final result = await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          reason: 'Karma İade',
          paymentDistributions: const [
            RefundPaymentSplit(type: PaymentType.cash, amount: MoneyCents(10000)),
            RefundPaymentSplit(type: PaymentType.onAccount, amount: MoneyCents(10000)),
          ],
        ),
      );

      expect(result.refundTotal.value, 20000);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 4. İADE İDEMPOTENCY: TAM PAYLOAD DOĞRULAMASI
    // ─────────────────────────────────────────────────────────────────────────
    test('4. İdempotency: Aynı anahtar ile aynı tutar fakat FARKLI ürün gönderilirse çakışma (conflict) fırlatılır', () async {
      // İkinci bir ürün ekle (fiyatı aynı 200 TL)
      await coreDb.db.insert('products', {
        'id': 'p-peynir',
        'barcode': '8690999',
        'name': 'Ezine Peyniri',
        'price_cents': 20000,
        'stock_quantity': 10,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      const manager = ActorContext(userId: 'm-1', username: 'yonetici', role: AppRole.manager);

      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(
        ProductEntity(id: 'p-103', barcode: '8690103', name: 'Zeytinyağı', price: const MoneyCents(20000), stockQuantity: 10, updatedAt: DateTime.now()),
        quantity: 1,
      );
      notifier.addProduct(
        ProductEntity(id: 'p-peynir', barcode: '8690999', name: 'Ezine Peyniri', price: const MoneyCents(20000), stockQuantity: 10, updatedAt: DateTime.now()),
        quantity: 1,
      );
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(40000)),
      ]);
      final sale = await checkoutUseCase.execute(
        CheckoutRequest(flowState: notifier.state, receiptNo: 'REC-TWO-ITEMS', storeTitle: 'Store', actor: manager),
      );

      const idempKey = 'idemp-payload-test-key';

      // 1. İade: Zeytinyağı iade edildi (200 TL)
      await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          items: [const RefundItemRequest(productId: 'p-103', quantity: 1)],
          idempotencyKey: idempKey,
        ),
      );

      // 2. İade: AYNI idempotency anahtarı ile AYNI tutarda (200 TL) fakat Ezine Peyniri iade edilmek istenir
      expect(
        () => refundUseCase.execute(
          RefundRequest(
            originalSaleId: sale.id,
            actor: manager,
            items: [const RefundItemRequest(productId: 'p-peynir', quantity: 1)], // FARKLI ÜRÜN
            idempotencyKey: idempKey,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 5. ÇOK SATIRLI ÜRÜN VE EŞZAMANLI İADE YARIŞI
    // ─────────────────────────────────────────────────────────────────────────
    test('5. Eşzamanlı Yarış: Çok satırlı gerçek satışta eşzamanlı iki istek satılan toplam miktarı aşamaz', () async {
      const manager = ActorContext(userId: 'm-1', username: 'yonetici', role: AppRole.manager);
      final saleId = 'sale-race-multiline';
      final now = DateTime.now().millisecondsSinceEpoch;

      // Gerçek SQLite tablolarına doğrudan 2 ayrı satır olarak ekle (Satır 1: 2 adet, Satır 2: 3 adet, Toplam: 5)
      await coreDb.db.insert('sales', {
        'id': saleId,
        'receipt_no': 'REC-RACE-5',
        'subtotal_cents': 100000,
        'total_cents': 100000,
        'paid_cents': 100000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': now,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'pay-race-1',
        'sale_id': saleId,
        'payment_type': 'cash',
        'amount_cents': 100000,
        'created_at': now,
      });
      await coreDb.db.insert('sale_items', {
        'id': 'line-1',
        'sale_id': saleId,
        'product_id': 'p-103',
        'barcode': '8690103',
        'product_name': 'Zeytinyağı',
        'unit_price_cents': 20000,
        'quantity': 2,
        'vat_rate': 20,
        'total_cents': 40000,
      });
      await coreDb.db.insert('sale_items', {
        'id': 'line-2',
        'sale_id': saleId,
        'product_id': 'p-103',
        'barcode': '8690103',
        'product_name': 'Zeytinyağı',
        'unit_price_cents': 20000,
        'quantity': 3,
        'vat_rate': 20,
        'total_cents': 60000,
      });

      // İki ayrı satırın gerçekten var olduğunu doğrula
      final itemLines = await coreDb.db.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
      expect(itemLines.length, 2);

      // İki eşzamanlı istek aynı anda 3'er adet iade talep eder (Toplam: 6 > 5)
      int successCount = 0;
      int errorCount = 0;

      final futures = [
        refundUseCase.execute(
          RefundRequest(
            originalSaleId: saleId,
            actor: manager,
            items: [const RefundItemRequest(productId: 'p-103', quantity: 3)],
            idempotencyKey: 'race-key-A',
          ),
        ).then((_) => successCount++).catchError((_) => errorCount++),
        refundUseCase.execute(
          RefundRequest(
            originalSaleId: saleId,
            actor: manager,
            items: [const RefundItemRequest(productId: 'p-103', quantity: 3)],
            idempotencyKey: 'race-key-B',
          ),
        ).then((_) => successCount++).catchError((_) => errorCount++),
      ];

      await Future.wait(futures);

      expect(successCount, 1, reason: 'Yalnızca ilk gelen 3 adetlik iade başarılı olmalıdır');
      expect(errorCount, 1, reason: 'Kalan miktar 2 olduğu için 3 adet isteyen ikinci işlem reddedilmelidir');

      // Toplam iade miktarını kontrol et: 3 adet iade edilmiş olmalıdır (asla 6 değil)
      final refundItems = await coreDb.db.query(
        'sale_items',
        where: "sale_id IN (SELECT id FROM sales WHERE status = 'REFUND')",
      );
      final totalRefundedQty = refundItems.fold<int>(0, (sum, row) => sum + (row['quantity'] as num).toInt());
      expect(totalRefundedQty, 3);
    });
  });
}
