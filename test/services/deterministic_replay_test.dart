import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/data_integrity_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';

import 'package:serenutos/infrastructure/database/schema/db_triggers.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_customer_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_payment_repository.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';

void main() {
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SqliteCustomerRepository sqliteCustomerRepo;
  late SqliteFinancialTransactionRepository sqliteTransactionRepo;
  late InMemoryCustomerRepository memoryCustomerRepo;
  late InMemoryFinancialTransactionRepository memoryTransactionRepo;

  setUpAll(() async {
    DatabaseManager.overrideDatabasePath = ':memory:';
    db = await DatabaseManager().getDatabase();
    final gateway = DbGatewayImpl.raw(db);

    sqliteCustomerRepo = SqliteCustomerRepository(gateway);
    sqliteTransactionRepo = SqliteFinancialTransactionRepository(gateway);

    memoryCustomerRepo = InMemoryCustomerRepository();
    memoryTransactionRepo = InMemoryFinancialTransactionRepository();
  });

  tearDownAll(() async {
    await db.close();
    DatabaseManager.overrideDatabasePath = null;
  });

  group('Phase 3.1 & 3.2 Hardening Tests', () {
    const String custId = 'deterministic-customer';

    setUp(() async {
      await db.update('ledger_bypass_flag', {'active': 1});
      await db.delete('financial_transactions');
      await db.delete('trigger_audit_logs');
      await db.delete('customers');
      await db.update('ledger_bypass_flag', {'active': 0});

      InMemoryDb.transactions.clear();
      InMemoryDb.customers.clear();
      InMemoryFinancialTransactionRepository.triggerAuditLogs.clear();

      final customer = CustomerEntity(
        id: custId,
        name: 'Deterministic Customer',
        email: 'det@test.com',
        phone: '1234',
        balance: 0.0,
        createdAt: DateTime.now(),
      );

      await sqliteCustomerRepo.create(customer);
      await memoryCustomerRepo.create(customer);
    });

    test(
        'SQLite vs InMemory Dual-Engine Deterministic Replay and Audit Log Match',
        () async {
      final random = Random(42);
      final List<Map<String, dynamic>> actions = [];

      for (int i = 0; i < 100; i++) {
        final isSale = random.nextBool();
        final amount = random.nextDouble() * 200 + 10;
        actions.add({
          'op': 'insert',
          'id': 'tx-rand-$i',
          'type': isSale ? 'sale' : 'collection',
          'amount': amount,
          'paidAmount':
              isSale ? (random.nextBool() ? 0.0 : amount / 2) : amount,
          'debtAmount':
              isSale ? (random.nextBool() ? amount : amount / 2) : 0.0,
        });
      }

      for (final action in actions) {
        final entity = FinancialTransactionEntity(
          id: action['id'],
          type: action['type'],
          customerId: custId,
          amount: action['amount'],
          paidAmount: action['paidAmount'],
          debtAmount: action['debtAmount'],
          date: DateTime.now(),
        );
        await sqliteTransactionRepo.create(entity);
        await memoryTransactionRepo.create(entity);
      }

      // Assert final customer balance matches to the decimal point
      final sqliteBalance = await sqliteCustomerRepo.getBalance(custId);
      final memoryBalance = await memoryCustomerRepo.getBalance(custId);
      expect(sqliteBalance, equals(memoryBalance));

      // Fetch trigger audit logs from SQLite
      final sqliteAuditRows =
          await db.query('trigger_audit_logs', orderBy: 'id ASC');
      final memoryAuditRows =
          InMemoryFinancialTransactionRepository.triggerAuditLogs;

      // Assert trigger counts match
      expect(sqliteAuditRows.length, equals(memoryAuditRows.length));

      // Assert every transition matches exactly (within floating point precision)
      for (int i = 0; i < sqliteAuditRows.length; i++) {
        final sqlRow = sqliteAuditRows[i];
        final memRow = memoryAuditRows[i];

        expect(sqlRow['trigger_name'], equals(memRow['trigger_name']));
        expect(sqlRow['customer_id'], equals(memRow['customer_id']));
        expect(sqlRow['transaction_id'], equals(memRow['transaction_id']));

        final sqlBefore = sqlRow['before_balance'] as double;
        final memBefore = memRow['before_balance'] as double;
        expect((sqlBefore - memBefore).abs(), lessThan(0.001));

        final sqlAfter = sqlRow['after_balance'] as double;
        final memAfter = memRow['after_balance'] as double;
        expect((sqlAfter - memAfter).abs(), lessThan(0.001));
      }
    });

    test(
        'Verifies that update and delete operations are strictly blocked on both engines (Ledger Immutability)',
        () async {
      final tx = FinancialTransactionEntity(
        id: 'tx-immut-1',
        type: 'sale',
        customerId: custId,
        amount: 100.0,
        paidAmount: 0.0,
        debtAmount: 100.0,
        date: DateTime.now(),
      );

      // Create initially
      await sqliteTransactionRepo.create(tx);
      await memoryTransactionRepo.create(tx);

      // 1. Assert SQLite block
      expect(
          () => db.update('financial_transactions', {'amount': 200.0},
              where: 'id = ?', whereArgs: ['tx-immut-1']),
          throwsA(isA<DatabaseException>()));
      expect(
          () => db.delete('financial_transactions',
              where: 'id = ?', whereArgs: ['tx-immut-1']),
          throwsA(isA<DatabaseException>()));

      // 2. Assert InMemory block
      expect(() => memoryTransactionRepo.update(tx),
          throwsA(isA<UnsupportedError>()));
      expect(() => memoryTransactionRepo.delete('tx-immut-1'),
          throwsA(isA<UnsupportedError>()));
    });

    test('DatabaseManager trigger self-healing validation', () async {
      var rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name = 'trg_ft_insert'");
      expect(rows.length, 1);

      await db.execute('DROP TRIGGER IF EXISTS trg_ft_insert');

      rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name = 'trg_ft_insert'");
      expect(rows.isEmpty, isTrue);

      await DatabaseTriggers.verifyAndRepairTriggers(db);

      rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name = 'trg_ft_insert'");
      expect(rows.length, 1);
    });

    test(
        'DataIntegrityService explainCustomerBalance calculations are mathematically correct',
        () async {
      final gateway = DbGatewayImpl.raw(db);
      final integrityService = DataIntegrityService(
        customerRepository: sqliteCustomerRepo,
        transactionRepository: sqliteTransactionRepo,
      );

      await sqliteTransactionRepo.create(FinancialTransactionEntity(
        id: 'expl-tx-1',
        type: 'sale',
        customerId: custId,
        amount: 150.0,
        paidAmount: 50.0,
        debtAmount: 100.0,
        date: DateTime.now().subtract(const Duration(minutes: 10)),
      ));

      await sqliteTransactionRepo.create(FinancialTransactionEntity(
        id: 'expl-tx-2',
        type: 'collection',
        customerId: custId,
        amount: 60.0,
        paidAmount: 60.0,
        debtAmount: 0.0,
        date: DateTime.now().subtract(const Duration(minutes: 5)),
      ));

      final explanations =
          await integrityService.explainCustomerBalance(custId);

      expect(explanations.length, equals(2));

      expect(explanations[0].transactionId, equals('expl-tx-1'));
      expect(explanations[0].runningBalance, equals(-100.0));
      expect(explanations[0].description,
          contains('150.00 TL değerinde satış yapıldı'));

      expect(explanations[1].transactionId, equals('expl-tx-2'));
      expect(explanations[1].runningBalance, equals(-40.0));
      expect(explanations[1].description, contains('60.00 TL tahsilat alındı'));

      final finalBalance = await sqliteCustomerRepo.getBalance(custId);
      expect(finalBalance, equals(explanations.last.runningBalance));
    });
  });
}
