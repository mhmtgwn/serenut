import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/services/native_printer_bridge.dart';
import 'package:serenutos/infrastructure/services/financial_integrity_service.dart';
import 'package:serenutos/infrastructure/services/persistent_print_queue.dart';
import 'package:serenutos/domain/services/license_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Sprint 3: Hardware, Storage, and License Verification', () {
    late DatabaseManager dbManager;
    late SharedPreferences prefs;

    setUp(() async {
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      dbManager = DatabaseManager();
      await dbManager.close(); // Reset/initialize in-memory database
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    tearDown(() async {
      await dbManager.close();
      DatabaseManager.overrideDatabasePath = null;
    });

    // ── 1. Kritik B: Windows Spooler FFI robustness test ────────────────────
    test('Kritik B: Windows USB printing FFI handles invalid printer names without crash', () async {
      // Calling printUsbRaw with an invalid/non-existent printer should catch error and return false
      // instead of crashing the Dart VM.
      final result = await NativePrinterBridge.printUsbRaw('Invalid_Printer_XYZ_999', [0x1B, 0x40, 0x0A]);
      expect(result, isFalse);
    });

    // ── 2. Kritik H: License Clock Tampering Protection test ──────────────────
    test('Kritik H: SQLite operational logs protect against clock manipulation', () async {
      final db = await dbManager.getDatabase();
      
      // Initially, when DB is empty, license service should initialize as not tampered
      final licenseService = LicenseService(prefs);
      await licenseService.initialize();
      expect(licenseService.checkLicenseStatus(), isNot(equals('tampered')));

      // Seed a sale with a future timestamp (simulating that the system clock has been set back)
      final futureDate = DateTime.now().add(const Duration(days: 10));
      await db.insert('sales', {
        'id': 'sale-test-999',
        'customer_id': '',
        'total_amount': 250.0,
        'paid_amount': 250.0,
        'status': 'completed',
        'created_at': futureDate.toIso8601String(),
        'updated_at': futureDate.toIso8601String(),
        'is_synced': 1,
      });

      // Clear the max_timestamp_seen from SharedPreferences to simulate the user clearing prefs
      await prefs.clear();

      // Re-initialize LicenseService
      final licenseServiceTampered = LicenseService(prefs);
      await licenseServiceTampered.initialize();

      // Because the SQLite database contains a sale with a timestamp in the future,
      // the initialization must detect that the clock is tampered!
      expect(licenseServiceTampered.checkLicenseStatus(), equals('tampered'));
    });

    // ── 3. Yüksek B: SharedPreferences Concurrency stress test ───────────────
    test('Yuksek B: Concurrency lock prevents lost writes in SharedPreferences lists', () async {
      final auditLogger = AuditLogger(dbManager);
      final operationQueue = OperationQueueService(prefs);

      // Perform 50 concurrent writes using Future.wait
      final tasks = List.generate(50, (index) {
        return Future.wait([
          auditLogger.logAction(
            action: 'action_$index',
            beforeState: 'state_before',
            afterState: 'state_after',
            metadata: {'index': index},
          ),
          operationQueue.queueOperation(
            type: 'type_$index',
            payload: {'index': index},
            idempotencyKey: 'key_$index',
          ),
        ]);
      });

      await Future.wait(tasks);

      // Verify that all 50 writes were persisted without any loss (race condition resolved)
      final logs = await auditLogger.getLogs();
      final queue = operationQueue.getQueue();

      expect(logs.length, equals(50));
      expect(queue.length, equals(50));

      // Verify that all indices 0 to 49 are present
      final logIndices = logs.map((l) {
        final meta = l['metadata'] as Map<String, dynamic>;
        return meta['index'] as int;
      }).toList()..sort();
      final queueIndices = queue.map((q) => q.payload['index'] as int).toList()..sort();

      expect(logIndices, equals(List.generate(50, (i) => i)));
      expect(queueIndices, equals(List.generate(50, (i) => i)));
    });
  });
}
