// test/services/service_decomposition_test.dart
// Phase 2.4 — Service Decomposition & Orchestration Integration Tests
// Generated: 21 Jun 2026

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/events/event_publisher.dart';
import 'package:serenutos/domain/services/inventory_service.dart';
import 'package:serenutos/domain/services/payment_service.dart';
import 'package:serenutos/domain/services/sales_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/security_gate.dart';

class FakeSecurityGate implements SecurityGate {
  @override
  void ensureAccess() {}
  @override
  void ensureDbIntegrity() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Service Decomposition & ERP Core Kernel Integration Tests', () {
    late Database db;
    late DatabaseManager databaseManager;
    late IProductRepository productRepo;
    late ICustomerRepository customerRepo;
    late ISaleRepository saleRepo;
    late IFinancialTransactionRepository transactionRepo;

    late EventPublisher eventPublisher;
    late InventoryService inventoryService;
    late PaymentService paymentService;
    late SalesService salesService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'serenut_pos_test.db');
      await deleteDatabase(path);

      databaseManager = DatabaseManager();
      db = await databaseManager.getDatabase();

      final gateway = DbGatewayImpl(databaseManager);
      productRepo = SqliteProductRepository(gateway);
      customerRepo = SqliteCustomerRepository(gateway);
      saleRepo = SqliteSaleRepository(gateway);
      transactionRepo = SqliteFinancialTransactionRepository(gateway);

      eventPublisher = EventPublisher();

      inventoryService = InventoryService(
        productRepository: productRepo,
        eventPublisher: eventPublisher,
      );

      paymentService = PaymentService(
        customerRepository: customerRepo,
        transactionRepository: transactionRepo,
        eventPublisher: eventPublisher,
      );

      salesService = SalesService(
        saleRepository: saleRepo,
        inventoryService: inventoryService,
        paymentService: paymentService,
        eventPublisher: eventPublisher,
        transactionRunner: gateway,
        securityGate: FakeSecurityGate(),
      );

      // Clean start: clear tables and add fresh mock data
      await db.update('ledger_bypass_flag', {'active': 1});
      await db.delete('sale_items');
      await db.delete('sales');
      await db.delete('financial_transactions');
      await db.delete('customers');
      await db.delete('products');
      await db.update('ledger_bypass_flag', {'active': 0});

      // Create test product (quantity: 10, price: 100)
      await productRepo.create(ProductEntity(
        id: 'prod-test-1',
        name: 'Test Product',
        description: 'Test Description',
        price: 100.0,
        quantity: 10,
        category: 'TestCategory',
        vat: 18,
      ));

      // Create test customer (balance: 0.0)
      await customerRepo.create(CustomerEntity(
        id: 'cust-test-1',
        name: 'Test Customer',
        email: 'test@customer.com',
        phone: '123-456-7890',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));
    });

    tearDown(() async {
      await databaseManager.close();
    });

    test('InventoryService.verifyStockAvailability - Stock checking', () async {
      // 1. Should succeed for available stock (quantity 5)
      await expectLater(
        inventoryService.verifyStockAvailability([
          SaleItemInput(productId: 'prod-test-1', quantity: 5, unitPrice: 100.0)
        ]),
        completes,
      );

      // 2. Should complete successfully for quantity 15 (only 10 in stock) because we allow negative stock
      await expectLater(
        inventoryService.verifyStockAvailability([
          SaleItemInput(
              productId: 'prod-test-1', quantity: 15, unitPrice: 100.0)
        ]),
        completes,
      );

      // 3. Should throw ProductNotFoundException for unknown product
      await expectLater(
        inventoryService.verifyStockAvailability([
          SaleItemInput(
              productId: 'prod-unknown', quantity: 1, unitPrice: 100.0)
        ]),
        throwsA(isA<ProductNotFoundException>()),
      );
    });

    test('SalesService.createSale - Full sale orchestrator flow with debt',
        () async {
      // Create a sale with total 300 TL, paid 100 TL, debt 200 TL
      final sale = await salesService.createSale(
        customerId: 'cust-test-1',
        items: [
          SaleItemInput(productId: 'prod-test-1', quantity: 3, unitPrice: 100.0)
        ],
        paymentMethod: 'credit',
        paidAmount: 100.0,
      );

      expect(sale.id, startsWith('sale-'));
      expect(sale.totalAmount, equals(300.0));
      expect(sale.paidAmount, equals(100.0));

      // Check stock decreased from 10 to 7
      final product = await productRepo.findById('prod-test-1');
      expect(product!.quantity, equals(7));

      // Check customer balance is updated (0 - 200 = -200)
      final customer = await customerRepo.findById('cust-test-1');
      expect(customer!.balance, equals(-200.0));

      // Check financial transaction record is created (type: 'sale')
      final txs = await transactionRepo.getByCustomerId('cust-test-1');
      expect(txs.length, equals(1));
      expect(txs.first.type, equals('sale'));
      expect(txs.first.amount, equals(300.0));
      expect(txs.first.paidAmount, equals(100.0));
      expect(txs.first.debtAmount, equals(200.0));
      expect(txs.first.referenceId, equals(sale.id));
    });

    test('SalesService.recordPayment - Record partial payment on existing sale',
        () async {
      // Create sale first
      final sale = await salesService.createSale(
        customerId: 'cust-test-1',
        items: [
          SaleItemInput(productId: 'prod-test-1', quantity: 3, unitPrice: 100.0)
        ],
        paymentMethod: 'credit',
        paidAmount: 100.0,
      );

      // Record 50 TL partial payment
      await salesService.recordPayment(
          saleId: sale.id, amount: 50.0, method: 'cash');

      // Check updated sale paid amount is 150 TL
      final updatedSale = await saleRepo.findById(sale.id);
      expect(updatedSale!.paidAmount, equals(150.0));
      expect(updatedSale.status, equals('partial'));

      // Check customer balance increased (reduced debt) by 50 (-200 + 50 = -150)
      final customer = await customerRepo.findById('cust-test-1');
      expect(customer!.balance, equals(-150.0));

      // Check financial transaction record is created (type: 'payment')
      final txs = await transactionRepo.getByCustomerId('cust-test-1');
      expect(txs.length, equals(2)); // sale + payment
      final paymentTx = txs.firstWhere((t) => t.type == 'payment');
      expect(paymentTx.amount, equals(50.0));
      expect(paymentTx.paidAmount, equals(50.0));
      expect(paymentTx.debtAmount, equals(150.0));
      expect(paymentTx.referenceId, equals(sale.id));
    });

    test(
        'SalesService.cancelSale - Reverses stock, customer balance, and records cancellation',
        () async {
      // Create sale
      final sale = await salesService.createSale(
        customerId: 'cust-test-1',
        items: [
          SaleItemInput(productId: 'prod-test-1', quantity: 4, unitPrice: 100.0)
        ],
        paymentMethod: 'credit',
        paidAmount: 100.0, // total: 400, paid: 100, debt: 300
      );

      // Cancel the sale
      await salesService.cancelSale(sale.id);

      // Check stock restored to 10 (was 6 after sale, now 10)
      final product = await productRepo.findById('prod-test-1');
      expect(product!.quantity, equals(10));

      // Check customer balance debt reversed (-300 debt restored back by adding 300, balance returns to 0.0)
      final customer = await customerRepo.findById('cust-test-1');
      expect(customer!.balance, equals(0.0));

      // Check cancellation transaction is created
      final txs = await transactionRepo.getByCustomerId('cust-test-1');
      final cancelTx = txs.firstWhere((t) => t.type == 'cancellation');
      expect(cancelTx.amount, equals(400.0));
      expect(cancelTx.referenceId, equals(sale.id));
    });

    test(
        'PaymentService.recordCollection - Cari tahsilat entry and balance adjustment',
        () async {
      // Record a customer collection of 500 TL (meaning customer starts with credit)
      await paymentService.recordCollection(
        customerId: 'cust-test-1',
        amount: 500.0,
        method: 'cash',
        notes: 'Cari tahsilat smoke test',
      );

      // Check customer balance is updated (+500.0)
      final customer = await customerRepo.findById('cust-test-1');
      expect(customer!.balance, equals(500.0));

      // Check financial transaction record is created (type: 'collection')
      final txs = await transactionRepo.getByCustomerId('cust-test-1');
      expect(txs.length, equals(1));
      expect(txs.first.type, equals('collection'));
      expect(txs.first.amount, equals(500.0));
      expect(txs.first.paidAmount, equals(500.0));
      expect(txs.first.debtAmount, equals(0.0));
      expect(txs.first.metadata?['notes'], equals('Cari tahsilat smoke test'));
    });

    test('SalesService.returnItems - Return items and credit customer balance',
        () async {
      // Create sale
      final sale = await salesService.createSale(
        customerId: 'cust-test-1',
        items: [
          SaleItemInput(productId: 'prod-test-1', quantity: 3, unitPrice: 100.0)
        ],
        paymentMethod: 'cash',
        paidAmount: 300.0, // total: 300, paid: 300, debt: 0
      );

      // Return 2 items back to balance
      await salesService.returnItems(
        saleId: sale.id,
        itemsToReturn: [
          SaleItemInput(productId: 'prod-test-1', quantity: 2, unitPrice: 100.0)
        ],
        refundMethod: 'balance',
      );

      // Check stock increased from 7 to 9
      final product = await productRepo.findById('prod-test-1');
      expect(product!.quantity, equals(9));

      // Check customer balance credited by 200 (was 0.0 after cash sale, now +200.0)
      final customer = await customerRepo.findById('cust-test-1');
      expect(customer!.balance, equals(200.0));

      // Check refund transaction created
      final txs = await transactionRepo.getByCustomerId('cust-test-1');
      final refundTx = txs.firstWhere((t) => t.type == 'refund');
      expect(refundTx.amount, equals(200.0));
      expect(refundTx.paidAmount,
          equals(0.0)); // refundMethod is balance, so cash refund is 0
      expect(refundTx.referenceId, equals(sale.id));
    });
    group('v_financial_ledger view integration', () {
      test(
          'Query from v_financial_ledger view aggregates debit/credit correctly',
          () async {
        // Create sale (total: 300, paid: 100, debt: 200)
        final sale = await salesService.createSale(
          customerId: 'cust-test-1',
          items: [
            SaleItemInput(
                productId: 'prod-test-1', quantity: 3, unitPrice: 100.0)
          ],
          paymentMethod: 'credit',
          paidAmount: 100.0,
        );

        // Record partial payment (50 TL)
        await salesService.recordPayment(
            saleId: sale.id, amount: 50.0, method: 'cash');

        // Query view directly
        final rows =
            await db.query('v_financial_ledger', orderBy: 'created_at ASC');
        expect(rows.length, equals(2));

        final saleRow = rows.firstWhere((r) => r['type'] == 'sale');
        expect(saleRow['debit'], equals(300.0));
        expect(saleRow['credit'], equals(100.0));

        final paymentRow = rows.firstWhere((r) => r['type'] == 'payment');
        expect(paymentRow['debit'], equals(0.0));
        expect(paymentRow['credit'], equals(50.0));
      });
    });
  });
}
