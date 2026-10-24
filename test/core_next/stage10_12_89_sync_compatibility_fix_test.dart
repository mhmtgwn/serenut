// test/core_next/stage10_12_89_sync_compatibility_fix_test.dart
// SERENUT OS — STAGE 10.12.89
// Hedefli Sync V4 / Protocol 6 Uyumluluk ve Koruma Doğrulama Testleri

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/sync_mutation.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_product_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_customer_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_financial_transaction_repository.dart';
import '../../core_next/client_core/lib/infrastructure/sync/sync_v4_payload_adapter.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('STAGE 10.12.89 — Sync V4 Payload Adaptörü ve Alan Eşleme Testleri', () {
    test('1. Ürün Fiyatı, Maliyet ve Stok Alanları Protocol 6 ile Tam Uyumlu', () {
      final mutation = SyncV4PayloadAdapter.buildProductMutation(
        productId: 'p-test-01',
        name: 'Ezine Peyniri 500g',
        priceCents: 25000, // 250.00 TL
        costPriceCents: 17550, // 175.50 TL
        stockQuantity: 42,
        minStock: 10,
        category: 'Şarküteri',
        unit: 'adet',
        vatRate: 20,
        imageUrl: 'https://cdn.serenut.com/p1.jpg',
        updatedAt: DateTime.parse('2026-10-22T00:00:00Z'),
        deterministicEventId: 'evt-test-p1',
      );

      final serverDto = mutation.toServerMutationDto();
      final payload = serverDto['payload'] as Map<String, dynamic>;

      // Sunucu zorunlu Protocol 6 anahtarları
      expect(serverDto['entity_type'], equals('product'));
      expect(serverDto['entity_id'], equals('p-test-01'));
      expect(serverDto['operation'], equals('UPSERT'));

      // Fiyat ve maliyetin Lira (ondalık) dönüşümü doğrulaması
      expect(payload['price'], equals(250.00));
      expect(payload['purchase_price'], equals(175.50));
      expect(payload['quantity'], equals(42));
      expect(payload['unit'], equals('adet'));
      expect(payload['category'], equals('Şarküteri'));
      expect(payload['vat'], equals(20));

      // İstemci yerel kuruş alanlarının korunması
      expect(payload['price_cents'], equals(25000));
      expect(payload['cost_price_cents'], equals(17550));
      expect(payload['stock_quantity'], equals(42));
    });

    test('2. Kısmi Güncelleme, Sıfır Fiyat ve Null Maliyet Ayrımı', () {
      // Sıfır fiyatlı promosyon ürünü
      final freeProd = SyncV4PayloadAdapter.buildProductMutation(
        productId: 'p-free-01',
        name: 'Tadım Promosyon',
        priceCents: 0,
        costPriceCents: null, // maliyet bilinmiyor
        stockQuantity: 100,
        updatedAt: DateTime.now(),
      );
      final freePayload = freeProd.payload;
      expect(freePayload['price'], equals(0.0));
      expect(freePayload['purchase_price'], equals(0.0));
      expect(freePayload['cost_price_cents'], isNull);

      // Negatif fiyat reddedilmeli
      expect(
        () => SyncV4PayloadAdapter.buildProductMutation(
          productId: 'p-neg',
          name: 'Hatalı Ürün',
          priceCents: -500,
          stockQuantity: 10,
          updatedAt: DateTime.now(),
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Negatif maliyet reddedilmeli
      expect(
        () => SyncV4PayloadAdapter.buildProductMutation(
          productId: 'p-neg-cost',
          name: 'Hatalı Maliyet',
          priceCents: 1000,
          costPriceCents: -100,
          stockQuantity: 10,
          updatedAt: DateTime.now(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('3. Müşteri Adres ve Kredi Limiti Alan Eşleme Doğrulaması', () {
      final custMutation = SyncV4PayloadAdapter.buildCustomerMutation(
        customerId: 'c-test-01',
        name: 'Ahmet Yılmaz',
        phone: '05551112233',
        email: 'ahmet@example.com',
        address: 'Bağdat Cad. No: 12 Kadıköy',
        balanceCents: 0,
        creditLimitCents: 500000, // 5000.00 TL
        updatedAt: DateTime.parse('2026-10-22T00:00:00Z'),
      );

      final payload = custMutation.payload;
      expect(payload['id'], equals('c-test-01'));
      expect(payload['name'], equals('Ahmet Yılmaz'));
      expect(payload['address'], equals('Bağdat Cad. No: 12 Kadıköy'));
      expect(payload['notes'], equals('Bağdat Cad. No: 12 Kadıköy'));
      expect(payload['credit_limit'], equals(5000.00));
      expect(payload['credit_limit_cents'], equals(500000));
      expect(payload['status'], equals('active'));
    });

    test('4. Finansal İşlem: debt -> manual_debt Dönüşümü ve Satış Referansı Koruması', () {
      // A. Satış referansı olmayan doğrudan borç -> manual_debt olmalıdır
      final manualDebtMutation = SyncV4PayloadAdapter.buildFinancialMutation(
        id: 'ft-m-1',
        type: 'debt',
        customerId: 'c-test-01',
        total: const MoneyCents(15000), // 150.00 TL
        paid: MoneyCents.zero,
        debt: const MoneyCents(15000),
        referenceId: null,
        description: 'Elden Veresiye Borç Kaydı',
        createdAt: DateTime.now(),
      );

      expect(manualDebtMutation.payload['type'], equals('manual_debt'));
      expect(manualDebtMutation.payload['amount'], equals(150.00));
      expect(manualDebtMutation.payload['paid_amount'], equals(0.0));
      expect(manualDebtMutation.payload['debt_amount'], equals(150.00));

      // B. Satış referansı içeren vadeli satış borcu -> sale olmalıdır
      final saleDebtMutation = SyncV4PayloadAdapter.buildFinancialMutation(
        id: 'ft-s-1',
        type: 'debt',
        customerId: 'c-test-01',
        total: const MoneyCents(20000),
        paid: MoneyCents.zero,
        debt: const MoneyCents(20000),
        referenceId: 'sale-uuid-123',
        createdAt: DateTime.now(),
      );

      expect(saleDebtMutation.payload['type'], equals('sale'));
      expect(saleDebtMutation.payload['reference_id'], equals('sale-uuid-123'));
    });

    test('5. Satış, Tahsilat, İptal ve İade Türlerinin Sözleşmeye Uygunluğu', () {
      final now = DateTime.now();

      // Tahsilat (collection)
      final col = SyncV4PayloadAdapter.buildFinancialMutation(
        id: 'ft-col-1',
        type: 'collection',
        customerId: 'c-1',
        total: const MoneyCents(5000),
        paid: const MoneyCents(5000),
        debt: MoneyCents.zero,
        createdAt: now,
      );
      expect(col.payload['type'], equals('collection'));
      expect(col.payload['amount'], equals(50.0));
      expect(col.payload['paid_amount'], equals(50.0));

      // Ödeme (payment)
      final pay = SyncV4PayloadAdapter.buildFinancialMutation(
        id: 'ft-pay-1',
        type: 'payment',
        customerId: 'c-1',
        total: const MoneyCents(3000),
        paid: const MoneyCents(3000),
        debt: MoneyCents.zero,
        createdAt: now,
      );
      expect(pay.payload['type'], equals('payment'));

      // İptal (cancellation)
      final cancel = SyncV4PayloadAdapter.buildFinancialMutation(
        id: 'ft-can-1',
        type: 'cancellation',
        customerId: 'c-1',
        total: const MoneyCents(10000),
        paid: MoneyCents.zero,
        debt: const MoneyCents(10000),
        referenceId: 'sale-ref-01',
        createdAt: now,
      );
      expect(cancel.payload['type'], equals('cancellation'));
      expect(cancel.payload['reference_id'], equals('sale-ref-01'));
    });

    test('6. Negatif Taksit ve Hareket Koruması (Fail-Closed)', () {
      // Negatif tutarlı finansal hareket SyncV4PayloadAdapter tarafından kesinlikle reddedilmeli
      expect(
        () => SyncV4PayloadAdapter.buildFinancialMutation(
          id: 'ft-neg-1',
          type: 'manual_debt',
          customerId: 'c-1',
          total: const MoneyCents(-446532), // -4465.32 TL (Nutopia taksit satırı örneği)
          paid: MoneyCents.zero,
          debt: const MoneyCents(-446532),
          createdAt: DateTime.now(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('STAGE 10.12.89 — Repository ve Outbox Kuyruğu Entegrasyon Testleri', () {
    late CoreAppDatabase coreDb;
    late CoreNextProductRepository productRepo;
    late CoreNextCustomerRepository customerRepo;
    late CoreNextFinancialTransactionRepository financialRepo;

    setUp(() async {
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: inMemoryDatabasePath);
      productRepo = CoreNextProductRepository(coreDb.db);
      customerRepo = CoreNextCustomerRepository(coreDb.db);
      financialRepo = CoreNextFinancialTransactionRepository(coreDb.db);
    });

    tearDown(() async {
      await coreDb.close();
    });

    test('7. CoreNextProductRepository.create ve update sunucu alanlarını eksiksiz üretir', () async {
      final entity = ProductEntity(
        id: 'p-repo-01',
        name: 'Kaşar Peyniri',
        description: 'Taze Kaşar',
        price: 180.0,
        purchasePrice: 120.0,
        quantity: 50,
        minStock: 5,
        brand: 'Sütaş',
        unit: 'adet',
        shelfCode: 'A1',
        category: 'Süt Ürünleri',
        vat: 20,
        saleType: 'piece',
      );

      await productRepo.create(entity);

      // sync_events kontrolü
      final rows = await coreDb.db.query('sync_events', where: 'entity_id = ?', whereArgs: ['p-repo-01']);
      expect(rows.length, equals(1));
      final payload = jsonDecode(rows.first['payload_json'] as String) as Map<String, dynamic>;

      // Fiyat ve stok alanları hem Lira hem kuruş olarak mevcut olmalı
      expect(payload['price'], equals(180.0));
      expect(payload['purchase_price'], equals(120.0));
      expect(payload['quantity'], equals(50));
      expect(payload['price_cents'], equals(18000));
      expect(payload['cost_price_cents'], equals(12000));
      expect(payload['stock_quantity'], equals(50));
    });

    test('8. CoreNextCustomerRepository.create sunucu address alanını eksiksiz üretir', () async {
      final cust = CustomerEntity(
        id: 'c-repo-01',
        name: 'Fatma Hanım',
        phone: '05441112233',
        email: 'fatma@example.com',
        address: 'Atatürk Mah. Karanfil Sok. No: 5',
        balance: 0.0,
        createdAt: DateTime.now(),
      );

      await customerRepo.create(cust);

      final rows = await coreDb.db.query('sync_events', where: 'entity_id = ?', whereArgs: ['c-repo-01']);
      expect(rows.length, equals(1));
      final payload = jsonDecode(rows.first['payload_json'] as String) as Map<String, dynamic>;

      expect(payload['address'], equals('Atatürk Mah. Karanfil Sok. No: 5'));
      expect(payload['notes'], equals('Atatürk Mah. Karanfil Sok. No: 5'));
    });

    test('9. CoreNextFinancialTransactionRepository: debt -> manual_debt ve Idempotency', () async {
      await coreDb.db.insert('customers', {
        'id': 'c-ft-01',
        'name': 'Borçlu Müşteri',
        'balance_cents': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      final ft = FinancialTransactionEntity(
        id: 'ft-test-01',
        type: 'debt',
        customerId: 'c-ft-01',
        amount: 250.0,
        paidAmount: 0.0,
        debtAmount: 250.0,
        date: DateTime.now(),
      );

      // 1. İlk kayıt
      await financialRepo.create(ft);

      final syncRows = await coreDb.db.query('sync_events', where: 'entity_id = ?', whereArgs: ['ft-test-01']);
      expect(syncRows.length, equals(1));
      final payload = jsonDecode(syncRows.first['payload_json'] as String) as Map<String, dynamic>;

      // Sunucuya 'manual_debt' olarak gitmeli
      expect(payload['type'], equals('manual_debt'));
      expect(payload['amount'], equals(250.0));
      expect(payload['debt_amount'], equals(250.0));
      expect(payload['paid_amount'], equals(0.0));

      // Bakiye kontrolü
      final custRow1 = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-ft-01'])).first;
      expect(custRow1['balance_cents'], equals(-25000));

      // 2. Mükerrer gönderim (Idempotency): bakiye ve kuyruk iki kez yazılmamalı
      await financialRepo.create(ft);
      final custRow2 = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-ft-01'])).first;
      expect(custRow2['balance_cents'], equals(-25000)); // Değişmedi

      final syncRowsAfter = await coreDb.db.query('sync_events', where: 'entity_id = ?', whereArgs: ['ft-test-01']);
      expect(syncRowsAfter.length, equals(1)); // Tek bir mutasyon
    });

    test('10. Negatif Taksit / Düzeltme Satırı sync_events Kuyruğuna Eklenmez (Yerelde Korunur)', () async {
      await coreDb.db.insert('customers', {
        'id': 'c-neg-cust',
        'name': 'Düzeltme Müşterisi',
        'balance_cents': -50000,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Nutopia'daki negatif taksit satırını temsil eden hareket
      final negFt = FinancialTransactionEntity(
        id: 'ft-neg-adjustment',
        type: 'manual_debt',
        customerId: 'c-neg-cust',
        amount: -4465.32,
        paidAmount: 0.0,
        debtAmount: -4465.32,
        date: DateTime.now(),
      );

      // Repo create işlemi çağrıldığında:
      await financialRepo.create(negFt);

      // 1. sync_events kuyruğuna ASLA eklenmemeli (sunucu 400 atmasın)
      final syncRows = await coreDb.db.query('sync_events', where: 'entity_id = ?', whereArgs: ['ft-neg-adjustment']);
      expect(syncRows.isEmpty, isTrue, reason: 'Negatif finansal hareket sunucu sync kuyruğuna eklenmemelidir');

      // 2. Yerel ledger_entries tablosunda kayıt korunmalıdır
      final ledgerRows = await coreDb.db.query('ledger_entries', where: 'id = ?', whereArgs: ['ft-neg-adjustment']);
      expect(ledgerRows.length, equals(1), reason: 'Kayıt yerel veritabanından silinmemeli veya kaybolmamalıdır');
    });

    test('11. getByType("manual_debt") ve getByType("debt") İstemci Sorgularında Uyumlu', () async {
      await coreDb.db.insert('customers', {
        'id': 'c-q-1',
        'name': 'Sorgu Müşterisi',
        'balance_cents': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await financialRepo.create(FinancialTransactionEntity(
        id: 'ft-q-1',
        type: 'manual_debt',
        customerId: 'c-q-1',
        amount: 75.0,
        paidAmount: 0.0,
        debtAmount: 75.0,
        date: DateTime.now(),
      ));

      final byManual = await financialRepo.getByType('manual_debt');
      expect(byManual.length, equals(1));
      expect(byManual.first.type, equals('manual_debt'));

      final byDebt = await financialRepo.getByType('debt');
      expect(byDebt.length, equals(1));
      expect(byDebt.first.type, equals('manual_debt'));
    });
  });
}
