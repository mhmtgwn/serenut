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

  group('SQLite Concurrency & Stress Tests', () {
    const String custId = 'concurrency-test-customer';

    setUp(() async {
      await db.update('ledger_bypass_flag', {'active': 1});
      await db.delete('financial_transactions');
      await db.delete('customers');
      await db.update('ledger_bypass_flag', {'active': 0});

      await customerRepo.create(CustomerEntity(
        id: custId,
        name: 'Concurrency Customer',
        email: 'concurrency@test.com',
        phone: '99999',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));
    });

    test('100 concurrent transactions on a single customer balance result in correct final balance without race conditions', () async {
      final futures = <Future<void>>[];
      double expectedBalance = 0.0;

      // We will perform 50 concurrent veresiye sales (each debt = 10 TL, balance impact = -10 TL)
      // and 50 concurrent collections (each paid = 5 TL, balance impact = +5 TL)
      for (int i = 0; i < 50; i++) {
        futures.add(
          transactionRepo.create(FinancialTransactionEntity(
            id: 'con-sale-$i',
            type: 'sale',
            customerId: custId,
            amount: 10.0,
            paidAmount: 0.0,
            debtAmount: 10.0,
            date: DateTime.now(),
            referenceId: 'sale-$i',
          )),
        );
        expectedBalance -= 10.0;

        futures.add(
          transactionRepo.create(FinancialTransactionEntity(
            id: 'con-coll-$i',
            type: 'collection',
            customerId: custId,
            amount: 5.0,
            paidAmount: 5.0,
            debtAmount: 0.0,
            date: DateTime.now(),
            referenceId: 'coll-$i',
          )),
        );
        expectedBalance += 5.0;
      }

      // Wait for all 100 concurrent transactions to execute
      await Future.wait(futures);

      // Verify that final customer balance matches exact cumulative trigger operations
      final finalBalance = await customerRepo.getBalance(custId);
      expect(finalBalance, expectedBalance);
    });
  });
}
