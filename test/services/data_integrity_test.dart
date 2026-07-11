import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/services/data_integrity_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';

class MockTelemetryService implements TelemetryService {
  final List<Map<String, dynamic>> loggedAlarms = [];

  @override
  Future<void> logEvent(String eventName, [Map<String, dynamic>? properties]) async {
    if (eventName == 'silent_data_corruption_alarm') {
      loggedAlarms.add(properties ?? {});
    }
  }

  @override
  Future<void> logStructured({
    required String event,
    required LogLevel level,
    Map<String, dynamic>? metadata,
    String? correlationId,
  }) async {
    if (event == 'silent_data_corruption_alarm') {
      loggedAlarms.add(metadata ?? {});
    }
  }

  @override
  Future<void> logError(Object error, StackTrace stackTrace,
      {String? context, LogLevel level = LogLevel.error, String? correlationId}) async {}

  @override
  Future<List<TelemetryEvent>> getEvents() async => [];

  @override
  Future<void> clearLogs() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}


void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Data Integrity & Ledger Invariant Tests', () {
    late Database db;
    late DatabaseManager databaseManager;
    late SqliteCustomerRepository customerRepo;
    late SqliteFinancialTransactionRepository transactionRepo;
    late MockTelemetryService mockTelemetry;
    late DataIntegrityService integrityService;

    setUp(() async {
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      databaseManager = DatabaseManager();
      db = await databaseManager.getDatabase();

      // Clear data
      await db.update('ledger_bypass_flag', {'active': 1});
      await db.delete('financial_transactions');
      await db.delete('customers');
      await db.update('ledger_bypass_flag', {'active': 0});

      final gateway = DbGatewayImpl(databaseManager);
      customerRepo = SqliteCustomerRepository(gateway);
      transactionRepo = SqliteFinancialTransactionRepository(gateway);
      mockTelemetry = MockTelemetryService();
      integrityService = DataIntegrityService(
        customerRepository: customerRepo,
        transactionRepository: transactionRepo,
        telemetryService: mockTelemetry,
      );
    });

    tearDown(() async {
      DatabaseManager.overrideDatabasePath = null;
      await databaseManager.close();
    });

    test('Ledger Invariant check detects drift, alerts via telemetry, and rebuild corrects state', () async {
      // 1. Create a customer with a balance of 0
      final customer = CustomerEntity(
        id: 'cust-integrity-1',
        name: 'John Doe',
        email: 'john@example.com',
        phone: '123456',
        balance: 0.0,
        createdAt: DateTime.now(),
      );
      await customerRepo.create(customer);

      // 2. Perform a sale of 100 TL with 30 TL paid and 70 TL debt (triggers balance update to -70.0)
      await transactionRepo.create(FinancialTransactionEntity(
        id: 'tx-1',
        type: 'sale',
        customerId: 'cust-integrity-1',
        amount: 100.0,
        paidAmount: 30.0,
        debtAmount: 70.0,
        date: DateTime.now().subtract(const Duration(minutes: 10)),
      ));

      // 3. Perform a payment of 20 TL (triggers balance update to -50.0)
      await transactionRepo.create(FinancialTransactionEntity(
        id: 'tx-2',
        type: 'payment',
        customerId: 'cust-integrity-1',
        amount: 20.0,
        paidAmount: 20.0,
        debtAmount: 50.0,
        date: DateTime.now().subtract(const Duration(minutes: 5)),
      ));

      // Current balance should be -70 + 20 = -50 TL
      var current = await customerRepo.getBalance('cust-integrity-1');
      expect(current, equals(-50.0));

      // 4. Simulate a SILENT DATA CORRUPTION by modifying customer balance directly to -10 TL
      await db.rawUpdate(
        'UPDATE customers SET balance = ? WHERE id = ?',
        [-10.0, 'cust-integrity-1'],
      );

      // 5. Run verifyLedgerInvariant and expect it to fail & log telemetry alarm
      final isValid = await integrityService.verifyLedgerInvariant('cust-integrity-1');
      expect(isValid, isFalse);
      expect(mockTelemetry.loggedAlarms.length, equals(1));
      expect(mockTelemetry.loggedAlarms.first['drift'], equals(40.0)); // Difference between -10 and -50

      // 6. Run rebuildCustomerBalance to rebuild state from transaction logs (State Replay)
      final correctedBalance = await integrityService.rebuildCustomerBalance('cust-integrity-1');
      expect(correctedBalance, equals(-50.0));

      // 7. Verify the database now contains the corrected balance
      current = await customerRepo.getBalance('cust-integrity-1');
      expect(current, equals(-50.0));

      // 8. Invariant should now pass
      final isNowValid = await integrityService.verifyLedgerInvariant('cust-integrity-1');
      expect(isNowValid, isTrue);
    });

    test('runGlobalDriftCheck auto-corrects all corrupted customer balances', () async {
      // Create two debtor customers starting with 0 balance
      await customerRepo.create(CustomerEntity(
        id: 'cust-drift-1',
        name: 'Alice',
        email: 'alice@example.com',
        phone: '111',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));
      await transactionRepo.create(FinancialTransactionEntity(
        id: 'tx-alice-1',
        type: 'sale',
        customerId: 'cust-drift-1',
        amount: 100.0,
        paidAmount: 0.0,
        debtAmount: 100.0,
        date: DateTime.now(),
      ));

      await customerRepo.create(CustomerEntity(
        id: 'cust-drift-2',
        name: 'Bob',
        email: 'bob@example.com',
        phone: '222',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));
      await transactionRepo.create(FinancialTransactionEntity(
        id: 'tx-bob-1',
        type: 'sale',
        customerId: 'cust-drift-2',
        amount: 200.0,
        paidAmount: 0.0,
        debtAmount: 200.0,
        date: DateTime.now(),
      ));

      // Corrupt Bob's balance in database directly to -50.0 (drift)
      await db.rawUpdate('UPDATE customers SET balance = -50.0 WHERE id = "cust-drift-2"');

      // Run Global Drift Check
      final corrected = await integrityService.runGlobalDriftCheck();
      
      // Bob should be corrected, Alice should remain untouched
      expect(corrected.containsKey('cust-drift-2'), isTrue);
      expect(corrected.containsKey('cust-drift-1'), isFalse);
      expect(corrected['cust-drift-2'], equals(-200.0));

      // Verify Bob's balance is corrected in SQLite
      final bobBalance = await customerRepo.getBalance('cust-drift-2');
      expect(bobBalance, equals(-200.0));
    });
  });
}
