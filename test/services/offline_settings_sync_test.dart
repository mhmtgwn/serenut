import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/services/bootstrap_sync_service.dart';
import 'package:path/path.dart';
import 'package:http/http.dart' as http;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Offline Settings Sync Tests', () {
    late DatabaseManager dbManager;
    late Database db;
    late ApiClient apiClient;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      
      final dbPath = await databaseFactory.getDatabasesPath();
      final path = join(dbPath, 'serenut_pos.db');
      await deleteDatabase(path);

      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      dbManager = DatabaseManager();
      db = await dbManager.getDatabase();

      await db.delete('settings');
      apiClient = ApiClient();
    });

    tearDown(() async {
      await dbManager.close();
      DatabaseManager.overrideDatabasePath = null;
    });

    test('Retries pending company settings patch at the start of bootstrap sync', () async {
      // 1. Insert settings in database
      await db.insert('settings', {
        'business_name': 'Offline Market',
        'business_phone': '999-999-9999',
        'business_address': 'Offline Adres',
        'currency': '₺',
        'owner_name': 'Owner Name',
        'business_type': 'Market',
        'business_city': 'Istanbul',
        'business_district': 'Kadikoy',
        'created_at': DateTime.now().toIso8601String(),
      });

      // Mark patch as pending in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('serenut_pending_company_patch', true);

      // Verify that sync completion state is marked as true on success
      bool patchReceived = false;
      apiClient.mockHandler = (request) {
        if (request.url.path.contains('/api/v1/company') && request.method == 'PATCH') {
          patchReceived = true;
          final body = (request as http.Request).body;
          expect(body.contains('Offline Market'), true);
          expect(body.contains('Owner Name'), true);
          return ApiResponse(statusCode: 200, body: '{"success": true}', headers: const {});
        }
        // Return dummy response for bootstrap modules
        if (request.url.path.contains('/sync/bootstrap/company') ||
            request.url.path.contains('/sync/bootstrap/settings') ||
            request.url.path.contains('/sync/bootstrap/printer-config') ||
            request.url.path.contains('/sync/bootstrap/license-config')) {
          return ApiResponse(statusCode: 200, body: '{"data": {}}', headers: const {});
        }
        return ApiResponse(statusCode: 200, body: '{"data": []}', headers: const {});
      };

      final syncService = BootstrapSyncService(prefs, apiClient);
      
      // Complete settings module directly to finish run
      await prefs.setInt('nutopiano_bootstrap_index', 10); // End of list
      await prefs.setBool('nutopiano_bootstrap_completed', false);

      await syncService.runBootstrap((progress, status) {});

      expect(patchReceived, true);
      expect(prefs.getBool('serenut_pending_company_patch'), false);
    });

    test('Sends expected_version and updates local version in business_profile on successful sync settings PATCH', () async {
      // 1. Seed settings and business_profile
      await db.insert('settings', {
        'business_name': 'Updated Market name',
        'business_phone': '999-999-9999',
        'business_address': 'Offline Adres',
        'currency': '₺',
        'owner_name': 'Owner Name',
        'business_type': 'Market',
        'business_city': 'Istanbul',
        'business_district': 'Kadikoy',
        'created_at': DateTime.now().toIso8601String(),
      });

      await db.insert('business_profile', {
        'id': 1,
        'name': 'Old Name',
        'owner_name': 'Owner Name',
        'type': 'Market',
        'phone': '999-999-9999',
        'email': '',
        'tax_number': '',
        'city': 'Istanbul',
        'district': 'Kadikoy',
        'currency': '₺',
        'version': 5, // expected_version should be 5
        'created_at': DateTime.now().toIso8601String(),
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('serenut_pending_company_patch', true);

      bool patchReceived = false;
      apiClient.mockHandler = (request) {
        if (request.url.path.contains('/api/v1/company') && request.method == 'PATCH') {
          patchReceived = true;
          final body = (request as http.Request).body;
          expect(body.contains('"expected_version":5'), true);
          return ApiResponse(
            statusCode: 200,
            body: '{"id": 1, "name": "Updated Market name", "owner_name": "Owner Name", "version": 6}',
            headers: const {},
          );
        }
        if (request.url.path.contains('/sync/bootstrap/company') ||
            request.url.path.contains('/sync/bootstrap/settings') ||
            request.url.path.contains('/sync/bootstrap/printer-config') ||
            request.url.path.contains('/sync/bootstrap/license-config')) {
          return ApiResponse(statusCode: 200, body: '{"data": {}}', headers: const {});
        }
        return ApiResponse(statusCode: 200, body: '{"data": []}', headers: const {});
      };

      final syncService = BootstrapSyncService(prefs, apiClient);
      await prefs.setInt('nutopiano_bootstrap_index', 10);
      await prefs.setBool('nutopiano_bootstrap_completed', false);

      await syncService.runBootstrap((progress, status) {});

      expect(patchReceived, true);
      expect(prefs.getBool('serenut_pending_company_patch'), false);

      // Verify that local version is updated to 6 in business_profile table
      final rows = await db.query('business_profile', where: 'id = ?', whereArgs: [1]);
      expect(rows.first['version'], 6);
      expect(rows.first['name'], 'Updated Market name');
    });

    test('Stops retrying and logs when version conflict (409 Conflict) is returned from server', () async {
      await db.insert('settings', {
        'business_name': 'Conflicted Market',
        'business_phone': '999-999-9999',
        'business_address': 'Offline Adres',
        'currency': '₺',
        'owner_name': 'Owner Name',
        'business_type': 'Market',
        'business_city': 'Istanbul',
        'business_district': 'Kadikoy',
        'created_at': DateTime.now().toIso8601String(),
      });

      await db.insert('business_profile', {
        'id': 1,
        'name': 'Old Name',
        'owner_name': 'Owner Name',
        'type': 'Market',
        'phone': '999-999-9999',
        'email': '',
        'tax_number': '',
        'city': 'Istanbul',
        'district': 'Kadikoy',
        'currency': '₺',
        'version': 5,
        'created_at': DateTime.now().toIso8601String(),
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('serenut_pending_company_patch', true);

      apiClient.mockHandler = (request) {
        if (request.url.path.contains('/api/v1/company') && request.method == 'PATCH') {
          return ApiResponse(
            statusCode: 409,
            body: '{"error": {"code": "CONFLICT", "message": "Version mismatch"}}',
            headers: const {},
          );
        }
        if (request.url.path.contains('/sync/bootstrap/company') ||
            request.url.path.contains('/sync/bootstrap/settings') ||
            request.url.path.contains('/sync/bootstrap/printer-config') ||
            request.url.path.contains('/sync/bootstrap/license-config')) {
          return ApiResponse(statusCode: 200, body: '{"data": {}}', headers: const {});
        }
        return ApiResponse(statusCode: 200, body: '{"data": []}', headers: const {});
      };

      final syncService = BootstrapSyncService(prefs, apiClient);
      await prefs.setInt('nutopiano_bootstrap_index', 10);
      await prefs.setBool('nutopiano_bootstrap_completed', false);

      await syncService.runBootstrap((progress, status) {});

      // It should clear the pending patch to avoid endless retry loop on client side
      expect(prefs.getBool('serenut_pending_company_patch'), false);

      // Verify that local version remains unchanged (still 5)
      final rows = await db.query('business_profile', where: 'id = ?', whereArgs: [1]);
      expect(rows.first['version'], 5);
    });
  });
}
