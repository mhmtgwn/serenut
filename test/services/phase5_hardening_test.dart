import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/domain/services/offline_sync_service.dart';
import 'package:serenutos/domain/services/sync_chaos_injector.dart';
import 'package:serenutos/domain/services/observability_service.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_customer_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_payment_repository.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';

class MockLicenseService implements LicenseService {
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
  String getDeviceUuid() => 'device-test-123';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 5 - Final Hardening Tests', () {
    const String custId = 'hardening-customer';
    const String dbPath = 'hardening_test.db';
    late Database db;
    late SqliteCustomerRepository customerRepo;
    late SqliteFinancialTransactionRepository transactionRepo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      MockLicenseService.mockPrefs = await SharedPreferences.getInstance();

      await databaseFactory.deleteDatabase(dbPath);
      await DatabaseManager().close();
      DatabaseManager.overrideDatabasePath = dbPath;
      db = await DatabaseManager().getDatabase();

      final gateway = DbGatewayImpl.raw(db);
      customerRepo = SqliteCustomerRepository(gateway);
      transactionRepo = SqliteFinancialTransactionRepository(gateway,
          deviceId: 'device-test-123');

      await customerRepo.create(CustomerEntity(
        id: custId,
        name: 'Hardening Customer',
        email: 'hardening@test.com',
        phone: '12345',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));

      await TelemetryService().clearLogs();
    });

    tearDown(() async {
      await DatabaseManager().close();
      await databaseFactory.deleteDatabase(dbPath);
      DatabaseManager.overrideDatabasePath = null;
      await TelemetryService().clearLogs();
    });

    test('Drift Rate Inversion Calculation Correctness', () {
      final obs = ObservabilityService(transactionRepository: transactionRepo);

      // Normal non-inverted transaction list (chronological matching logical clock)
      final txsNormal = [
        FinancialTransactionEntity(
            id: '1',
            type: 'sale',
            customerId: custId,
            amount: 100,
            paidAmount: 0,
            debtAmount: 100,
            date: DateTime.now().subtract(const Duration(hours: 3)),
            logicalClock: 1),
        FinancialTransactionEntity(
            id: '2',
            type: 'sale',
            customerId: custId,
            amount: 100,
            paidAmount: 0,
            debtAmount: 100,
            date: DateTime.now().subtract(const Duration(hours: 2)),
            logicalClock: 2),
        FinancialTransactionEntity(
            id: '3',
            type: 'sale',
            customerId: custId,
            amount: 100,
            paidAmount: 0,
            debtAmount: 100,
            date: DateTime.now().subtract(const Duration(hours: 1)),
            logicalClock: 3),
      ];

      expect(obs.calculateDriftRate(txsNormal), equals(0.0));

      // Inverted transaction list (Clock Skew Inversion)
      // Transaction chronologically later (date 1hr ago) has lower clock than transaction earlier (2hr ago)
      final txsInverted = [
        FinancialTransactionEntity(
            id: '1',
            type: 'sale',
            customerId: custId,
            amount: 100,
            paidAmount: 0,
            debtAmount: 100,
            date: DateTime.now().subtract(const Duration(hours: 3)),
            logicalClock: 1),
        FinancialTransactionEntity(
            id: '2',
            type: 'sale',
            customerId: custId,
            amount: 100,
            paidAmount: 0,
            debtAmount: 100,
            date: DateTime.now().subtract(const Duration(hours: 2)),
            logicalClock: 3 // Skewed high
            ),
        FinancialTransactionEntity(
            id: '3',
            type: 'sale',
            customerId: custId,
            amount: 100,
            paidAmount: 0,
            debtAmount: 100,
            date: DateTime.now().subtract(const Duration(hours: 1)),
            logicalClock: 2 // Out of logical order!
            ),
      ];

      // Total pairs: (1, 2) clocks (1, 3) - OK
      //              (1, 3) clocks (1, 2) - OK
      //              (2, 3) clocks (3, 2) - Inverted! (3 > 2)
      // Expected drift rate: 1 inversion / 3 total pairs = 0.3333333333333333
      expect(obs.calculateDriftRate(txsInverted), closeTo(0.333, 0.01));
    });

    test(
        'Clock Spoof Resistance: Rejects anomalous remote updates and logs anomalies',
        () async {
      // 1. Setup local base clock (max local clock is 1)
      await transactionRepo.create(FinancialTransactionEntity(
        id: 'tx-local-base',
        type: 'sale',
        customerId: custId,
        amount: 100.0,
        paidAmount: 0.0,
        debtAmount: 100.0,
        date: DateTime.now(),
      ));

      // 2. Setup mock server pull response containing:
      // - One normal transaction
      // - One future clock spoof transaction (+2 days in the future)
      // - One logically inflated spoof transaction (clock = 500,000)
      final mockPullResponse = {
        'status': 'ok',
        'transactions': [
          {
            'type': 'financial_transaction',
            'payload': {
              'id': 'tx-remote-normal',
              'type': 'collection',
              'customer_id': custId,
              'amount': 50.0,
              'paid_amount': 50.0,
              'debt_amount': 0.0,
              'created_at': DateTime.now().toIso8601String(),
              'logical_clock': 2,
              'device_id': 'device-B'
            }
          },
          {
            'type': 'financial_transaction',
            'payload': {
              'id': 'tx-remote-future-spoof',
              'type': 'collection',
              'customer_id': custId,
              'amount': 50.0,
              'paid_amount': 50.0,
              'debt_amount': 0.0,
              'created_at':
                  DateTime.now().add(const Duration(days: 3)).toIso8601String(),
              'logical_clock': 3,
              'device_id': 'device-B'
            }
          },
          {
            'type': 'financial_transaction',
            'payload': {
              'id': 'tx-remote-logical-spoof',
              'type': 'collection',
              'customer_id': custId,
              'amount': 50.0,
              'paid_amount': 50.0,
              'debt_amount': 0.0,
              'created_at': DateTime.now().toIso8601String(),
              'logical_clock': 999999, // Extreme inflation!
              'device_id': 'device-B'
            }
          }
        ]
      };

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('sync/pull')) {
          return http.Response(jsonEncode(mockPullResponse), 200);
        }
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final apiClient = ApiClient(httpClient: mockClient);
      final syncService = OfflineSyncService(
        saleRepository: InMemorySaleRepository(),
        transactionRepository: transactionRepo,
        licenseService: MockLicenseService(),
        apiClient: apiClient,
      );

      // Trigger pull sync
      final result = await syncService.syncPendingSales();
      expect(result.errors.length, equals(2));
      expect(result.errors[0], contains('Security anomaly'));

      // Check database to ensure ONLY the normal remote transaction was inserted
      final list = await transactionRepo.getByCustomerId(custId);
      // Expected: tx-local-base and tx-remote-normal. Rejects the other two.
      expect(list.length, equals(2));
      expect(list.any((t) => t.id == 'tx-remote-normal'), isTrue);
      expect(list.any((t) => t.id == 'tx-remote-future-spoof'), isFalse);
      expect(list.any((t) => t.id == 'tx-remote-logical-spoof'), isFalse);

      // Verify TelemetryService recorded the anomaly
      final obs = ObservabilityService(transactionRepository: transactionRepo);
      final metrics = await obs.getSystemHealthMetrics();
      expect(metrics['anomaly_count'], equals(2));
    });

    test(
        'Disk Full Chaos Resilience: Aborts gracefully, registers failure and leaves database in consistent state',
        () async {
      // Create local sale and try to push/commit under DiskFullFault simulation
      final sale = SaleEntity(
        id: 'sale-unsynced-chaos',
        customerId: custId,
        totalAmount: 300.0,
        paidAmount: 300.0,
        paymentMethod: 'cash',
        status: 'completed',
        createdAt: DateTime.now(),
        isSynced: 0,
        items: [],
      );

      final saleRepo = SqliteSaleRepository(DbGatewayImpl.raw(db));
      await saleRepo.create(sale);

      final injector = SyncChaosInjector().addFault(const DiskFullFault());

      final mockClient = MockClient((request) async {
        return http.Response('{"status":"ok"}', 200);
      });

      final apiClient = ApiClient(httpClient: mockClient);
      final syncService = OfflineSyncService(
        saleRepository: saleRepo,
        transactionRepository: transactionRepo,
        licenseService: MockLicenseService(),
        apiClient: apiClient,
        chaosInjector: injector,
      );

      // Sync must throw the simulated DiskFullDatabaseException
      expect(
        () => syncService.syncPendingSales(),
        throwsA(isA<DiskFullDatabaseException>()),
      );

      // Verify that local sale remains UNSYNCED (rollback verified!)
      final updatedSale = await saleRepo.findById('sale-unsynced-chaos');
      expect(updatedSale!.isSynced, equals(0));
    });
  });
}
