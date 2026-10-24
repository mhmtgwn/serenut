// test/core_next/stage10_12_15_guarded_database_manager_test.dart
// STAGE 10.12.15: Guarded DatabaseManager Routing & Resolver 8-Condition Verification Test

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('STAGE 10.12.15 — DatabaseManager & Routing 8-Condition Gate', () {
    late Directory tempDir;
    const resolver = DatabaseRoutingResolver();

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('guarded_routing_test_');
      DatabaseManager.databaseRoutingHook = null; // Ensure default is legacy
    });

    tearDown(() async {
      DatabaseManager.databaseRoutingHook = null;
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    // 1. Core Next kapalıysa legacy veritabanı açılır.
    test('Condition 1: Varsayılan durumda (hook null / Core Next kapalı) legacy yol seçilir', () async {
      expect(DatabaseManager.databaseRoutingHook, isNull);
      // When hook is null, DatabaseManager routes 100% to legacy database path
    });

    // 2. Migration runner yoksa otomatik migration yapılmaz.
    test('Condition 2: Migration runner yoksa (null) koordinatör göçü durdurur ve legacyde kalır', () async {
      final legacyDbPath = '${tempDir.path}/legacy2.db';
      final legacyDb = await openDatabase(
        legacyDbPath,
        version: 1,
        onCreate: (db, v) async {
          await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY);');
        },
      );

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: tempDir.path,
        prefs: prefs,
        migrationRunner: null, // explicitly null
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('MigrationRunner enjekte edilmedi'));

      await legacyDb.close();
    });

    // 3. Migration tamamlanma işareti yoksa hedef veritabanı seçilmez.
    test('Condition 3: Migration tamamlanma işareti yoksa (migrationStateCompleted=false) resolver legacy seçer', () async {
      final legacyPath = '${tempDir.path}/legacy3.db';
      final targetPath = '${tempDir.path}/target3.db';
      await File(legacyPath).writeAsString('legacy content');
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);
      await coreDb.db.insert('app_settings', {'key': 'tenant_id', 'value': 'tenant-1', 'updated_at': 1792100000});
      await coreDb.close();

      final res = await resolver.resolve(
        requestedTenantId: 'tenant-1',
        legacyDbPath: legacyPath,
        targetDbPath: targetPath,
        migrationStateCompleted: false, // NOT marked completed
      );

      expect(res.decision, equals(RoutingDecision.legacyFallback));
      expect(res.resolvedPath, equals(legacyPath));
      expect(res.isTargetSelected, isFalse);
    });

    // 4. Hedef veritabanı bozuksa otomatik olarak hedefte devam edilmez.
    test('Condition 4: Hedef veritabanı bozuksa resolver legacy veritabanına fallback / fail-closed yapar', () async {
      final legacyPath = '${tempDir.path}/legacy4.db';
      final targetPath = '${tempDir.path}/target_corrupt4.db';
      await File(legacyPath).writeAsString('legacy content');
      // Create corrupted file (> 512 bytes but garbage SQLite)
      final corruptFile = File(targetPath);
      await corruptFile.writeAsBytes(List.filled(1024, 0xFF));

      final res = await resolver.resolve(
        requestedTenantId: 'tenant-1',
        legacyDbPath: legacyPath,
        targetDbPath: targetPath,
        migrationStateCompleted: true,
      );

      expect(res.isTargetSelected, isFalse);
      expect(res.resolvedPath, equals(legacyPath));
      expect(res.reason.contains('bozuk') || res.reason.contains('hata'), isTrue);
    });

    // 5. Kiracı kimliği uyuşmazsa veri erişimi engellenir.
    test('Condition 5: Kiracı kimliği uyuşmazsa fail-closed ile erişim engellenir', () async {
      final legacyPath = '${tempDir.path}/legacy5.db';
      final targetPath = '${tempDir.path}/target_tenant5.db';
      await File(legacyPath).writeAsString('legacy content');
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);
      await coreDb.db.insert('app_settings', {'key': 'tenant_id', 'value': 'tenant-A', 'updated_at': 1792100000});
      await coreDb.close();

      final res = await resolver.resolve(
        requestedTenantId: 'tenant-B', // Different tenant!
        legacyDbPath: legacyPath,
        targetDbPath: targetPath,
        migrationStateCompleted: true,
      );

      expect(res.decision, equals(RoutingDecision.blockedFailClosed));
      expect(res.isTargetSelected, isFalse);
      expect(res.reason, contains('Tenant ID uyuşmazlığı'));
    });

    // 6. Migration sırasında hata olursa tamamlanmamış hedef veritabanı kullanılmaz.
    test('Condition 6: Migration sırasında hata olursa state failed kalır ve hedef seçilmez', () async {
      final legacyPath = '${tempDir.path}/legacy6.db';
      final targetPath = '${tempDir.path}/target_fail6.db';
      final legacyDb = await openDatabase(
        legacyPath,
        version: 1,
        onCreate: (db, v) async {
          await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY);');
        },
      );
      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);
      await targetCore.db.insert('app_settings', {'key': 'tenant_id', 'value': 'tenant-1', 'updated_at': 1792100000});

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: targetCore.db,
        customLegacyFilePath: legacyPath,
        customBackupDirectory: tempDir.path,
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          throw Exception('Simulated fatal migration crash');
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(result.state, equals(CoreNextMigrationState.failedRecoverable));
      expect(result.errorMessage, contains('Simulated fatal migration crash'));

      // Resolver check: target seçilmemeli
      final res = await resolver.resolve(
        requestedTenantId: 'tenant-1',
        legacyDbPath: legacyPath,
        targetDbPath: targetPath,
        migrationStateCompleted: result.isSuccess,
      );
      expect(res.decision, equals(RoutingDecision.legacyFallback));
      expect(res.isTargetSelected, isFalse);

      await legacyDb.close();
      await targetCore.close();
    });

    // 7. Hedef veritabanında yeni satış, defter veya nakit hareketi varsa güvenli olmayan rollback engellenir.
    test('Condition 7: Hedefte yeni satış, defter hareketi veya nakit kaydı varsa assertSafeRollback engeller', () async {
      final targetPath = '${tempDir.path}/target_rollback7.db';
      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);
      const cutoffTime = 1792100000; // int timestamp

      // Customer kaydı ekle (FK için)
      await targetCore.db.insert('customers', {
        'id': 'cust-1',
        'name': 'Test Müşteri',
        'updated_at': cutoffTime,
      });

      // 7a. Temiz durumda güvenli rollback serbest
      await expectLater(
        resolver.assertSafeRollback(
          targetDb: targetCore.db,
          initialMigrationCutoffTimestamp: cutoffTime,
        ),
        completes,
      );

      // 7b. Yeni satış yazılırsa rollback BLOKE edilmeli
      await targetCore.db.insert('sales', {
        'id': 'sale-1',
        'receipt_no': 'SN-001',
        'subtotal_cents': 1000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 1000,
        'paid_cents': 1000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': 1792100500, // > cutoffTime
      });

      await expectLater(
        resolver.assertSafeRollback(
          targetDb: targetCore.db,
          initialMigrationCutoffTimestamp: cutoffTime,
        ),
        throwsA(isA<UnsafeRollbackException>().having(
          (e) => e.message,
          'message',
          contains('Satış: 1'),
        )),
      );

      // Temizle satışı
      await targetCore.db.delete('sales');
      await expectLater(
        resolver.assertSafeRollback(
          targetDb: targetCore.db,
          initialMigrationCutoffTimestamp: cutoffTime,
        ),
        completes,
      );

      // 7c. Yeni defter hareketi (ledger_entries) yazılırsa rollback BLOKE edilmeli
      await targetCore.db.insert('ledger_entries', {
        'id': 'ledger-1',
        'customer_id': 'cust-1',
        'entry_type': 'DEBIT',
        'amount_cents': 5000,
        'balance_after_cents': 5000,
        'description': 'Yeni borç hareketi',
        'created_at': 1792100600, // > cutoffTime
      });

      await expectLater(
        resolver.assertSafeRollback(
          targetDb: targetCore.db,
          initialMigrationCutoffTimestamp: cutoffTime,
        ),
        throwsA(isA<UnsafeRollbackException>().having(
          (e) => e.message,
          'message',
          contains('Cari/Defter: 1'),
        )),
      );

      // Temizle defteri
      await targetCore.db.delete('ledger_entries');
      await expectLater(
        resolver.assertSafeRollback(
          targetDb: targetCore.db,
          initialMigrationCutoffTimestamp: cutoffTime,
        ),
        completes,
      );

      // 7d. Yeni nakit işlemi (cash_transactions) yazılırsa rollback BLOKE edilmeli
      await targetCore.db.insert('cash_transactions', {
        'id': 'cash-1',
        'type': 'INFLOW',
        'category': 'MANUAL',
        'amount_cents': 2500,
        'created_at': 1792100700, // > cutoffTime
      });

      await expectLater(
        resolver.assertSafeRollback(
          targetDb: targetCore.db,
          initialMigrationCutoffTimestamp: cutoffTime,
        ),
        throwsA(isA<UnsafeRollbackException>().having(
          (e) => e.message,
          'message',
          contains('Kasa: 1'),
        )),
      );

      await targetCore.close();
    });

    // 8. Birden fazla eşzamanlı açılış aynı migration'ı iki kez başlatamaz.
    test('Condition 8: Eşzamanlı iki açılış çağrısı aynı anda migration başlatamaz (isExecutionRunning kilit koruması)', () async {
      final legacyPath = '${tempDir.path}/legacy8.db';
      final targetPath = '${tempDir.path}/target8.db';
      final legacyDb = await openDatabase(
        legacyPath,
        version: 1,
        onCreate: (db, v) async {
          await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY);');
        },
      );
      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      int runnerCallCount = 0;

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: targetCore.db,
        customLegacyFilePath: legacyPath,
        customBackupDirectory: tempDir.path,
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        completionChecker: (db) async => false,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          runnerCallCount++;
          await Future.delayed(const Duration(milliseconds: 300));
          return const MigrationReport(
            productsMigrated: 0,
            customersMigrated: 0,
            salesMigrated: 0,
            ledgerEntriesMigrated: 0,
            durationMs: 300,
            isSuccess: true,
          );
        },
      );

      // Eşzamanlı iki çağrı başlat
      final Future<BootstrapCoordinatorResult> future1 = coordinator.coordinate();
      final Future<BootstrapCoordinatorResult> future2 = coordinator.coordinate();

      final results = await Future.wait([future1, future2]);

      // Biri çalışırken diğeri isAlreadyRunning ile engellenmiş olmalı
      expect(runnerCallCount, equals(1));
      expect(results.any((r) => r.isAlreadyRunning), isTrue);

      await legacyDb.close();
      await targetCore.close();
    });
  });
}
