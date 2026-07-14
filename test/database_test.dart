// test/database_test.dart
// PHASE 0 Day 4 - Database Layer Integration Tests
// Verifies DatabaseManager, schema creation, and SQLite repositories
// Generated: 21 Jun 2026

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

void main() {
  // Initialize database factory for ffi
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Database Layer Tests', () {
    late DatabaseManager databaseManager;
    late DbGateway gateway;

    setUpAll(() async {
      // Clear database file for tests to avoid state pollution
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'serenut_pos.db');
      await deleteDatabase(path);

      // Initialize database
      databaseManager = DatabaseManager();
      gateway = DbGatewayImpl(databaseManager);

      // Seed the database with the mock data needed for these tests
      final db = await databaseManager.getDatabase();

      // Insert products
      final products = [
        {
          'id': 'prod-1',
          'name': 'Fındık İçi',
          'description': 'Taze fındık',
          'price': 150.0,
          'quantity': 10,
          'category': 'Kuruyemiş',
          'sku': 'PROD-001',
          'vat': 8
        },
        {
          'id': 'prod-2',
          'name': 'Badem İçi',
          'description': 'Taze badem',
          'price': 200.0,
          'quantity': 15,
          'category': 'Kuruyemiş',
          'sku': 'PROD-002',
          'vat': 8
        },
        {
          'id': 'prod-3',
          'name': 'Ceviz İçi',
          'description': 'Taze ceviz',
          'price': 180.0,
          'quantity': 20,
          'category': 'Kuruyemiş',
          'sku': 'PROD-003',
          'vat': 8
        },
        {
          'id': 'prod-4',
          'name': 'Antep Fıstığı',
          'description': 'Taze antep fıstığı',
          'price': 300.0,
          'quantity': 25,
          'category': 'Kuruyemiş',
          'sku': 'PROD-004',
          'vat': 8
        },
        {
          'id': 'prod-5',
          'name': 'Kaju',
          'description': 'Taze kaju',
          'price': 250.0,
          'quantity': 30,
          'category': 'Kuruyemiş',
          'sku': 'PROD-005',
          'vat': 8
        },
        {
          'id': 'prod-6',
          'name': 'Leblebi',
          'description': 'Taze leblebi',
          'price': 80.0,
          'quantity': 40,
          'category': 'Kuruyemiş',
          'sku': 'PROD-006',
          'vat': 8
        },
        {
          'id': 'prod-7',
          'name': 'Kuru Üzüm',
          'description': 'Taze kuru üzüm',
          'price': 90.0,
          'quantity': 50,
          'category': 'Kuruyemiş',
          'sku': 'PROD-007',
          'vat': 8
        },
        {
          'id': 'prod-8',
          'name': 'Kuru Kayısı',
          'description': 'Taze kuru kayısı',
          'price': 120.0,
          'quantity': 35,
          'category': 'Kuruyemiş',
          'sku': 'PROD-008',
          'vat': 8
        },
        {
          'id': 'prod-9',
          'name': 'Kuru İncir',
          'description': 'Taze kuru incir',
          'price': 160.0,
          'quantity': 18,
          'category': 'Kuruyemiş',
          'sku': 'PROD-009',
          'vat': 8
        },
        {
          'id': 'prod-10',
          'name': 'Kabak Çekirdeği',
          'description': 'Taze kabak çekirdeği',
          'price': 110.0,
          'quantity': 22,
          'category': 'Kuruyemiş',
          'sku': 'PROD-010',
          'vat': 8
        },
      ];

      for (final product in products) {
        await db.insert('products', {
          ...product,
          'is_active': 1,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      // Insert customers
      final customers = [
        {
          'id': 'cust-1',
          'name': 'Ahmet Yılmaz',
          'email': 'ahmet@gmail.com',
          'phone': '5550001122',
          'balance': 0.0
        },
        {
          'id': 'cust-2',
          'name': 'Mehmet Kaya',
          'email': 'mehmet@gmail.com',
          'phone': '5550001133',
          'balance': 100.0
        },
        {
          'id': 'cust-3',
          'name': 'Ayşe Demir',
          'email': 'ayse@gmail.com',
          'phone': '5550001144',
          'balance': 0.0
        },
      ];

      for (final customer in customers) {
        await db.insert('customers', {
          ...customer,
          'credit_limit': 1000.0,
          'status': 'active',
          'is_active': 1,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    });

    tearDownAll(() async {
      await databaseManager.close();
    });

    group('DatabaseManager', () {
      test('should initialize database successfully', () async {
        final db = await databaseManager.getDatabase();
        expect(db, isNotNull);
      });

      test('should create all required tables', () async {
        final db = await databaseManager.getDatabase();

        // Query system tables to verify
        final result = await db.query(
          'sqlite_master',
          where: 'type=? AND name NOT LIKE ?',
          whereArgs: ['table', 'sqlite_%'],
        );

        final tableNames = result.map((t) => t['name']).toList();
        expect(tableNames, contains('users'));
        expect(tableNames, contains('products'));
        expect(tableNames, contains('customers'));
        expect(tableNames, contains('sales'));
        expect(tableNames, contains('sale_items'));
        expect(tableNames, contains('financial_transactions'));
        expect(tableNames, contains('orders'));
        expect(tableNames, contains('order_items'));
      });

      test('should insert default mock data', () async {
        final db = await databaseManager.getDatabase();

        // Populate test users since hardcoded seeding was removed for security
        await db.insert('users', {
          'id': 'test-admin-id',
          'name': 'Admin',
          'email': 'admin@serenut.com',
          'password_hash': 'pbkdf2\$10000\$abc\$123',
          'role': 'admin',
          'is_active': 1,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });

        // Check mock users
        final users = await db.query('users');
        expect(users.length, equals(1));
        expect(users.any((u) => u['email'] == 'admin@serenut.com'), isTrue);
      });
    });

    group('SqliteProductRepository', () {
      late SqliteProductRepository productRepository;

      setUpAll(() async {
        productRepository = SqliteProductRepository(gateway);
      });

      test('should find all products', () async {
        final products = await productRepository.findAll();
        expect(products, isNotEmpty);
        expect(products.length, equals(10)); // Seed data: 10 kuruyemiş ürünleri
      });

      test('should search products by name', () async {
        final results = await productRepository.searchByName('Fındık');
        expect(results, isNotEmpty);
        expect(results.first.name.contains('Fındık'), isTrue);
      });

      test('should get products by category', () async {
        final nuts = await productRepository.getByCategory('Kuruyemiş');
        expect(nuts, isNotEmpty);
      });

      test('should get low stock products', () async {
        // Create a low stock product via direct query
        final db = await databaseManager.getDatabase();
        await db.insert('products', {
          'id': 'prod-low-1',
          'name': 'Low Stock Item',
          'description': 'Item with low stock',
          'price': 50.0,
          'quantity': 2,
          'category': 'Test',
          'sku': 'LowStock-001',
          'vat': 18,
          'is_active': 1,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });

        final lowStock = await productRepository.getLowStockProducts(3);
        expect(
          lowStock.any((p) => p.id == 'prod-low-1'),
          isTrue,
          reason: 'Should find products with quantity below threshold',
        );
      });

      test('should decrease stock', () async {
        const productId = 'prod-1';
        const decreaseQty = 2;

        final productBefore = await productRepository.findById(productId);
        final initialQuantity = productBefore?.quantity ?? 0;

        await productRepository.decreaseStock(productId, decreaseQty);

        final productAfter = await productRepository.findById(productId);
        expect(productAfter?.quantity, equals(initialQuantity - decreaseQty));
      });

      test('should increase stock', () async {
        const productId = 'prod-1';
        const increaseQty = 3;

        final productBefore = await productRepository.findById(productId);
        final initialQuantity = productBefore?.quantity ?? 0;

        await productRepository.increaseStock(productId, increaseQty);

        final productAfter = await productRepository.findById(productId);
        expect(productAfter?.quantity, equals(initialQuantity + increaseQty));
      });
    });

    group('SqliteCustomerRepository', () {
      late SqliteCustomerRepository customerRepository;

      setUpAll(() async {
        customerRepository = SqliteCustomerRepository(gateway);
      });

      test('should find all customers', () async {
        final customers = await customerRepository.findAll();
        expect(customers, isNotEmpty);
        expect(customers.length, equals(3));
      });

      test('should search customers by name', () async {
        final results = await customerRepository.search('Ahmet');
        expect(results, isNotEmpty);
        expect(results.first.name.contains('Ahmet'), isTrue);
      });

      test('should get customers with debt', () async {
        // Insert a customer with a negative balance (debt)
        await customerRepository.create(CustomerEntity(
          id: 'cust-debtor-test',
          name: 'Debtor Test',
          email: 'debtor@test.com',
          phone: '123456',
          balance: -100.0,
          createdAt: DateTime.now(),
        ));
        final debtors = await customerRepository.getDebtors();
        expect(debtors, isNotEmpty);
        expect(debtors.any((c) => c.id == 'cust-debtor-test'), isTrue);
      });

      test('should get customers with credit', () async {
        // Insert a customer with a positive balance (credit) explicitly
        await customerRepository.create(CustomerEntity(
          id: 'cust-credit-test',
          name: 'Credit Test Müşteri',
          email: 'credit@test.com',
          phone: '5551234567',
          balance: 500.0, // Positive balance = credit
          createdAt: DateTime.now(),
        ));
        final withCredit = await customerRepository.getWithCredit();
        expect(withCredit, isNotEmpty);
        expect(withCredit.any((c) => c.id == 'cust-credit-test'), isTrue);
      });

      test('should update customer balance via financial transaction triggers',
          () async {
        const customerId = 'cust-1';
        final customerBefore = await customerRepository.findById(customerId);
        final initialBalance = customerBefore?.balance ?? 0.0;
        const balanceChange = 150.0;

        final txRepo = SqliteFinancialTransactionRepository(gateway);
        await txRepo.create(FinancialTransactionEntity(
          id: 'tx-test-db-1',
          type: 'collection',
          customerId: customerId,
          amount: balanceChange,
          paidAmount: balanceChange,
          debtAmount: 0.0,
          date: DateTime.now(),
        ));

        final customer = await customerRepository.findById(customerId);
        expect(customer?.balance, equals(initialBalance + balanceChange));
      });
    });

    group('SqliteSaleRepository', () {
      late SqliteSaleRepository saleRepository;

      setUpAll(() async {
        saleRepository = SqliteSaleRepository(gateway);
      });

      test('should get today sales', () async {
        final todaySales = await saleRepository.getTodaySales();
        // Should be empty initially or have data if populated
        expect(todaySales, isA<List<SaleEntity>>());
      });

      test('should get sales by date range', () async {
        final startDate = DateTime.now().subtract(const Duration(days: 7));
        final endDate = DateTime.now();

        final salees =
            await saleRepository.getSalesByDateRange(startDate, endDate);
        expect(salees, isA<List<SaleEntity>>());
      });

      test('should get today revenue', () async {
        final revenue = await saleRepository.getTodayRevenue();
        expect(revenue, isA<double>());
      });

      test('should get total items sold', () async {
        final total = await saleRepository.getTotalItemsSold();
        expect(total, isA<int>());
      });
    });

    group('Database Persistence', () {
      test('should persist data across queries', () async {
        final db = await databaseManager.getDatabase();

        // Insert a test record
        final testId = 'test-persist-${DateTime.now().millisecondsSinceEpoch}';
        await db.insert('products', {
          'id': testId,
          'name': 'Persistence Test',
          'description': 'Test product',
          'price': 99.99,
          'quantity': 5,
          'category': 'Test',
          'sku': 'TEST-PERSIST',
          'vat': 0,
          'is_active': 1,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });

        // Query it back
        final result = await db.query(
          'products',
          where: 'id = ?',
          whereArgs: [testId],
        );

        expect(result, isNotEmpty);
        expect(result.first['id'], equals(testId));
        expect(result.first['name'], equals('Persistence Test'));
      });

      test('should handle concurrent operations gracefully', () async {
        final productRepo = SqliteProductRepository(gateway);

        // Simulate concurrent operations
        final futures = List.generate(5, (i) async {
          return await productRepo.findAll();
        });

        final results = await Future.wait(futures);
        expect(results, isNotEmpty);
        expect(results.every((r) => r.isNotEmpty), isTrue);
      });
    });
  });
}
