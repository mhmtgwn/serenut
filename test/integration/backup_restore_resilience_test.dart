import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' hide equals;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/services/backup_service.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => '.';

  @override
  Future<String?> getApplicationSupportPath() async => '.';

  @override
  Future<String?> getLibraryPath() async => '.';

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.current.absolute.path;

  @override
  Future<String?> getExternalStoragePath() async => '.';

  @override
  Future<List<String>?> getExternalCachePaths() async => [];

  @override
  Future<List<String>?> getExternalStoragePaths(
          {StorageDirectory? type}) async =>
      [];

  @override
  Future<String?> getDownloadsPath() async => '.';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = MockPathProviderPlatform();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Backup/Restore Resilience Large Scale Integration Test', () {
    late BackupService backupService;
    late String dbPath;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      backupService = BackupService();
      dbPath = join(await getDatabasesPath(), 'serenut_pos_integration.db');

      // Ensure fresh database path
      final file = File(dbPath);
      if (await file.exists()) await file.delete();
      final walFile = File('$dbPath-wal');
      if (await walFile.exists()) await walFile.delete();
      final shmFile = File('$dbPath-shm');
      if (await shmFile.exists()) await shmFile.delete();

      DatabaseManager.overrideDatabasePath = dbPath;
    });

    tearDownAll(() async {
      DatabaseManager.overrideDatabasePath = null;
      // Clean up backup directory if it exists
      final docsDir = Directory.current.absolute.path;
      final backupsDir = Directory(join(docsDir, 'SerenutBackups'));
      if (await backupsDir.exists()) {
        await backupsDir.delete(recursive: true);
      }
    });

    test('Resilience test with 500 customers, 5000 sales, 1000 collections',
        () async {
      final dbManager = DatabaseManager();
      final db = await dbManager.getDatabase();

      // Verify schema is initialized by querying sqlite_master
      final tables = await db
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tables.map((t) => t['name'] as String).toList();
      expect(tableNames.contains('customers'), isTrue);
      expect(tableNames.contains('sales'), isTrue);
      expect(tableNames.contains('financial_transactions'), isTrue);

      final now = DateTime.now();

      // ── Step 1: Seed 500 Customers ──
      final customerBatch = db.batch();
      for (int i = 0; i < 500; i++) {
        customerBatch.insert('customers', {
          'id': 'cust-$i',
          'name': 'Customer $i',
          'email': 'customer$i@email.com',
          'phone': '555-01$i',
          'balance': 0.0, // starts at 0, updated below
          'status': 'active',
          'is_active': 1,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      }
      await customerBatch.commit(noResult: true);

      // Track expected balances locally for verification
      final Map<String, double> expectedBalances = {};
      for (int i = 0; i < 500; i++) {
        expectedBalances['cust-$i'] = 0.0;
      }

      // ── Step 2: Seed 5,000 Sales ──
      // Run inside transaction for performance
      await db.transaction((txn) async {
        final saleBatch = txn.batch();
        for (int i = 0; i < 5000; i++) {
          final custIndex = i % 500;
          final custId = 'cust-$custIndex';
          final double amount = 100.0 + (i % 50);
          final double paid = (i % 2 == 0) ? amount : (amount / 2);
          final double debt = amount - paid;

          // Track expected balance: debt reduces balance (negative)
          expectedBalances[custId] = expectedBalances[custId]! - debt;

          saleBatch.insert('sales', {
            'id': 'sale-$i',
            'customer_id': custId,
            'total_amount': amount,
            'paid_amount': paid,
            'payment_method': 'mixed',
            'status': 'completed',
            'created_at': now.subtract(Duration(minutes: i)).toIso8601String(),
            'updated_at': now.subtract(Duration(minutes: i)).toIso8601String(),
            'idempotency_key': 'idem-sale-$i',
            'is_synced': 0,
          });

          saleBatch.insert('financial_transactions', {
            'id': 'tx-sale-$i',
            'type': 'sale',
            'customer_id': custId,
            'amount': amount,
            'paid_amount': paid,
            'debt_amount': debt,
            'reference_id': 'sale-$i',
            'created_at': now.subtract(Duration(minutes: i)).toIso8601String(),
          });
        }
        await saleBatch.commit(noResult: true);
      });

      // ── Step 3: Seed 1,000 Collections ──
      await db.transaction((txn) async {
        final collBatch = txn.batch();
        for (int i = 0; i < 1000; i++) {
          final custIndex = (i * 7) % 500; // distribute collections
          final custId = 'cust-$custIndex';
          final double collected = 20.0 + (i % 10);

          // Track expected balance: payment increases balance
          expectedBalances[custId] = expectedBalances[custId]! + collected;

          collBatch.insert('financial_transactions', {
            'id': 'tx-coll-$i',
            'type': 'payment',
            'customer_id': custId,
            'amount': collected,
            'paid_amount': collected,
            'debt_amount': 0.0,
            'reference_id': 'payment-$i',
            'created_at': now.subtract(Duration(seconds: i)).toIso8601String(),
          });
        }
        await collBatch.commit(noResult: true);
      });

      // Update customers table balances with expected values
      await db.transaction((txn) async {
        final updateBatch = txn.batch();
        for (final entry in expectedBalances.entries) {
          updateBatch.update(
              'customers',
              {
                'balance': entry.value,
              },
              where: 'id = ?',
              whereArgs: [entry.key]);
        }
        await updateBatch.commit(noResult: true);
      });

      // Assert database sizes and counts
      final salesCount = (await db.rawQuery('SELECT COUNT(*) FROM sales'))
          .first
          .values
          .first as int;
      final txCount =
          (await db.rawQuery('SELECT COUNT(*) FROM financial_transactions'))
              .first
              .values
              .first as int;
      expect(salesCount, equals(5000));
      expect(txCount, equals(6000)); // 5000 sales + 1000 payments

      // Verify a sample customer balance
      final sampleB = await db.query('customers',
          columns: ['balance'], where: 'id = ?', whereArgs: ['cust-123']);
      expect(sampleB.first['balance'] as double,
          closeTo(expectedBalances['cust-123']!, 0.01));

      // ── Step 4: Perform Database Backup ──
      final backupPath = await backupService.backupDatabase();
      expect(backupPath, isNotEmpty);
      expect(await File(backupPath).exists(), isTrue);

      // Close connection to allow file deletions safely
      await dbManager.close();

      // ── Step 5: Simulate Disaster / File Deletion ──
      final dbFile = File(dbPath);
      final walFile = File('$dbPath-wal');
      final shmFile = File('$dbPath-shm');

      if (await dbFile.exists()) await dbFile.delete();
      if (await walFile.exists()) await walFile.delete();
      if (await shmFile.exists()) await shmFile.delete();

      expect(await dbFile.exists(), isFalse);

      // ── Step 6: Restore Database from Backup ──
      final restoreSuccess = await backupService.restoreDatabase(backupPath);
      expect(restoreSuccess, isTrue);
      expect(await dbFile.exists(), isTrue);

      // ── Step 7: Verify Restored State & Invariants ──
      final restoredDb = await dbManager.getDatabase();
      final restoredSalesCount =
          (await restoredDb.rawQuery('SELECT COUNT(*) FROM sales'))
              .first
              .values
              .first as int;
      final restoredTxCount = (await restoredDb
              .rawQuery('SELECT COUNT(*) FROM financial_transactions'))
          .first
          .values
          .first as int;
      expect(restoredSalesCount, equals(5000));
      expect(restoredTxCount, equals(6000));

      // Verify all customer balances are identical to pre-backup state
      for (final entry in expectedBalances.entries) {
        final id = entry.key;
        final expected = entry.value;
        final custResult = await restoredDb.query('customers',
            columns: ['balance'], where: 'id = ?', whereArgs: [id]);
        expect(custResult, isNotEmpty);
        final balance = custResult.first['balance'] as double;
        expect(balance, closeTo(expected, 0.01));
      }

      await restoredDb.close();
      await File(backupPath).delete();
    });
  });
}
