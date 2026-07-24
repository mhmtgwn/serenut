// test/services/dashboard_service_test.dart
// Phase 3 — Dashboard Repository and Service Integration Tests
// Generated: 21 Jun 2026

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/infrastructure/repositories/dashboard_repository.dart';
import 'package:serenutos/domain/services/dashboard_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Dashboard Service & SQLite Engine Integration Tests', () {
    late DatabaseManager databaseManager;
    late Database db;
    late IProductRepository productRepo;
    late ICustomerRepository customerRepo;
    late ISaleRepository saleRepo;
    late IDashboardRepository dashboardRepo;
    late DashboardService dashboardService;

    setUpAll(() async {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'serenut_pos_dashboard.db');
      await deleteDatabase(path);

      db = await openDatabase(
        path,
        version: 6,
        onCreate: (db, version) async {
          // Re-create the required tables manually to isolate from global file
          await db.execute('''
            CREATE TABLE IF NOT EXISTS products (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              description TEXT,
              price REAL NOT NULL,
              quantity INTEGER NOT NULL,
              category TEXT NOT NULL,
              sku TEXT UNIQUE,
              vat INTEGER,
              is_active INTEGER NOT NULL DEFAULT 1,
              is_synced INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              image_url TEXT,
              sale_type TEXT NOT NULL DEFAULT 'piece',
              minimum_weight_grams INTEGER NOT NULL DEFAULT 20
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS customers (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              normalized_name TEXT,
              email TEXT,
              normalized_email TEXT,
              phone TEXT,
              balance REAL NOT NULL DEFAULT 0,
              credit_limit REAL,
              status TEXT NOT NULL DEFAULT 'active',
              is_active INTEGER NOT NULL DEFAULT 1,
              is_synced INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS sales (
              id TEXT PRIMARY KEY,
              customer_id TEXT NOT NULL,
              total_amount REAL NOT NULL,
              paid_amount REAL NOT NULL DEFAULT 0,
              payment_method TEXT,
              status TEXT NOT NULL DEFAULT 'completed',
              notes TEXT,
              idempotency_key TEXT,
              is_synced INTEGER NOT NULL DEFAULT 0,
              created_by TEXT,
              entitlement_snapshot TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              FOREIGN KEY (customer_id) REFERENCES customers(id)
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS sale_items (
              id TEXT PRIMARY KEY,
              sale_id TEXT NOT NULL,
              product_id TEXT NOT NULL,
              quantity INTEGER NOT NULL,
              unit_price REAL NOT NULL,
              subtotal REAL NOT NULL,
              created_at TEXT NOT NULL,
              FOREIGN KEY (sale_id) REFERENCES sales(id),
              FOREIGN KEY (product_id) REFERENCES products(id)
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS financial_transactions (
              id TEXT PRIMARY KEY,
              type TEXT NOT NULL,
              customer_id TEXT NOT NULL,
              amount REAL NOT NULL,
              paid_amount REAL NOT NULL DEFAULT 0,
              debt_amount REAL NOT NULL DEFAULT 0,
              reference_id TEXT,
              metadata TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY (customer_id) REFERENCES customers(id)
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS orders (
              id TEXT PRIMARY KEY,
              customer_id TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'created',
              total_amount REAL,
              order_date TEXT,
              expected_delivery_date TEXT,
              actual_delivery_date TEXT,
              notes TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              FOREIGN KEY (customer_id) REFERENCES customers(id)
            )
          ''');

          await db.execute('''
            CREATE VIEW IF NOT EXISTS v_financial_ledger AS
            SELECT 
              id,
              type,
              customer_id,
              amount,
              paid_amount,
              debt_amount,
              reference_id,
              created_at,
              CASE 
                WHEN type = 'sale' THEN amount
                ELSE 0
              END AS debit,
              CASE 
                WHEN type = 'sale' THEN paid_amount
                WHEN type = 'payment' THEN amount
                WHEN type = 'collection' THEN amount
                WHEN type = 'refund' THEN amount
                WHEN type = 'cancellation' THEN debt_amount
                ELSE 0
              END AS credit
            FROM financial_transactions
          ''');
        },
      );

      final gateway = DbGatewayImpl.raw(db);
      productRepo = SqliteProductRepository(gateway);
      customerRepo = SqliteCustomerRepository(gateway);
      saleRepo = SqliteSaleRepository(gateway);
      dashboardRepo = SqliteDashboardRepository(gateway);
      dashboardService = DashboardService(dashboardRepo);

      // Clean start: clear tables and add fresh mock data
      await db.delete('sales');
      await db.delete('sale_items');
      await db.delete('financial_transactions');
      await db.delete('customers');
      await db.delete('products');
      await db.delete('orders');

      // Populate products
      await productRepo.create(ProductEntity(
        id: 'prod-p1',
        name: 'Elma',
        description: 'Meyve',
        price: 10.0,
        quantity: 2, // Low stock! (threshold <= 5)
        category: 'Manav',
        vat: 1,
      ));

      await productRepo.create(ProductEntity(
        id: 'prod-p2',
        name: 'Süt',
        description: 'Günlük Süt',
        price: 30.0,
        quantity: 20,
        category: 'Süt Ürünleri',
        vat: 8,
      ));

      // Populate customers
      await customerRepo.create(CustomerEntity(
        id: 'cust-c1',
        name: 'Ahmet Yılmaz',
        email: 'ahmet@example.com',
        phone: '111',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));

      // 1. Create a sale today
      // Sale 1: Total: 100 TL, Paid: 40 TL, Debt: 60 TL (Nakit/Vadeli)
      const saleId = 'sale-s1';
      final todayStr = DateTime.now().toIso8601String();
      await db.insert('sales', {
        'id': saleId,
        'customer_id': 'cust-c1',
        'total_amount': 100.0,
        'paid_amount': 40.0,
        'payment_method': 'Vadeli',
        'status': 'completed',
        'created_at': todayStr,
        'updated_at': todayStr,
      });

      await db.insert('sale_items', {
        'id': 'si-1',
        'sale_id': saleId,
        'product_id': 'prod-p2', // Süt
        'quantity': 3,
        'unit_price': 30.0,
        'subtotal': 90.0,
        'created_at': todayStr,
      });

      await db.insert('sale_items', {
        'id': 'si-2',
        'sale_id': saleId,
        'product_id': 'prod-p1', // Elma
        'quantity': 1,
        'unit_price': 10.0,
        'subtotal': 10.0,
        'created_at': todayStr,
      });

      // Write corresponding financial transaction
      await db.insert('financial_transactions', {
        'id': 'ft-s1',
        'type': 'sale',
        'customer_id': 'cust-c1',
        'amount': 100.0,
        'paid_amount': 40.0,
        'debt_amount': 60.0,
        'reference_id': saleId,
        'created_at': todayStr,
      });

      // 2. Create a pending order
      await db.insert('orders', {
        'id': 'order-o1',
        'customer_id': 'cust-c1',
        'status': 'preparing',
        'total_amount': 50.0,
        'created_at': todayStr,
        'updated_at': todayStr,
      });
    });

    tearDownAll(() async {
      await db.close();
    });

    test('getTodaySummary yields correct financial metrics', () async {
      final summary = await dashboardRepo.getTodaySummary();
      expect(summary.totalSalesToday, equals(1));
      expect(summary.todayRevenue, equals(100.0));
      expect(summary.todayCollected, equals(40.0));
      expect(summary.todayDebt, equals(60.0));
      expect(summary.pendingOrdersCount, equals(1));
    });

    test('getWeeklyTrend includes today and shows correct daily metrics',
        () async {
      final trend = await dashboardRepo.getWeeklyTrend();
      expect(trend.length, equals(7));

      // Last element is today
      final todayPoint = trend.last;
      expect(todayPoint.revenue, equals(100.0));
      expect(todayPoint.saleCount, equals(1));
    });

    test('getTopProducts lists best products with correct ranks', () async {
      final top = await dashboardRepo.getTopProducts(limit: 5);
      expect(top.length, equals(2));

      // Milk should be first since ciro = 90
      expect(top.first.productName, equals('Süt'));
      expect(top.first.totalRevenue, equals(90.0));
      expect(top.first.totalSold, equals(3));
      expect(top.first.rank, equals(1));

      // Apple second ciro = 10
      expect(top.last.productName, equals('Elma'));
      expect(top.last.totalRevenue, equals(10.0));
      expect(top.last.rank, equals(2));
    });

    test('getCategoryShares calculates ciro share correctly', () async {
      final shares = await dashboardRepo.getCategoryShares();
      expect(shares.length, equals(2));

      // Süt Ürünleri: 90.0, Manav: 10.0 => Total 100.0 => 90% and 10%
      final milkShare = shares.firstWhere((s) => s.category == 'Süt Ürünleri');
      final appleShare = shares.firstWhere((s) => s.category == 'Manav');

      expect(milkShare.totalAmount, equals(90.0));
      expect(milkShare.percentage, equals(90.0));
      expect(appleShare.totalAmount, equals(10.0));
      expect(appleShare.percentage, equals(10.0));
    });

    test('getLowStockProducts retrieves items below threshold', () async {
      final lowStock = await dashboardRepo.getLowStockProducts(threshold: 5);
      expect(lowStock.length, equals(1));
      expect(lowStock.first.name, equals('Elma'));
      expect(lowStock.first.quantity, equals(2));
    });

    test(
        'DashboardService getDashboardData returns populated aggregated data object',
        () async {
      final data = await dashboardService.getDashboardData();

      expect(data.summary.todayRevenue, equals(100.0));
      expect(data.weeklyTrend.last.revenue, equals(100.0));
      expect(data.topProducts.first.productName, equals('Süt'));
      expect(data.categoryShares.length, equals(2));
      expect(data.recentSales.length, equals(1));
      expect(data.lowStockProducts.length, equals(1));
    });
  });
}
