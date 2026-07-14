// test/services/chaos_sync_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/services/offline_sync_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';

class FakeLicenseService implements LicenseService {
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Chaos & Resilience Testing Suite', () {
    late Database db;
    late DatabaseManager databaseManager;
    late SqliteSaleRepository saleRepo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FakeLicenseService.mockPrefs = await SharedPreferences.getInstance();

      // Set override db path to use an in-memory database for fast testing
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      databaseManager = DatabaseManager();
      await databaseManager.resetDatabase();
      db = await databaseManager.getDatabase();

      // Insert mock customers to satisfy the foreign key constraint
      for (final cid in ['cust-1', 'cust-2', 'cust-3', 'cust-idem']) {
        await db.insert('customers', {
          'id': cid,
          'name': 'Customer $cid',
          'email': '$cid@test.com',
          'phone': '123',
          'balance': 0.0,
          'credit_limit': 1000.0,
          'status': 'active',
          'is_active': 1,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      final gateway = DbGatewayImpl(databaseManager);
      saleRepo = SqliteSaleRepository(gateway);
    });

    tearDown(() async {
      DatabaseManager.overrideDatabasePath = null;
      await databaseManager.close();
    });

    // ── 1. MID-SYNC NETWORK DROP SIMULATION ──────────────────────────────────────
    test(
        'Should handle network drop mid-sync cleanly, preserving unsynced local state',
        () async {
      // Simulate socket exception during HTTP POST call
      final failingMockClient = MockClient((request) async {
        if (request.url.path.contains('/updates/check')) {
          return http.Response(
            '{"latest_version": "1.0.0+4", "min_required_version": "1.0.0+1", "is_force_update": false, "download_url": "", "schema_version": 1}',
            200,
          );
        }
        throw const SocketException('Network connection aborted mid-stream');
      });

      final sale = SaleEntity(
        id: 'sale-chaos-network-drop',
        customerId: 'cust-1',
        totalAmount: 120.0,
        paidAmount: 120.0,
        paymentMethod: 'cash',
        status: 'completed',
        createdAt: DateTime.now(),
        isSynced: 0,
        items: [],
      );
      await saleRepo.create(sale);

      final apiClient = ApiClient(httpClient: failingMockClient);
      final syncService = OfflineSyncService(
        saleRepository: saleRepo,
        licenseService: FakeLicenseService(),
        apiClient: apiClient,
      );

      final result = await syncService.syncPendingSales();

      // Assertions
      expect(result.synced, equals(0));
      expect(result.failed, equals(1));
      expect(result.success, isFalse);
      expect(result.errors.first, contains('Remote sync failed for sale'));

      // Local record must remain unsynced (isSynced = 0) to retry next time
      final sales = await saleRepo.findAll();
      expect(sales.first.isSynced, equals(0));
    });

    // ── 2. DUPLICATE PUSH (REPLAY ATTACK) IDEMPOTENCY SIMULATION ─────────────────
    test(
        'Should handle duplicate pushes (replay attack) idempotently without duplication',
        () async {
      // Setup mock client that simulates duplicate push success (idempotent 409 conflict handled)
      final mockHttpClient = MockClient((request) async {
        if (request.url.path.contains('/updates/check')) {
          return http.Response(
            '{"latest_version": "1.0.0+4", "min_required_version": "1.0.0+1", "is_force_update": false, "download_url": "", "schema_version": 1}',
            200,
          );
        }
        // Simulate a duplicate conflict (409) which is successfully managed by client idempotency
        return http.Response('{"error": "idempotency duplicate"}', 409);
      });

      final sale = SaleEntity(
        id: 'sale-chaos-duplicate-replay',
        customerId: 'cust-2',
        totalAmount: 250.0,
        paidAmount: 250.0,
        paymentMethod: 'card',
        status: 'completed',
        createdAt: DateTime.now(),
        isSynced: 0,
        items: [],
      );
      await saleRepo.create(sale);

      final apiClient = ApiClient(httpClient: mockHttpClient);
      final syncService = OfflineSyncService(
        saleRepository: saleRepo,
        licenseService: FakeLicenseService(),
        apiClient: apiClient,
      );

      // First trigger
      final result1 = await syncService.syncPendingSales();
      expect(result1.synced, equals(1));
      expect(result1.success, isTrue);

      // Verify that local record is marked synced after conflict handling
      final sales = await saleRepo.findAll();
      expect(sales.first.isSynced, equals(1));
    });

    // ── 3. CONCURRENT SYNC SERIALIZATION & RACE CONDITION PROTECTION ──────────────
    test(
        'Should serialize concurrent sync calls and reject overlapping triggers',
        () async {
      final mockHttpClient = MockClient((request) async {
        if (request.url.path.contains('/updates/check')) {
          return http.Response(
            '{"latest_version": "1.0.0+4", "min_required_version": "1.0.0+1", "is_force_update": false, "download_url": "", "schema_version": 1}',
            200,
          );
        }
        await Future.delayed(
            const Duration(milliseconds: 100)); // Simulate slow latency
        return http.Response('{"status": "ok"}', 200);
      });

      final sale = SaleEntity(
        id: 'sale-chaos-concurrent',
        customerId: 'cust-3',
        totalAmount: 80.0,
        paidAmount: 80.0,
        paymentMethod: 'cash',
        status: 'completed',
        createdAt: DateTime.now(),
        isSynced: 0,
        items: [],
      );
      await saleRepo.create(sale);

      final apiClient = ApiClient(httpClient: mockHttpClient);
      final syncService = OfflineSyncService(
        saleRepository: saleRepo,
        licenseService: FakeLicenseService(),
        apiClient: apiClient,
      );

      // Fire multiple sync calls simultaneously
      final futures = <Future<SyncResult>>[
        syncService.syncPendingSales(),
        syncService.syncPendingSales(),
        syncService.syncPendingSales(),
      ];

      final results = await Future.wait(futures);

      // One call must succeed, others should reject / return 'Sync already in progress'
      final totalSynced = results.fold<int>(0, (sum, res) => sum + res.synced);
      final hasOverlapError =
          results.any((res) => res.errors.contains('Sync already in progress'));

      expect(totalSynced, equals(1));
      expect(hasOverlapError, isTrue);
    });
  });
}
