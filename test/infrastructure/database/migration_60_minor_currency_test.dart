import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/schema/db_migrations.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Migration 60 — Minor Currency (Kuruş) Expand & Backfill Tests', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 59,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE products (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              price REAL NOT NULL,
              purchase_price REAL NOT NULL DEFAULT 0,
              quantity INTEGER NOT NULL,
              category TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE customers (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              balance REAL NOT NULL DEFAULT 0,
              credit_limit REAL
            )
          ''');
          await db.execute('''
            CREATE TABLE sales (
              id TEXT PRIMARY KEY,
              customer_id TEXT NOT NULL,
              total_amount REAL NOT NULL,
              paid_amount REAL NOT NULL DEFAULT 0,
              refunded_amount REAL NOT NULL DEFAULT 0,
              discount_amount REAL NOT NULL DEFAULT 0.0
            )
          ''');
          await db.execute('''
            CREATE TABLE sale_items (
              id TEXT PRIMARY KEY,
              sale_id TEXT NOT NULL,
              product_id TEXT NOT NULL,
              unit_price REAL NOT NULL,
              subtotal REAL NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE financial_transactions (
              id TEXT PRIMARY KEY,
              type TEXT NOT NULL,
              customer_id TEXT NOT NULL,
              amount REAL NOT NULL,
              paid_amount REAL NOT NULL DEFAULT 0,
              debt_amount REAL NOT NULL DEFAULT 0
            )
          ''');

          // Seed test legacy data with float fractions
          await db.insert('products', {
            'id': 'p1',
            'name': 'Ürün 1',
            'price': 12.34,
            'purchase_price': 8.50,
            'quantity': 10,
            'category': 'Genel',
          });
          await db.insert('customers', {
            'id': 'c1',
            'name': 'Müşteri 1',
            'balance': -150.75,
            'credit_limit': 1000.00,
          });
          await db.insert('sales', {
            'id': 's1',
            'customer_id': 'c1',
            'total_amount': 250.25,
            'paid_amount': 100.00,
            'refunded_amount': 25.50,
            'discount_amount': 10.00,
          });
          await db.insert('sale_items', {
            'id': 'si1',
            'sale_id': 's1',
            'product_id': 'p1',
            'unit_price': 12.34,
            'subtotal': 24.68,
          });
          await db.insert('financial_transactions', {
            'id': 'ft1',
            'type': 'sale',
            'customer_id': 'c1',
            'amount': 250.25,
            'paid_amount': 100.00,
            'debt_amount': 150.25,
          });
        },
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('Migration 60 successfully adds minor columns and backfills existing records', () async {
      // Execute Migration from 59 to 60
      await DatabaseMigrations.onUpgrade(db, 59, 60);

      // 1. Verify products minor columns
      final products = await db.query('products', where: 'id = ?', whereArgs: ['p1']);
      expect(products.isNotEmpty, isTrue);
      expect(products.first['price_minor'], 1234);
      expect(products.first['purchase_price_minor'], 850);

      // 2. Verify customers minor columns
      final customers = await db.query('customers', where: 'id = ?', whereArgs: ['c1']);
      expect(customers.isNotEmpty, isTrue);
      expect(customers.first['balance_minor'], -15075);
      expect(customers.first['credit_limit_minor'], 100000);

      // 3. Verify sales minor columns
      final sales = await db.query('sales', where: 'id = ?', whereArgs: ['s1']);
      expect(sales.isNotEmpty, isTrue);
      expect(sales.first['total_amount_minor'], 25025);
      expect(sales.first['paid_amount_minor'], 10000);
      expect(sales.first['refunded_amount_minor'], 2550);
      expect(sales.first['discount_amount_minor'], 1000);

      // 4. Verify sale_items minor columns
      final saleItems = await db.query('sale_items', where: 'id = ?', whereArgs: ['si1']);
      expect(saleItems.isNotEmpty, isTrue);
      expect(saleItems.first['unit_price_minor'], 1234);
      expect(saleItems.first['subtotal_minor'], 2468);

      // 5. Verify financial_transactions minor columns
      final ft = await db.query('financial_transactions', where: 'id = ?', whereArgs: ['ft1']);
      expect(ft.isNotEmpty, isTrue);
      expect(ft.first['amount_minor'], 25025);
      expect(ft.first['paid_amount_minor'], 10000);
      expect(ft.first['debt_amount_minor'], 15025);
    });
  });
}
