import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:path/path.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Migration Critical Error Handling Tests', () {
    late String tempDbPath;

    setUp(() async {
      DatabaseManager().reset();
      final dbPath = await databaseFactory.getDatabasesPath();
      tempDbPath = join(dbPath, 'migration_test_temp.db');
      await deleteDatabase(tempDbPath);
    });

    tearDown(() async {
      DatabaseManager().reset();
      await deleteDatabase(tempDbPath);
      DatabaseManager.overrideDatabasePath = null;
    });

    test('Rethrows critical migration errors and records failure in history', () async {
      // 1. Create a database at version 17 with duplicate users (violating v18 UNIQUE constraint)
      final db = await openDatabase(
        tempDbPath,
        version: 17,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS users (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              email TEXT NOT NULL,
              password_hash TEXT NOT NULL,
              role TEXT NOT NULL,
              is_active INTEGER NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT,
              username TEXT,
              pin_hash TEXT,
              business_code TEXT
            )
          ''');
        },
      );

      // Insert duplicate usernames
      await db.insert('users', {
        'id': 'user_1',
        'name': 'Kasiyer 1',
        'email': 'k1@shaman.com',
        'password_hash': 'pw',
        'role': 'cashier',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'username': 'mavi',
        'business_code': 'STORE_A',
      });
      await db.insert('users', {
        'id': 'user_2',
        'name': 'Kasiyer 2',
        'email': 'k2@shaman.com',
        'password_hash': 'pw',
        'role': 'cashier',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'username': 'mavi',
        'business_code': 'STORE_A',
      });

      await db.close();

      // 2. Set override path so DatabaseManager targets our duplicate-ridden DB
      DatabaseManager.overrideDatabasePath = tempDbPath;
      final dbManager = DatabaseManager();

      // 3. Attempt to open via DatabaseManager. It should upgrade to v25, hitting v18 index and throwing.
      await expectLater(
        dbManager.getDatabase(),
        throwsA(anything), // Rethrown critical constraint failure
      );
    });

    test('Throws StateError if database schema invariants fail (PRAGMA table_info / sqlite_master check)', () async {
      final db = await openDatabase(
        tempDbPath,
        version: 26,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS users (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              email TEXT NOT NULL,
              password_hash TEXT NOT NULL,
              role TEXT NOT NULL,
              is_active INTEGER NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
        },
      );
      await db.close();

      DatabaseManager.overrideDatabasePath = tempDbPath;
      final dbManager = DatabaseManager();

      expect(
        () => dbManager.getDatabase(),
        throwsA(isA<StateError>().having((e) => e.toString(), 'message', contains('Database invariant violation'))),
      );
    });
  });
}
