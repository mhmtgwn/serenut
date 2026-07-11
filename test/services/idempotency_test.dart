import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:serenutos/domain/events/event_publisher.dart';
import 'package:serenutos/domain/events/domain_event.dart';
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
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Idempotency, Locking & Sale State Machine Tests', () {
    late DatabaseManager databaseManager;
    late Database db;
    late IProductRepository productRepo;
    late ICustomerRepository customerRepo;
    late ISaleRepository saleRepo;
    late IFinancialTransactionRepository transactionRepo;
    late EventPublisher eventPublisher;

    late InventoryService inventoryService;
    late PaymentService paymentService;
    late SalesService salesService;

    setUp(() async {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'serenut_pos_idempotency.db');
      await deleteDatabase(path);

      DatabaseManager.overrideDatabasePath = path;
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

      // Clear all tables to be 100% clean
      await db.update('ledger_bypass_flag', {'active': 1});
      await db.delete('sale_items');
      await db.delete('sales');
      await db.delete('financial_transactions');
      await db.delete('customers');
      await db.delete('products');
      await db.update('ledger_bypass_flag', {'active': 0});

      // Add mock data
      await productRepo.create(ProductEntity(
        id: 'prod-1',
        name: 'Product 1',
        description: 'Desc',
        price: 50.0,
        quantity: 10,
        category: 'Electronics',
        vat: 18,
      ));

      await customerRepo.create(CustomerEntity(
        id: 'cust-1',
        name: 'Customer 1',
        email: 'cust1@example.com',
        phone: '123-456-7890',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));
    });

    tearDown(() async {
      DatabaseManager.overrideDatabasePath = null;
      DatabaseManager.isWriteLocked = false;
      await databaseManager.close();
    });

    test('Should block writes and throw DatabaseLockedException when database is write-locked', () async {
      DatabaseManager.isWriteLocked = true;

      expect(
        () => productRepo.create(ProductEntity(
          id: 'prod-2',
          name: 'Product 2',
          description: 'Desc',
          price: 10.0,
          quantity: 5,
          category: 'Electronics',
        )),
        throwsA(isA<DatabaseLockedException>()),
      );
    });

    test('Should complete sale idempotently if idempotencyKey is used twice', () async {
      const idempotencyKey = 'key-unique-123';

      final sale1 = await salesService.createSale(
        customerId: 'cust-1',
        items: [SaleItemInput(productId: 'prod-1', quantity: 2, unitPrice: 50.0)],
        paymentMethod: 'cash',
        paidAmount: 100.0,
        idempotencyKey: idempotencyKey,
      );

      expect(sale1.status, equals('completed'));
      expect(sale1.idempotencyKey, equals(idempotencyKey));

      // Verify stock decreased from 10 to 8
      final prod1 = await productRepo.findById('prod-1');
      expect(prod1!.quantity, equals(8));

      // Try creating the exact same sale with the same idempotency key again
      final sale2 = await salesService.createSale(
        customerId: 'cust-1',
        items: [SaleItemInput(productId: 'prod-1', quantity: 2, unitPrice: 50.0)],
        paymentMethod: 'cash',
        paidAmount: 100.0,
        idempotencyKey: idempotencyKey,
      );

      // Verify second attempt returned the same entity and did not create a new DB row
      expect(sale2.id, equals(sale1.id));
      expect(sale2.idempotencyKey, equals(idempotencyKey));

      // Verify stock is still 8 (no double-decrement)
      final prod2 = await productRepo.findById('prod-1');
      expect(prod2!.quantity, equals(8));
    });

    test('Should allow out-of-stock sale and set negative stock', () async {
      final events = <DomainEvent>[];
      eventPublisher.subscribe<SaleCreatedEvent>((e) => events.add(e));

      final sale = await salesService.createSale(
        customerId: 'cust-1',
        items: [SaleItemInput(productId: 'prod-1', quantity: 15, unitPrice: 50.0)],
        paymentMethod: 'cash',
        paidAmount: 750.0,
      );

      expect(sale.id, startsWith('sale-'));

      // Verify stock is now -5 (decremented from 10 to -5)
      final prod = await productRepo.findById('prod-1');
      expect(prod!.quantity, equals(-5));

      // Verify sale was recorded in DB
      final allSales = await saleRepo.findAll();
      expect(allSales.length, equals(1));
    });

    test('Should defer event publishing until transaction commits, and discard events on rollback', () async {
      final events = <DomainEvent>[];
      eventPublisher.subscribe<DomainEvent>((e) => events.add(e));

      // 1. Transaction that succeeds
      final gateway = DbGatewayImpl(databaseManager);
      await gateway.transaction(() async {
        eventPublisher.publish(SaleCreatedEvent(
          saleId: 999,
          customerId: 1,
          totalAmount: 100.0,
        ));
        // Event should be deferred, so not in 'events' yet
        expect(events, isEmpty);
      });

      // After commit, event should be published
      await Future.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.first, isA<SaleCreatedEvent>());

      events.clear();

      // 2. Transaction that rolls back (throws exception)
      try {
        await gateway.transaction(() async {
          eventPublisher.publish(SaleCreatedEvent(
            saleId: 888,
            customerId: 1,
            totalAmount: 100.0,
          ));
          throw Exception('Force Rollback');
        });
      } catch (_) {}

      // Event should be discarded, not published
      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
    });
  });
}
