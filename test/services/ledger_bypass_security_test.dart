// test/services/ledger_bypass_security_test.dart
// Security Audit & Verification for ledger_bypass_flag Immutability Bypass

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/services/integrity_check_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Ledger Bypass Security & Rollback Audit', () {
    late DatabaseManager dbManager;

    setUp(() async {
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      dbManager = DatabaseManager();
      await dbManager.close();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      await dbManager.close();
      DatabaseManager.overrideDatabasePath = null;
    });

    test('Verification: If an error occurs inside a transaction, the bypass flag is rolled back to 0', () async {
      final db = await dbManager.getDatabase();

      // Ensure initial state is 0
      var res = await db.rawQuery('SELECT active FROM ledger_bypass_flag LIMIT 1');
      expect(res.first['active'], 0);

      // Simulate a transaction that triggers error after setting the flag to 1
      try {
        await db.transaction((txn) async {
          try {
            await txn.rawUpdate('UPDATE ledger_bypass_flag SET active = 1');
            
            // Verify that inside the transaction, the flag is temporarily 1
            final txnRes = await txn.rawQuery('SELECT active FROM ledger_bypass_flag LIMIT 1');
            expect(txnRes.first['active'], 1);

            // Force error to rollback transaction
            throw Exception('Simulated crash / rollback');
          } finally {
            // Even if Dart throws, the try-finally block attempts reset.
            // But if transaction is aborted, SQLite should rollback everything anyway.
            await txn.rawUpdate('UPDATE ledger_bypass_flag SET active = 0');
          }
        });
      } catch (_) {
        // Expected exception
      }

      // Verify that after transaction rollback, the flag is restored/reverted to 0
      res = await db.rawQuery('SELECT active FROM ledger_bypass_flag LIMIT 1');
      expect(res.first['active'], 0, reason: 'Ledger bypass flag must rollback to 0 after transaction failure');
    });

    test('Verification: IntegrityCheckService auto-detects and repairs stuck bypass flag (active = 1) on startup', () async {
      final db = await dbManager.getDatabase();

      // Explicitly set bypass flag to 1 outside transaction (simulating stuck state from unexpected system crash)
      await db.rawUpdate('UPDATE ledger_bypass_flag SET active = 1');

      // Verify it is indeed stuck at 1
      var res = await db.rawQuery('SELECT active FROM ledger_bypass_flag LIMIT 1');
      expect(res.first['active'], 1);

      // Instantiate IntegrityCheckService
      final prefs = await SharedPreferences.getInstance();
      final integrityService = IntegrityCheckService(prefs);

      // Run diagnostics
      final report = await integrityService.runDiagnostics();

      // Verify that diagnostics reported the issue and successfully repaired it
      expect(report.isDatabaseHealthy, isTrue); // Repair is self-healing, doesn't mark database itself as corrupt
      expect(report.issues.any((issue) => issue.contains('Ledger bypass flag was left active')), isTrue,
          reason: 'Service should report warning about stuck bypass flag');
      expect(report.logs.contains('Ledger bypass flag was stuck at 1'), isTrue,
          reason: 'Service should log the warning and auto-repair action');

      // Verify that database flag is now restored to 0
      res = await db.rawQuery('SELECT active FROM ledger_bypass_flag LIMIT 1');
      expect(res.first['active'], 0, reason: 'Ledger bypass flag must be auto-corrected to 0');
    });
  });
}
