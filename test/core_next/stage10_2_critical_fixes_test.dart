// test/core_next/stage10_2_critical_fixes_test.dart

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
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_state.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Stage 10.2 — Beş Kritik Bulgunun Regresyon ve Doğrulama Testleri', () {
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

      // Başlangıç fixture verileri
      await coreDb.db.insert('products', {
        'id': 'p-bal',
        'barcode': '8690555',
        'name': 'Karakovan Balı',
        'price_cents': 50000, // 500.00 TL
        'stock_quantity': 50,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('customers', {
        'id': 'c-ali',
        'name': 'Ali Veli',
        'phone': '05559876543',
        'balance_cents': 0,
        'credit_limit_cents': 200000,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      await hardwareWorker.dispose();
      await coreDb.close();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // BULGU 10.1.1: RBAC FAIL-OPEN (ACTOR NULL VE YETKİ KONTROLLERİ)
    // ─────────────────────────────────────────────────────────────────────────
    test('10.1.1: Actor null olduğunda istek sysadmin yetkisi almamalı, AuthenticationRequiredException fırlatılmalıdır', () async {
      final pEntity = ProductEntity(
        id: 'p-bal',
        barcode: '8690555',
        name: 'Karakovan Balı',
        price: const MoneyCents(50000),
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pEntity, quantity: 1);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(50000)),
      ]);

      // Actor null olarak checkout dene
      expect(
        () => checkoutUseCase.execute(
          CheckoutRequest(
            flowState: notifier.state,
            receiptNo: 'REC-NO-ACTOR',
            storeTitle: 'Test Store',
            actor: null, // KIMLIKSIZ ISTEK
          ),
        ),
        throwsA(isA<AuthenticationRequiredException>()),
      );

      // Veritabanı ve outbox kesinlikle temiz kalmalıdır
      final sales = await coreDb.db.query('sales');
      expect(sales.isEmpty, true);
      final events = await coreDb.db.query('sync_events');
      expect(events.isEmpty, true);
    });

    test('10.1.1: Staff rolüyle iskonto ve veresiye engellenmeli, veritabanı temiz kalmalıdır', () async {
      final pEntity = ProductEntity(
        id: 'p-bal',
        barcode: '8690555',
        name: 'Karakovan Balı',
        price: const MoneyCents(50000),
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pEntity, quantity: 1);
      notifier.setGeneralDiscount(const MoneyCents(10000)); // 100 TL İskonto
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(40000)),
      ]);

      const staffActor = ActorContext(
        userId: 'stf-1',
        username: 'personel',
        role: AppRole.staff,
      );

      expect(
        () => checkoutUseCase.execute(
          CheckoutRequest(
            flowState: notifier.state,
            receiptNo: 'REC-STAFF-DISC',
            storeTitle: 'Test Store',
            actor: staffActor,
          ),
        ),
        throwsA(isA<AuthorizationException>()),
      );

      final sales = await coreDb.db.query('sales');
      expect(sales.isEmpty, true);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // BULGU 10.1.2: PULL INGESTION VE ÇEVRİMDIŞI SATIŞ KORUMASI
    // ─────────────────────────────────────────────────────────────────────────
    test('10.1.2: Çevrimdışı satışın stok düşümü, sunucudan gelen eski ürün snapshotı ile ezilmemelidir', () async {
      final pEntity = ProductEntity(
        id: 'p-bal',
        barcode: '8690555',
        name: 'Karakovan Balı',
        price: const MoneyCents(50000),
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      const cashier = ActorContext(userId: 'c-1', username: 'kasiyer', role: AppRole.cashier);

      // 1. Çevrimdışı Satış: 2 adet bal sat (Stok 50 -> 48'e inmeli, outbox'ta pending sale oluşur)
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pEntity, quantity: 2);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(100000)),
      ]);
      await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: notifier.state,
          receiptNo: 'REC-OFFLINE-1',
          storeTitle: 'Store',
          actor: cashier,
        ),
      );

      var pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-bal'])).first;
      expect(pRow['stock_quantity'], 48);

      // 2. Sunucudan eski snapshot geldi (Stok hâlâ 50 görünüyor)
      final pullDto = SyncPullResponseDto(
        changes: [
          const SyncPullChange(
            revision: 10,
            mutationId: 'mut-remote-p-bal',
            deviceId: 'server',
            entityType: 'product',
            entityId: 'p-bal',
            operation: 'UPSERT',
            payload: {
              'barcode': '8690555',
              'name': 'Karakovan Balı (Uzak)',
              'price': 550.0, // Fiyat güncellenmiş olabilir
              'stock_quantity': 50, // Eski stok
            },
            createdAt: '2026-10-13T12:00:00Z',
          ),
        ],
        nextCursor: 100,
      );

      await ingestionService.ingestPull(pullDto);

      // Doğrulama: Yerel bekleyen satış (2 adet) düşülmüş olmalı!
      // Beklenen stok: 50 - 2 = 48 (50'ye geri dönmemeli!)
      pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-bal'])).first;
      expect(pRow['stock_quantity'], 48, reason: 'Yerel çevrimdışı satışın 2 adetlik düşümü korunmalıdır');
      expect(pRow['price_cents'], 55000, reason: 'Uzak fiyat güncellemesi başarıyla uygulanabilmelidir');
    });

    test('10.1.2: Çevrimdışı veresiye satışın müşteri borcu, sunucudan gelen eski müşteri snapshotı ile ezilmemelidir', () async {
      final pEntity = ProductEntity(
        id: 'p-bal',
        barcode: '8690555',
        name: 'Karakovan Balı',
        price: const MoneyCents(50000),
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      const manager = ActorContext(userId: 'm-1', username: 'yonetici', role: AppRole.manager);
      final cust = await ledgerRepo.getCustomer('c-ali');

      // 1. Çevrimdışı vadeli satış: 500 TL borç (Bakiye 0 -> -500 TL / -50000 kuruş)
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pEntity, quantity: 1);
      notifier.selectCustomer(cust);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(50000)),
      ]);
      await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: notifier.state,
          receiptNo: 'REC-OFFLINE-DEBT-1',
          storeTitle: 'Store',
          actor: manager,
        ),
      );

      var cRow = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-ali'])).first;
      expect(cRow['balance_cents'], -50000);

      // 2. Sunucudan eski müşteri snapshotı geldi (Bakiye 0)
      final pullDto = SyncPullResponseDto(
        changes: [
          const SyncPullChange(
            revision: 11,
            mutationId: 'mut-remote-c-ali',
            deviceId: 'server',
            entityType: 'customer',
            entityId: 'c-ali',
            operation: 'UPSERT',
            payload: {
              'name': 'Ali Veli (Güncel İsim)',
              'balance': 0.0, // Eski bakiye!
            },
            createdAt: '2026-10-13T12:00:00Z',
          ),
        ],
        nextCursor: 101,
      );

      await ingestionService.ingestPull(pullDto);

      // Doğrulama: Müşterinin yerel borcu ezilmemeli (-50000 kuruş kalmalı), isim ise güncellenmeli
      cRow = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-ali'])).first;
      expect(cRow['balance_cents'], -50000, reason: 'Yerel bekleyen borç bakiyesi korunmalıdır');
      expect(cRow['name'], 'Ali Veli (Güncel İsim)');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // BULGU 10.1.3: NAKİT SATIŞ İADESİNDE HATALI MÜŞTERİ ALACAĞI ENGELİ
    // ─────────────────────────────────────────────────────────────────────────
    test('10.1.3: Müşterili NAKİT satış iade edildiğinde müşteri cari hesabına haksız alacak yazılmamalıdır', () async {
      final pEntity = ProductEntity(
        id: 'p-bal',
        barcode: '8690555',
        name: 'Karakovan Balı',
        price: const MoneyCents(50000),
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      const manager = ActorContext(userId: 'm-1', username: 'yonetici', role: AppRole.manager);
      final cust = await ledgerRepo.getCustomer('c-ali');

      // 1. Müşteri seçili ancak %100 NAKİT ödenmiş satış
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pEntity, quantity: 1);
      notifier.selectCustomer(cust);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(50000)),
      ]);
      final sale = await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: notifier.state,
          receiptNo: 'REC-CASH-WITH-CUST',
          storeTitle: 'Store',
          actor: manager,
        ),
      );

      var cRow = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-ali'])).first;
      expect(cRow['balance_cents'], 0, reason: 'Nakit satışta borç oluşmaz');

      // 2. İade yap
      await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          reason: 'Müşteri vazgeçti',
        ),
      );

      // Doğrulama: Müşteri bakiyesi HÂLÂ 0 olmalıdır (+500 TL olmamalıdır!)
      cRow = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-ali'])).first;
      expect(cRow['balance_cents'], 0, reason: 'Nakit satış iadesinde müşteriye havadan alacak yazılamaz');

      final ledgerEntries = await coreDb.db.query('ledger_entries', where: 'customer_id = ?', whereArgs: ['c-ali']);
      expect(ledgerEntries.isEmpty, true, reason: 'Cari defterde alacak kaydı oluşmamalıdır');

      // Kasa nakit defterinde OUTFLOW kaydı oluştuğunu doğrula
      final cashTxs = await coreDb.db.query('cash_transactions', where: "type = 'OUTFLOW'");
      expect(cashTxs.length, 1, reason: 'Kasa nakit hareketlerinde OUTFLOW kaydı oluşmalıdır');
      expect(cashTxs.first['amount_cents'], 50000);
      expect(cashTxs.first['category'], 'REFUND');
    });

    test('10.1.3: VADELİ satış iade edildiğinde müşteri borcu kuruşu kuruşuna silinmelidir', () async {
      final pEntity = ProductEntity(
        id: 'p-bal',
        barcode: '8690555',
        name: 'Karakovan Balı',
        price: const MoneyCents(50000),
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      const manager = ActorContext(userId: 'm-1', username: 'yonetici', role: AppRole.manager);
      final cust = await ledgerRepo.getCustomer('c-ali');

      // 1. Vadeli satış: 500 TL borç
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pEntity, quantity: 1);
      notifier.selectCustomer(cust);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(50000)),
      ]);
      final sale = await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: notifier.state,
          receiptNo: 'REC-CREDIT-TO-REFUND',
          storeTitle: 'Store',
          actor: manager,
        ),
      );

      var cRow = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-ali'])).first;
      expect(cRow['balance_cents'], -50000);

      // 2. İade yap
      await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          reason: 'Vadeli İade',
        ),
      );

      // Doğrulama: Vadeli satış iadesi borcu kapatmalıdır (Bakiye 0 olmalı)
      cRow = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-ali'])).first;
      expect(cRow['balance_cents'], 0, reason: 'Vadeli iade borcu kapatmalıdır');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // BULGU 10.1.4: İADE İDEMPOTENCY (ÇÖKME YERİNE GÜVENLİ DÖNÜŞ)
    // ─────────────────────────────────────────────────────────────────────────
    test('10.1.4: Aynı idempotency anahtarı ile aynı iade tekrarlandığında çökmemeli, mevcut sonuç dönmeli ve stok ikinci kez artmamalıdır', () async {
      final pEntity = ProductEntity(
        id: 'p-bal',
        barcode: '8690555',
        name: 'Karakovan Balı',
        price: const MoneyCents(50000),
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      const manager = ActorContext(userId: 'm-1', username: 'yonetici', role: AppRole.manager);

      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pEntity, quantity: 1);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(50000)),
      ]);
      final sale = await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: notifier.state,
          receiptNo: 'REC-IDEMP-SALE',
          storeTitle: 'Store',
          actor: manager,
        ),
      );

      var pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-bal'])).first;
      expect(pRow['stock_quantity'], 49);

      const idempKey = 'idemp-refund-exact-1';

      // 1. İlk İade Çağrısı (Başarılı, stok 49 -> 50)
      final ref1 = await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          idempotencyKey: idempKey,
        ),
      );
      expect(ref1.refundTotal.value, 50000);

      pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-bal'])).first;
      expect(pRow['stock_quantity'], 50);

      // 2. İkinci İade Çağrısı (Aynı anahtar, aynı istek) -> ÇÖKMEMELİ, aynı sonucu dönmeli
      final ref2 = await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          idempotencyKey: idempKey,
        ),
      );
      expect(ref2.receiptNo, ref1.receiptNo);
      expect(ref2.refundTotal.value, ref1.refundTotal.value);

      // Stok ikinci kez artmamalı (hâlâ 50 olmalı!)
      pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-bal'])).first;
      expect(pRow['stock_quantity'], 50, reason: 'İdempotent tekrarda stok ikinci kez artırılamaz');
    });

    test('10.1.4: Aynı idempotency anahtarı farklı bir iade tutarı ile kullanılırsa açık çatışma hatası fırlatılmalıdır', () async {
      final pEntity = ProductEntity(
        id: 'p-bal',
        barcode: '8690555',
        name: 'Karakovan Balı',
        price: const MoneyCents(50000),
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      const manager = ActorContext(userId: 'm-1', username: 'yonetici', role: AppRole.manager);

      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pEntity, quantity: 2);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(100000)),
      ]);
      final sale = await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: notifier.state,
          receiptNo: 'REC-IDEMP-CONFLICT',
          storeTitle: 'Store',
          actor: manager,
        ),
      );

      const idempKey = 'idemp-conflict-test-key';

      // 1. Adım: 1 adet iade et (500 TL)
      await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          items: [const RefundItemRequest(productId: 'p-bal', quantity: 1)],
          idempotencyKey: idempKey,
        ),
      );

      // 2. Adım: Aynı anahtarla 2 adet (1000 TL) iade etmeye çalış -> StateError
      expect(
        () => refundUseCase.execute(
          RefundRequest(
            originalSaleId: sale.id,
            actor: manager,
            items: [const RefundItemRequest(productId: 'p-bal', quantity: 2)],
            idempotencyKey: idempKey,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    // ─────────────────────────────────────────────────────────────────────────
    // BULGU 10.1.5: EŞZAMANLI İADE YARIŞI VE ÇOKLU SATIR KORUMASI
    // ─────────────────────────────────────────────────────────────────────────
    test('10.1.5: Eşzamanlı iki iade yarıştığında toplam iade satılan miktarı aşamaz, kaybeden güvenle hata alır', () async {
      final pEntity = ProductEntity(
        id: 'p-bal',
        barcode: '8690555',
        name: 'Karakovan Balı',
        price: const MoneyCents(50000),
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      const manager = ActorContext(userId: 'm-1', username: 'yonetici', role: AppRole.manager);

      // 2 adet sat (Stok 48)
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pEntity, quantity: 2);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(100000)),
      ]);
      final sale = await checkoutUseCase.execute(
        CheckoutRequest(
          flowState: notifier.state,
          receiptNo: 'REC-RACE-SALE',
          storeTitle: 'Store',
          actor: manager,
        ),
      );

      // Eşzamanlı olarak 2 adet iade isteğini yarıştır (Her ikisi de 2'şer adet iade etmeye çalışsın)
      // Toplam satılan 2 olduğundan, biri başarılı olmalı, diğeri StateError almalıdır!
      int successCount = 0;
      int errorCount = 0;

      final futures = [
        refundUseCase.execute(
          RefundRequest(
            originalSaleId: sale.id,
            actor: manager,
            items: [const RefundItemRequest(productId: 'p-bal', quantity: 2)],
            idempotencyKey: 'race-key-1',
          ),
        ).then((_) {
          successCount++;
        }).catchError((_) {
          errorCount++;
        }),
        refundUseCase.execute(
          RefundRequest(
            originalSaleId: sale.id,
            actor: manager,
            items: [const RefundItemRequest(productId: 'p-bal', quantity: 2)],
            idempotencyKey: 'race-key-2',
          ),
        ).then((_) {
          successCount++;
        }).catchError((_) {
          errorCount++;
        }),
      ];

      await Future.wait(futures);

      expect(successCount, 1, reason: 'Yalnızca bir istek başarılı olmalıdır');
      expect(errorCount, 1, reason: 'Diğer istek satılan miktarı aştığı için hata almalıdır');

      // Nihai stok kesinlikle 50 olmalıdır (48 + 2 = 50, asla 52 olmamalı!)
      final pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-bal'])).first;
      expect(pRow['stock_quantity'], 50, reason: 'Stok haksız biçimde 52ye çıkamaz');
    });

    test('10.1.5: Aynı ürünün birden fazla satırda bulunduğu satışta tüm miktarlar doğru toplanmalıdır', () async {
      final pEntity = ProductEntity(
        id: 'p-bal',
        barcode: '8690555',
        name: 'Karakovan Balı',
        price: const MoneyCents(50000),
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      const manager = ActorContext(userId: 'm-1', username: 'yonetici', role: AppRole.manager);

      // Veritabanına doğrudan AYNI ürün için 2 AYRI satır ekle (2 + 3 = 5 adet)
      final saleId = 'sale-multiline-real';
      final now = DateTime.now().millisecondsSinceEpoch;
      await coreDb.db.insert('sales', {
        'id': saleId,
        'receipt_no': 'REC-MULTI-LINE-SALE',
        'subtotal_cents': 250000,
        'total_cents': 250000,
        'paid_cents': 250000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': now,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'pay-multiline-1',
        'sale_id': saleId,
        'payment_type': 'cash',
        'amount_cents': 250000,
        'created_at': now,
      });
      // SATIR 1: p-bal, 2 adet
      await coreDb.db.insert('sale_items', {
        'id': 'item-line-1',
        'sale_id': saleId,
        'product_id': 'p-bal',
        'barcode': '8690555',
        'product_name': 'Karakovan Balı',
        'unit_price_cents': 50000,
        'quantity': 2,
        'vat_rate': 20,
        'total_cents': 100000,
      });
      // SATIR 2: p-bal, 3 adet (Aynı ürün, ikinci ayrı satır!)
      await coreDb.db.insert('sale_items', {
        'id': 'item-line-2',
        'sale_id': saleId,
        'product_id': 'p-bal',
        'barcode': '8690555',
        'product_name': 'Karakovan Balı',
        'unit_price_cents': 50000,
        'quantity': 3,
        'vat_rate': 20,
        'total_cents': 150000,
      });

      // Doğrula: sale_items tablosunda gerçekten 2 ayrı satır var mı?
      final linesInDb = await coreDb.db.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
      expect(linesInDb.length, 2, reason: 'sale_items tablosunda gerçekten 2 ayrı satır bulunmalıdır');
      expect(linesInDb[0]['product_id'], linesInDb[1]['product_id']);

      // Toplam 5 adet satıldı. 4 adet kısmi iade yapılabilmelidir!
      final refResult = await refundUseCase.execute(
        RefundRequest(
          originalSaleId: saleId,
          actor: manager,
          items: [const RefundItemRequest(productId: 'p-bal', quantity: 4)],
        ),
      );

      expect(refResult.refundTotal.value, 200000);
      expect(refResult.refundedItems.first.quantity, 4);
    });
  });
}
