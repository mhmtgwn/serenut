// test/core_next/database_integration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_product_repository.dart';

void main() {
  // Desktop/Test ortamı için FFI başlat
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late CoreAppDatabase coreDb;
  late SqliteLedgerRepository ledgerRepo;
  late SqliteProductRepository productRepo;
  late LedgerService ledgerService;

  setUp(() async {
    // Testler için her seferinde temiz bellek içi veritabanı
    coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: inMemoryDatabasePath);
    ledgerRepo = SqliteLedgerRepository(coreDb.db);
    productRepo = SqliteProductRepository(coreDb.db);
    ledgerService = LedgerService(ledgerRepo);
  });

  tearDown(() async {
    await coreDb.close();
  });

  group('CoreAppDatabase & SQLite Repository Integration Tests', () {
    test('Veritabanı tabloları ve indeksleri temiz bir şekilde oluşmalıdır', () async {
      final tables = await coreDb.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('products', 'customers', 'sales', 'ledger_entries', 'installments')",
      );
      expect(tables.length, 5);
    });

    test('Ürün kuruş bazında eklenmeli, barkod ve ada göre aranabilmelidir', () async {
      final product = ProductEntity(
        id: 'prod-1',
        barcode: '8690504123456',
        name: 'Doğal İncir 500g',
        price: MoneyCents.fromLira(85.50), // 8550 kuruş
        costPrice: MoneyCents.fromLira(50.00),
        vatRate: 20,
        stockQuantity: 100,
        updatedAt: DateTime.now(),
      );

      await productRepo.upsertProduct(product);

      // Barkod ile çek
      final byBarcode = await productRepo.getByBarcode('8690504123456');
      expect(byBarcode, isNotNull);
      expect(byBarcode!.name, 'Doğal İncir 500g');
      expect(byBarcode.price.value, 8550);
      expect(byBarcode.price.formatTL(), '85,50 ₺');

      // Arama ile çek
      final searchResults = await productRepo.searchProducts('İncir');
      expect(searchResults.length, 1);
      expect(searchResults.first.id, 'prod-1');
    });

    test('Trigger olmadan çalışan LedgerService SQLite üzerinde bakiye ve defter kaydını doğru işlemelidir', () async {
      // 1. Müşteri ekle
      final customer = CustomerEntity(
        id: 'cust-100',
        name: 'Mehmet Demir',
        balance: MoneyCents.zero,
        creditLimit: MoneyCents.fromLira(500.0), // 50.000 kuruş
        updatedAt: DateTime.now(),
      );
      await coreDb.db.insert('customers', customer.toMap());

      // 2. Satış kaydı ekle (Foreign key korumasını doğrulamak için)
      await coreDb.db.insert('sales', {
        'id': 'sale-1',
        'receipt_no': '2026-0042',
        'customer_id': 'cust-100',
        'subtotal_cents': 15000,
        'discount_cents': 0,
        'vat_total_cents': 2500,
        'total_cents': 15000,
        'paid_cents': 0,
        'debt_cents': 15000,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // 3. Vadeli satış yap (150 TL borçlandır)
      final debitEntry = await ledgerService.postDebitSale(
        entryId: 'led-1',
        customerId: 'cust-100',
        saleId: 'sale-1',
        debtAmount: MoneyCents.fromLira(150.0),
        receiptNo: '2026-0042',
        timestamp: DateTime.now(),
      );

      expect(debitEntry.balanceAfter.value, -15000);

      // Veritabanından müşteriyi kontrol et
      final updatedCust = await ledgerRepo.getCustomer('cust-100');
      expect(updatedCust!.balance.value, -15000);
      expect(updatedCust.balance.formatTL(), '-150,00 ₺');

      // 3. Borç tahsilatı yap (50 TL tahsil et)
      await ledgerService.postCollection(
        entryId: 'led-2',
        customerId: 'cust-100',
        collectionAmount: MoneyCents.fromLira(50.0),
        description: 'Kısmi Nakit Tahsilat',
        timestamp: DateTime.now(),
      );

      // 4. Müşteri ekstresini çek
      final history = await ledgerRepo.getCustomerLedgerHistory('cust-100');
      expect(history.length, 2);
      expect(history.first.balanceAfter.value, -10000); // En son bakiye -100 TL (-10.000 kuruş)
    });
  });
}
