// test/core_next/sync_v4_outbox_adapter_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/sync_mutation.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/schema_definitions.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_payload_adapter.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Stage 8.2B — Outbox ve Payload Adaptörü Adli Doğrulama Testleri', () {
    late CoreAppDatabase coreDb;
    late SqliteLedgerRepository ledgerRepo;
    late LedgerService ledgerService;
    late HardwareWorker hardwareWorker;
    late CoreCheckoutUseCase checkoutUseCase;

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

      // Test için örnek ürün ve müşteri ekle
      await coreDb.db.insert('products', {
        'id': 'p-peynir',
        'barcode': '8690001',
        'name': 'Ezine Peyniri',
        'price_cents': 25000, // 250.00 TL
        'stock_quantity': 100,
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

    test('1 & 2. DTO Alanları Sunucu Şemasıyla Uyumlu ve Entity Type Küçük Harf', () {
      final item = SaleOrderItemEntity(
        id: 'item-1',
        saleId: 'sale-1',
        productId: 'p-peynir',
        barcode: '8690001',
        productName: 'Ezine Peyniri',
        vatRate: 20,
        unitPrice: const MoneyCents(25000),
        quantity: 2,
        total: const MoneyCents(50000),
      );

      final mutation = SyncV4PayloadAdapter.buildSaleMutation(
        saleId: 'sale-1',
        receiptNo: 'REC-001',
        customerId: null,
        orderItems: [item],
        subtotal: const MoneyCents(50000),
        generalDiscount: MoneyCents.zero,
        total: const MoneyCents(50000),
        paid: const MoneyCents(50000),
        debt: MoneyCents.zero,
        splits: [const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(50000))],
        createdAt: DateTime.parse('2026-10-13T12:00:00Z'),
        idempotencyKey: 'idemp-1',
      );

      final serverDto = mutation.toServerMutationDto();

      // Sunucu zorunlu alan kontrolü
      expect(serverDto['mutation_id'], mutation.eventId);
      expect(serverDto['entity_type'], 'sale'); // BÜYÜK DEĞİL, KÜÇÜK HARF
      expect(serverDto['entity_id'], 'sale-1');
      expect(serverDto['operation'], 'UPSERT');
      expect(serverDto['base_revision'], 0);
      expect(serverDto['payload'], isA<Map<String, dynamic>>());

      final payload = serverDto['payload'] as Map<String, dynamic>;
      expect(payload['total_amount'], 500.0);
      expect(payload['paid_amount'], 500.0);
      expect(payload['payment_method'], 'cash');
    });

    test('3. Satış Kalemleri Eksiksiz ve Tutarlı', () {
      final item1 = SaleOrderItemEntity(
        id: 'item-1',
        saleId: 'sale-2',
        productId: 'p-1',
        barcode: '111',
        productName: 'Ürün 1',
        vatRate: 20,
        unitPrice: const MoneyCents(1000), // 10.00 TL
        quantity: 3,
        total: const MoneyCents(3000), // 30.00 TL
      );
      final item2 = SaleOrderItemEntity(
        id: 'item-2',
        saleId: 'sale-2',
        productId: 'p-2',
        barcode: '222',
        productName: 'Ürün 2',
        vatRate: 20,
        unitPrice: const MoneyCents(2050), // 20.50 TL
        quantity: 1,
        total: const MoneyCents(2050), // 20.50 TL
      );

      final mutation = SyncV4PayloadAdapter.buildSaleMutation(
        saleId: 'sale-2',
        receiptNo: 'REC-002',
        customerId: null,
        orderItems: [item1, item2],
        subtotal: const MoneyCents(5050),
        generalDiscount: MoneyCents.zero,
        total: const MoneyCents(5050),
        paid: const MoneyCents(5050),
        debt: MoneyCents.zero,
        splits: [const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(5050))],
        createdAt: DateTime.now(),
        idempotencyKey: 'idemp-2',
      );

      final payload = mutation.payload;
      final items = payload['items'] as List;
      expect(items.length, 2);
      expect(items[0]['product_id'], 'p-1');
      expect(items[0]['quantity'], 3);
      expect(items[0]['unit_price'], 10.0);
      expect(items[0]['subtotal'], 30.0);

      expect(items[1]['product_id'], 'p-2');
      expect(items[1]['quantity'], 1);
      expect(items[1]['unit_price'], 20.5);
      expect(items[1]['subtotal'], 20.5);
    });

    test('4. Kuruş / Lira Dönüşümü Sınır Değerlerinde Kuruşu Kuruşuna Doğru', () {
      expect(SyncV4PayloadAdapter.toLira(const MoneyCents(1)), 0.01);
      expect(SyncV4PayloadAdapter.toLira(const MoneyCents(1234)), 12.34);
      expect(SyncV4PayloadAdapter.toLira(const MoneyCents(100050)), 1000.50);
      expect(SyncV4PayloadAdapter.toLira(const MoneyCents(0)), 0.0);
    });

    test('5. Nakit, Kart, Vadeli ve Karma Ödemeler Doğru Temsil Ediliyor', () {
      final dummyItem = SaleOrderItemEntity(
        id: 'it-1',
        saleId: 's',
        productId: 'p',
        barcode: '8690000',
        productName: 'P',
        vatRate: 20,
        unitPrice: const MoneyCents(10000),
        quantity: 1,
        total: const MoneyCents(10000),
      );

      // A) Tamamen Nakit
      final cashMut = SyncV4PayloadAdapter.buildSaleMutation(
        saleId: 's1',
        receiptNo: 'R1',
        customerId: null,
        orderItems: [dummyItem],
        subtotal: const MoneyCents(10000),
        generalDiscount: MoneyCents.zero,
        total: const MoneyCents(10000),
        paid: const MoneyCents(10000),
        debt: MoneyCents.zero,
        splits: [const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(10000))],
        createdAt: DateTime.now(),
        idempotencyKey: 'k1',
      );
      expect(cashMut.payload['payment_method'], 'cash');
      expect(cashMut.payload['paid_amount'], 100.0);

      // B) Tamamen Kart
      final cardMut = SyncV4PayloadAdapter.buildSaleMutation(
        saleId: 's2',
        receiptNo: 'R2',
        customerId: null,
        orderItems: [dummyItem],
        subtotal: const MoneyCents(10000),
        generalDiscount: MoneyCents.zero,
        total: const MoneyCents(10000),
        paid: const MoneyCents(10000),
        debt: MoneyCents.zero,
        splits: [const PaymentSplitEntity(type: PaymentType.creditCard, amount: MoneyCents(10000))],
        createdAt: DateTime.now(),
        idempotencyKey: 'k2',
      );
      expect(cardMut.payload['payment_method'], 'card');
      expect(cardMut.payload['paid_amount'], 100.0);

      // C) Tamamen Veresiye
      final debtMut = SyncV4PayloadAdapter.buildSaleMutation(
        saleId: 's3',
        receiptNo: 'R3',
        customerId: 'c-kemal',
        orderItems: [dummyItem],
        subtotal: const MoneyCents(10000),
        generalDiscount: MoneyCents.zero,
        total: const MoneyCents(10000),
        paid: MoneyCents.zero,
        debt: const MoneyCents(10000),
        splits: [const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(10000))],
        createdAt: DateTime.now(),
        idempotencyKey: 'k3',
      );
      expect(debtMut.payload['payment_method'], 'veresiye');
      expect(debtMut.payload['paid_amount'], 0.0);

      // D) Karma (Mixed) Ödeme (40 TL Nakit, 60 TL Veresiye)
      final mixedMut = SyncV4PayloadAdapter.buildSaleMutation(
        saleId: 's4',
        receiptNo: 'R4',
        customerId: 'c-kemal',
        orderItems: [dummyItem],
        subtotal: const MoneyCents(10000),
        generalDiscount: MoneyCents.zero,
        total: const MoneyCents(10000),
        paid: const MoneyCents(4000),
        debt: const MoneyCents(6000),
        splits: [
          const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(4000)),
          const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(6000)),
        ],
        createdAt: DateTime.now(),
        idempotencyKey: 'k4',
      );
      expect(mixedMut.payload['payment_method'], 'mixed');
      expect(mixedMut.payload['paid_amount'], 40.0);
      expect(mixedMut.payload['total_amount'], 100.0);
    });

    test('6. Satış ve Finansal Mutasyonlar Tek Transaction İçinde Oluşturuluyor', () async {
      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      final product = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-peynir']);
      final pEntity = ProductEntity(
        id: product.first['id'] as String,
        barcode: product.first['barcode'] as String,
        name: product.first['name'] as String,
        price: MoneyCents(product.first['price_cents'] as int),
        stockQuantity: (product.first['stock_quantity'] as num).toInt(),
        updatedAt: DateTime.now(),
      );

      notifier.addProduct(pEntity, quantity: 1); // 250 TL
      final cust = await ledgerRepo.getCustomer('c-kemal');
      notifier.selectCustomer(cust);
      // 100 TL peşin, 150 TL veresiye
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(10000)),
        const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(15000)),
      ]);

      final completedSale = await notifier.completeCheckout(
        receiptNo: 'REC-TX-1',
        storeTitle: 'Serenut Gurme',
      );
      expect(completedSale.receiptNo, 'REC-TX-1');

      // Outbox tablosunu doğrula
      final outbox = await coreDb.db.query('sync_events', orderBy: 'causal_sequence ASC');
      expect(outbox.length, 2, reason: '1 sale + 1 financial_transaction mutasyonu olmalıdır');

      // 1. Sıradaki: sale
      expect(outbox[0]['entity_type'], 'sale');
      expect(outbox[0]['entity_id'], completedSale.id);
      expect(outbox[0]['causal_sequence'], 1);
      expect(outbox[0]['group_id'], completedSale.id);

      // 2. Sıradaki: financial_transaction
      expect(outbox[1]['entity_type'], 'financial_transaction');
      expect(outbox[1]['causal_sequence'], 2);
      expect(outbox[1]['group_id'], completedSale.id);

      final finPayload = SyncMutation.fromDbRow(outbox[1]).payload;
      expect(finPayload['type'], 'sale');
      expect(finPayload['customer_id'], 'c-kemal');
      expect(finPayload['reference_id'], completedSale.id);
      expect(finPayload['amount'], 250.0);
      expect(finPayload['paid_amount'], 100.0);
      expect(finPayload['debt_amount'], 150.0);
    });

    test('7. Her Hata Enjeksiyonunda Bütün Outbox ve Finansal Kayıtlar Rollback Oluyor', () async {
      final faultHookUseCase = CoreCheckoutUseCase(
        db: coreDb,
        ledgerService: ledgerService,
        hardwareWorker: hardwareWorker,
        faultHook: (step) async {
          if (step == 'after_sync_events_insert') {
            throw Exception('Simulated crash after outbox insert');
          }
        },
      );

      final notifier = CoreSalesFlowNotifier(faultHookUseCase);
      final pEntity = ProductEntity(
        id: 'p-peynir',
        barcode: '8690001',
        name: 'Ezine Peyniri',
        price: const MoneyCents(25000),
        stockQuantity: 100,
        updatedAt: DateTime.now(),
      );
      notifier.addProduct(pEntity, quantity: 1);
      notifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(25000)),
      ]);

      expect(
        () => notifier.completeCheckout(
          receiptNo: 'REC-FAIL-1',
          storeTitle: 'Serenut Gurme',
        ),
        throwsA(isA<Exception>()),
      );

      // Sıfır artık kayıt kontrolü
      final sales = await coreDb.db.query('sales', where: 'receipt_no = ?', whereArgs: ['REC-FAIL-1']);
      expect(sales.isEmpty, true);

      final syncEvents = await coreDb.db.query('sync_events');
      expect(syncEvents.isEmpty, true, reason: 'Transaction rollback olduğunda sync_events bomboş kalmalıdır');
    });

    test('8. Aynı Satış Tekrar Hazırlandığında Determinizm ve İdempotency', () {
      final item = SaleOrderItemEntity(
        id: 'it-1',
        saleId: 'sale-det-1',
        productId: 'p-1',
        barcode: '111',
        productName: 'Ürün',
        vatRate: 20,
        unitPrice: const MoneyCents(1000),
        quantity: 1,
        total: const MoneyCents(1000),
      );

      final time = DateTime.parse('2026-10-13T10:00:00Z');
      const eventId = 'det-uuid-1';

      final mut1 = SyncV4PayloadAdapter.buildSaleMutation(
        saleId: 'sale-det-1',
        receiptNo: 'R-DET',
        customerId: null,
        orderItems: [item],
        subtotal: const MoneyCents(1000),
        generalDiscount: MoneyCents.zero,
        total: const MoneyCents(1000),
        paid: const MoneyCents(1000),
        debt: MoneyCents.zero,
        splits: [const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(1000))],
        createdAt: time,
        idempotencyKey: 'key-det-1',
        deterministicEventId: eventId,
      );

      final mut2 = SyncV4PayloadAdapter.buildSaleMutation(
        saleId: 'sale-det-1',
        receiptNo: 'R-DET',
        customerId: null,
        orderItems: [item],
        subtotal: const MoneyCents(1000),
        generalDiscount: MoneyCents.zero,
        total: const MoneyCents(1000),
        paid: const MoneyCents(1000),
        debt: MoneyCents.zero,
        splits: [const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(1000))],
        createdAt: time,
        idempotencyKey: 'key-det-1',
        deterministicEventId: eventId,
      );

      expect(mut1.eventId, mut2.eventId);
      expect(mut1.toServerMutationDto(), mut2.toServerMutationDto());
    });

    test('9. Kuyrukta Eski v1 Kayıtlar Varsa Migration Onları Kaybetmiyor ve Normalize Ediyor', () async {
      // 1. Doğrudan v1 formatında izole bir SQLite veritabanı oluştur
      final dbPath = 'in_memory_migration_v1_test_${DateTime.now().microsecondsSinceEpoch}.db';
      final legacyDb = await openDatabase(
        dbPath,
        singleInstance: false,
        version: 1,
        onCreate: (db, v) async {
          await db.execute('''
            CREATE TABLE sync_events (
              event_id TEXT PRIMARY KEY NOT NULL,
              entity_type TEXT NOT NULL,
              entity_id TEXT NOT NULL,
              operation TEXT NOT NULL,
              payload_json TEXT NOT NULL,
              client_timestamp INTEGER NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'PENDING'
            );
          ''');
          // Eski büyük harfli kayıt ekle
          await db.insert('sync_events', {
            'event_id': 'legacy-ev-1',
            'entity_type': 'SALE',
            'entity_id': 'legacy-sale-1',
            'operation': 'UPSERT',
            'payload_json': '{"legacy": true}',
            'client_timestamp': 1700000000,
            'sync_state': 'PENDING',
          });
        },
      );

      // 2. Migration'ı çalıştır (v1 -> v2)
      await CoreSchemaDefinitions.migrate(legacyDb, 1, 2);

      // 3. Tabloyu doğrula: Kolonlar eklenmiş ve veri korunmuş olmalı
      final migratedRows = await legacyDb.query('sync_events');
      expect(migratedRows.length, 1);
      final row = migratedRows.first;

      expect(row['event_id'], 'legacy-ev-1');
      expect(row['entity_type'], 'sale'); // 'SALE' -> 'sale' normalize edildi!
      expect(row['base_revision'], 0);
      expect(row['attempts'], 0);
      expect(row['causal_sequence'], 0);

      await legacyDb.close();
    });

    test('10. Müşteri-Satış-Finansal İşlem Bağımlılıkları ve Nedensel Sıra Korunuyor', () {
      final saleMutation = SyncV4PayloadAdapter.buildSaleMutation(
        saleId: 'sale-dep',
        receiptNo: 'REC-DEP',
        customerId: 'cust-dep',
        orderItems: [
          SaleOrderItemEntity(
            id: 'it-1',
            saleId: 'sale-dep',
            productId: 'p-1',
            barcode: '111',
            productName: 'P',
            vatRate: 20,
            unitPrice: const MoneyCents(5000),
            quantity: 1,
            total: const MoneyCents(5000),
          )
        ],
        subtotal: const MoneyCents(5000),
        generalDiscount: MoneyCents.zero,
        total: const MoneyCents(5000),
        paid: MoneyCents.zero,
        debt: const MoneyCents(5000),
        splits: [const PaymentSplitEntity(type: PaymentType.onAccount, amount: MoneyCents(5000))],
        createdAt: DateTime.now(),
        idempotencyKey: 'k-dep',
      );

      final finMutation = SyncV4PayloadAdapter.buildFinancialTransactionMutation(
        saleId: 'sale-dep',
        customerId: 'cust-dep',
        total: const MoneyCents(5000),
        paid: MoneyCents.zero,
        debt: const MoneyCents(5000),
        paymentMethod: 'veresiye',
        createdAt: DateTime.now(),
      );

      // Grup ve Nedensel Sıra İncelemesi:
      expect(saleMutation.groupId, 'sale-dep');
      expect(finMutation.groupId, 'sale-dep');

      expect(saleMutation.causalSequence < finMutation.causalSequence, true,
          reason: 'Satış (causalSequence=1), finansal hareketten (causalSequence=2) önce gelmelidir.');
    });

    test('11. Bozuk veya Eksik Satış İçin Geçerli Görünen Payload Üretilemez', () {
      // Kalemsiz satış:
      expect(
        () => SyncV4PayloadAdapter.buildSaleMutation(
          saleId: 's',
          receiptNo: 'r',
          customerId: null,
          orderItems: [],
          subtotal: MoneyCents.zero,
          generalDiscount: MoneyCents.zero,
          total: MoneyCents.zero,
          paid: MoneyCents.zero,
          debt: MoneyCents.zero,
          splits: [],
          createdAt: DateTime.now(),
          idempotencyKey: 'k',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Toplam tutar uyuşmazlığı (subtotal 100 TL iken total 200 TL verilirse):
      expect(
        () => SyncV4PayloadAdapter.buildSaleMutation(
          saleId: 's',
          receiptNo: 'r',
          customerId: null,
          orderItems: [
            SaleOrderItemEntity(
              id: '1',
              saleId: 's',
              productId: 'p',
              barcode: '869',
              productName: 'P',
              vatRate: 20,
              unitPrice: const MoneyCents(10000),
              quantity: 1,
              total: const MoneyCents(10000),
            )
          ],
          subtotal: const MoneyCents(10000),
          generalDiscount: MoneyCents.zero,
          total: const MoneyCents(20000), // Uyuşmazlık!
          paid: const MoneyCents(20000),
          debt: MoneyCents.zero,
          splits: [const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(20000))],
          createdAt: DateTime.now(),
          idempotencyKey: 'k',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('12. İade ve İptal Desteği Yoksa Bu Durum Açıkça Reddediliyor', () {
      // Satış DELETE girişimi:
      expect(
        () => SyncV4PayloadAdapter.validateOperation('sale', 'DELETE'),
        throwsA(isA<UnsupportedError>()),
      );

      // İade girişimi:
      expect(
        () => SyncV4PayloadAdapter.validateOperation('refund', 'UPSERT'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
