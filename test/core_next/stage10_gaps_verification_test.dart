// test/core_next/stage10_gaps_verification_test.dart

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_http_client.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_outbox_processor.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_state.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Stage 10 — Kritik Açıkların Kapatılması ve Kanıtlı Doğrulama Testleri', () {
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

      // Başlangıç test ürünü ve müşterisi
      await coreDb.db.insert('products', {
        'id': 'p-peynir',
        'barcode': '8690001',
        'name': 'Ezine Peyniri',
        'price_cents': 20000, // 200.00 TL
        'stock_quantity': 50,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('customers', {
        'id': 'c-kemal',
        'name': 'Kemal Bey',
        'phone': '05551234567',
        'balance_cents': 0,
        'credit_limit_cents': 100000,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      await hardwareWorker.dispose();
      await coreDb.close();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 1. PULL INGESTION: BOOTSTRAP VE ATOMİK CURSOR İLERLEMESİ
    // ─────────────────────────────────────────────────────────────────────────
    test('1. Pull Ingestion: Bootstrap değişiklikleri yerel tablolara atomik yazılmalı ve cursor ilerlemeli', () async {
      final bootstrapDto = SyncBootstrapResponseDto(
        changes: [
          const SyncPullChange(
            revision: 1,
            mutationId: 'm-boot-1',
            deviceId: 'server',
            entityType: 'product',
            entityId: 'p-boot-zeytin',
            operation: 'UPSERT',
            payload: {
              'barcode': '8690099',
              'name': 'Gemlik Zeytini',
              'price': 150.0, // 150 TL -> 15000 kuruş olmalı
              'stock_quantity': 80,
            },
            createdAt: '2026-10-13T10:00:00Z',
          ),
          const SyncPullChange(
            revision: 2,
            mutationId: 'm-boot-2',
            deviceId: 'server',
            entityType: 'customer',
            entityId: 'c-boot-ayse',
            operation: 'UPSERT',
            payload: {
              'name': 'Ayşe Hanım',
              'phone': '05554443322',
              'balance': 500.0, // 500 TL -> 50000 kuruş
            },
            createdAt: '2026-10-13T10:00:00Z',
          ),
        ],
        nextCursor: 500,
      );

      final result = await ingestionService.ingestBootstrap(bootstrapDto);

      expect(result.totalChanges, 2);
      expect(result.productsApplied, 1);
      expect(result.customersApplied, 1);
      expect(result.newCursor, 500);

      // Veritabanı doğrulaması:
      final pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-boot-zeytin'])).first;
      expect(pRow['name'], 'Gemlik Zeytini');
      expect(pRow['price_cents'], 15000);
      expect(pRow['stock_quantity'], 80);

      final cRow = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-boot-ayse'])).first;
      expect(cRow['name'], 'Ayşe Hanım');
      expect(cRow['balance_cents'], 50000);

      // Cursor'ın app_settings içine kaydedildiğini doğrula
      final savedCursor = await ingestionService.getSavedCursor();
      expect(savedCursor, 500);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 2. PULL INGESTION: LWW VE YEREL BEKLEYEN MUTASYONUN KORUNMASI
    // ─────────────────────────────────────────────────────────────────────────
    test('2. Pull Ingestion: Yerelde push bekleyen ürünün üzerine uzak pull yazılmamalı (LWW Koruması)', () async {
      // Yerelde henüz senkronize edilmemiş bir değişiklik kuyruğa at
      await coreDb.db.insert('sync_events', {
        'event_id': 'local-mut-peynir',
        'entity_type': 'product',
        'entity_id': 'p-peynir',
        'operation': 'UPSERT',
        'payload_json': jsonEncode({'price': 300.0}),
        'client_timestamp': 1000,
        'sync_state': 'PENDING',
        'base_revision': 0,
        'attempts': 0,
      });

      // Sunucudan aynı ürün için eski/farklı bir güncelleme geldi
      final pullDto = SyncPullResponseDto(
        changes: [
          const SyncPullChange(
            revision: 5,
            mutationId: 'remote-mut-peynir',
            deviceId: 'other-device',
            entityType: 'product',
            entityId: 'p-peynir',
            operation: 'UPSERT',
            payload: {
              'name': 'Ezine Peyniri (Uzak İsim)',
              'price': 100.0, // 100 TL
            },
            createdAt: '2026-10-13T10:00:00Z',
          ),
        ],
        nextCursor: 600,
      );

      final result = await ingestionService.ingestPull(pullDto);

      // Kural gereği yerel bekleyen değişiklik ezilmemeli!
      expect(result.skippedDueToPendingLocal, 1);
      expect(result.productsApplied, 0);

      // Yerel ürünün fiyatı hâlâ 20000 kuruş olmalı (ezilmedi)
      final row = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-peynir'])).first;
      expect(row['price_cents'], 20000);
      expect(row['name'], 'Ezine Peyniri');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 3. PULL INGESTION: TOMBSTONE VE SİLME YÖNETİMİ
    // ─────────────────────────────────────────────────────────────────────────
    test('3. Pull Ingestion: DELETE veya is_deleted=true kaydı ürünü tombstone olarak işaretlemeli', () async {
      final deleteDto = SyncPullResponseDto(
        changes: [
          const SyncPullChange(
            revision: 8,
            mutationId: 'del-peynir',
            deviceId: 'server',
            entityType: 'product',
            entityId: 'p-peynir',
            operation: 'DELETE',
            payload: {'is_deleted': true},
            createdAt: '2026-10-13T10:30:00Z',
          ),
        ],
        nextCursor: 700,
      );

      await ingestionService.ingestPull(deleteDto);

      final row = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-peynir'])).first;
      expect(row['is_deleted'], 1);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 4. RBAC: POZİTİF YETKİ SENARYOLARI (YÖNETİCİ VE YETKİLİ KASİYER)
    // ─────────────────────────────────────────────────────────────────────────
    test('4. RBAC: Yetkili yönetici iskonto ve veresiye ile satışı tamamlayabilmeli', () async {
      final pEntity = ProductEntity(
        id: 'p-peynir',
        barcode: '8690001',
        name: 'Ezine Peyniri',
        price: const MoneyCents(20000), // 200 TL
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pEntity, quantity: 1);
      notifier.setGeneralDiscount(const MoneyCents(5000)); // 50 TL iskonto (Net 150 TL)
      final cust = await ledgerRepo.getCustomer('c-kemal');
      notifier.selectCustomer(cust);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(15000)),
      ]);

      const managerActor = ActorContext(
        userId: 'mgr-1',
        username: 'ahmet_manager',
        role: AppRole.manager,
      );

      final sale = await notifier.completeCheckout(
        receiptNo: 'REC-RBAC-OK-1',
        storeTitle: 'Serenut Gurme',
        actor: managerActor,
      );

      expect(sale.receiptNo, 'REC-RBAC-OK-1');
      expect(sale.discount.value, 5000);
      expect(sale.total.value, 15000);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 5. RBAC: NEGATİF YETKİ KONTROLLERİ (YETKİSİZ İŞLEMLERİN ENGELLENMESİ)
    // ─────────────────────────────────────────────────────────────────────────
    test('5. RBAC: Kasiyer iskonto yetkisi olmadan iskonto uygulayamaz, DB ve outbox temiz kalmalıdır', () async {
      final pEntity = ProductEntity(
        id: 'p-peynir',
        barcode: '8690001',
        name: 'Ezine Peyniri',
        price: const MoneyCents(20000),
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pEntity, quantity: 1);
      notifier.setGeneralDiscount(const MoneyCents(2000)); // 20 TL İskonto
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(18000)),
      ]);

      const cashierActor = ActorContext(
        userId: 'csh-1',
        username: 'kasiyer_veli',
        role: AppRole.cashier, // Kasiyerin varsayılan olarak iskonto yetkisi YOK
      );

      // Yetkisiz işlem istisnası fırlatılmalıdır
      expect(
        () => notifier.completeCheckout(
          receiptNo: 'REC-UNAUTH-1',
          storeTitle: 'Serenut Gurme',
          actor: cashierActor,
        ),
        throwsA(
          isA<AuthorizationException>()
              .having((e) => e.requiredPermission, 'permission', AppPermission.applyDiscount)
              .having((e) => e.userRole, 'role', AppRole.cashier),
        ),
      );

      // Kritik Güvenlik Doğrulaması: Satış ve outbox tablolarında HİÇBİR artık kayıt oluşmamalıdır!
      final sales = await coreDb.db.query('sales', where: 'receipt_no = ?', whereArgs: ['REC-UNAUTH-1']);
      expect(sales.isEmpty, true);

      final outbox = await coreDb.db.query('sync_events');
      expect(outbox.isEmpty, true);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 6. İADE VE İPTAL: TAM İADE VE STOK GERİ ALIMI (REINSTATEMENT)
    // ─────────────────────────────────────────────────────────────────────────
    test('6. İade: Tam iade orijinal satışı silmeden ters kayıt açmalı ve stoğu geri artırmalıdır', () async {
      final pEntity = ProductEntity(
        id: 'p-peynir',
        barcode: '8690001',
        name: 'Ezine Peyniri',
        price: const MoneyCents(20000), // 200 TL
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      // 1. Satış yap (Stok 50 -> 48'e iner)
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pEntity, quantity: 2);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(40000)),
      ]);

      final completedSale = await notifier.completeCheckout(
        receiptNo: 'REC-TO-REFUND-1',
        storeTitle: 'Serenut',
        actor: ActorContext.testCashier,
      );

      var pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-peynir'])).first;
      expect(pRow['stock_quantity'], 48);

      // 2. Yetkili Yönetici İle Tam İade Yap
      const managerActor = ActorContext(
        userId: 'mgr-1',
        username: 'yonetici',
        role: AppRole.manager,
      );

      final refundResult = await refundUseCase.execute(
        RefundRequest(
          originalSaleId: completedSale.id,
          actor: managerActor,
          reason: 'Bozuk Ürün İadesi',
        ),
      );

      expect(refundResult.refundTotal.value, 40000);
      expect(refundResult.receiptNo, 'REF-REC-TO-REFUND-1');

      // 3. Stok Kontrolü: 48 + 2 = 50'ye geri dönmeli!
      pRow = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-peynir'])).first;
      expect(pRow['stock_quantity'], 50);

      // 4. Orijinal Satış Korunmalı (Silinmemeli)
      final origSale = (await coreDb.db.query('sales', where: 'id = ?', whereArgs: [completedSale.id])).first;
      expect(origSale['status'], 'COMPLETED');

      // 5. İade Satış Kaydı Oluşmalı
      final refSale = (await coreDb.db.query('sales', where: 'id = ?', whereArgs: [refundResult.refundId])).first;
      expect(refSale['status'], 'REFUND');
      expect(refSale['total_cents'], -40000);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 7. İADE: KISMİ İADE VE AŞIRI İADE ENGELİ
    // ─────────────────────────────────────────────────────────────────────────
    test('7. İade: Kısmi iade yapılabilmeli, ancak satın alınandan fazla iade engellenmelidir', () async {
      final pEntity = ProductEntity(
        id: 'p-peynir',
        barcode: '8690001',
        name: 'Ezine Peyniri',
        price: const MoneyCents(20000),
        stockQuantity: 50,
        updatedAt: DateTime.now(),
      );

      // 2 adet sat
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      notifier.addProduct(pEntity, quantity: 2);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(40000)),
      ]);
      final sale = await notifier.completeCheckout(
        receiptNo: 'REC-PARTIAL-1',
        storeTitle: 'Serenut',
        actor: ActorContext.testCashier,
      );

      const manager = ActorContext(userId: 'm-1', username: 'm', role: AppRole.manager);

      // 1. Adım: 1 adet kısmi iade yap (Başarılı olmalı)
      final partialRef = await refundUseCase.execute(
        RefundRequest(
          originalSaleId: sale.id,
          actor: manager,
          items: [const RefundItemRequest(productId: 'p-peynir', quantity: 1)],
        ),
      );
      expect(partialRef.refundTotal.value, 20000);

      // 2. Adım: Kalan 1 adetten fazlasını (örn. 2 adet daha) iade etmeye çalış
      expect(
        () => refundUseCase.execute(
          RefundRequest(
            originalSaleId: sale.id,
            actor: manager,
            items: [const RefundItemRequest(productId: 'p-peynir', quantity: 2)],
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 8. İADE: YETKİSİZ KULLANICI İADE YAPAMAZ
    // ─────────────────────────────────────────────────────────────────────────
    test('8. İade: İade yetkisi olmayan kasiyer iade talebinde AuthorizationException almalıdır', () async {
      const cashier = ActorContext(userId: 'c-1', username: 'kasiyer', role: AppRole.cashier);

      expect(
        () => refundUseCase.execute(
          const RefundRequest(
            originalSaleId: 'sale-dummy-id',
            actor: cashier,
          ),
        ),
        throwsA(isA<AuthorizationException>()),
      );
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 9. OUTBOX: GRUP İÇİ NEDENSEL SIRALAMA (ZAMAN FARKLILIKLARINA KARŞI GÜVENCE)
    // ─────────────────────────────────────────────────────────────────────────
    test('9. Outbox: Aynı grupta finansal hareket daha eski zaman damgasına sahip olsa bile Satış (causal 1) önce gitmelidir', () async {
      // Bilerek finansal hareketi 1000ms, satışı 2000ms zaman damgasıyla ekle
      const groupId = 'group-resilience-sale-1';

      await coreDb.db.insert('sync_events', {
        'event_id': 'mut-fin-early-time',
        'entity_type': 'financial_transaction',
        'entity_id': 'fin-1',
        'operation': 'UPSERT',
        'payload_json': jsonEncode({'amount': 100.0}),
        'client_timestamp': 1000, // DAHA ESKİ ZAMAN DAMGASI
        'sync_state': 'PENDING',
        'base_revision': 0,
        'attempts': 0,
        'group_id': groupId,
        'causal_sequence': 2, // ANCAK 2. SIRA!
      });

      await coreDb.db.insert('sync_events', {
        'event_id': 'mut-sale-late-time',
        'entity_type': 'sale',
        'entity_id': 'sale-1',
        'operation': 'UPSERT',
        'payload_json': jsonEncode({'total_amount': 100.0}),
        'client_timestamp': 2000, // DAHA YENİ ZAMAN DAMGASI
        'sync_state': 'PENDING',
        'base_revision': 0,
        'attempts': 0,
        'group_id': groupId,
        'causal_sequence': 1, // ANCAK 1. SIRA!
      });

      late List<dynamic> pushedList;
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        pushedList = body['mutations'] as List;
        return http.Response(
          jsonEncode({
            'results': [
              {'mutation_id': 'mut-sale-late-time', 'revision': 1},
              {'mutation_id': 'mut-fin-early-time', 'revision': 2},
            ],
            'conflicts': [],
            'rejected': [],
          }),
          200,
        );
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: 'https://fake-audit.local/api/v4/sync',
        deviceActivationId: 'act-1',
        deviceId: 'dev-1',
        client: mockClient,
      );
      final processor = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient);

      await processor.processOutbox();

      // Grup farkındalığı sayesinde Satış (causal 1) kesinlikle ilk sırada gitmelidir!
      expect(pushedList.length, 2);
      expect(pushedList[0]['mutation_id'], 'mut-sale-late-time');
      expect(pushedList[0]['entity_type'], 'sale');
      expect(pushedList[1]['mutation_id'], 'mut-fin-early-time');
      expect(pushedList[1]['entity_type'], 'financial_transaction');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 10. OUTBOX KURTARMA: REDDEDİLEN MUTASYONLARI LİSTELEME VE YENİDEN DENEME
    // ─────────────────────────────────────────────────────────────────────────
    test('10. Outbox Kurtarma: REJECTED mutasyonlar listelenebilmeli ve düzeltildikten sonra PENDING yapılabilmelidir', () async {
      await coreDb.db.insert('sync_events', {
        'event_id': 'mut-rejected-item',
        'entity_type': 'sale',
        'entity_id': 'sale-rej-1',
        'operation': 'UPSERT',
        'payload_json': jsonEncode({'total': 100}),
        'client_timestamp': 5000,
        'sync_state': 'REJECTED',
        'last_error': 'invalid_customer',
        'attempts': 1,
      });

      final httpClient = SyncV4HttpClient(
        baseUrl: 'https://fake-audit.local/api/v4/sync',
        deviceActivationId: 'act-1',
        deviceId: 'dev-1',
      );
      final processor = SyncV4OutboxProcessor(db: coreDb, httpClient: httpClient);

      // Reddedilenleri listele
      final rejected = await processor.getRejectedMutations();
      expect(rejected.length, 1);
      expect(rejected.first.eventId, 'mut-rejected-item');
      expect(rejected.first.lastError, 'invalid_customer');

      // Kurtarma / Yeniden denemeye alma
      await processor.retryRejectedMutation('mut-rejected-item');

      final row = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut-rejected-item'])).first;
      expect(row['sync_state'], 'PENDING');
      expect(row['last_error'], isNull);
    });
  });
}
