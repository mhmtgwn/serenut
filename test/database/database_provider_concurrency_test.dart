import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseManager Concurrency & Connection Isolation Tests', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('db_concurrency_test_');
      dbPath = '${tempDir.path}/test_db.db';
      DatabaseManager.overrideDatabasePath = dbPath;
      DatabaseManager.instance.reset();
    });

    tearDown(() async {
      await DatabaseManager.instance.close();
      DatabaseManager.overrideDatabasePath = null;
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('Concurrent getDatabase() calls resolve to the identical open instance without error', () async {
      // Dispatch 10 concurrent getDatabase calls
      final futures = List.generate(10, (_) => DatabaseManager.instance.getDatabase());
      final databases = await Future.wait(futures);

      expect(databases.length, 10);
      final firstDb = databases.first;
      expect(firstDb.isOpen, isTrue);

      for (final db in databases) {
        expect(identical(db, firstDb), isTrue);
        expect(db.isOpen, isTrue);
      }

      // Query should succeed
      final res = await firstDb.rawQuery('SELECT 1 as val');
      expect(res.first['val'], 1);
    });

    test('Temporary inspection connection with singleInstance: false does not close primary DatabaseManager instance', () async {
      final primaryDb = await DatabaseManager.instance.getDatabase();
      expect(primaryDb.isOpen, isTrue);

      // Open a second, temporary inspection connection with singleInstance: false
      final tempInspectDb = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(tempInspectDb.isOpen, isTrue);

      // Verify and close temp inspection connection
      final check = await tempInspectDb.rawQuery('PRAGMA integrity_check');
      expect(check.first.values.first, 'ok');
      await tempInspectDb.close();
      expect(tempInspectDb.isOpen, isFalse);

      // Primary connection MUST remain open and functional!
      expect(primaryDb.isOpen, isTrue);
      final settings = await primaryDb.query('settings', limit: 1);
      expect(settings, isNotNull);
    });

    test('DatabaseManager safely reconnects if database was externally closed', () async {
      final primaryDb = await DatabaseManager.instance.getDatabase();
      expect(primaryDb.isOpen, isTrue);

      // Force close the primary instance simulating external close
      await primaryDb.close();
      expect(primaryDb.isOpen, isFalse);

      // Calling getDatabase() must detect closed state and cleanly re-open
      final reconnectedDb = await DatabaseManager.instance.getDatabase();
      expect(reconnectedDb.isOpen, isTrue);
      final res = await reconnectedDb.rawQuery('SELECT 1 as val');
      expect(res.first['val'], 1);
    });
  });
}

