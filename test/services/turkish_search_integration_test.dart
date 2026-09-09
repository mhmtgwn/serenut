import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_payment_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Turkish Normalized Search Integration Tests', () {
    late Database db;
    late DatabaseManager databaseManager;
    late SqliteProductRepository productRepo;
    late SqliteSaleRepository saleRepo;

    setUp(() async {
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      databaseManager = DatabaseManager();
      db = await databaseManager.getDatabase();

      // Clear test data
      await db.delete('financial_transactions');
      await db.delete('sale_items');
      await db.delete('sales');
      await db.delete('products');
      await db.delete('customers');

      final gateway = DbGatewayImpl(databaseManager);
      productRepo = SqliteProductRepository(gateway);
      saleRepo = SqliteSaleRepository(gateway);
    });

    tearDown(() async {
      DatabaseManager.overrideDatabasePath = null;
      await databaseManager.close();
    });

    test('findFiltered matches products with Turkish diacritics, ASCII equivalents, and mixed case', () async {
      final nowStr = DateTime.now().toIso8601String();

      await db.insert('products', {
        'id': '8690504012345',
        'name': 'Fındık Ezmesi 350g',
        'description': 'Kavrulmuş taze fındık',
        'price': 150.0,
        'quantity': 20,
        'category': 'Ezme',
        'brand': 'Giresun Lezzetleri',
        'shelf_code': 'A-12',
        'is_active': 1,
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      await db.insert('products', {
        'id': '8690504099999',
        'name': 'Çilekli Süt 1L',
        'description': 'Doğal köy sütü',
        'price': 45.0,
        'quantity': 50,
        'category': 'İçecek',
        'brand': 'Sütaş',
        'shelf_code': 'B-04',
        'is_active': 1,
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      await db.insert('products', {
        'id': '8690504077777',
        'name': 'Şeker Pare Tatlısı',
        'description': 'Geleneksel şerbetli tatlı',
        'price': 120.0,
        'quantity': 15,
        'category': 'Tatlı',
        'brand': 'Tatlıcı Şahin',
        'shelf_code': 'C-01',
        'is_active': 1,
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      // 1. "findik" matches "Fındık Ezmesi 350g"
      var results = await productRepo.findFiltered(searchQuery: 'findik');
      expect(results.length, equals(1));
      expect(results.first.name, equals('Fındık Ezmesi 350g'));

      // 2. "FINDIK" matches "Fındık Ezmesi 350g"
      results = await productRepo.findFiltered(searchQuery: 'FINDIK');
      expect(results.length, equals(1));
      expect(results.first.name, equals('Fındık Ezmesi 350g'));

      // 3. "fındık" matches "Fındık Ezmesi 350g"
      results = await productRepo.findFiltered(searchQuery: 'fındık');
      expect(results.length, equals(1));
      expect(results.first.name, equals('Fındık Ezmesi 350g'));

      // 4. "cilekli" matches "Çilekli Süt 1L"
      results = await productRepo.findFiltered(searchQuery: 'cilekli');
      expect(results.length, equals(1));
      expect(results.first.name, equals('Çilekli Süt 1L'));

      // 5. "ÇİLEKLİ" matches "Çilekli Süt 1L"
      results = await productRepo.findFiltered(searchQuery: 'ÇİLEKLİ');
      expect(results.length, equals(1));
      expect(results.first.name, equals('Çilekli Süt 1L'));

      // 6. "sut" matches "Çilekli Süt 1L"
      results = await productRepo.findFiltered(searchQuery: 'sut');
      expect(results.length, equals(1));
      expect(results.first.name, equals('Çilekli Süt 1L'));

      // 7. "SÜT" matches "Çilekli Süt 1L"
      results = await productRepo.findFiltered(searchQuery: 'SÜT');
      expect(results.length, equals(1));
      expect(results.first.name, equals('Çilekli Süt 1L'));

      // 8. "seker" matches "Şeker Pare Tatlısı"
      results = await productRepo.findFiltered(searchQuery: 'seker');
      expect(results.length, equals(1));
      expect(results.first.name, equals('Şeker Pare Tatlısı'));

      // 9. "ŞEKER" matches "Şeker Pare Tatlısı"
      results = await productRepo.findFiltered(searchQuery: 'ŞEKER');
      expect(results.length, equals(1));
      expect(results.first.name, equals('Şeker Pare Tatlısı'));

      // 10. Brand match: "sahin" matches "Tatlıcı Şahin"
      results = await productRepo.findFiltered(searchQuery: 'sahin');
      expect(results.length, equals(1));
      expect(results.first.name, equals('Şeker Pare Tatlısı'));

      // 11. Barcode candidate match: "08690504012345" matches "8690504012345"
      results = await productRepo.findFiltered(searchQuery: '08690504012345');
      expect(results.length, equals(1));
      expect(results.first.name, equals('Fındık Ezmesi 350g'));
    });

    test('findFiltered in SalesHistory matches customer name, phone, notes and product name', () async {
      final nowStr = DateTime.now().toIso8601String();

      // Insert customer
      await db.insert('customers', {
        'id': 'cust-ahmet-1',
        'name': 'Ahmet Çelik',
        'phone': '05551234567',
        'balance': 0.0,
        'is_active': 1,
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      // Insert sale
      await db.insert('sales', {
        'id': 'sale-1001',
        'customer_id': 'cust-ahmet-1',
        'total_amount': 250.0,
        'paid_amount': 250.0,
        'payment_method': 'cash',
        'status': 'completed',
        'notes': 'Hızlı paket teslimatı',
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      // Insert dummy product for FK
      await db.insert('products', {
        'id': 'prod-1',
        'name': 'Kavrulmuş Fındık',
        'price': 250.0,
        'quantity': 10,
        'category': 'Kuruyemiş',
        'is_active': 1,
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      // Insert sale item
      await db.insert('sale_items', {
        'id': 'item-101',
        'sale_id': 'sale-1001',
        'product_id': 'prod-1',
        'product_name': 'Kavrulmuş Fındık',
        'quantity': 1.0,
        'unit_price': 250.0,
        'subtotal': 250.0,
        'created_at': nowStr,
      });

      // 1. Search by customer name: "ahmet"
      var sales = await saleRepo.findFiltered(searchQuery: 'ahmet');
      expect(sales.length, equals(1));
      expect(sales.first.id, equals('sale-1001'));

      // 2. Search by customer surname: "celik"
      sales = await saleRepo.findFiltered(searchQuery: 'celik');
      expect(sales.length, equals(1));
      expect(sales.first.id, equals('sale-1001'));

      // 3. Search by Turkish customer surname: "ÇELİK"
      sales = await saleRepo.findFiltered(searchQuery: 'ÇELİK');
      expect(sales.length, equals(1));
      expect(sales.first.id, equals('sale-1001'));

      // 4. Search by phone: "05551234567"
      sales = await saleRepo.findFiltered(searchQuery: '05551234567');
      expect(sales.length, equals(1));
      expect(sales.first.id, equals('sale-1001'));

      // 5. Search by product name: "findik"
      sales = await saleRepo.findFiltered(searchQuery: 'findik');
      expect(sales.length, equals(1));
      expect(sales.first.id, equals('sale-1001'));

      // 6. Search by notes: "paket"
      sales = await saleRepo.findFiltered(searchQuery: 'paket');
      expect(sales.length, equals(1));
      expect(sales.first.id, equals('sale-1001'));

      // 7. Search by sale ID: "1001"
      sales = await saleRepo.findFiltered(searchQuery: '1001');
      expect(sales.length, equals(1));
      expect(sales.first.id, equals('sale-1001'));
    });
  });
}
