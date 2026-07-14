// test/services/chaos_sync_advanced_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
  LicenseInfo? getLicenseInfo() => LicenseInfo(
        merchantId: 'MOCK_MERCHANT',
        allowedDevices: ['*'],
        expiryDate: DateTime.now().add(const Duration(days: 30)),
        tier: LicenseTier.proPlus,
        features: ['cloud_sync'],
        signature: '',
      );
  @override
  String? getLicenseToken() => 'mock_token';
  @override
  bool verifyLicenseToken(String token) => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Standard version check response stub used across all mock clients.
const _versionCheckPath = '/updates/check';
const _versionOkBody =
    '{"latest_version":"1.0.0+4","min_required_version":"1.0.0+1","is_force_update":false,"download_url":"","schema_version":1}';

http.Response _versionOkResponse() => http.Response(_versionOkBody, 200);

SaleEntity _makeSale(String id,
        {String customerId = 'cust-1', double amount = 100.0}) =>
    SaleEntity(
      id: id,
      customerId: customerId,
      totalAmount: amount,
      paidAmount: amount,
      paymentMethod: 'cash',
      status: 'completed',
      createdAt: DateTime.now(),
      isSynced: 0,
      items: [],
    );

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Chaos Engineering 2.0 — Advanced Race Conditions', () {
    late Database db;
    late DatabaseManager databaseManager;
    late SqliteSaleRepository saleRepo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FakeLicenseService.mockPrefs = await SharedPreferences.getInstance();

      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      databaseManager = DatabaseManager();
      await databaseManager.resetDatabase();
      db = await databaseManager.getDatabase();

      // Insert mock customers to satisfy the foreign key constraint
      for (final cid in ['cust-1', 'cust-idem']) {
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

    // ── 5. MULTI-DEVICE RACE CONDITION ────────────────────────────────────────
    test('5 concurrent devices: only one sync wins, no double-push', () async {
      await saleRepo.create(_makeSale('sale-race-multi'));

      final slowMock = MockClient((req) async {
        if (req.url.path.contains(_versionCheckPath))
          return _versionOkResponse();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return http.Response('{"status":"ok"}', 200);
      });

      final apiClient = ApiClient(httpClient: slowMock);
      final service = OfflineSyncService(
        saleRepository: saleRepo,
        licenseService: FakeLicenseService(),
        apiClient: apiClient,
      );

      final results = await Future.wait<SyncResult>([
        for (var i = 0; i < 5; i++) service.syncPendingSales(),
      ]);

      final totalSynced = results.fold<int>(0, (s, r) => s + r.synced);
      final overlapRejections = results
          .where((r) => r.errors.contains('Sync already in progress'))
          .length;

      expect(totalSynced, equals(1),
          reason: 'Exactly one device wins the sync mutex');
      expect(overlapRejections, equals(4),
          reason: 'Remaining 4 devices are rejected immediately');

      final synced = (await saleRepo.findAll()).where((s) => s.isSynced == 1);
      expect(synced.length, equals(1));
    });

    // ── 6. DELAYED SYNC INJECTION ─────────────────────────────────────────────
    test('Delayed sync injection: second call deferred, third finds nothing',
        () async {
      await saleRepo.create(_makeSale('sale-delayed'));

      final slowMock = MockClient((req) async {
        if (req.url.path.contains(_versionCheckPath))
          return _versionOkResponse();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response('{"status":"ok"}', 200);
      });

      final apiClient1 = ApiClient(httpClient: slowMock);
      final service = OfflineSyncService(
        saleRepository: saleRepo,
        licenseService: FakeLicenseService(),
        apiClient: apiClient1,
      );

      final first = service.syncPendingSales();
      final second = service.syncPendingSales();

      final r1 = await first;
      final r2 = await second;

      expect(r1.synced, equals(1), reason: 'First sync succeeds');
      expect(r2.errors.contains('Sync already in progress'), isTrue,
          reason: 'Second is rejected while first is in-flight');

      final fastMock = MockClient((req) async {
        if (req.url.path.contains(_versionCheckPath))
          return _versionOkResponse();
        return http.Response('{"status":"ok"}', 200);
      });
      final apiClient2 = ApiClient(httpClient: fastMock);
      final service2 = OfflineSyncService(
        saleRepository: saleRepo,
        licenseService: FakeLicenseService(),
        apiClient: apiClient2,
      );
      final r3 = await service2.syncPendingSales();
      expect(r3.synced, equals(0), reason: 'Nothing left to sync');
    });

    // ── 7. PARTIAL PUSH RETRY (3-sale batch, 1 fails mid-batch) ──────────────
    test('Partial push retry: two of three succeed, failed one stays unsynced',
        () async {
      await saleRepo.create(_makeSale('sale-p1'));
      await saleRepo.create(_makeSale('sale-p2'));
      await saleRepo.create(_makeSale('sale-p3'));

      final partialMock = MockClient((req) async {
        if (req.url.path.contains(_versionCheckPath))
          return _versionOkResponse();
        if (req.body.contains('sale-p2')) {
          throw const SocketException('Simulated mid-batch network failure');
        }
        return http.Response('{"status":"ok"}', 200);
      });

      final apiClient = ApiClient(httpClient: partialMock);
      final service = OfflineSyncService(
        saleRepository: saleRepo,
        licenseService: FakeLicenseService(),
        apiClient: apiClient,
      );

      final result = await service.syncPendingSales();

      expect(result.synced, equals(2));
      expect(result.failed, equals(1));

      final all = await saleRepo.findAll();
      final syncedCount = all.where((s) => s.isSynced == 1).length;
      final unsyncedCount = all.where((s) => s.isSynced == 0).length;
      expect(syncedCount, equals(2));
      expect(unsyncedCount, equals(1));
    });

    // ── 8. IDEMPOTENCY KEY UNIQUENESS UNDER HIGH-FREQUENCY CREATION ───────────
    test('100 rapid sales all get unique idempotency keys', () async {
      const count = 100;

      for (var i = 0; i < count; i++) {
        final sale = SaleEntity(
          id: 'sale-idem-$i',
          customerId: 'cust-idem',
          totalAmount: (i + 1).toDouble(),
          paidAmount: (i + 1).toDouble(),
          paymentMethod: 'cash',
          status: 'completed',
          createdAt: DateTime.now(),
          isSynced: 0,
          idempotencyKey: 'idem-$i',
          items: [],
        );
        await saleRepo.create(sale);
      }

      final all = await saleRepo.findAll();
      final keys = all.map((s) => s.idempotencyKey).toSet();
      expect(keys.length, equals(count));
    });
  });
}
