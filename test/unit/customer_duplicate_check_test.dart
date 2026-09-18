// test/unit/customer_duplicate_check_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/database/schema/db_schema.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_customer_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Customer Duplicate Check & Phone Conflict Tests', () {
    late InMemoryCustomerRepository repo;

    setUp(() {
      repo = InMemoryCustomerRepository();
      InMemoryDb.customers.clear();
      InMemoryDb.customers.add(
        CustomerEntity(
          id: 'cust-1',
          name: 'Ahmet Yılmaz',
          email: 'ahmet@example.com',
          phone: '+905321234567',
          balance: 0.0,
          createdAt: DateTime.now(),
        ),
      );
    });

    test('Exact match (same name and same phone) returns exactMatch', () async {
      // Different casing & phone format: "AHMET YILMAZ" & "0532 123 45 67"
      final result = await repo.checkDuplicates(
        name: 'AHMET YILMAZ',
        phone: '0532 123 45 67',
      );

      expect(result.status, equals(CustomerDuplicateStatus.exactMatch));
      expect(result.isExactMatch, isTrue);
      expect(result.hasPhoneConflict, isFalse);
      expect(result.matchedCustomer?.id, equals('cust-1'));
    });

    test('Phone conflict (same phone, different name) returns phoneConflict', () async {
      // Same phone: "0532 123 4567", different name: "Mehmet Demir"
      final result = await repo.checkDuplicates(
        name: 'Mehmet Demir',
        phone: '05321234567',
      );

      expect(result.status, equals(CustomerDuplicateStatus.phoneConflict));
      expect(result.isExactMatch, isFalse);
      expect(result.hasPhoneConflict, isTrue);
      expect(result.matchedCustomer?.id, equals('cust-1'));
      expect(result.matchedCustomer?.name, equals('Ahmet Yılmaz'));
    });

    test('Different phone with same name returns none (allowed)', () async {
      final result = await repo.checkDuplicates(
        name: 'Ahmet Yılmaz',
        phone: '05449998877',
      );

      expect(result.status, equals(CustomerDuplicateStatus.none));
      expect(result.hasConflict, isFalse);
    });

    test('Completely new customer returns none', () async {
      final result = await repo.checkDuplicates(
        name: 'Fatma Kaya',
        phone: '05553332211',
      );

      expect(result.status, equals(CustomerDuplicateStatus.none));
      expect(result.hasConflict, isFalse);
    });

    test('Updating existing customer with excludeId ignores self match', () async {
      final result = await repo.checkDuplicates(
        name: 'Ahmet Yılmaz',
        phone: '+905321234567',
        excludeId: 'cust-1',
      );

      expect(result.status, equals(CustomerDuplicateStatus.none));
    });

    test('CustomersController blocks exact match with DuplicateCustomerException', () async {
      final container = ProviderContainer(
        overrides: [
          customerRepositoryProvider.overrideWith((ref) => Future.value(repo)),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(customersControllerProvider.notifier);

      final duplicateCustomer = CustomerEntity(
        id: 'cust-new',
        name: 'AHMET YILMAZ',
        email: '',
        phone: '05321234567',
        balance: 0.0,
        createdAt: DateTime.now(),
      );

      expect(
        () => controller.addCustomer(duplicateCustomer),
        throwsA(isA<DuplicateCustomerException>()),
      );
    });

    test('CustomersController throws CustomerPhoneConflictException without force', () async {
      final container = ProviderContainer(
        overrides: [
          customerRepositoryProvider.overrideWith((ref) => Future.value(repo)),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(customersControllerProvider.notifier);

      final conflictingCustomer = CustomerEntity(
        id: 'cust-new',
        name: 'Mehmet Demir',
        email: '',
        phone: '05321234567',
        balance: 0.0,
        createdAt: DateTime.now(),
      );

      // Without force -> Throws conflict exception
      expect(
        () => controller.addCustomer(conflictingCustomer, force: false),
        throwsA(isA<CustomerPhoneConflictException>()),
      );

      // With force: true (user insisted) -> Succeeds!
      await controller.addCustomer(conflictingCustomer, force: true);
      expect(InMemoryDb.customers.length, equals(2));
      expect(InMemoryDb.customers.any((c) => c.name == 'Mehmet Demir'), isTrue);
    });
  });

  group('SqliteCustomerRepository Duplicate Check Tests', () {
    late Database db;
    late SqliteCustomerRepository sqliteRepo;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await DatabaseSchema.createTables(db);
      sqliteRepo = SqliteCustomerRepository(DbGatewayImpl.raw(db));

      await sqliteRepo.create(
        CustomerEntity(
          id: 'sqlite-cust-1',
          name: 'Ahmet Yılmaz',
          email: 'ahmet@example.com',
          phone: '+905321234567',
          balance: 0.0,
          createdAt: DateTime.now(),
        ),
      );
    });

    tearDown(() => db.close());

    test('SQLite exact match (same name and same phone) returns exactMatch', () async {
      final result = await sqliteRepo.checkDuplicates(
        name: 'AHMET YILMAZ',
        phone: '0532 123 45 67',
      );

      expect(result.status, equals(CustomerDuplicateStatus.exactMatch));
      expect(result.isExactMatch, isTrue);
      expect(result.matchedCustomer?.id, equals('sqlite-cust-1'));
    });

    test('SQLite phone conflict (same phone, different name) returns phoneConflict', () async {
      final result = await sqliteRepo.checkDuplicates(
        name: 'Mehmet Demir',
        phone: '05321234567',
      );

      expect(result.status, equals(CustomerDuplicateStatus.phoneConflict));
      expect(result.hasPhoneConflict, isTrue);
      expect(result.matchedCustomer?.id, equals('sqlite-cust-1'));
      expect(result.matchedCustomer?.name, equals('Ahmet Yılmaz'));
    });

    test('SQLite different phone with same name returns none (allowed)', () async {
      final result = await sqliteRepo.checkDuplicates(
        name: 'Ahmet Yılmaz',
        phone: '05449998877',
      );

      expect(result.status, equals(CustomerDuplicateStatus.none));
    });

    test('SQLite updating existing customer with excludeId ignores self match', () async {
      final result = await sqliteRepo.checkDuplicates(
        name: 'Ahmet Yılmaz',
        phone: '+905321234567',
        excludeId: 'sqlite-cust-1',
      );

      expect(result.status, equals(CustomerDuplicateStatus.none));
    });
  });
}
