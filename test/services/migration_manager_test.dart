// test/services/migration_manager_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/migration_manager.dart';
import 'package:serenutos/infrastructure/services/backup_service.dart';

class MockBackupService implements BackupService {
  bool backupCalled = false;
  String? returnPath;

  @override
  Future<String> backupDatabase() async {
    backupCalled = true;
    return returnPath ?? 'dummy_backup_path';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  databaseFactory = databaseFactoryFfi;
  group('MigrationManager Tests', () {
    late DatabaseManager dbManager;
    late MockBackupService backupService;
    late MigrationManager migrationManager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dbManager = DatabaseManager();
      // Use in-memory SQLite database path for unit testing isolation
      DatabaseManager.overrideDatabasePath = ':memory:';
      backupService = MockBackupService();
      migrationManager = MigrationManager(
        dbManager: dbManager,
        backupService: backupService,
      );
    });



    test('Registers steps and executes successful migrations', () async {
      migrationManager.registerStep(const MigrationStep(
        version: 1,
        sqlStatements: [
          'CREATE TABLE test_table (id TEXT PRIMARY KEY, value TEXT)',
          'INSERT INTO test_table (id, value) VALUES ("1", "hello")'
        ],
      ));

      await migrationManager.runMigrations();

      final db = await dbManager.getDatabase();
      final List<Map<String, dynamic>> res = await db.rawQuery('SELECT * FROM test_table');
      expect(res.length, 1);
      expect(res.first['value'], 'hello');

      // Verify log history
      final currentVer = await migrationManager.getCurrentAppliedVersion(db);
      expect(currentVer, 1);
    });

    test('Rolls back transaction when a migration step fails', () async {
      migrationManager.registerStep(const MigrationStep(
        version: 1,
        sqlStatements: [
          'CREATE TABLE test_table_failed (id TEXT PRIMARY KEY)',
        ],
      ));

      // Step 2 has an invalid syntax to force a database exception
      migrationManager.registerStep(const MigrationStep(
        version: 2,
        sqlStatements: [
          'INVALID SQL SYNTAX HERE THAT WILL FAIL',
        ],
      ));

      expect(() => migrationManager.runMigrations(), throwsA(anything));

      final db = await dbManager.getDatabase();
      
      // Verify version stays at 1 due to step 2 failure
      final currentVer = await migrationManager.getCurrentAppliedVersion(db);
      expect(currentVer, 1);
    });
  });
}
