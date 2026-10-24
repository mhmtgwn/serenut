// test/core_next/stage10_12_26_pilot_cutover_gate_test.dart
// SERENUT OS — STAGE 10.12.26
// FAIL-CLOSED PILOT CUTOVER GATE & APP_BOOTSTRAP ENTEGRASYON TESTLERİ
// ignore_for_file: avoid_relative_lib_imports

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/app_bootstrap.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/providers/repository_providers.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_customer_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_product_repository.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDocDir;
  MockPathProviderPlatform(this.tempDocDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDocDir;

  @override
  Future<String?> getApplicationSupportPath() async => tempDocDir;

  @override
  Future<String?> getTemporaryPath() async => tempDocDir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testTempDir;
  late String legacyDbPath;
  late String coreNextDbPath;
  late String backupFilePath;
  const String testTenantId = 'tenant_nutopia_pos_001';

  Future<void> createValidLegacyDb() async {
    final db = await DatabaseManager.instance.getDatabase();
    await db.update('settings', {'business_name': 'Nutopia Pos'});
    await db.insert('products', {
      'id': 'p-legacy-1',
      'name': 'Legacy Fındık',
      'price': 150.0,
      'quantity': 20,
      'category': 'Genel',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    await db.insert('customers', {
      'id': 'c-legacy-1',
      'name': 'Legacy Müşteri',
      'balance': -100.0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> createValidCoreNextDb(String path, {String tenantId = testTenantId, int userVersion = 3}) async {
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: userVersion),
    );
    await db.execute('PRAGMA user_version = $userVersion;');
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at INTEGER
      );
    ''');
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT,
        barcode TEXT,
        price_cents INTEGER,
        stock_quantity REAL,
        category_id TEXT,
        is_deleted INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1
      );
    ''');
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT,
        color TEXT,
        icon TEXT,
        is_deleted INTEGER DEFAULT 0,
        created_at INTEGER,
        updated_at INTEGER
      );
    ''');
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT,
        balance_cents INTEGER DEFAULT 0
      );
    ''');
    await db.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        receipt_no TEXT,
        total_amount_cents INTEGER,
        created_at INTEGER
      );
    ''');
    await db.execute('''
      CREATE TABLE ledger_entries (
        id TEXT PRIMARY KEY,
        customer_id TEXT,
        amount_cents INTEGER,
        entry_type TEXT,
        created_at INTEGER
      );
    ''');
    await db.execute('''
      CREATE TABLE sync_events (
        id TEXT PRIMARY KEY,
        entity_name TEXT,
        operation TEXT,
        status TEXT
      );
    ''');

    await db.insert('app_settings', {
      'key': 'tenant_id',
      'value': tenantId,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    await db.insert('app_settings', {
      'key': 'legacy_migration_completed',
      'value': 'true',
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    await db.insert('products', {
      'id': 'p-core-1',
      'name': 'Core Next Ürün',
      'barcode': '869099',
      'price_cents': 20000,
      'stock_quantity': 50.0,
    });
    await db.insert('customers', {
      'id': 'c-core-1',
      'name': 'Core Next Müşteri',
      'balance_cents': -5000,
    });
    await db.close();
  }

  PilotRepositoryOverrideGenerator testOverrideGenerator() {
    return ({
      required requestedTenantId,
      required legacyDbPath,
      required targetDbPath,
      required enableSalesEngine,
      dbFactory,
    }) async {
      final coordinator = const DualDatabaseRoutingCoordinator();
      final routing = await coordinator.resolveAndOpen(
        requestedTenantId: requestedTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: targetDbPath,
        migrationStateCompleted: true,
        dbFactory: dbFactory,
      );
      if (!routing.isSuccess || routing.targetDatabase == null) return null;
      return DualDatabaseRoutingCoordinator.createRepositoryOverrides(
        coreDb: routing.targetDatabase!,
        enableSalesEngine: enableSalesEngine,
      );
    };
  }

  setUp(() async {
    testTempDir = await Directory.systemTemp.createTemp('serenut_pilot_gate_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(testTempDir.path);

    final dbsDir = Directory(p.join(testTempDir.path, 'databases'));
    await dbsDir.create(recursive: true);

    legacyDbPath = p.join(dbsDir.path, 'serenut_pos.db');
    coreNextDbPath = p.join(dbsDir.path, 'serenut_core_v2.db');
    backupFilePath = p.join(testTempDir.path, 'serenut_pos_backup_mock.db');

    // Sahte geçerli yedek dosyası oluştur
    final backupFile = File(backupFilePath);
    await backupFile.writeAsBytes(List.filled(1024, 1));

    DatabaseManager.overrideDatabasePath = legacyDbPath;
    DatabaseManager.overrideCoreNextDatabasePath = coreNextDbPath;
    DatabaseManager.instance.reset();
  });

  tearDown(() async {
    try {
      await DatabaseManager.instance.close();
    } catch (_) {}
    DatabaseManager.overrideDatabasePath = null;
    DatabaseManager.overrideCoreNextDatabasePath = null;
    DatabaseManager.instance.reset();
    try {
      if (await testTempDir.exists()) {
        await testTempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Stage 10.12.26 — Pilot Cutover Gate Test Matrix', () {
    const gate = PilotCutoverGate();

    test('1. Flag kapalıyken (varsayılan): fail-closed döner, legacy akış korunur', () async {
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: false,
      });
      final prefs = await SharedPreferences.getInstance();

      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: testTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: coreNextDbPath,
      );

      expect(result.isPilotActive, isFalse);
      expect(result.status, equals(PilotGateStatus.disabledByDefault));
      expect(result.overrides, isEmpty);
      expect(result.reason, contains('core_next_pilot_enabled = false'));
    });

    test('2. Flag eksik veya null olduğunda: fail-closed döner', () async {
      SharedPreferences.setMockInitialValues({}); // Boş yapılandırma
      final prefs = await SharedPreferences.getInstance();

      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: testTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: coreNextDbPath,
      );

      expect(result.isPilotActive, isFalse);
      expect(result.status, equals(PilotGateStatus.disabledByDefault));
      expect(result.overrides, isEmpty);
    });

    test('3. Acil durum devre kesici (kill switch) aktif olduğunda: geçiş derhal engellenir', () async {
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        PilotCutoverGate.prefKeyKillSwitch: true,
      });
      final prefs = await SharedPreferences.getInstance();

      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: testTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: coreNextDbPath,
      );

      expect(result.isPilotActive, isFalse);
      expect(result.status, equals(PilotGateStatus.blockedKillSwitch));
      expect(result.overrides, isEmpty);
      expect(result.reason, contains('kill_switch'));
    });

    test('4. Migration durumu tamamlanmamışsa: cutover engellenir', () async {
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'in_progress',
      });
      final prefs = await SharedPreferences.getInstance();

      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: testTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: coreNextDbPath,
      );

      expect(result.isPilotActive, isFalse);
      expect(result.status, equals(PilotGateStatus.blockedMigrationNotCompleted));
      expect(result.reason, contains('Core Next migration tamamlanmamış'));
    });

    test('5. Yedekleme kanıtı eksikse: fail-closed durdurulur', () async {
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
        // 'last_backup_date' ve 'core_next_migration_backup_path' eksik
      });
      final prefs = await SharedPreferences.getInstance();

      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: testTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: coreNextDbPath,
      );

      expect(result.isPilotActive, isFalse);
      expect(result.status, equals(PilotGateStatus.blockedMissingBackupProof));
      expect(result.reason, contains('yedekleme kanıtı bulunamadı'));
    });

    test('6. Hedef Core Next veritabanı dosyası yoksa: fail-closed durdurulur', () async {
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
        'last_backup_date': DateTime.now().toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();

      expect(await File(coreNextDbPath).exists(), isFalse);

      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: testTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: coreNextDbPath,
      );

      expect(result.isPilotActive, isFalse);
      expect(result.status, equals(PilotGateStatus.blockedTargetDatabaseNotFound));
      expect(result.reason, contains('bulunamadı'));
    });

    test('7. Hedef Core Next veritabanı 0 bayt veya bozuk header ise: fail-closed durdurulur', () async {
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
        'last_backup_date': DateTime.now().toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();

      // 100 baytlık geçersiz dosya
      await File(coreNextDbPath).writeAsBytes(List.filled(100, 77));

      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: testTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: coreNextDbPath,
      );

      expect(result.isPilotActive, isFalse);
      expect(result.status, equals(PilotGateStatus.blockedTargetDatabaseCorrupt));
    });

    test('8. Hedef şema sürüm uyumsuzluğu (user_version != 3): fail-closed durdurulur', () async {
      await createValidLegacyDb();
      await createValidCoreNextDb(coreNextDbPath, userVersion: 2); // Sürüm 2 (Uyumsuz!)

      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
        'last_backup_date': DateTime.now().toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();

      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: testTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: coreNextDbPath,
      );

      expect(result.isPilotActive, isFalse);
      expect(result.status, equals(PilotGateStatus.blockedTargetSchemaMismatch));
      expect(result.reason, contains('şema sürümü uyumsuz'));
    });

    test('9. Tenant uyuşmazlığında: fail-closed engellenir', () async {
      await createValidLegacyDb();
      await createValidCoreNextDb(coreNextDbPath, tenantId: 'tenant_nutopia_pos_001');

      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
        'last_backup_date': DateTime.now().toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();

      // Farklı bir tenant talep ediliyor
      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: 'tenant_erkul_ceyiz_999',
        legacyDbPath: legacyDbPath,
        targetDbPath: coreNextDbPath,
      );

      expect(result.isPilotActive, isFalse);
      expect(result.status, equals(PilotGateStatus.blockedTenantMismatch));
      expect(result.reason, contains('Tenant ID uyuşmazlığı'));
    });

    test('10. Zaman aşımı koruması (Timeout): 10ms timeout verildiğinde fail-closed döner', () async {
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
        'last_backup_date': DateTime.now().toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      await createValidLegacyDb();
      await createValidCoreNextDb(coreNextDbPath);

      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: testTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: coreNextDbPath,
        timeout: const Duration(microseconds: 1), // Hemen timeout tetikleyecek sınır
      );

      expect(result.isPilotActive, isFalse);
      expect(result.status, equals(PilotGateStatus.blockedTimeout));
      expect(result.reason, contains('zaman aşımına uğradı'));
    });

    test('11. Tüm koşullar sağlandığında: pilot aktif olur, override listesi üretilir ve sales engine legacy kalır', () async {
      await createValidLegacyDb();
      await createValidCoreNextDb(coreNextDbPath, tenantId: testTenantId);

      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
        'last_backup_date': DateTime.now().toIso8601String(),
        CoreNextBootstrapCoordinator.prefKeyBackupPath: backupFilePath,
      });
      final prefs = await SharedPreferences.getInstance();

      final pilotGateWithGenerator = PilotCutoverGate(
        overrideGenerator: testOverrideGenerator(),
      );

      final result = await pilotGateWithGenerator.evaluate(
        prefs: prefs,
        requestedTenantId: testTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: coreNextDbPath,
        enableSalesEngine: false, // Kesin güvenlik kuralı: false kalmalı
      );

      expect(result.isPilotActive, isTrue);
      expect(result.status, equals(PilotGateStatus.pilotActiveApproved));
      expect(result.overrides.length, equals(3)); // customer, product, financial_transaction (sale repo yok)
    });

    test('12. AppBootstrap.initPreApp() gerçek entegrasyonu: Varsayılan kapalı durumda legacy repolar bağlanır', () async {
      await createValidLegacyDb();
      SharedPreferences.setMockInitialValues({}); // Default: bayrak yok

      final bootstrap = await AppBootstrap.initPreApp();
      expect(bootstrap.pilotGateResult, isNotNull);
      expect(bootstrap.pilotGateResult!.isPilotActive, isFalse);

      // ProviderContainer ayağa kaldırıp repoların legacy olduğunu doğrula
      final container = ProviderContainer(
        overrides: bootstrap.overrides,
        observers: bootstrap.observers,
      );

      final customerRepo = await container.read(customerRepositoryProvider.future);
      final productRepo = await container.read(productRepositoryProvider.future);

      expect(customerRepo is SqliteCustomerRepository, isTrue);
      expect(productRepo is SqliteProductRepository, isTrue);

      final customers = await customerRepo.findAll();
      expect(customers.any((c) => c.name == 'Legacy Müşteri'), isTrue);

      container.dispose();
    });

    test('13. AppBootstrap.initPreApp() gerçek entegrasyonu: Pilot onaylandığında Core Next repolar bağlanır', () async {
      await createValidLegacyDb();
      await createValidCoreNextDb(coreNextDbPath, tenantId: testTenantId);

      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
        'last_backup_date': DateTime.now().toIso8601String(),
        CoreNextBootstrapCoordinator.prefKeyBackupPath: backupFilePath,
      });

      final pilotGateWithGenerator = PilotCutoverGate(
        overrideGenerator: testOverrideGenerator(),
      );

      final bootstrap = await AppBootstrap.initPreApp(
        pilotGate: pilotGateWithGenerator,
        requestedTenantId: testTenantId,
      );

      expect(bootstrap.pilotGateResult, isNotNull);
      expect(bootstrap.pilotGateResult!.isPilotActive, isTrue);
      expect(bootstrap.pilotGateResult!.status, equals(PilotGateStatus.pilotActiveApproved));

      // ProviderContainer ayağa kaldırıp repoların Core Next olduğunu doğrula
      final container = ProviderContainer(
        overrides: bootstrap.overrides,
        observers: bootstrap.observers,
      );

      final customerRepo = await container.read(customerRepositoryProvider.future);
      final productRepo = await container.read(productRepositoryProvider.future);

      expect(customerRepo is CoreNextCustomerRepository, isTrue);
      expect(productRepo is CoreNextProductRepository, isTrue);

      final products = await productRepo.findAll();
      expect(products.any((p) => p.name == 'Core Next Ürün'), isTrue);

      container.dispose();
    });
  });
}
