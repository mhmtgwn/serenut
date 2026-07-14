import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/services/bootstrap_sync_service.dart';
import 'package:path/path.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('BootstrapSyncService Local Fields Protection Tests', () {
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

      await db.delete('users');

      apiClient = ApiClient();
    });

    tearDown(() async {
      await dbManager.close();
      DatabaseManager.overrideDatabasePath = null;
    });

    test('Preserves local-only user fields and updates role/name during bootstrap sync', () async {
      // 1. Insert existing user with offline PIN, lockout data, and business code
      await db.insert('users', {
        'id': 'user-123',
        'name': 'Old Name',
        'email': 'old@email.com',
        'password_hash': 'old_pw_hash',
        'role': 'cashier',
        'is_active': 1,
        'created_at': '2026-07-12T10:00:00Z',
        'updated_at': '2026-07-12T10:00:00Z',
        'pin_hash': 'my_secure_pin_hash',
        'failed_pin_attempts': 3,
        'locked_until': '2026-07-12T22:00:00Z',
        'business_code': 'COMPANY_A',
        'device_token_version': 5,
        'username': 'kasiyer1',
      });

      apiClient.mockHandler = (request) {
        final path = request.url.path;
        if (path.contains('/sync/bootstrap/users')) {
          return const ApiResponse(
            statusCode: 200,
            body: '{"data": [{"id": "user-123", "name": "New Name", "email": "new@email.com", "password_hash": "new_pw_hash", "role": "manager", "is_active": true}]}',
            headers: {},
          );
        }
        if (path.contains('/sync/bootstrap/company') ||
            path.contains('/sync/bootstrap/settings') ||
            path.contains('/sync/bootstrap/printer-config') ||
            path.contains('/sync/bootstrap/license-config')) {
          return const ApiResponse(
            statusCode: 200,
            body: '{"data": {}}',
            headers: {},
          );
        }
        return const ApiResponse(statusCode: 200, body: '{"data": []}', headers: {});
      };

      final prefs = await SharedPreferences.getInstance();
      final syncService = BootstrapSyncService(prefs, apiClient);

      // Run bootstrap sync just for the users module (the index starts at 0, users is index 2)
      await prefs.setInt('nutopiano_bootstrap_index', 2); // Start at users
      
      // Let's modify the index completion key to false to allow running
      await prefs.setBool('nutopiano_bootstrap_completed', false);

      await syncService.runBootstrap((progress, text) {});

      // 2. Query the updated user and check values
      final userRows = await db.query('users', where: 'id = ?', whereArgs: ['user-123']);
      expect(userRows.length, 1);
      final row = userRows.first;

      // Server values must be updated
      expect(row['name'], 'New Name');
      expect(row['email'], 'new@email.com');
      expect(row['password_hash'], 'new_pw_hash');
      expect(row['role'], 'manager');
      expect(row['is_active'], 1);

      // Local-only values MUST remain unchanged!
      expect(row['pin_hash'], 'my_secure_pin_hash');
      expect(row['failed_pin_attempts'], 3);
      expect(row['locked_until'], '2026-07-12T22:00:00Z');
      expect(row['business_code'], 'COMPANY_A');
      expect(row['device_token_version'], 5);
      expect(row['username'], 'kasiyer1');
    });
  });
}
