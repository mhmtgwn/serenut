import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_global_search_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Global Search Repository Integration Tests', () {
    late Database db;
    late DatabaseManager databaseManager;
    late SqliteGlobalSearchRepository searchRepo;

    setUp(() async {
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      databaseManager = DatabaseManager();
      db = await databaseManager.getDatabase();

      // Clean setup of required tables
      await db.execute('DROP TABLE IF EXISTS customers');
      await db.execute('DROP TABLE IF EXISTS products');
      await db.execute('DROP TABLE IF EXISTS sales');
      await db.execute('DROP TABLE IF EXISTS financial_transactions');

      await db.execute('''
        CREATE TABLE customers (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          email TEXT,
          phone TEXT,
          balance REAL NOT NULL DEFAULT 0,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE products (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT,
          price REAL NOT NULL,
          quantity INTEGER NOT NULL,
          category TEXT NOT NULL,
          sku TEXT UNIQUE,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE sales (
          id TEXT PRIMARY KEY,
          customer_id TEXT NOT NULL,
          total_amount REAL NOT NULL,
          paid_amount REAL NOT NULL DEFAULT 0,
          payment_method TEXT,
          status TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE financial_transactions (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          customer_id TEXT NOT NULL,
          amount REAL NOT NULL,
          paid_amount REAL NOT NULL DEFAULT 0,
          debt_amount REAL NOT NULL DEFAULT 0,
          reference_id TEXT,
          created_at TEXT NOT NULL
        )
      ''');

      final gateway = DbGatewayImpl(databaseManager);
      searchRepo = SqliteGlobalSearchRepository(gateway);
    });

    tearDown(() async {
      DatabaseManager.overrideDatabasePath = null;
      await databaseManager.close();
    });

    test('searchAll retrieves matches across multiple tables correctly', () async {
      final nowStr = DateTime.now().toIso8601String();
      // 1. Insert seed data
      await db.insert('customers', {
        'id': 'cust-john',
        'name': 'John Doe',
        'email': 'john@example.com',
        'phone': '555-1234',
        'balance': 0.0,
        'is_active': 1,
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      await db.insert('customers', {
        'id': 'cust-jane',
        'name': 'Jane Doe',
        'email': 'jane@example.com',
        'phone': '555-5678',
        'balance': -100.0,
        'is_active': 1,
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      await db.insert('products', {
        'id': 'prod-apple',
        'name': 'Red Apple',
        'description': 'Fresh red apple from Amasya',
        'price': 2.50,
        'quantity': 100,
        'category': 'Fruit',
        'sku': 'SKU-APPLE-123',
        'is_active': 1,
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      await db.insert('products', {
        'id': 'prod-orange',
        'name': 'Juicy Orange',
        'description': 'Sweet seedless orange',
        'price': 3.00,
        'quantity': 50,
        'category': 'Fruit',
        'sku': 'SKU-ORANGE-456',
        'is_active': 1,
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      await db.insert('sales', {
        'id': 'sale-1',
        'customer_id': 'cust-jane',
        'total_amount': 50.0,
        'paid_amount': 0.0,
        'payment_method': 'Veresiye',
        'status': 'pending',
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      await db.insert('financial_transactions', {
        'id': 'tx-1',
        'type': 'sale',
        'customer_id': 'cust-jane',
        'amount': 50.0,
        'debt_amount': 50.0,
        'reference_id': 'sale-1',
        'created_at': nowStr,
      });

      // Test 1: Search by term matching multiple things ("Doe" matches John & Jane)
      var res = await searchRepo.searchAll('Doe');
      expect(res.customers.length, equals(2));
      expect(res.products, isEmpty);
      expect(res.sales, isEmpty);

      // Test 2: Search by term matching products only ("Apple")
      res = await searchRepo.searchAll('Apple');
      expect(res.customers, isEmpty);
      expect(res.products.length, equals(1));
      expect(res.products.first.name, equals('Red Apple'));

      // Test 3: Search by SKU/Barcode ("SKU-ORANGE")
      res = await searchRepo.searchAll('SKU-ORANGE');
      expect(res.products.length, equals(1));
      expect(res.products.first.name, equals('Juicy Orange'));

      // Test 4: Search by sale status / reference ("pending")
      res = await searchRepo.searchAll('pending');
      expect(res.sales.length, equals(1));
      expect(res.sales.first.id, equals('sale-1'));

      // Test 5: Search by transaction reference ("tx-1")
      res = await searchRepo.searchAll('tx-1');
      expect(res.transactions.length, equals(1));
      expect(res.transactions.first.id, equals('tx-1'));
    });

    test('searchAll ignores inactive products and customers', () async {
      final nowStr = DateTime.now().toIso8601String();
      await db.insert('customers', {
        'id': 'cust-inactive',
        'name': 'Bob Inactive',
        'email': 'bob@example.com',
        'phone': '555-9999',
        'balance': 0.0,
        'is_active': 0, // Inactive!
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      await db.insert('products', {
        'id': 'prod-inactive',
        'name': 'Old Apple',
        'description': 'Expired apple',
        'price': 1.0,
        'quantity': 0,
        'category': 'Fruit',
        'sku': 'SKU-OLD-1',
        'is_active': 0, // Inactive!
        'created_at': nowStr,
        'updated_at': nowStr,
      });

      final res = await searchRepo.searchAll('Apple');
      expect(res.products, isEmpty);

      final resCust = await searchRepo.searchAll('Bob');
      expect(resCust.customers, isEmpty);
    });
  });
}
