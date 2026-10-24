// test/core_next/stage10_9_2_startup_safety_test.dart
// SERENUT OS — STAGE 10.9.2
// Startup Safety, Fault-Tolerant Housekeeping & Fail-Closed Integrity Tests

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

import 'package:serenutos/infrastructure/bootstrap/app_bootstrap.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/services/integrity_check_service.dart';
import 'package:serenutos/infrastructure/services/remote_config_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/printing/printing_runtime.dart';
import 'package:serenutos/infrastructure/services/crash_recovery_manager.dart';
import 'package:serenutos/infrastructure/repositories/sms_log_repository.dart';
import 'package:serenutos/domain/hardware/hardware_device.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/providers/database_provider.dart';
import 'package:serenutos/providers/hardware_devices_provider.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/sms_provider.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';

class TestIntegrityCheckService implements IntegrityCheckService {
  final bool isHealthy;
  final bool repairSucceeds;
  final Duration? delay;

  TestIntegrityCheckService({
    this.isHealthy = true,
    this.repairSucceeds = true,
    this.delay,
  });

  @override
  Future<IntegrityReport> runDiagnostics() async {
    if (delay != null) {
      await Future.delayed(delay!);
    }
    return IntegrityReport(
      isDatabaseHealthy: isHealthy,
      isFileSystemHealthy: isHealthy,
      issues: isHealthy ? const [] : const ['CORRUPT_DATABASE_HEADER'],
      logs: isHealthy ? 'PASS' : 'FAIL',
    );
  }

  @override
  Future<bool> attemptDatabaseRepair() async => repairSucceeds;
}

class TestRemoteConfigService extends RemoteConfigService {
  TestRemoteConfigService(SharedPreferences prefs) : super(prefs, ApiClient());

  @override
  Future<void> fetchAndActivate() async {}

  @override
  bool isSharedHardwareEnabled() => false;
}

class TestCrashRecoveryManager extends CrashRecoveryManager {
  @override
  Future<bool> checkForCrashOnStartup() async => false;

  @override
  Future<int> recoverInterruptedSyncJobs() async => 0;
}

class TestPrintingRuntime implements PrintingRuntime {
  @override
  Future<PrintRecoverySummary> start() async =>
      const PrintRecoverySummary(safelyRequeued: 0, awaitingUserCheck: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestHardwareDevicesNotifier extends HardwareDevicesNotifier {
  @override
  Future<List<HardwareDevice>> build() async => const [];
}

class TestSmsLogRepository extends SmsLogRepository {
  final bool shouldThrow;
  final Duration? delay;

  TestSmsLogRepository(DatabaseManager dbManager, {this.shouldThrow = false, this.delay})
      : super(dbManager);

  @override
  Future<void> resetStuckJobs() async {
    if (delay != null) {
      await Future.delayed(delay!);
    }
    if (shouldThrow) {
      throw StateError('Simulated SMS database lock or query failure');
    }
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String legacyDbPath;
  late String coreDbPath;
  late String backupDirPath;
  late Database legacyDb;
  late CoreAppDatabase coreDb;

  setUp(() async {
    CoreNextBootstrapCoordinator.resetExecutionLock();
    SharedPreferences.setMockInitialValues({});

    tempDir = await Directory.systemTemp.createTemp('stage10_9_2_startup_');
    legacyDbPath = p.join(tempDir.path, 'serenut_pos.db');
    coreDbPath = p.join(tempDir.path, 'serenut_core_v2.db');
    backupDirPath = p.join(tempDir.path, 'SerenutBackups');

    DatabaseManager.overrideDatabasePath = legacyDbPath;

    legacyDb = await openDatabase(
      legacyDbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE users (id TEXT PRIMARY KEY, name TEXT);');
        await db.execute('CREATE TABLE settings (id TEXT PRIMARY KEY, business_name TEXT);');
        await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT, quantity REAL DEFAULT 0, min_stock REAL DEFAULT 0, purchase_price REAL DEFAULT 0, price REAL DEFAULT 0, is_active INTEGER DEFAULT 1, is_deleted INTEGER DEFAULT 0);');
        await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT, balance REAL DEFAULT 0);');
      },
    );

    coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: coreDbPath);
  });

  tearDown(() async {
    CoreNextBootstrapCoordinator.resetExecutionLock();
    DatabaseManager.overrideDatabasePath = null;
    DatabaseManager.instance.reset();
    try {
      await legacyDb.close();
      await coreDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('STAGE 10.9.2 — Görev A: Startup Safety & Bounded Timeouts', () {
    test('1. Sağlıklı Başlangıç: Tüm kontroller geçer, Legacy akışı korunur', () async {
      final prefs = await SharedPreferences.getInstance();
      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          integrityCheckServiceProvider.overrideWithValue(TestIntegrityCheckService(isHealthy: true)),
          remoteConfigServiceProvider.overrideWithValue(TestRemoteConfigService(prefs)),
          crashRecoveryManagerProvider.overrideWithValue(TestCrashRecoveryManager()),
          printingRuntimeProvider.overrideWithValue(TestPrintingRuntime()),
          hardwareDevicesProvider.overrideWith(TestHardwareDevicesNotifier.new),
          smsLogRepositoryProvider.overrideWithValue(TestSmsLogRepository(DatabaseManager.instance)),
          dbGatewayProvider.overrideWithValue(DbGatewayImpl.raw(legacyDb)),
          databaseProvider.overrideWith((ref) => Future.value(legacyDb)),
          coreNextBootstrapCoordinatorProvider.overrideWithValue(coordinator),
          coreNextMigrationRunnerProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      final result = await AppBootstrap.runStartupDiagnostics(container);
      expect(result.isSuccess, true);
      expect(result.errorMessage, isNull);

      final salesEngineEnabled = container.read(coreNextSalesEngineEnabledProvider);
      expect(salesEngineEnabled, false, reason: 'Varsayılan feature flag kapalı kalmalıdır.');
    });

    test('2. Fail-Closed Güvencesi: Veritabanı bozuk ve tamir edilemezse açılış durdurulur', () async {
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          integrityCheckServiceProvider.overrideWithValue(
            TestIntegrityCheckService(isHealthy: false, repairSucceeds: false),
          ),
          remoteConfigServiceProvider.overrideWithValue(TestRemoteConfigService(prefs)),
          crashRecoveryManagerProvider.overrideWithValue(TestCrashRecoveryManager()),
          printingRuntimeProvider.overrideWithValue(TestPrintingRuntime()),
          hardwareDevicesProvider.overrideWith(TestHardwareDevicesNotifier.new),
          smsLogRepositoryProvider.overrideWithValue(TestSmsLogRepository(DatabaseManager.instance)),
          dbGatewayProvider.overrideWithValue(DbGatewayImpl.raw(legacyDb)),
          databaseProvider.overrideWith((ref) => Future.value(legacyDb)),
        ],
      );
      addTearDown(container.dispose);

      final result = await AppBootstrap.runStartupDiagnostics(container);
      expect(result.isSuccess, false);
      expect(result.errorReference, startsWith('ERR-'));
      expect(result.errorMessage, contains('Veritabanı veya sistem bileşenleri hazırlanırken bir sorun oluştu'));
    });

    test('3. Hata İzolasyonu: SMS süpürme hatası veya kilidi açılışı durdurmaz ve çökertmez', () async {
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          integrityCheckServiceProvider.overrideWithValue(TestIntegrityCheckService(isHealthy: true)),
          remoteConfigServiceProvider.overrideWithValue(TestRemoteConfigService(prefs)),
          crashRecoveryManagerProvider.overrideWithValue(TestCrashRecoveryManager()),
          printingRuntimeProvider.overrideWithValue(TestPrintingRuntime()),
          hardwareDevicesProvider.overrideWith(TestHardwareDevicesNotifier.new),
          smsLogRepositoryProvider.overrideWithValue(
            TestSmsLogRepository(DatabaseManager.instance, shouldThrow: true),
          ),
          dbGatewayProvider.overrideWithValue(DbGatewayImpl.raw(legacyDb)),
          databaseProvider.overrideWith((ref) => Future.value(legacyDb)),
        ],
      );
      addTearDown(container.dispose);

      // SMS hatası açılışı engellememeli, isSuccess true olmalıdır
      final result = await AppBootstrap.runStartupDiagnostics(container);
      expect(result.isSuccess, true);
    });

    test('4. Zaman Aşımı Muhafızı: Ağır/kilitli SMS işlemi bounded timeout (3s) ile açılışı kilitletmez', () async {
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          integrityCheckServiceProvider.overrideWithValue(TestIntegrityCheckService(isHealthy: true)),
          remoteConfigServiceProvider.overrideWithValue(TestRemoteConfigService(prefs)),
          crashRecoveryManagerProvider.overrideWithValue(TestCrashRecoveryManager()),
          printingRuntimeProvider.overrideWithValue(TestPrintingRuntime()),
          hardwareDevicesProvider.overrideWith(TestHardwareDevicesNotifier.new),
          smsLogRepositoryProvider.overrideWithValue(
            TestSmsLogRepository(DatabaseManager.instance, delay: const Duration(seconds: 5)),
          ),
          dbGatewayProvider.overrideWithValue(DbGatewayImpl.raw(legacyDb)),
          databaseProvider.overrideWith((ref) => Future.value(legacyDb)),
        ],
      );
      addTearDown(container.dispose);

      final stopwatch = Stopwatch()..start();
      final result = await AppBootstrap.runStartupDiagnostics(container);
      stopwatch.stop();

      // Zaman aşımı 3s civarında tetiklenmeli ve 5s'lik tam gecikmeyi beklemeden güvenle açılmalıdır
      expect(result.isSuccess, true);
      expect(stopwatch.elapsed.inSeconds, lessThan(5));
    });

    test('5. Kalıcı Blokaj Koruması: Core Next failedBlocked ise yeniden denenmez, Legacy korunur', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        CoreNextBootstrapCoordinator.prefKeyMigrationState,
        CoreNextMigrationState.failedBlocked.value,
      );

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          integrityCheckServiceProvider.overrideWithValue(TestIntegrityCheckService(isHealthy: true)),
          remoteConfigServiceProvider.overrideWithValue(TestRemoteConfigService(prefs)),
          crashRecoveryManagerProvider.overrideWithValue(TestCrashRecoveryManager()),
          printingRuntimeProvider.overrideWithValue(TestPrintingRuntime()),
          hardwareDevicesProvider.overrideWith(TestHardwareDevicesNotifier.new),
          smsLogRepositoryProvider.overrideWithValue(TestSmsLogRepository(DatabaseManager.instance)),
          dbGatewayProvider.overrideWithValue(DbGatewayImpl.raw(legacyDb)),
          databaseProvider.overrideWith((ref) => Future.value(legacyDb)),
          coreNextBootstrapCoordinatorProvider.overrideWithValue(coordinator),
        ],
      );
      addTearDown(container.dispose);

      final result = await AppBootstrap.runStartupDiagnostics(container);
      expect(result.isSuccess, true);
      expect(await coordinator.getPersistentState(), CoreNextMigrationState.failedBlocked);

      final salesEngineEnabled = container.read(coreNextSalesEngineEnabledProvider);
      expect(salesEngineEnabled, false);
    });
  });
}
