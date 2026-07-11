// test/services/offline_sync_test.dart
// Serenut POS — Offline Sync Safety Tests
// Tests that unsynced sales are properly marked after sync using ApiClient.
// Created: 04 Jul 2026

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:serenutos/domain/services/offline_sync_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/config/environment.dart';

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

  group('Offline Sync Safety Tests', () {
    late DatabaseManager databaseManager;
    late Database db;
    late SqliteSaleRepository saleRepo;
    late OfflineSyncService syncService;
    late ApiClient apiClient;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FakeLicenseService.mockPrefs = await SharedPreferences.getInstance();

      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'serenut_sync_test.db');
      await deleteDatabase(path);

      databaseManager = DatabaseManager();
      DatabaseManager.overrideDatabasePath = path;
      await databaseManager.resetDatabase();
      db = await databaseManager.getDatabase();

      // Insert mock customers to satisfy the sales foreign key constraint
      await db.insert('customers', {
        'id': 'cust-1',
        'name': 'Sync Customer 1',
        'email': 'sync1@customer.com',
        'phone': '111',
        'balance': 0.0,
        'credit_limit': 1000.0,
        'status': 'active',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      await db.insert('customers', {
        'id': 'cust-2',
        'name': 'Sync Customer 2',
        'email': 'sync2@customer.com',
        'phone': '222',
        'balance': 0.0,
        'credit_limit': 1000.0,
        'status': 'active',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final gateway = DbGatewayImpl(databaseManager);
      saleRepo = SqliteSaleRepository(gateway);

      apiClient = ApiClient(config: EnvironmentConfig.fromEnv(AppEnvironment.test));
      apiClient.mockHandler = (request) {
        if (request.url.path.endsWith('/version/check')) {
          return const ApiResponse(
            statusCode: 200,
            body: '{"latestVersion": "1.0.0+1", "minRequiredVersion": "1.0.0+1", "isForceUpdate": false, "downloadUrl": "", "schemaVersion": 1}',
            headers: {},
          );
        }
        return const ApiResponse(
          statusCode: 200,
          body: '{"status":"ok", "transactions":[]}',
          headers: {},
        );
      };

      syncService = OfflineSyncService(
        saleRepository: saleRepo,
        licenseService: FakeLicenseService(),
        apiClient: apiClient,
      );

      // Clean table records
      await db.delete('sale_items');
      await db.delete('sales');
    });

    tearDown(() async {
      DatabaseManager.overrideDatabasePath = null;
      await databaseManager.close();
    });

    test('syncPendingSales should fetch unsynced sales and mark them synced in database', () async {
      // 1. Create two unsynced sales directly
      final sale1 = SaleEntity(
        id: 'sale-unsynced-1',
        customerId: 'cust-1',
        totalAmount: 100.0,
        paidAmount: 100.0,
        paymentMethod: 'cash',
        status: 'completed',
        createdAt: DateTime.now(),
        isSynced: 0,
        items: const [],
      );

      final sale2 = SaleEntity(
        id: 'sale-unsynced-2',
        customerId: 'cust-2',
        totalAmount: 200.0,
        paidAmount: 200.0,
        paymentMethod: 'card',
        status: 'completed',
        createdAt: DateTime.now(),
        isSynced: 0,
        items: const [],
      );

      await saleRepo.create(sale1);
      await saleRepo.create(sale2);

      // Verify they are unsynced in the database
      var list = await saleRepo.findAll();
      expect(list.length, equals(2));
      expect(list.every((s) => s.isSynced == 0), isTrue);

      // 2. Trigger synchronization
      final result = await syncService.syncPendingSales();

      // Assert using SyncResult
      expect(result.synced, equals(2));
      expect(result.failed, equals(0));
      expect(result.success, isTrue);

      // 3. Verify sync flag is updated to 1 (synced) in database
      list = await saleRepo.findAll();
      expect(list.length, equals(2));
      expect(list.every((s) => s.isSynced == 1), isTrue);
    });

    test('syncPendingSales should return success when no unsynced sales', () async {
      final result = await syncService.syncPendingSales();
      expect(result.synced, equals(0));
      expect(result.failed, equals(0));
      expect(result.success, isTrue);
    });

    test('syncPendingSales should mark failed when HTTP returns error', () async {
      final failingClient = ApiClient(config: EnvironmentConfig.fromEnv(AppEnvironment.test));
      failingClient.mockHandler = (request) {
        if (request.url.path.endsWith('/version/check')) {
          return const ApiResponse(
            statusCode: 200,
            body: '{"latestVersion": "1.0.0+1", "minRequiredVersion": "1.0.0+1", "isForceUpdate": false, "downloadUrl": "", "schemaVersion": 1}',
            headers: {},
          );
        }
        return const ApiResponse(
          statusCode: 500,
          body: '{"error":"server error"}',
          headers: {},
        );
      };

      final failingSync = OfflineSyncService(
        saleRepository: saleRepo,
        licenseService: FakeLicenseService(),
        apiClient: failingClient,
      );

      await saleRepo.create(SaleEntity(
        id: 'sale-fail-1',
        customerId: 'cust-1',
        totalAmount: 50.0,
        paidAmount: 50.0,
        paymentMethod: 'cash',
        status: 'completed',
        createdAt: DateTime.now(),
        isSynced: 0,
        items: const [],
      ));

      final result = await failingSync.syncPendingSales();
      expect(result.failed, equals(1));
      expect(result.synced, equals(0));
      expect(result.success, isFalse);

      // Sale should remain unsynced
      final list = await saleRepo.findAll();
      expect(list.first.isSynced, equals(0));
    });

    test('syncPendingSales handles 409 Conflict as success (idempotent)', () async {
      final conflictClient = ApiClient(config: EnvironmentConfig.fromEnv(AppEnvironment.test));
      conflictClient.mockHandler = (request) {
        if (request.url.path.endsWith('/version/check')) {
          return const ApiResponse(
            statusCode: 200,
            body: '{"latestVersion": "1.0.0+1", "minRequiredVersion": "1.0.0+1", "isForceUpdate": false, "downloadUrl": "", "schemaVersion": 1}',
            headers: {},
          );
        }
        throw ApiException('Conflict', statusCode: 409, responseBody: '{"error":"duplicate"}');
      };

      final idempotentSync = OfflineSyncService(
        saleRepository: saleRepo,
        licenseService: FakeLicenseService(),
        apiClient: conflictClient,
      );

      await saleRepo.create(SaleEntity(
        id: 'sale-conflict-1',
        customerId: 'cust-1',
        totalAmount: 75.0,
        paidAmount: 75.0,
        paymentMethod: 'cash',
        status: 'completed',
        createdAt: DateTime.now(),
        isSynced: 0,
        items: const [],
      ));

      final result = await idempotentSync.syncPendingSales();
      expect(result.synced, equals(1));
      expect(result.failed, equals(0));

      // Should be marked as synced in DB
      final list = await saleRepo.findAll();
      expect(list.first.isSynced, equals(1));
    });

    test('concurrent sync calls are serialized (no double-sync)', () async {
      final concurrentClient = ApiClient(config: EnvironmentConfig.fromEnv(AppEnvironment.test));
      concurrentClient.mockHandler = (request) {
        if (request.url.path.endsWith('/version/check')) {
          return const ApiResponse(
            statusCode: 200,
            body: '{"latestVersion": "1.0.0+1", "minRequiredVersion": "1.0.0+1", "isForceUpdate": false, "downloadUrl": "", "schemaVersion": 1}',
            headers: {},
          );
        }
        return const ApiResponse(
          statusCode: 200,
          body: '{"status":"ok", "transactions":[]}',
          headers: {},
        );
      };

      final serializedSync = OfflineSyncService(
        saleRepository: saleRepo,
        licenseService: FakeLicenseService(),
        apiClient: concurrentClient,
      );

      await saleRepo.create(SaleEntity(
        id: 'sale-concurrent-1',
        customerId: 'cust-1',
        totalAmount: 100.0,
        paidAmount: 100.0,
        paymentMethod: 'cash',
        status: 'completed',
        createdAt: DateTime.now(),
        isSynced: 0,
        items: const [],
      ));

      // Fire two concurrent syncs
      final results = await Future.wait([
        serializedSync.syncPendingSales(),
        serializedSync.syncPendingSales(),
      ]);

      // Total synced across both should be 1
      final totalSynced = results.fold<int>(0, (sum, r) => sum + r.synced);
      expect(totalSynced, equals(1));
    });
  });
}
