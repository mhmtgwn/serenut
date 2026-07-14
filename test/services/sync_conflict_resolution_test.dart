import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/data_integrity_service.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/domain/services/offline_sync_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_customer_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_payment_repository.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';

class MockLicenseService implements LicenseService {
  final String _uuid;
  MockLicenseService(this._uuid);

  static SharedPreferences? mockPrefs;

  @override
  SharedPreferences get prefs {
    if (mockPrefs == null) {
      throw StateError('mockPrefs not initialized');
    }
    return mockPrefs!;
  }

  @override
  LicenseInfo? getLicenseInfo() {
    return LicenseInfo(
      merchantId: 'MOCK_MERCHANT',
      allowedDevices: ['*'],
      expiryDate: DateTime.now().add(const Duration(days: 30)),
      tier: LicenseTier.proPlus,
      features: ['cloud_sync'],
      signature: '',
    );
  }

  @override
  String? getLicenseToken() => 'mock_token';

  @override
  bool verifyLicenseToken(String token) => true;

  @override
  String getDeviceUuid() => _uuid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 4 - Sync Conflict Resolution Tests (Lamport Clocks)', () {
    const String custId = 'conflict-customer-123';
    const String dbPathA = 'device_a_temp.db';
    const String dbPathB = 'device_b_temp.db';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      MockLicenseService.mockPrefs = await SharedPreferences.getInstance();

      await databaseFactory.deleteDatabase(dbPathA);
      await databaseFactory.deleteDatabase(dbPathB);
      await DatabaseManager().close();
    });

    tearDown(() async {
      await DatabaseManager().close();
      await databaseFactory.deleteDatabase(dbPathA);
      await databaseFactory.deleteDatabase(dbPathB);
      DatabaseManager.overrideDatabasePath = null;
    });

    test('Ensures Lamport Timestamps are logically incremented locally',
        () async {
      DatabaseManager.overrideDatabasePath = dbPathA;
      final db = await DatabaseManager().getDatabase();
      final gateway = DbGatewayImpl.raw(db);
      final customerRepo = SqliteCustomerRepository(gateway);
      final transactionRepo =
          SqliteFinancialTransactionRepository(gateway, deviceId: 'device-A');

      // Setup customer
      await customerRepo.create(CustomerEntity(
        id: custId,
        name: 'Test Customer',
        email: 'test@customer.com',
        phone: '12345',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));

      // Create first transaction on A
      await transactionRepo.create(FinancialTransactionEntity(
        id: 'tx-a-1',
        type: 'sale',
        customerId: custId,
        amount: 500.0,
        paidAmount: 0.0,
        debtAmount: 500.0,
        date: DateTime.now(),
      ));

      // Create second transaction on A
      await transactionRepo.create(FinancialTransactionEntity(
        id: 'tx-a-2',
        type: 'collection',
        customerId: custId,
        amount: 200.0,
        paidAmount: 200.0,
        debtAmount: 0.0,
        date: DateTime.now(),
      ));

      final tx1 = await transactionRepo.findById('tx-a-1');
      final tx2 = await transactionRepo.findById('tx-a-2');

      // Clocks should increment logically: 1 -> 2
      expect(tx1!.logicalClock, equals(1));
      expect(tx1.deviceId, equals('device-A'));

      expect(tx2!.logicalClock, equals(2));
      expect(tx2.deviceId, equals('device-A'));

      await DatabaseManager().close();
    });

    test('Multi-Device Deterministic Convergence & Balance Drift Prevention',
        () async {
      // ────────────────────────────────────────────────────────────────────────
      // Step 1: Device A creates a sale of 1000 TL offline
      // ────────────────────────────────────────────────────────────────────────
      DatabaseManager.overrideDatabasePath = dbPathA;
      var db = await DatabaseManager().getDatabase();
      var gateway = DbGatewayImpl.raw(db);
      var customerRepo = SqliteCustomerRepository(gateway);
      var transactionRepo =
          SqliteFinancialTransactionRepository(gateway, deviceId: 'device-A');

      await customerRepo.create(CustomerEntity(
        id: custId,
        name: 'Conflict Customer',
        email: 'conflict@test.com',
        phone: '555',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));

      await transactionRepo.create(FinancialTransactionEntity(
        id: 'tx-conflict-sale',
        type: 'sale',
        customerId: custId,
        amount: 1000.0,
        paidAmount: 0.0,
        debtAmount: 1000.0,
        date: DateTime.now(),
      ));

      final balanceBeforeA = await customerRepo.getBalance(custId);
      expect(balanceBeforeA, equals(-1000.0));

      await DatabaseManager().close();

      // ────────────────────────────────────────────────────────────────────────
      // Step 2: Device B creates a collection of 400 TL offline
      // ────────────────────────────────────────────────────────────────────────
      DatabaseManager.overrideDatabasePath = dbPathB;
      db = await DatabaseManager().getDatabase();
      gateway = DbGatewayImpl.raw(db);
      customerRepo = SqliteCustomerRepository(gateway);
      transactionRepo =
          SqliteFinancialTransactionRepository(gateway, deviceId: 'device-B');

      await customerRepo.create(CustomerEntity(
        id: custId,
        name: 'Conflict Customer',
        email: 'conflict@test.com',
        phone: '555',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));

      await transactionRepo.create(FinancialTransactionEntity(
        id: 'tx-conflict-payment',
        type: 'collection',
        customerId: custId,
        amount: 400.0,
        paidAmount: 400.0,
        debtAmount: 0.0,
        date: DateTime.now(),
      ));

      final balanceBeforeB = await customerRepo.getBalance(custId);
      expect(balanceBeforeB, equals(400.0));

      await DatabaseManager().close();

      // ────────────────────────────────────────────────────────────────────────
      // Step 3: Trigger pull/merge on Device A
      // ────────────────────────────────────────────────────────────────────────
      DatabaseManager.overrideDatabasePath = dbPathA;
      db = await DatabaseManager().getDatabase();
      gateway = DbGatewayImpl.raw(db);
      customerRepo = SqliteCustomerRepository(gateway);
      transactionRepo =
          SqliteFinancialTransactionRepository(gateway, deviceId: 'device-A');

      final mockResponseForA = {
        'status': 'ok',
        'transactions': [
          {
            'type': 'financial_transaction',
            'payload': {
              'id': 'tx-conflict-payment',
              'type': 'collection',
              'customer_id': custId,
              'amount': 400.0,
              'paid_amount': 400.0,
              'debt_amount': 0.0,
              'created_at': DateTime.now().toIso8601String(),
              'logical_clock': 1,
              'device_id': 'device-B'
            }
          }
        ]
      };

      final mockClientA = MockClient((request) async {
        if (request.url.path.contains('sync/pull')) {
          return http.Response(jsonEncode(mockResponseForA), 200);
        }
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final apiClientA = ApiClient(httpClient: mockClientA);
      final syncServiceA = OfflineSyncService(
        saleRepository: InMemorySaleRepository(),
        transactionRepository: transactionRepo,
        licenseService: MockLicenseService('device-A'),
        apiClient: apiClientA,
      );

      await syncServiceA.syncPendingSales();

      // Check balance on A has updated to -600
      final balanceAfterA = await customerRepo.getBalance(custId);
      expect(balanceAfterA, equals(-600.0));

      // Get explanations on A
      final integrityA = DataIntegrityService(
        customerRepository: customerRepo,
        transactionRepository: transactionRepo,
      );
      final explainA = await integrityA.explainCustomerBalance(custId);

      await DatabaseManager().close();

      // ────────────────────────────────────────────────────────────────────────
      // Step 4: Trigger pull/merge on Device B
      // ────────────────────────────────────────────────────────────────────────
      DatabaseManager.overrideDatabasePath = dbPathB;
      db = await DatabaseManager().getDatabase();
      gateway = DbGatewayImpl.raw(db);
      customerRepo = SqliteCustomerRepository(gateway);
      transactionRepo =
          SqliteFinancialTransactionRepository(gateway, deviceId: 'device-B');

      final mockResponseForB = {
        'status': 'ok',
        'transactions': [
          {
            'type': 'financial_transaction',
            'payload': {
              'id': 'tx-conflict-sale',
              'type': 'sale',
              'customer_id': custId,
              'amount': 1000.0,
              'paid_amount': 0.0,
              'debt_amount': 1000.0,
              'created_at': DateTime.now().toIso8601String(),
              'logical_clock': 1,
              'device_id': 'device-A'
            }
          }
        ]
      };

      final mockClientB = MockClient((request) async {
        if (request.url.path.contains('sync/pull')) {
          return http.Response(jsonEncode(mockResponseForB), 200);
        }
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final apiClientB = ApiClient(httpClient: mockClientB);
      final syncServiceB = OfflineSyncService(
        saleRepository: InMemorySaleRepository(),
        transactionRepository: transactionRepo,
        licenseService: MockLicenseService('device-B'),
        apiClient: apiClientB,
      );

      await syncServiceB.syncPendingSales();

      // Check balance on B has updated to -600
      final balanceAfterB = await customerRepo.getBalance(custId);
      expect(balanceAfterB, equals(-600.0));

      // Get explanations on B
      final integrityB = DataIntegrityService(
        customerRepository: customerRepo,
        transactionRepository: transactionRepo,
      );
      final explainB = await integrityB.explainCustomerBalance(custId);

      await DatabaseManager().close();

      // ────────────────────────────────────────────────────────────────────────
      // Step 5: Assert absolute deterministic convergence on explainable traces
      // ────────────────────────────────────────────────────────────────────────
      expect(explainA.length, equals(2));
      expect(explainB.length, equals(2));

      // Logical order must always put 'device-A' first, then 'device-B'
      expect(explainA[0].transactionId, equals('tx-conflict-sale'));
      expect(explainA[1].transactionId, equals('tx-conflict-payment'));

      expect(explainB[0].transactionId, equals('tx-conflict-sale'));
      expect(explainB[1].transactionId, equals('tx-conflict-payment'));

      // Verify intermediate running balances are identical at each step
      expect(explainA[0].runningBalance, equals(-1000.0));
      expect(explainA[1].runningBalance, equals(-600.0));

      expect(explainB[0].runningBalance, equals(-1000.0));
      expect(explainB[1].runningBalance, equals(-600.0));
    });
  });
}
