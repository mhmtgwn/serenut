import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:serenutos/infrastructure/database/database_provider.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Database Migration & Rollback Safety Tests', () {
    late String dbPath;
    late String backupPath;

    setUp(() async {
      final dbDir = await getDatabasesPath();
      dbPath = join(dbDir, 'serenut_migration_test.db');
      backupPath = join(dbDir, 'serenut_pos_upgrade_backup.db');

      // Ensure clean start
      final file = File(dbPath);
      if (await file.exists()) await file.delete();
      final backupFile = File(backupPath);
      if (await backupFile.exists()) await backupFile.delete();
      
      final walFile = File('$dbPath-wal');
      if (await walFile.exists()) await walFile.delete();
      final shmFile = File('$dbPath-shm');
      if (await shmFile.exists()) await shmFile.delete();
    });

    tearDown(() async {
      DatabaseManager.overrideDatabasePath = null;
      await DatabaseManager().close();
      
      final file = File(dbPath);
      if (await file.exists()) await file.delete();
      final backupFile = File(backupPath);
      if (await backupFile.exists()) await backupFile.delete();
    });

    test('Should create a pre-migration backup file before upgrading schema', () async {
      // 1. Create a version 3 mock database
      final db = await openDatabase(dbPath, version: 3, onCreate: (db, version) async {
        await db.execute('CREATE TABLE settings (id INTEGER PRIMARY KEY, business_name TEXT)');
        await db.execute('CREATE TABLE sales (id TEXT PRIMARY KEY, created_at TEXT)');
        await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY)');
        await db.execute('CREATE TABLE financial_transactions (id TEXT PRIMARY KEY, created_at TEXT)');
        await db.execute('CREATE TABLE sale_items (id TEXT PRIMARY KEY, sale_id TEXT)');
        await db.insert('settings', {'business_name': 'Test Store V3'});
      });
      await db.close();

      // 2. Set database provider override path
      DatabaseManager.overrideDatabasePath = dbPath;

      // 3. Trigger upgrade using DatabaseManager (upgrades to version 5)
      final upgradedDb = await DatabaseManager().getDatabase();
      
      // Check that tables were upgraded and the pre-migration backup was created
      final tables = await upgradedDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tables.map((t) => t['name'] as String).toList();
      expect(tableNames.contains('settings'), isTrue);

      final backupFile = File(backupPath);
      expect(await backupFile.exists(), isTrue);

      // Verify the backup file itself still contains the V3 version schema
      final backupDb = await openDatabase(backupPath, readOnly: true);
      expect(await backupDb.getVersion(), equals(3));
      await backupDb.close();

      await upgradedDb.close();
    });
  });
}
