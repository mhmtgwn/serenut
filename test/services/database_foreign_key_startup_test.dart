import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/schema/db_schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String databasePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('serenut-fk-startup-');
    databasePath = p.join(tempDir.path, 'serenut_pos.db');
    DatabaseManager().reset();
    DatabaseManager.overrideDatabasePath = databasePath;

    final seedDb = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 38,
        onCreate: (db, _) => DatabaseSchema.createTables(db),
      ),
    );
    await seedDb.insert('sales', {
      'id': 'legacy-sale',
      'customer_id': 'missing-synced-customer',
      'total_amount': 10.0,
      'paid_amount': 10.0,
      'created_at': DateTime.utc(2026, 7, 29).toIso8601String(),
      'updated_at': DateTime.utc(2026, 7, 29).toIso8601String(),
    });
    await seedDb.close();
  });

  tearDown(() async {
    await DatabaseManager().close();
    DatabaseManager().reset();
    DatabaseManager.overrideDatabasePath = null;
    await tempDir.delete(recursive: true);
  });

  test('legacy foreign-key anomaly does not block database startup', () async {
    final db = await DatabaseManager().getDatabase();

    final violations = await db.rawQuery('PRAGMA foreign_key_check');
    expect(violations, isNotEmpty);
    expect(
      await db.query('customers', where: 'id = ?', whereArgs: ['']),
      isNotEmpty,
    );
  });
}
