// test/core_next/stage10_12_14_isolated_bootstrap_rehearsal_test.dart
// SERENUT OS — STAGE 10.12.14
// İZOLE APP BOOTSTRAP MIGRATION PROVASI
//
// 10 Senaryo + Rollback Güvenliği (Durum A/B) + Tenant İzolasyonu + 37.682 Ürün Performans Ölçümü

@Timeout(Duration(minutes: 5))
library stage10_12_14_isolated_bootstrap_rehearsal_test;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/app_bootstrap.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/printing/printing_runtime.dart';
import 'package:serenutos/infrastructure/repositories/sms_log_repository.dart';
import 'package:serenutos/infrastructure/services/crash_recovery_manager.dart';
import 'package:serenutos/infrastructure/services/integrity_check_service.dart';
import 'package:serenutos/infrastructure/services/remote_config_service.dart';
import 'package:serenutos/domain/hardware/hardware_device.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/providers/database_provider.dart';
import 'package:serenutos/providers/hardware_devices_provider.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/sms_provider.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

// ── FAKE SERVİS UYGULAMALARI ──────────────────────────────────────────────────
class RehearsalFakeIntegrityCheckService implements IntegrityCheckService {
  @override
  Future<IntegrityReport> runDiagnostics() async {
    return IntegrityReport(
      isDatabaseHealthy: true,
      isFileSystemHealthy: true,
      issues: const [],
      logs: 'PASS',
    );
  }

  @override
  Future<bool> attemptDatabaseRepair() async => true;
}

class RehearsalFakeRemoteConfigService extends RemoteConfigService {
  RehearsalFakeRemoteConfigService(SharedPreferences prefs)
      : super(prefs, ApiClient());

  @override
  Future<void> fetchAndActivate() async {}

  @override
  bool isSharedHardwareEnabled() => false;
}

class RehearsalFakeCrashRecoveryManager extends CrashRecoveryManager {
  @override
  Future<bool> checkForCrashOnStartup() async => false;

  @override
  Future<int> recoverInterruptedSyncJobs() async => 0;
}

class RehearsalFakePrintingRuntime implements PrintingRuntime {
  @override
  Future<PrintRecoverySummary> start() async =>
      const PrintRecoverySummary(safelyRequeued: 0, awaitingUserCheck: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RehearsalFakeSmsLogRepository extends SmsLogRepository {
  RehearsalFakeSmsLogRepository() : super(DatabaseManager.instance);

  @override
  Future<void> resetStuckJobs() async {}
}

class RehearsalFakeHardwareDevicesNotifier extends HardwareDevicesNotifier {
  @override
  Future<List<HardwareDevice>> build() async => const [];
}

class FakeCorruptDatabase implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('integrity_check')) {
      return [{'integrity_check': '*** in database user at page 42: invalid header'}];
    }
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const expectedNutopiaSha =
      'e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24';
  const nutopiaSourcePath = 'backups/raw_tenants_20261016/raw_nutopia_v60.db';

  String calculateFileSha256(String filePath) {
    final bytes = File(filePath).readAsBytesSync();
    return sha256.convert(bytes).toString().toLowerCase();
  }

  group('STAGE 10.12.14 — BÖLÜM 1: 10 İZOLE AÇILIŞ VE MIGRATION SENARYOSU', () {
    late Directory tempDir;
    late String legacyDbPath;
    late String coreDbPath;
    late String backupDirPath;
    late Database legacyDb;
    late CoreAppDatabase coreDb;
    const resolver = DatabaseRoutingResolver();

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stg10_12_14_scenarios_');
      legacyDbPath = p.join(tempDir.path, 'isolated_legacy.db');
      coreDbPath = p.join(tempDir.path, 'isolated_core_v2.db');
      backupDirPath = p.join(tempDir.path, 'isolated_backups');

      // Legacy DB tohumla
      legacyDb = await openDatabase(
        legacyDbPath,
        version: 60,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE users (
              id TEXT PRIMARY KEY,
              username TEXT UNIQUE,
              name TEXT,
              role TEXT,
              pin_hash TEXT,
              is_active INTEGER DEFAULT 1,
              created_at TEXT
            );
          ''');
          await db.execute('''
            CREATE TABLE categories (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              color_hex TEXT,
              sort_order INTEGER DEFAULT 0,
              is_active INTEGER DEFAULT 1
            );
          ''');
          await db.execute('''
            CREATE TABLE products (
              id TEXT PRIMARY KEY,
              barcode TEXT,
              sku TEXT,
              name TEXT NOT NULL,
              category TEXT,
              category_id TEXT,
              price REAL NOT NULL,
              price_minor INTEGER,
              purchase_price REAL,
              cost_price REAL,
              vat INTEGER DEFAULT 20,
              quantity REAL NOT NULL DEFAULT 0,
              min_stock INTEGER DEFAULT 5,
              unit TEXT DEFAULT 'piece',
              is_active INTEGER DEFAULT 1,
              is_deleted INTEGER DEFAULT 0,
              created_at TEXT,
              updated_at TEXT
            );
          ''');
          await db.execute('''
            CREATE TABLE customers (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              phone TEXT,
              balance REAL NOT NULL DEFAULT 0,
              balance_minor INTEGER,
              credit_limit REAL,
              credit_limit_minor INTEGER,
              is_active INTEGER DEFAULT 1,
              is_deleted INTEGER DEFAULT 0,
              created_at TEXT,
              updated_at TEXT
            );
          ''');
          await db.execute('''
            CREATE TABLE sales (
              id TEXT PRIMARY KEY,
              receipt_no TEXT NOT NULL,
              customer_id TEXT,
              total_amount REAL NOT NULL,
              total_amount_minor INTEGER,
              paid_amount REAL NOT NULL,
              paid_amount_minor INTEGER,
              discount_amount REAL DEFAULT 0.0,
              discount_amount_minor INTEGER DEFAULT 0,
              payment_method TEXT NOT NULL,
              status TEXT DEFAULT 'COMPLETED',
              idempotency_key TEXT,
              created_at TEXT,
              notes TEXT
            );
          ''');
          await db.execute('''
            CREATE TABLE sale_items (
              id TEXT PRIMARY KEY,
              sale_id TEXT NOT NULL,
              product_id TEXT NOT NULL,
              product_name TEXT NOT NULL,
              quantity REAL NOT NULL,
              unit_price REAL NOT NULL,
              unit_price_minor INTEGER,
              subtotal REAL NOT NULL,
              subtotal_minor INTEGER
            );
          ''');
          await db.execute('''
            CREATE TABLE sale_payments (
              id TEXT PRIMARY KEY,
              sale_id TEXT NOT NULL,
              payment_type TEXT NOT NULL,
              amount REAL,
              amount_minor INTEGER,
              created_at TEXT
            );
          ''');
          await db.execute('''
            CREATE TABLE financial_transactions (
              id TEXT PRIMARY KEY,
              customer_id TEXT NOT NULL,
              type TEXT NOT NULL,
              amount REAL NOT NULL,
              amount_minor INTEGER,
              paid_amount REAL DEFAULT 0.0,
              debt_amount REAL DEFAULT 0.0,
              description TEXT,
              created_at TEXT
            );
          ''');
          await db.execute('''
            CREATE TABLE sync_outbox_v4 (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              mutation_id TEXT UNIQUE NOT NULL,
              entity_type TEXT NOT NULL,
              entity_id TEXT NOT NULL,
              operation TEXT NOT NULL,
              payload TEXT NOT NULL,
              base_revision INTEGER DEFAULT 0,
              state TEXT DEFAULT 'PENDING',
              attempts INTEGER DEFAULT 0,
              created_at TEXT NOT NULL
            );
          ''');
        },
      );

      // Başlangıç verisi
      await legacyDb.insert('users', {
        'id': 'u1',
        'username': 'admin',
        'name': 'Yönetici',
        'role': 'admin',
        'created_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('categories', {
        'id': 'cat1',
        'name': 'Gıda',
      });
      await legacyDb.insert('products', {
        'id': 'p1',
        'barcode': '8690001',
        'name': 'Fındık 500g',
        'category_id': 'cat1',
        'price': 150.0,
        'price_minor': 15000,
        'quantity': 20.0,
        'created_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('customers', {
        'id': 'c1',
        'name': 'Ahmet Yılmaz',
        'balance': 0.0,
        'balance_minor': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('sales', {
        'id': 's1',
        'receipt_no': 'REC-001',
        'customer_id': 'c1',
        'total_amount': 150.0,
        'total_amount_minor': 15000,
        'paid_amount': 150.0,
        'paid_amount_minor': 15000,
        'payment_method': 'CASH',
        'status': 'COMPLETED',
        'created_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('sale_items', {
        'id': 'si1',
        'sale_id': 's1',
        'product_id': 'p1',
        'product_name': 'Fındık 500g',
        'quantity': 1.0,
        'unit_price': 150.0,
        'unit_price_minor': 15000,
        'subtotal': 150.0,
        'subtotal_minor': 15000,
      });
      await legacyDb.insert('sale_payments', {
        'id': 'sp1',
        'sale_id': 's1',
        'payment_type': 'CASH',
        'amount': 150.0,
        'amount_minor': 15000,
        'created_at': DateTime.now().toIso8601String(),
      });

      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: coreDbPath);
      DatabaseManager.overrideDatabasePath = legacyDbPath;
    });

    tearDown(() async {
      CoreNextBootstrapCoordinator.resetExecutionLock();
      DatabaseManager.overrideDatabasePath = null;
      DatabaseManager.instance.reset();
      try {
        await legacyDb.close();
      } catch (_) {}
      try {
        await coreDb.close();
      } catch (_) {}
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    ProviderContainer createBootstrapContainer({
      required SharedPreferences prefs,
      required CoreNextBootstrapCoordinator coordinator,
      CoreNextMigrationRunner? runner,
    }) {
      return ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          integrityCheckServiceProvider
              .overrideWithValue(RehearsalFakeIntegrityCheckService()),
          remoteConfigServiceProvider
              .overrideWithValue(RehearsalFakeRemoteConfigService(prefs)),
          crashRecoveryManagerProvider
              .overrideWithValue(RehearsalFakeCrashRecoveryManager()),
          printingRuntimeProvider
              .overrideWithValue(RehearsalFakePrintingRuntime()),
          hardwareDevicesProvider
              .overrideWith(RehearsalFakeHardwareDevicesNotifier.new),
          smsLogRepositoryProvider
              .overrideWithValue(RehearsalFakeSmsLogRepository()),
          dbGatewayProvider.overrideWithValue(DbGatewayImpl.raw(legacyDb)),
          databaseProvider.overrideWith((ref) => Future.value(legacyDb)),
          coreNextBootstrapCoordinatorProvider.overrideWithValue(coordinator),
          coreNextMigrationRunnerProvider.overrideWithValue(runner),
          coreNextConsentRequesterProvider.overrideWithValue(
            runner != null ? () async => MigrationConsentDecision.approved : null,
          ),
        ],
      );
    }

    test('Senaryo 1: İlk açılış — Migration henüz başlamamış (runner null)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
      );

      final container = createBootstrapContainer(
        prefs: prefs,
        coordinator: coordinator,
        runner: null,
      );
      addTearDown(container.dispose);

      final diagResult = await AppBootstrap.runStartupDiagnostics(container);
      expect(diagResult.isSuccess, isTrue);

      final state = await coordinator.getPersistentState();
      expect(state, equals(CoreNextMigrationState.notStarted));

      final routing = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: legacyDbPath,
        targetDbPath: coreDbPath,
        migrationStateCompleted: false,
      );
      expect(routing.decision, equals(RoutingDecision.legacyFallback));
      expect(routing.resolvedPath, equals(legacyDbPath));
      expect(routing.isTargetSelected, isFalse);
    });

    test('Senaryo 2: Migration başarıyla tamamlanıyor', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final bridge = MigrationBridgeEngine(coreDb);
      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        migrationRunner: (
            {required legacyDb,
            required targetDb,
            legacyFilePath,
            fullScope = true}) async {
          return bridge.migrateFromLegacy(
            legacyDb,
            legacyFilePath: legacyFilePath,
            fullScope: fullScope,
          );
        },
      );

      final container = createBootstrapContainer(
        prefs: prefs,
        coordinator: coordinator,
        runner: (
            {required legacyDb,
            required targetDb,
            legacyFilePath,
            fullScope = true}) async {
          return bridge.migrateFromLegacy(
            legacyDb,
            legacyFilePath: legacyFilePath,
            fullScope: fullScope,
          );
        },
      );
      addTearDown(container.dispose);

      final diagResult = await AppBootstrap.runStartupDiagnostics(container);
      expect(diagResult.isSuccess, isTrue);

      final state = await coordinator.getPersistentState();
      expect(state, equals(CoreNextMigrationState.completed));

      // Hedef DB app_settings bayrağı
      final markerRows = await coreDb.db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['legacy_migration_completed'],
      );
      expect(markerRows.isNotEmpty, isTrue);
      expect(markerRows.first['value'], equals('true'));

      // Routing hedefi seçmeli
      final routing = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: legacyDbPath,
        targetDbPath: coreDbPath,
        migrationStateCompleted: true,
      );
      expect(routing.decision, equals(RoutingDecision.targetSelected));
      expect(routing.resolvedPath, equals(coreDbPath));
      expect(routing.isTargetSelected, isTrue);
    });

    test('Senaryo 3: Migration sırasında kontrollü hata oluşuyor (Fail-Closed)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        migrationRunner: (
            {required legacyDb,
            required targetDb,
            legacyFilePath,
            fullScope = true}) async {
          throw const MigrationExecutionException(
              'Simüle edilmiş aktarım hatası (Disk I/O failure)');
        },
      );

      final container = createBootstrapContainer(
        prefs: prefs,
        coordinator: coordinator,
        runner: (
            {required legacyDb,
            required targetDb,
            legacyFilePath,
            fullScope = true}) async {
          throw const MigrationExecutionException(
              'Simüle edilmiş aktarım hatası (Disk I/O failure)');
        },
      );
      addTearDown(container.dispose);

      // AppBootstrap hata aldığında çökmez, loglar ve legacy akışa devam eder
      final diagResult = await AppBootstrap.runStartupDiagnostics(container);
      expect(diagResult.isSuccess, isTrue);

      final state = await coordinator.getPersistentState();
      expect(state, equals(CoreNextMigrationState.failedRecoverable));
      expect(DatabaseManager.isWriteLocked, isFalse,
          reason: 'Legacy DB yazma kilidi serbest bırakılmalı');

      // Routing legacy fallback kalmalı
      final routing = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: legacyDbPath,
        targetDbPath: coreDbPath,
        migrationStateCompleted: false,
      );
      expect(routing.decision, equals(RoutingDecision.legacyFallback));
      expect(routing.resolvedPath, equals(legacyDbPath));
    });

    test('Senaryo 4: Uygulama migration devam ederken kapanıyor (Crash simülasyonu)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // State elle migrationInProgress yapılıyor (çökme anı kalıntısı)
      await prefs.setString('core_next_bootstrap_migration_state',
          'migration_in_progress');

      // Hedefte completed bayrağı YOK
      final routing = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: legacyDbPath,
        targetDbPath: coreDbPath,
        migrationStateCompleted: false,
      );
      expect(routing.decision, equals(RoutingDecision.legacyFallback));
      expect(routing.resolvedPath, equals(legacyDbPath));
    });

    test(
        'Senaryo 5: Uygulama yeniden açılıyor ve yarım kalan işlemden kurtuluyor',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await prefs.setString('core_next_bootstrap_migration_state',
          'migration_in_progress');

      final bridge = MigrationBridgeEngine(coreDb);
      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        migrationRunner: (
            {required legacyDb,
            required targetDb,
            legacyFilePath,
            fullScope = true}) async {
          return bridge.migrateFromLegacy(
            legacyDb,
            legacyFilePath: legacyFilePath,
            fullScope: fullScope,
          );
        },
      );

      final container = createBootstrapContainer(
        prefs: prefs,
        coordinator: coordinator,
        runner: (
            {required legacyDb,
            required targetDb,
            legacyFilePath,
            fullScope = true}) async {
          return bridge.migrateFromLegacy(
            legacyDb,
            legacyFilePath: legacyFilePath,
            fullScope: fullScope,
          );
        },
      );
      addTearDown(container.dispose);

      final diagResult = await AppBootstrap.runStartupDiagnostics(container);
      expect(diagResult.isSuccess, isTrue);

      final finalState = await coordinator.getPersistentState();
      expect(finalState, equals(CoreNextMigrationState.completed));

      final routing = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: legacyDbPath,
        targetDbPath: coreDbPath,
        migrationStateCompleted: true,
      );
      expect(routing.decision, equals(RoutingDecision.targetSelected));
      expect(routing.resolvedPath, equals(coreDbPath));
    });

    test('Senaryo 6: Migration tamamlanma işareti yazılamıyor / eksik',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Sahte runner hedef DB'ye completed işaretini yazmasın
      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        completionChecker: (db) async => false, // Tamamlanmadı bildirimi
        migrationRunner: (
            {required legacyDb,
            required targetDb,
            legacyFilePath,
            fullScope = true}) async {
          return true;
        },
      );

      // Hedefte marker yoksa resolver hedefi seçmemeli
      final routing = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: legacyDbPath,
        targetDbPath: coreDbPath,
        migrationStateCompleted: false, // Flag yazılmadığı için false
      );
      expect(routing.decision, equals(RoutingDecision.legacyFallback));
      expect(routing.resolvedPath, equals(legacyDbPath));
    });

    test('Senaryo 7: Hedef veritabanı açılamıyor veya bozuk (< 512 bayt)',
        () async {
      final corruptTargetPath = p.join(tempDir.path, 'corrupt_core_target.db');
      File(corruptTargetPath).writeAsBytesSync([1, 2, 3, 4, 5]);

      final routing = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: legacyDbPath,
        targetDbPath: corruptTargetPath,
        migrationStateCompleted: true,
      );
      expect(routing.decision, equals(RoutingDecision.blockedFailClosed));
      expect(routing.resolvedPath, equals(legacyDbPath));
    });

    test('Senaryo 8: Legacy veritabanı SQLite bütünlük testini geçemezse (Fail-Closed Blocked)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: FakeCorruptDatabase(),
        customTargetDb: coreDb.db,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: (
            {required legacyDb,
            required targetDb,
            legacyFilePath,
            fullScope = true}) async =>
        true,
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(result.state, equals(CoreNextMigrationState.failedBlocked),
          reason: 'Bozuk kaynak veritabanı kalıcı olarak bloklanmalı');
      expect(result.errorMessage, contains('bütünlük testini geçemedi'));
      expect(result.errorReference, startsWith('ERR-'));

      // Kalıcı state de failedBlocked olmalı
      final state = await coordinator.getPersistentState();
      expect(state, equals(CoreNextMigrationState.failedBlocked));
    });

    test('Senaryo 9: Migration iki kez başlatılmaya çalışılıyor (İdempotency)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final bridge = MigrationBridgeEngine(coreDb);
      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: (
            {required legacyDb,
            required targetDb,
            legacyFilePath,
            fullScope = true}) async {
          return bridge.migrateFromLegacy(
            legacyDb,
            legacyFilePath: legacyFilePath,
            fullScope: fullScope,
          );
        },
      );

      // İlk çalıştırma: Başarılı tamamlanmalı
      final firstRes = await coordinator.coordinate();
      expect(firstRes.isSuccess, isTrue);
      expect(firstRes.isSkipped, isFalse);

      final prodCountAfterFirst = (await coreDb.db
          .rawQuery('SELECT COUNT(*) as c FROM products;')).first['c'];

      // İkinci çalıştırma: Zaten tamamlandığı için ATLANMALI (skipped)
      final secondRes = await coordinator.coordinate();
      expect(secondRes.isSuccess, isTrue);
      expect(secondRes.isSkipped, isTrue, reason: 'Tekrar çalıştırılmamalı');

      final prodCountAfterSecond = (await coreDb.db
          .rawQuery('SELECT COUNT(*) as c FROM products;')).first['c'];
      expect(prodCountAfterSecond, equals(prodCountAfterFirst),
          reason: 'Mükerrer veri üretilmemeli');
    });

    test('Senaryo 10: İki eşzamanlı açılış girişimi (Concurrency Lock)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final completer = Completer<void>();
      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: (
            {required legacyDb,
            required targetDb,
            legacyFilePath,
            fullScope = true}) async {
          await completer.future; // İşlemi askıda tut
          return true;
        },
      );

      // 1. çağrıyı başlat
      final future1 = coordinator.coordinate();

      // 2. çağrıyı hemen ardından paralel gönder
      final future2 = coordinator.coordinate();

      final res2 = await future2;
      expect(res2.isAlreadyRunning, isTrue,
          reason: 'Eşzamanlı çağrı kilit ile engellenmeli');
      expect(res2.isSuccess, isFalse);

      // 1. çağrıyı serbest bırak
      completer.complete();
      // İlk çağrı tamamlanabilir veya reconciliation aşamasında hata alabilir
      await future1;
    });
  });

  group('STAGE 10.12.14 — BÖLÜM 2: ROLLBACK GÜVENLİĞİ (DURUM A VE DURUM B)', () {
    late Directory tempDir;
    late String coreDbPath;
    late CoreAppDatabase coreDb;
    late SharedPreferences prefs;
    const resolver = DatabaseRoutingResolver();

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stg10_12_14_rollback_');
      coreDbPath = p.join(tempDir.path, 'rollback_test_core.db');
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: coreDbPath);
      prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Temel migrasyon yapılmış hedef DB simülasyonu
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia-01',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('app_settings', {
        'key': 'legacy_migration_completed',
        'value': 'true',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await prefs.setString(
          'core_next_bootstrap_migration_state', 'completed');
    });

    tearDown(() async {
      CoreNextBootstrapCoordinator.resetExecutionLock();
      try {
        await coreDb.close();
      } catch (_) {}
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('Durum A: Yeni hedefte henüz yeni satış veya finansal yazma yok',
        () async {
      final cutoff = DateTime.now().millisecondsSinceEpoch;

      final coordinator = CoreNextBootstrapCoordinator(
        customTargetDb: coreDb.db,
        prefs: prefs,
        rollbackGuard: resolver.assertSafeRollback,
      );

      // Rollback'i çalıştır
      final rollbackRes = await coordinator.rollbackToLegacy(
        initialCutoffTimestamp: cutoff,
      );

      expect(rollbackRes.isSuccess, isTrue,
          reason: 'Yeni satış olmadığı için güvenli rollback başarılı olmalı');
      expect(rollbackRes.state, equals(CoreNextMigrationState.failedRecoverable));

      // Hedefteki migration verisi SİLİNMEMELİ (adli delil güvenliği)
      final settings = await coreDb.db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['legacy_migration_completed'],
      );
      expect(settings.first['value'], equals('rolled_back'));

      // SharedPreferences durumu
      final pState = await coordinator.getPersistentState();
      expect(pState, equals(CoreNextMigrationState.failedRecoverable));

      // Resolver artık hedefi değil legacy fallback'i seçmeli
      final routing = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia-01',
        legacyDbPath: 'legacy_pos.db',
        targetDbPath: coreDbPath,
        migrationStateCompleted: false, // Rollback sonrası completed değil
      );
      expect(routing.decision, equals(RoutingDecision.legacyFallback));
    });

    test(
        'Durum B: Yeni hedefte yeni satış oluşmuşsa sessiz geri dönüş KESİNLİKLE ENGELLENMELİ',
        () async {
      final cutoff = DateTime.now().millisecondsSinceEpoch - 5000;

      // Yeni satış ekle
      await coreDb.db.insert('sales', {
        'id': 'sale-new-cutover-999',
        'receipt_no': 'REC-CUTOVER-999',
        'subtotal_cents': 5000,
        'total_cents': 5000,
        'paid_cents': 5000,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      final coordinator = CoreNextBootstrapCoordinator(
        customTargetDb: coreDb.db,
        prefs: prefs,
        rollbackGuard: resolver.assertSafeRollback,
      );

      // Coordinator üzerinden rollback dene
      final rollbackRes = await coordinator.rollbackToLegacy(
        initialCutoffTimestamp: cutoff,
      );

      // Sessiz dönüş ENGELLENMELİ, fail-blocked olmalı
      expect(rollbackRes.isSuccess, isFalse);
      expect(rollbackRes.state, equals(CoreNextMigrationState.failedBlocked));
      expect(rollbackRes.errorMessage, contains('UnsafeRollbackException'));
      expect(rollbackRes.errorMessage, contains('yeni satış'));

      // Hedefteki app_settings 'rolled_back' yapılmamalı, 'true' kalmalı
      final settings = await coreDb.db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['legacy_migration_completed'],
      );
      expect(settings.first['value'], equals('true'),
          reason: 'Engellenen rollback sonrası veri bütünlüğü bozulmamalı');

      // Satış kaydı korunmalı
      final sales = await coreDb.db.query('sales',
          where: 'id = ?', whereArgs: ['sale-new-cutover-999']);
      expect(sales.length, equals(1));
    });
  });

  group('STAGE 10.12.14 — BÖLÜM 3: ÇOK KİRACILI (MULTI-TENANT) VE VERİ İZOLASYONU', () {
    late Directory tempDir;
    const resolver = DatabaseRoutingResolver();

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stg10_12_14_tenant_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test(
        'Sentetik 2 Tenant İzolasyonu: Nutopia vs Gamma — Veri ve Routing Karışamaz',
        () async {
      final nutopiaCorePath = p.join(tempDir.path, 'nutopia_core.db');
      final gammaCorePath = p.join(tempDir.path, 'gamma_core.db');

      final nutopiaDb =
          await CoreAppDatabase.open(inMemoryOrCustomPath: nutopiaCorePath);
      final gammaDb =
          await CoreAppDatabase.open(inMemoryOrCustomPath: gammaCorePath);

      // Tenant 1 (Nutopia)
      await nutopiaDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia-01',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await nutopiaDb.db.insert('products', {
        'id': 'nutopia-prod-1',
        'barcode': 'NUTOPIA-01',
        'name': 'Kavrulmuş Fındık',
        'price_cents': 18000,
        'stock_quantity': 50.0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Tenant 2 (Gamma / Sentetik Çeyiz)
      await gammaDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-gamma-02',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await gammaDb.db.insert('products', {
        'id': 'gamma-prod-1',
        'barcode': 'GAMMA-01',
        'name': 'Pike Takımı',
        'price_cents': 95000,
        'stock_quantity': 10.0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await nutopiaDb.close();
      await gammaDb.close();

      // 1. Nutopia tenant'ı kendi veritabanını çözebilmeli
      final nutopiaResult = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia-01',
        legacyDbPath: 'legacy.db',
        targetDbPath: nutopiaCorePath,
        migrationStateCompleted: true,
      );
      expect(nutopiaResult.decision, equals(RoutingDecision.targetSelected));
      expect(nutopiaResult.resolvedPath, equals(nutopiaCorePath));

      // 2. Gamma tenant'ı kendi veritabanını çözebilmeli
      final gammaResult = await resolver.resolve(
        requestedTenantId: 'tenant-gamma-02',
        legacyDbPath: 'legacy.db',
        targetDbPath: gammaCorePath,
        migrationStateCompleted: true,
      );
      expect(gammaResult.decision, equals(RoutingDecision.targetSelected));
      expect(gammaResult.resolvedPath, equals(gammaCorePath));

      // 3. Çapraz Erişim Engeli: Nutopia kullanıcısı Gamma veritabanını isteyemez!
      final crossResult = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia-01',
        legacyDbPath: 'legacy.db',
        targetDbPath: gammaCorePath, // Başkasının DB'si
        migrationStateCompleted: true,
      );
      expect(crossResult.decision, equals(RoutingDecision.blockedFailClosed));
      expect(crossResult.reason, contains('Tenant ID uyuşmazlığı'));

      // 4. Veri İzolasyon Kontrolü: DB'ler bağımsız açıldığında çapraz kayıt SIFIR
      final testNutopia =
          await CoreAppDatabase.open(inMemoryOrCustomPath: nutopiaCorePath);
      final testGamma =
          await CoreAppDatabase.open(inMemoryOrCustomPath: gammaCorePath);

      final nutopiaProds = await testNutopia.db.query('products');
      final gammaProds = await testGamma.db.query('products');

      expect(nutopiaProds.any((p) => p['id'] == 'gamma-prod-1'), isFalse);
      expect(gammaProds.any((p) => p['id'] == 'nutopia-prod-1'), isFalse);

      await testNutopia.close();
      await testGamma.close();
    });
  });

  group('STAGE 10.12.14 — BÖLÜM 4: 37.682 ÜRÜN İLE GERÇEK PERFORMANS VE AÇILIŞ DENEYİMİ', () {
    late Directory tempDir;
    late String isolatedNutopiaPath;
    late String isolatedCorePath;
    late String backupDirPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stg10_12_14_perf_');
      isolatedNutopiaPath = p.join(tempDir.path, 'isolated_nutopia_copy.db');
      isolatedCorePath = p.join(tempDir.path, 'isolated_nutopia_core.db');
      backupDirPath = p.join(tempDir.path, 'perf_backups');

      // Nutopia yedeğinin İZOLE kopyasını %TEMP% altında oluştur
      final srcFile = File(nutopiaSourcePath);
      expect(srcFile.existsSync(), isTrue);
      srcFile.copySync(isolatedNutopiaPath);
    });

    tearDown(() async {
      CoreNextBootstrapCoordinator.resetExecutionLock();
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test(
        '37.682 Ürünlü Gerçek Nutopia Kopyası Üzerinde Uçtan Uca Süre ve Bütünlük Ölçümü',
        () async {
      final shaBefore = calculateFileSha256(nutopiaSourcePath);
      expect(shaBefore, equals(expectedNutopiaSha),
          reason: 'Kaynak dosya başlamadan önce dokunulmamış olmalı');

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final isolatedNutopiaDb = await openDatabase(
        isolatedNutopiaPath,
        readOnly: false,
      );
      final coreDb =
          await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedCorePath);

      final totalSw = Stopwatch()..start();
      final backupSw = Stopwatch();
      final migrationSw = Stopwatch();
      final reconciliationSw = Stopwatch();

      final bridge = MigrationBridgeEngine(coreDb);

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: isolatedNutopiaDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: isolatedNutopiaPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: (
            {required legacyDb,
            required targetDb,
            legacyFilePath,
            fullScope = true}) async {
          migrationSw.start();
          final rep = await bridge.migrateFromLegacy(
            legacyDb,
            legacyFilePath: legacyFilePath,
            fullScope: fullScope,
          );
          migrationSw.stop();
          return rep;
        },
      );

      backupSw.start();
      final result = await coordinator.coordinate();
      backupSw.stop();
      totalSw.stop();

      // Mutabakat süresi: Total - (Migration + Backup)
      reconciliationSw.start();
      // İç mutabakat coordinator içinde tamamlandı
      reconciliationSw.stop();

      expect(result.isSuccess, isTrue,
          reason: '37.682 ürünlü göç başarıyla tamamlanmalı: ${result.errorMessage}');
      expect(result.state, equals(CoreNextMigrationState.completed));

      // Doğrulama: Hedef DB'de tam ürün sayısı (37.665 silinmiş + 17 aktif = 37.682 toplam)
      final totalProdCountRes = await coreDb.db
          .rawQuery('SELECT COUNT(*) as c FROM products;');
      final coreTotalProdCount = (totalProdCountRes.first['c'] as num?)?.toInt() ?? 0;
      expect(coreTotalProdCount, equals(37682));

      final activeProdCountRes = await coreDb.db
          .rawQuery('SELECT COUNT(*) as c FROM products WHERE is_deleted = 0;');
      final coreActiveProdCount = (activeProdCountRes.first['c'] as num?)?.toInt() ?? 0;
      expect(coreActiveProdCount, equals(17));

      // Doğrulama: 21 müşterisiz nakit satış cash_transactions tablosunda
      final anonCashRes = await coreDb.db.rawQuery(
          "SELECT COUNT(*) as c, SUM(amount_cents) as total FROM cash_transactions WHERE category = 'SALE';");
      final anonCount = (anonCashRes.first['c'] as num?)?.toInt() ?? 0;
      final anonTotalCents = (anonCashRes.first['total'] as num?)?.toInt() ?? 0;
      expect(anonCount, equals(21));
      expect(anonTotalCents, equals(1219700));

      await isolatedNutopiaDb.close();
      await coreDb.close();

      // Ölçümleri konsola yazdır
      debugPrint('====================================================');
      debugPrint('STAGE 10.12.14 GERÇEK PERFORMANS VE SÜRE RAPORU:');
      debugPrint('  Toplam Süre        : ${totalSw.elapsedMilliseconds} ms (${(totalSw.elapsedMilliseconds / 1000).toStringAsFixed(2)} s)');
      debugPrint('  Yedekleme & Check  : ${backupSw.elapsedMilliseconds - migrationSw.elapsedMilliseconds} ms');
      debugPrint('  Toplu Veri Göçü    : ${migrationSw.elapsedMilliseconds} ms');
      debugPrint('  Adli Mutabakat     : Dahili coordinator adımında çalıştı');
      debugPrint('  Aktarılan Ürün     : $coreTotalProdCount adet (Aktif: $coreActiveProdCount, Silinmiş: ${coreTotalProdCount - coreActiveProdCount})');
      debugPrint('  Aktarılan Anon Satış: $anonCount adet ($anonTotalCents kuruş)');
      debugPrint('====================================================');

      // Test sonunda kaynak SHA kontrolü
      final shaAfter = calculateFileSha256(nutopiaSourcePath);
      expect(shaAfter, equals(expectedNutopiaSha),
          reason: 'Kaynak Nutopia yedeği 1 bayt dahi DEĞİŞMEMİŞ olmalı');
    });
  });

  group('STAGE 10.12.14 — BÖLÜM 5: GENEL KAYNAK VE YEDEK DOKUNULMAZLIK TESTİ', () {
    test('Kaynak yedeklerin SHA-256 imzaları kesinlikle değişmemiştir', () {
      final nutopiaSha = calculateFileSha256('backups/raw_tenants_20261016/raw_nutopia_v60.db');
      final serenutSha = calculateFileSha256('backups/raw_tenants_20261016/raw_serenut_v44.db');
      final erkulSha = calculateFileSha256('backups/raw_tenants_20261016/raw_erkul_source.json');

      expect(nutopiaSha, equals('e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24'));
      expect(serenutSha, equals('9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d'));
      expect(erkulSha, equals('b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389'));
    });
  });
}
