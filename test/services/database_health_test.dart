import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_database_health_repository.dart';
import 'package:serenutos/domain/services/data_integrity_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Database Health Check & Repair Integration Tests', () {
    late Database db;
    late DatabaseManager databaseManager;
    late SqliteDatabaseHealthRepository healthRepo;
    late DataIntegrityService integrityService;

    setUp(() async {
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      databaseManager = DatabaseManager();
      db = await databaseManager.getDatabase();

      // Setup clean tables needed for health check tests
      await db.execute('DROP TABLE IF EXISTS sale_items');
      await db.execute('DROP TABLE IF EXISTS sales');
      await db.execute('DROP TABLE IF EXISTS order_items');
      await db.execute('DROP TABLE IF EXISTS orders');
      await db.execute('DROP TABLE IF EXISTS order_payments');
      await db.execute('DROP TABLE IF EXISTS financial_transactions');
      await db.execute('DROP TABLE IF EXISTS customers');
      await db.execute('DROP TABLE IF EXISTS products');

      await db.execute('''
        CREATE TABLE customers (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          balance REAL NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'active',
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
          category TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE sales (
          id TEXT PRIMARY KEY,
          customer_id TEXT NOT NULL,
          total_amount REAL NOT NULL,
          paid_amount REAL NOT NULL,
          payment_method TEXT,
          status TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE sale_items (
          id TEXT PRIMARY KEY,
          sale_id TEXT NOT NULL,
          product_id TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          unit_price REAL NOT NULL,
          subtotal REAL NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE orders (
          id TEXT PRIMARY KEY,
          customer_id TEXT NOT NULL,
          status TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE order_items (
          id TEXT PRIMARY KEY,
          order_id TEXT NOT NULL,
          product_id TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE order_payments (
          id TEXT PRIMARY KEY,
          order_id TEXT NOT NULL,
          amount REAL NOT NULL
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
      healthRepo = SqliteDatabaseHealthRepository(gateway);
      integrityService = DataIntegrityService(
        customerRepository: _DummyCustomerRepo(), // not used for this test
        transactionRepository: _DummyTxRepo(), // not used for this test
        healthRepository: healthRepo,
      );
    });

    tearDown(() async {
      DatabaseManager.overrideDatabasePath = null;
      await databaseManager.close();
    });

    test('checkDatabaseHealth detects anomalies correctly', () async {
      // 1. Insert orphaned sale_item (sales is empty)
      await db.insert('sale_items', {
        'id': 'orphan-item-1',
        'sale_id': 'missing-sale-id',
        'product_id': 'prod-1',
        'quantity': 1,
        'unit_price': 10.0,
        'subtotal': 10.0,
      });

      // 2. Insert orphaned order_item
      await db.insert('order_items', {
        'id': 'orphan-order-item',
        'order_id': 'missing-order-id',
        'product_id': 'prod-1',
      });

      // 3. Insert orphaned order_payment
      await db.insert('order_payments', {
        'id': 'orphan-order-pay',
        'order_id': 'missing-order-id',
        'amount': 20.0,
      });

      // 4. Insert orphaned financial transaction (no customer exists)
      await db.insert('financial_transactions', {
        'id': 'orphan-tx',
        'type': 'sale',
        'customer_id': 'missing-cust-id',
        'amount': 100.0,
        'debt_amount': 100.0,
        'created_at': DateTime.now().toIso8601String(),
      });

      // 5. Insert negative stock product
      await db.insert('products', {
        'id': 'prod-neg',
        'name': 'Negative Product',
        'description': '',
        'price': 5.0,
        'quantity': -5,
        'category': 'Default',
      });

      // 6. Insert customer with balance drift
      await db.insert('customers', {
        'id': 'cust-drift',
        'name': 'Drift Customer',
        'balance': 10.0, // Expected should be 0 because they have no transactions
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Scan health
      final report = await integrityService.checkDatabaseHealth();

      expect(report.isHealthy, isFalse);
      expect(report.orphanedSaleItemsCount, equals(1));
      expect(report.orphanedOrderItemsCount, equals(1));
      expect(report.orphanedOrderPaymentsCount, equals(1));
      expect(report.orphanedTransactionsCount, equals(1));
      expect(report.negativeStockProductsCount, equals(1));
      expect(report.customerBalanceDriftsCount, equals(1));
    });

    test('repairDatabaseHealth resolves all structural and balance drift issues', () async {
      // Seed orphans & negatives
      await db.insert('sale_items', {'id': 'si-1', 'sale_id': 'none', 'product_id': 'p', 'quantity': 1, 'unit_price': 1, 'subtotal': 1});
      await db.insert('products', {'id': 'p-neg', 'name': 'P', 'price': 1.0, 'quantity': -10, 'category': 'C'});
      await db.insert('customers', {'id': 'c-1', 'name': 'C', 'balance': -50.0, 'created_at': 'now', 'updated_at': 'now'});
      // Create a sale transaction that matches -30.0 instead of -50.0 bakiye (so 20.0 TL drift)
      await db.insert('financial_transactions', {
        'id': 't-1',
        'type': 'sale',
        'customer_id': 'c-1',
        'amount': 100.0,
        'paid_amount': 70.0,
        'debt_amount': 30.0,
        'created_at': 'now',
      });

      // Repair DB health
      await integrityService.repairDatabaseHealth();

      // Scan again
      final report = await integrityService.checkDatabaseHealth();
      expect(report.isHealthy, isTrue);

      // Verify negative stock was reset to 0
      final prodResult = await db.query('products', columns: ['quantity'], where: 'id = ?', whereArgs: ['p-neg']);
      expect(prodResult.first['quantity'] as int, equals(0));

      // Verify customer balance drift was corrected to -30.0
      final custResult = await db.query('customers', columns: ['balance'], where: 'id = ?', whereArgs: ['c-1']);
      expect(custResult.first['balance'] as double, equals(-30.0));

      // Verify orphaned sale item was deleted
      final saleItems = await db.query('sale_items');
      expect(saleItems, isEmpty);
    });
  });
}

class _DummyCustomerRepo extends Fake implements ICustomerRepository {}
class _DummyTxRepo extends Fake implements IFinancialTransactionRepository {}
