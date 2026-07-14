import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_customer_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_payment_repository.dart';

void main() {
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SqliteCustomerRepository customerRepo;
  late SqliteFinancialTransactionRepository transactionRepo;

  setUpAll(() async {
    // Force override database path to memory database for clean testing
    DatabaseManager.overrideDatabasePath = ':memory:';
    db = await DatabaseManager().getDatabase();
    final gateway = DbGatewayImpl.raw(db);
    customerRepo = SqliteCustomerRepository(gateway);
    transactionRepo = SqliteFinancialTransactionRepository(gateway);
  });

  tearDownAll(() async {
    await db.close();
    DatabaseManager.overrideDatabasePath = null;
  });

  group('Financial Trigger Integrity Tests (SQLite Database Level)', () {
    const String custId = 'cust-trigger-test';

    setUp(() async {
      // Clear data before each test
      await db.update('ledger_bypass_flag', {'active': 1});
      await db.delete('financial_transactions');
      await db.delete('customers');
      await db.update('ledger_bypass_flag', {'active': 0});

      // Create a test customer with 0 balance
      await customerRepo.create(CustomerEntity(
        id: custId,
        name: 'Test Customer',
        email: 'test@customer.com',
        phone: '12345',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));
    });

    test(
        'Inserting transaction automatically updates customer balance via triggers',
        () async {
      // 1. Double check balance is 0
      var balance = await customerRepo.getBalance(custId);
      expect(balance, 0.0);

      // 2. Insert veresiye sale of 100 TL (debt = 100)
      await transactionRepo.create(FinancialTransactionEntity(
        id: 'tx-1',
        type: 'sale',
        customerId: custId,
        amount: 100.0,
        paidAmount: 0.0,
        debtAmount: 100.0,
        date: DateTime.now(),
        referenceId: 'sale-1',
      ));

      // Balance should be -100.0 (debt is negative)
      balance = await customerRepo.getBalance(custId);
      expect(balance, -100.0);

      // 3. Insert collection of 60 TL
      await transactionRepo.create(FinancialTransactionEntity(
        id: 'tx-2',
        type: 'collection',
        customerId: custId,
        amount: 60.0,
        paidAmount: 60.0,
        debtAmount: 0.0,
        date: DateTime.now(),
        referenceId: 'coll-1',
      ));

      // Balance should be -40.0 (-100 + 60)
      balance = await customerRepo.getBalance(custId);
      expect(balance, -40.0);
    });

    test('Updating transaction throws DatabaseException and is blocked',
        () async {
      // 1. Insert a sale transaction
      await transactionRepo.create(FinancialTransactionEntity(
        id: 'tx-update-1',
        type: 'sale',
        customerId: custId,
        amount: 200.0,
        paidAmount: 50.0,
        debtAmount: 150.0,
        date: DateTime.now(),
        referenceId: 'sale-update',
      ));

      // 2. Try to update and expect exception
      expect(
        () => db.rawUpdate(
          'UPDATE financial_transactions SET amount = ? WHERE id = ?',
          [220.0, 'tx-update-1'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('Deleting transaction throws DatabaseException and is blocked',
        () async {
      // 1. Insert collection of 80 TL
      await transactionRepo.create(FinancialTransactionEntity(
        id: 'tx-del-1',
        type: 'collection',
        customerId: custId,
        amount: 80.0,
        paidAmount: 80.0,
        debtAmount: 0.0,
        date: DateTime.now(),
        referenceId: 'coll-del',
      ));

      // 2. Try to delete and expect exception
      expect(
        () => db.rawDelete(
          'DELETE FROM financial_transactions WHERE id = ?',
          ['tx-del-1'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
