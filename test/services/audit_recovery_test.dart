// test/services/audit_recovery_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/models/audit_event.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_audit_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_recovery_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_customer_repository.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Audit Center & Recovery Center Integration Tests', () {
    late Database db;
    late DatabaseManager databaseManager;
    late SqliteAuditRepository auditRepo;
    late SqliteRecoveryRepository recoveryRepo;
    late SqliteProductRepository productRepo;
    late SqliteCustomerRepository customerRepo;

    setUp(() async {
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      databaseManager = DatabaseManager();
      db = await databaseManager.getDatabase();

      auditRepo = SqliteAuditRepository(databaseManager);
      recoveryRepo = SqliteRecoveryRepository(databaseManager);
      final gateway = DbGatewayImpl(databaseManager);
      productRepo = SqliteProductRepository(gateway);
      customerRepo = SqliteCustomerRepository(gateway);
    });

    test('Audit Center - Log event, retrieve, and search', () async {
      final now = DateTime.now();
      final event = AuditEvent(
        id: 'evt-test-1',
        eventType: 'price_changed',
        entityType: 'product',
        entityId: 'prod-1',
        userId: 'user-admin',
        userName: 'Admin User',
        oldValue: '₺10.00',
        newValue: '₺15.00',
        timestamp: now,
        deviceId: 'dev-12345',
        notes: 'Fiyat arttırıldı.',
      );

      // Log event
      await auditRepo.logEvent(event);

      // Retrieve events
      final events = await auditRepo.getEvents(eventType: 'price_changed');
      expect(events, hasLength(1));
      expect(events.first.id, 'evt-test-1');
      expect(events.first.oldValue, '₺10.00');
      expect(events.first.newValue, '₺15.00');

      // Search events
      final searchResults = await auditRepo.search('arttırıldı');
      expect(searchResults, hasLength(1));
      expect(searchResults.first.notes, 'Fiyat arttırıldı.');
    });

    test('Recovery Center - Soft delete, list, restore and purge products', () async {
      final product = ProductEntity(
        id: 'prod-test-99',
        name: 'Test Kola',
        description: 'Soğuk içecek',
        price: 25.0,
        quantity: 50,
        category: 'İçecek',
      );

      // Create product
      await productRepo.create(product);
      
      var list = await productRepo.findAll();
      expect(list.any((p) => p.id == 'prod-test-99'), isTrue);

      // Soft delete
      await productRepo.delete('prod-test-99');

      // Product should be hidden from findAll
      list = await productRepo.findAll();
      expect(list.any((p) => p.id == 'prod-test-99'), isFalse);

      // Listing deleted items from Recovery center
      var deleted = await recoveryRepo.getDeletedItems('product');
      expect(deleted.any((item) => item['id'] == 'prod-test-99'), isTrue);
      expect(deleted.first['is_deleted'], 1);
      expect(deleted.first['deleted_at'], isNotNull);

      // Restore product
      await recoveryRepo.restore('product', 'prod-test-99');

      list = await productRepo.findAll();
      expect(list.any((p) => p.id == 'prod-test-99'), isTrue);

      deleted = await recoveryRepo.getDeletedItems('product');
      expect(deleted.any((item) => item['id'] == 'prod-test-99'), isFalse);

      // Purge (hard delete)
      await productRepo.delete('prod-test-99');
      await recoveryRepo.purge('product', 'prod-test-99');

      final exists = await productRepo.exists('prod-test-99');
      expect(exists, isFalse);
    });

    test('Recovery Center - Soft delete and restore customers', () async {
      final customer = CustomerEntity(
        id: 'cust-test-99',
        name: 'Yasin Karaca',
        email: 'yasin@example.com',
        phone: '5554443322',
        balance: -100.0,
        createdAt: DateTime.now(),
      );

      // Create customer
      await customerRepo.create(customer);
      
      var list = await customerRepo.findAll();
      expect(list.any((c) => c.id == 'cust-test-99'), isTrue);

      // Soft delete
      await customerRepo.delete('cust-test-99');

      // Customer should be hidden from findAll
      list = await customerRepo.findAll();
      expect(list.any((c) => c.id == 'cust-test-99'), isFalse);

      // Retrieve deleted items
      var deleted = await recoveryRepo.getDeletedItems('customer');
      expect(deleted.any((item) => item['id'] == 'cust-test-99'), isTrue);

      // Restore customer
      await recoveryRepo.restore('customer', 'cust-test-99');

      list = await customerRepo.findAll();
      expect(list.any((c) => c.id == 'cust-test-99'), isTrue);
    });
  });
}
