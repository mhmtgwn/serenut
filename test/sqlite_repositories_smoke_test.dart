// test/sqlite_repositories_smoke_test.dart
import 'dart:convert';
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

      test('ürün fiyatı güncellendiğinde açık sipariş ve vadeli satış fiyatları da güncellenir', () async {
        final prod = ProductEntity(
          id: 'prod-price-test',
          name: 'Peynir',
          description: '',
          price: 100.0,
          quantity: 50,
          category: 'Sut',
        );
        await productRepo.create(prod);

        // 1. Open Order with 2x Peynir at 100 TL = 200 TL
        const orderId = 'ord-test-1';
        await db.insert('orders', {
          'id': orderId,
          'order_number': 'ORD-1001',
          'customer_id': 'cust-1',
          'status': 'created',
          'total_amount': 200.0,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        await db.insert('order_items', {
          'id': 'oi-1',
          'order_id': orderId,
          'product_id': 'prod-price-test',
          'product_name': 'Peynir',
          'quantity': 2.0,
          'unit_price': 100.0,
          'created_at': DateTime.now().toIso8601String(),
        });

        // 2. Open/Deferred Sale (debt) with 3x Peynir at 100 TL = 300 TL
        const saleId = 'sale-test-1';
        await db.insert('sales', {
          'id': saleId,
          'customer_id': 'cust-1',
          'total_amount': 300.0,
          'paid_amount': 0.0,
          'payment_method': 'debt',
          'status': 'completed',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        await db.insert('sale_items', {
          'id': 'si-1',
          'sale_id': saleId,
          'product_id': 'prod-price-test',
          'product_name': 'Peynir',
          'quantity': 3.0,
          'unit_price': 100.0,
          'subtotal': 300.0,
          'created_at': DateTime.now().toIso8601String(),
        });
        await db.insert('financial_transactions', {
          'id': 'ft-1',
          'type': 'sale',
          'customer_id': 'cust-1',
          'amount': 300.0,
          'paid_amount': 0.0,
          'debt_amount': 300.0,
          'reference_id': saleId,
          'created_at': DateTime.now().toIso8601String(),
        });

        // Update product price from 100 TL to 150 TL
        final updatedProd = prod.copyWith(price: 150.0);
        await productRepo.update(updatedProd);

        // Verify order item and order total
        final orderItems = await db.query('order_items', where: 'order_id = ?', whereArgs: [orderId]);
        expect(orderItems.first['unit_price'], equals(150.0));

        final orderRows = await db.query('orders', where: 'id = ?', whereArgs: [orderId]);
        expect(orderRows.first['total_amount'], equals(300.0)); // 2x 150 = 300

        // Verify sale item, sale total, and financial transaction
        final saleItems = await db.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
        expect(saleItems.first['unit_price'], equals(150.0));
        expect(saleItems.first['subtotal'], equals(450.0)); // 3x 150 = 450

        final saleRows = await db.query('sales', where: 'id = ?', whereArgs: [saleId]);
        expect(saleRows.first['total_amount'], equals(450.0));

        final ftRows = await db.query('financial_transactions', where: 'reference_id = ?', whereArgs: [saleId]);
        expect(ftRows.first['amount'], equals(450.0));
        expect(ftRows.first['debt_amount'], equals(450.0));
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
        expect(found.orderNumber, matches(RegExp(r'^SP-\d{6,}$')));
        expect(found.displayNumber, equals(found.orderNumber));
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
        expect(foundAfterUpdate.orderNumber, equals(found.orderNumber));
        expect(foundAfterUpdate.actualDeliveryDate, isNotNull);

        final foundByNumber = await orderRepo.findFiltered(
          searchQuery: found.orderNumber,
        );
        expect(foundByNumber.map((item) => item.id), contains(order.id));

        // A status-only transition must be durable and replicated. Previously
        // this changed SQLite but never entered the v4 outbox.
        await orderRepo.updateStatus(order.id, 'ready');
        final foundAfterStatus = await orderRepo.findById(order.id);
        expect(foundAfterStatus!.status, equals('ready'));
        final statusMutations = await db.query(
          'sync_outbox_v4',
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: ['order', order.id],
          orderBy: 'id DESC',
          limit: 1,
        );
        expect(statusMutations, hasLength(1));
        final statusPayload =
            jsonDecode(statusMutations.single['payload']! as String)
                as Map<String, dynamic>;
        expect(statusPayload['status'], equals('ready'));
        expect(statusPayload['items'], isA<List<dynamic>>());

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
        expect(allOrdersAfterDelete.length, equals(0));
      });

      test('çakışan sipariş numarasında benzersiz sipariş numarası üretir', () async {
        await db.insert('orders', {
          'id': 'existing-ord-1',
          'order_number': 'SP-000001',
          'customer_id': 'cust-1',
          'status': 'created',
          'total_amount': 100.0,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });

        final newOrder = OrderEntity(
          id: 'test-order-collision',
          customerId: 'cust-1',
          status: 'created',
          createdAt: DateTime.now(),
          items: [],
        );

        final result = await orderRepo.create(newOrder);
        expect(result, greaterThan(0));

        final saved = await orderRepo.findById(newOrder.id);
        expect(saved, isNotNull);
        expect(saved!.orderNumber, equals('SP-000002'));
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
