import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/backup_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => '.';

  @override
  Future<String?> getApplicationSupportPath() async => '.';

  @override
  Future<String?> getLibraryPath() async => '.';

  @override
  Future<String?> getApplicationDocumentsPath() async => Directory.current.absolute.path;

  @override
  Future<String?> getExternalStoragePath() async => '.';

  @override
  Future<List<String>?> getExternalCachePaths() async => [];

  @override
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) async => [];

  @override
  Future<String?> getDownloadsPath() async => '.';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = MockPathProviderPlatform();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('BackupService Unit Tests', () {
    late BackupService backupService;
    late String dbPath;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      backupService = BackupService();
      dbPath = join(await getDatabasesPath(), 'serenut_pos_backup_test.db');

      final file = File(dbPath);
      if (await file.exists()) await file.delete();
      final walFile = File('$dbPath-wal');
      if (await walFile.exists()) await walFile.delete();
      final shmFile = File('$dbPath-shm');
      if (await shmFile.exists()) await shmFile.delete();

      DatabaseManager.overrideDatabasePath = dbPath;
      DatabaseManager().reset();

      // Open via DatabaseManager to create clean, real database structure
      final db = await DatabaseManager().getDatabase();
      await db.update('settings', {
        'business_name': 'Test Market A.S.',
        'business_phone': '555',
        'business_address': 'address',
      });
      DatabaseManager().reset(); // Reset to close cache
    });

    tearDownAll(() async {
      DatabaseManager.overrideDatabasePath = null;
    });

    test('backupDatabase clones the database file and saves timestamp', () async {
      final backupPath = await backupService.backupDatabase();
      expect(backupPath, isNotEmpty);

      final backupFile = File(backupPath);
      expect(await backupFile.exists(), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_backup_date'), isNotNull);

      await backupFile.delete();
    });

    test('getBackupFiles retrieves backups sorted correctly', () async {
      final backupPath = await backupService.backupDatabase();
      final files = await backupService.getBackupFiles();
      expect(files, isNotEmpty);
      expect(files.first.path, equals(backupPath));

      await File(backupPath).delete();
    });

    test('restoreDatabase validates schema and successfully restores the state', () async {
      // 1. Create a backup first
      final backupPath = await backupService.backupDatabase();

      // 2. Tamper/delete the original active db
      await DatabaseManager().close();
      final dbFile = File(dbPath);
      await dbFile.delete();
      expect(await dbFile.exists(), isFalse);

      // 3. Restore from backup
      final success = await backupService.restoreDatabase(backupPath);
      expect(success, isTrue);
      expect(await dbFile.exists(), isTrue);

      // 4. Verify data integrity in restored db
      final db = await openDatabase(dbPath);
      final result = await db.query('settings');
      expect(result.first['business_name'], equals('Test Market A.S.'));
      await db.close();

      await File(backupPath).delete();
    });
  });
}
