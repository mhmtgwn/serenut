import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' hide equals;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/services/bootstrap_sync_service.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => '.';

  @override
  Future<String?> getApplicationSupportPath() async => '.';

  @override
  Future<String?> getLibraryPath() async => '.';

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.current.absolute.path;

  @override
  Future<String?> getExternalStoragePath() async => '.';

  @override
  Future<List<String>?> getExternalCachePaths() async => [];

  @override
  Future<List<String>?> getExternalStoragePaths(
          {StorageDirectory? type}) async =>
      [];

  @override
  Future<String?> getDownloadsPath() async => '.';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = MockPathProviderPlatform();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Bootstrap Sync Hydration Integration Test', () {
    late String dbPath;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      dbPath = join(await getDatabasesPath(), 'serenut_pos_bootstrap_test.db');

      // Clean up previous test database
      final file = File(dbPath);
      if (await file.exists()) await file.delete();
      final walFile = File('$dbPath-wal');
      if (await walFile.exists()) await walFile.delete();
      final shmFile = File('$dbPath-shm');
      if (await shmFile.exists()) await shmFile.delete();

      DatabaseManager.overrideDatabasePath = dbPath;
    });

    tearDownAll(() async {
      await DatabaseManager().close();
      DatabaseManager.overrideDatabasePath = null;
      final file = File(dbPath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    });

    test(
        'runBootstrap loads company profile and hydrates settings table correctly',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final config = EnvironmentConfig.fromEnv(AppEnvironment.test);
      final apiClient = ApiClient(httpClient: http.Client(), config: config);

      // Setup mock API response interceptor
      apiClient.mockHandler = (request) {
        final path = request.url.path;
        if (path.contains('/sync/bootstrap/company')) {
          return const ApiResponse(
            statusCode: 200,
            body:
                '{"data": {"name": "Hydrated Market", "owner_name": "John Doe", "type": "market", "phone": "05553334455", "email": "info@hydrated.com", "tax_number": "999888777", "city": "Istanbul", "district": "Kadikoy", "currency": "₺"}}',
            headers: {},
          );
        } else if (path.contains('/sync/bootstrap/license-config')) {
          return const ApiResponse(
            statusCode: 200,
            body:
                '{"data": {"license_key": "TEST-KEY-123", "license_token": "TEST-TOKEN-456"}}',
            headers: {},
          );
        } else if (path.contains('/sync/bootstrap/stores') ||
            path.contains('/sync/bootstrap/users') ||
            path.contains('/sync/bootstrap/categories') ||
            path.contains('/sync/bootstrap/products') ||
            path.contains('/sync/bootstrap/customers') ||
            path.contains('/sync/bootstrap/payment-types') ||
            path.contains('/sync/bootstrap/tax-rates')) {
          return const ApiResponse(
            statusCode: 200,
            body: '{"data": []}',
            headers: {},
          );
        } else {
          return const ApiResponse(
            statusCode: 200,
            body: '{"data": {}}',
            headers: {},
          );
        }
      };

      final bootstrapService = BootstrapSyncService(prefs, apiClient);

      // Run bootstrap process
      await bootstrapService.runBootstrap((progress, statusText) {
        // print('Progress: $progress% -> $statusText');
      });

      // Verify that local database tables are correctly populated
      final db = await DatabaseManager().getDatabase();

      // Query business_profile
      final profileRows =
          await db.rawQuery('SELECT * FROM business_profile WHERE id = 1');
      expect(profileRows.length, equals(1));
      expect(profileRows.first['name'], equals('Hydrated Market'));
      expect(profileRows.first['owner_name'], equals('John Doe'));
      expect(profileRows.first['city'], equals('Istanbul'));
      expect(profileRows.first['district'], equals('Kadikoy'));

      // Query settings
      final settingsRows = await db.rawQuery('SELECT * FROM settings LIMIT 1');
      expect(settingsRows.length, equals(1));
      expect(settingsRows.first['business_name'], equals('Hydrated Market'));
      expect(settingsRows.first['business_phone'], equals('05553334455'));
      expect(settingsRows.first['owner_name'], equals('John Doe'));
      expect(settingsRows.first['business_city'], equals('Istanbul'));
      expect(settingsRows.first['business_district'], equals('Kadikoy'));

      // Verify license settings in SharedPreferences
      expect(prefs.getString('activated_license_key'), equals('TEST-KEY-123'));
      expect(prefs.getString('license_token'), equals('TEST-TOKEN-456'));

      // Verify license token in SQLite settings table
      final settingsTokenRows =
          await db.rawQuery('SELECT license_token FROM settings LIMIT 1');
      expect(
          settingsTokenRows.first['license_token'], equals('TEST-TOKEN-456'));
    });
  });
}
