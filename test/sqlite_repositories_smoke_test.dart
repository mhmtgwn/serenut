// test/sqlite_repositories_smoke_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('SQLite Repositories CRUD Smoke Tests', () {
    late DatabaseManager databaseManager;
    late Database db;
    late SqliteProductRepository productRepo;
    late SqliteCustomerRepository customerRepo;
    late SqliteOrderRepository orderRepo;
    late SqliteSaleRepository saleRepo;

    setUp(() async {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'serenut_pos.db');
      await deleteDatabase(path);

      databaseManager = DatabaseManager();
      db = await databaseManager.getDatabase();

      // Clean tables in correct foreign key constraint order
      await db.update('ledger_bypass_flag', {'active': 1});
      await db.delete('sale_items');
      await db.delete('order_items');
      await db.delete('sales');
      await db.delete('orders');
      await db.delete('financial_transactions');
      await db.delete('customers');
      await db.delete('products');
      await db.update('ledger_bypass_flag', {'active': 0});

      final gateway = DbGatewayImpl(databaseManager);
      productRepo = SqliteProductRepository(gateway);
      customerRepo = SqliteCustomerRepository(gateway);
      orderRepo = SqliteOrderRepository(gateway);
      saleRepo = SqliteSaleRepository(gateway);

      // Create a default customer to satisfy foreign key constraints in sales/orders
      await customerRepo.create(CustomerEntity(
        id: 'cust-1',
        name: 'Default Customer',
        email: 'default@customer.com',
        phone: '111-111-1111',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));
    });

    tearDown(() async {
      await databaseManager.close();
    });

    group('ProductRepository CRUD', () {
      test('Insert, GetById, Update, Delete, List', () async {
        final product = ProductEntity(
          id: 'test-prod-101',
          name: 'Smoke Test Product',
          description: 'A product for smoke testing',
          price: 99.90,
          quantity: 25,
          category: 'TestCategory',
          vat: 18,
        );

        // 1. Insert (Create)
        final createResult = await productRepo.create(product);
        expect(createResult, greaterThan(0));

        // 2. GetById (FindById)
        final found = await productRepo.findById(product.id);
        expect(found, isNotNull);
        expect(found!.id, equals(product.id));
        expect(found.name, equals(product.name));
        expect(found.price, equals(product.price));
        expect(found.quantity, equals(product.quantity));

        // 3. Update
        final updatedProduct = ProductEntity(
          id: product.id,
          name: 'Updated Smoke Product',
          description: 'Updated description',
          price: 109.90,
          quantity: 20,
          category: 'TestCategory',
          vat: 18,
        );
        final updateResult = await productRepo.update(updatedProduct);
        expect(updateResult, equals(1));

        final foundAfterUpdate = await productRepo.findById(product.id);
        expect(foundAfterUpdate!.name, equals('Updated Smoke Product'));
        expect(foundAfterUpdate.price, equals(109.90));
        expect(foundAfterUpdate.quantity, equals(20));

        // 4. List (FindAll)
        final allProducts = await productRepo.findAll();
        // Since we cleared tables, exactly 1 active product
        expect(allProducts.length, equals(1));
        expect(allProducts.any((p) => p.id == product.id), isTrue);

        // 5. Delete (Soft delete in SqliteProductRepository)
        final deleteResult = await productRepo.delete(product.id);
        expect(deleteResult, equals(1));

        final foundAfterDelete = await productRepo.findById(product.id);
        expect(foundAfterDelete, isNull);

        final allProductsAfterDelete = await productRepo.findAll();
        expect(allProductsAfterDelete.length, equals(0));
      });
    });

    group('CustomerRepository CRUD', () {
      test('Insert, GetById, Update, Delete, List', () async {
        final customer = CustomerEntity(
          id: 'test-cust-201',
          name: 'Smoke Customer',
          email: 'smoke@customer.com',
          phone: '555-555-5555',
          balance: 0.0,
          createdAt: DateTime.now(),
        );

        // 1. Insert
        final createResult = await customerRepo.create(customer);
        expect(createResult, greaterThan(0));

        // 2. GetById
        final found = await customerRepo.findById(customer.id);
        expect(found, isNotNull);
        expect(found!.id, equals(customer.id));
        expect(found.name, equals(customer.name));
        expect(found.email, equals(customer.email));

        // 3. Update
        final updatedCustomer = CustomerEntity(
          id: customer.id,
          name: 'Updated Smoke Customer',
          email: 'updated-smoke@customer.com',
          phone: '555-555-1111',
          balance: 100.0,
          createdAt: customer.createdAt,
        );
        final updateResult = await customerRepo.update(updatedCustomer);
        expect(updateResult, equals(1));

        final foundAfterUpdate = await customerRepo.findById(customer.id);
        expect(foundAfterUpdate!.name, equals('Updated Smoke Customer'));
        expect(foundAfterUpdate.email, equals('updated-smoke@customer.com'));
        expect(foundAfterUpdate.balance, equals(100.0));

        // 4. List
        final allCustomers = await customerRepo.findAll();
        // Default customer (cust-1) + our test customer = 2 active customers
        expect(allCustomers.length, equals(2));
        expect(allCustomers.any((c) => c.id == customer.id), isTrue);

        // 5. Delete (Soft delete in SqliteCustomerRepository)
        final deleteResult = await customerRepo.delete(customer.id);
        expect(deleteResult, equals(1));

        final foundAfterDelete = await customerRepo.findById(customer.id);
        expect(foundAfterDelete, isNull);

        final allCustomersAfterDelete = await customerRepo.findAll();
        // Test customer deleted, leaving the default customer
        expect(allCustomersAfterDelete.length, equals(1));
      });
    });

    group('OrderRepository CRUD', () {
      test('Insert, GetById, Update, Delete, List', () async {
        final order = OrderEntity(
          id: 'test-order-301',
          customerId: 'cust-1',
          status: 'created',
          createdAt: DateTime.now(),
          expectedDeliveryDate: DateTime.now().add(const Duration(days: 2)),
          items: [],
        );

        // 1. Insert
        final createResult = await orderRepo.create(order);
        expect(createResult, greaterThan(0));

        // 2. GetById
        final found = await orderRepo.findById(order.id);
        expect(found, isNotNull);
        expect(found!.id, equals(order.id));
        expect(found.customerId, equals(order.customerId));
        expect(found.status, equals('created'));

        // 3. Update
        final updatedOrder = OrderEntity(
          id: order.id,
          customerId: order.customerId,
          status: 'preparing',
          createdAt: order.createdAt,
          expectedDeliveryDate: order.expectedDeliveryDate,
          actualDeliveryDate: DateTime.now(),
          items: [],
        );
        final updateResult = await orderRepo.update(updatedOrder);
        expect(updateResult, equals(1));

        final foundAfterUpdate = await orderRepo.findById(order.id);
        expect(foundAfterUpdate!.status, equals('preparing'));
        expect(foundAfterUpdate.actualDeliveryDate, isNotNull);

        // 4. List
        final allOrders = await orderRepo.findAll();
        expect(allOrders.length, equals(1));
        expect(allOrders.any((o) => o.id == order.id), isTrue);

        // 5. Delete
        final deleteResult = await orderRepo.delete(order.id);
        expect(deleteResult, equals(1));

        final foundAfterDelete = await orderRepo.findById(order.id);
        expect(foundAfterDelete, isNull);

        final allOrdersAfterDelete = await orderRepo.findAll();
        expect(allOrdersAfterDelete.isEmpty, isTrue);
      });
    });

    group('SaleRepository CRUD', () {
      test('Insert, GetById, Update, Delete, List', () async {
        final sale = SaleEntity(
          id: 'test-sale-401',
          customerId: 'cust-1',
          totalAmount: 1500.0,
          paidAmount: 500.0,
          paymentMethod: 'credit_card',
          status: 'pending',
          createdAt: DateTime.now(),
          items: [],
        );

        // 1. Insert
        final createResult = await saleRepo.create(sale);
        expect(createResult, greaterThan(0));

        // 2. GetById
        final found = await saleRepo.findById(sale.id);
        expect(found, isNotNull);
        expect(found!.id, equals(sale.id));
        expect(found.customerId, equals(sale.customerId));
        expect(found.totalAmount, equals(1500.0));
        expect(found.paidAmount, equals(500.0));

        // 3. Update
        final updatedSale = SaleEntity(
          id: sale.id,
          customerId: sale.customerId,
          totalAmount: 1500.0,
          paidAmount: 1500.0,
          paymentMethod: 'cash',
          status: 'completed',
          createdAt: sale.createdAt,
          items: [],
        );
        final updateResult = await saleRepo.update(updatedSale);
        expect(updateResult, equals(1));

        final foundAfterUpdate = await saleRepo.findById(sale.id);
        expect(foundAfterUpdate!.status, equals('completed'));
        expect(foundAfterUpdate.paidAmount, equals(1500.0));

        // 4. List
        final allSales = await saleRepo.findAll();
        expect(allSales.length, equals(1));
        expect(allSales.any((s) => s.id == sale.id), isTrue);

        // 5. Delete
        final deleteResult = await saleRepo.delete(sale.id);
        expect(deleteResult, equals(1));

        final foundAfterDelete = await saleRepo.findById(sale.id);
        expect(foundAfterDelete, isNull);

        final allSalesAfterDelete = await saleRepo.findAll();
        expect(allSalesAfterDelete.isEmpty, isTrue);
      });
    });
  });
}
