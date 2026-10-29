// test/core_next/stage10_9_7_startup_restore_rollback_test.dart
// SERENUT OS — STAGE 10.9.7
// Gerçek Başlangıç Entegrasyonu, Yedekleme/Geri Yükleme Tatbikatı ve Rollback Kapısı

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
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/printing/printing_runtime.dart';
import 'package:serenutos/infrastructure/services/crash_recovery_manager.dart';
import 'package:serenutos/domain/hardware/hardware_device.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/providers/database_provider.dart';
import 'package:serenutos/providers/hardware_devices_provider.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/sms_provider.dart';
import 'package:serenutos/infrastructure/repositories/sms_log_repository.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';
import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart';

class FakeIntegrityCheckService implements IntegrityCheckService {
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

class FakeRemoteConfigService extends RemoteConfigService {
  FakeRemoteConfigService(SharedPreferences prefs) : super(prefs, ApiClient());

  @override
  Future<void> fetchAndActivate() async {}

  @override
  bool isSharedHardwareEnabled() => false;
}

class FakeCrashRecoveryManager extends CrashRecoveryManager {
  @override
  Future<bool> checkForCrashOnStartup() async => false;

  @override
  Future<int> recoverInterruptedSyncJobs() async => 0;
}

class FakePrintingRuntime implements PrintingRuntime {
  @override
  Future<PrintRecoverySummary> start() async =>
      const PrintRecoverySummary(safelyRequeued: 0, awaitingUserCheck: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSmsLogRepository extends SmsLogRepository {
  FakeSmsLogRepository() : super(DatabaseManager.instance);

  @override
  Future<void> resetStuckJobs() async {}
}

class FakeHardwareDevicesNotifier extends HardwareDevicesNotifier {
  @override
  Future<List<HardwareDevice>> build() async => const [];
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

  Future<void> populateLegacyDatabase(Database db) async {
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
        name TEXT NOT NULL,
        category TEXT,
        category_id TEXT,
        price REAL NOT NULL,
        price_minor INTEGER,
        cost_price REAL,
        cost_price_minor INTEGER,
        vat_rate INTEGER DEFAULT 20,
        unit TEXT DEFAULT 'piece',
        quantity REAL DEFAULT 0,
        min_stock REAL DEFAULT 5,
        is_active INTEGER DEFAULT 1,
        created_at TEXT,
        updated_at TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        balance REAL DEFAULT 0.0,
        balance_minor INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1,
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
        subtotal_minor INTEGER,
        FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id)
      );
    ''');

    await db.execute('''
      CREATE TABLE sale_payments (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        payment_type TEXT NOT NULL,
        amount REAL,
        amount_minor INTEGER,
        reference_note TEXT,
        created_at TEXT,
        FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE
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
        created_at TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers (id)
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

    // Başlangıç verilerini tohumla
    await db.insert('users', {
      'id': 'usr-admin',
      'username': 'admin',
      'name': 'Yönetici',
      'role': 'admin',
      'pin_hash': '1234',
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });

    await db.insert('categories', {
      'id': 'cat-gida',
      'name': 'Gıda',
      'color_hex': '#FF0000',
      'sort_order': 1,
      'is_active': 1,
    });

    await db.insert('products', {
      'id': 'p-ekmek',
      'barcode': '8690001',
      'name': 'Somun Ekmek',
      'category': 'Gıda',
      'category_id': 'cat-gida',
      'price': 10.0,
      'price_minor': 1000,
      'cost_price': 7.0,
      'cost_price_minor': 700,
      'quantity': 100.0,
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });

    await db.insert('customers', {
      'id': 'c-ahmet',
      'name': 'Ahmet Yılmaz',
      'phone': '05551234567',
      'balance': 50.0,
      'balance_minor': 5000,
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });

    await db.insert('sales', {
      'id': 's-1001',
      'receipt_no': 'REC-1001',
      'customer_id': 'c-ahmet',
      'total_amount': 50.0,
      'total_amount_minor': 5000,
      'paid_amount': 50.0,
      'paid_amount_minor': 5000,
      'payment_method': 'cash',
      'status': 'COMPLETED',
      'created_at': DateTime.now().toIso8601String(),
    });

    await db.insert('sale_items', {
      'id': 'si-1',
      'sale_id': 's-1001',
      'product_id': 'p-ekmek',
      'product_name': 'Somun Ekmek',
      'quantity': 5.0,
      'unit_price': 10.0,
      'unit_price_minor': 1000,
      'subtotal': 50.0,
      'subtotal_minor': 5000,
    });

    await db.insert('sale_payments', {
      'id': 'sp-1',
      'sale_id': 's-1001',
      'payment_type': 'cash',
      'amount': 50.0,
      'amount_minor': 5000,
      'created_at': DateTime.now().toIso8601String(),
    });

    await db.insert('sync_outbox_v4', {
      'mutation_id': 'mut-init-1',
      'entity_type': 'sale',
      'entity_id': 's-1001',
      'operation': 'INSERT',
      'payload': '{"receipt_no": "REC-1001"}',
      'base_revision': 1,
      'state': 'PENDING',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  setUp(() async {
    CoreNextBootstrapCoordinator.resetExecutionLock();
    SharedPreferences.setMockInitialValues({});

    tempDir = await Directory.systemTemp.createTemp('stage10_9_7_test_');
    legacyDbPath = p.join(tempDir.path, 'serenut_pos.db');
    coreDbPath = p.join(tempDir.path, 'serenut_core_v2.db');
    backupDirPath = p.join(tempDir.path, 'SerenutBackups');

    DatabaseManager.overrideDatabasePath = legacyDbPath;

    legacyDb = await openDatabase(
      legacyDbPath,
      version: 60,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
        await db.rawQuery('PRAGMA journal_mode = WAL;');
      },
    );

    await populateLegacyDatabase(legacyDb);
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

  group('STAGE 10.9.7 — A: Gerçek Başlangıç Çağrı Zinciri ve Entegrasyon Testleri', () {
    test('1. AppBootstrap.runStartupDiagnostics Varsayılan Modda (Runner null) Legacy Açılışını Korur', () async {
      final prefs = await SharedPreferences.getInstance();

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        autonomousMode: true,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          integrityCheckServiceProvider.overrideWithValue(FakeIntegrityCheckService()),
          remoteConfigServiceProvider.overrideWithValue(FakeRemoteConfigService(prefs)),
          crashRecoveryManagerProvider.overrideWithValue(FakeCrashRecoveryManager()),
          printingRuntimeProvider.overrideWithValue(FakePrintingRuntime()),
          hardwareDevicesProvider.overrideWith(FakeHardwareDevicesNotifier.new),
          smsLogRepositoryProvider.overrideWithValue(FakeSmsLogRepository()),
          dbGatewayProvider.overrideWithValue(DbGatewayImpl.raw(legacyDb)),
          databaseProvider.overrideWith((ref) => Future.value(legacyDb)),
          coreNextBootstrapCoordinatorProvider.overrideWithValue(coordinator),
          coreNextMigrationRunnerProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      final diagResult = await AppBootstrap.runStartupDiagnostics(container);
      final salesEngineEnabled = container.read(coreNextSalesEngineEnabledProvider);

      expect(diagResult.isSuccess, true);
      expect(await coordinator.getPersistentState(), CoreNextMigrationState.notStarted);
      expect(salesEngineEnabled, false);
    });

    test('2. AppBootstrap.runStartupDiagnostics Runner Enjekte Edildiğinde Koordinatörü Gerçekten Çalıştırır ve Tamamlar', () async {
      final prefs = await SharedPreferences.getInstance();

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        autonomousMode: true,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          return MigrationBridgeEngine(coreDb).migrateFromLegacy(
            legacyDb,
            legacyFilePath: legacyFilePath,
            fullScope: fullScope,
          );
        },
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          integrityCheckServiceProvider.overrideWithValue(FakeIntegrityCheckService()),
          remoteConfigServiceProvider.overrideWithValue(FakeRemoteConfigService(prefs)),
          crashRecoveryManagerProvider.overrideWithValue(FakeCrashRecoveryManager()),
          printingRuntimeProvider.overrideWithValue(FakePrintingRuntime()),
          hardwareDevicesProvider.overrideWith(FakeHardwareDevicesNotifier.new),
          smsLogRepositoryProvider.overrideWithValue(FakeSmsLogRepository()),
          dbGatewayProvider.overrideWithValue(DbGatewayImpl.raw(legacyDb)),
          databaseProvider.overrideWith((ref) => Future.value(legacyDb)),
          coreNextBootstrapCoordinatorProvider.overrideWithValue(coordinator),
          coreNextMigrationRunnerProvider.overrideWithValue(
            ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
              return MigrationBridgeEngine(coreDb).migrateFromLegacy(
                legacyDb,
                legacyFilePath: legacyFilePath,
                fullScope: fullScope,
              );
            },
          ),
        ],
      );
      addTearDown(container.dispose);

      final diagResult = await AppBootstrap.runStartupDiagnostics(container);

      expect(diagResult.isSuccess, true);
      expect(await coordinator.getPersistentState(), CoreNextMigrationState.completed);

      // Hedef DB'de kayıtların varlığını doğrula
      final coreProducts = await coreDb.db.query('products');
      expect(coreProducts.length, 1);
      expect(coreProducts.first['name'], 'Somun Ekmek');
    });

    test('3. Koordinasyon Başarısız Olursa Açılış Durmaz, Legacy Modda Fail-Closed Devam Eder', () async {
      final prefs = await SharedPreferences.getInstance();

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: '/invalid/path.db', // Hatalı yedekleme yolu
        customBackupDirectory: '/invalid/backup/dir/?*:',
        prefs: prefs,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          return MigrationBridgeEngine(coreDb).migrateFromLegacy(legacyDb);
        },
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          integrityCheckServiceProvider.overrideWithValue(FakeIntegrityCheckService()),
          remoteConfigServiceProvider.overrideWithValue(FakeRemoteConfigService(prefs)),
          crashRecoveryManagerProvider.overrideWithValue(FakeCrashRecoveryManager()),
          printingRuntimeProvider.overrideWithValue(FakePrintingRuntime()),
          hardwareDevicesProvider.overrideWith(FakeHardwareDevicesNotifier.new),
          smsLogRepositoryProvider.overrideWithValue(FakeSmsLogRepository()),
          dbGatewayProvider.overrideWithValue(DbGatewayImpl.raw(legacyDb)),
          databaseProvider.overrideWith((ref) => Future.value(legacyDb)),
          coreNextBootstrapCoordinatorProvider.overrideWithValue(coordinator),
          coreNextMigrationRunnerProvider.overrideWithValue(
            ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async => false,
          ),
        ],
      );
      addTearDown(container.dispose);

      final diagResult = await AppBootstrap.runStartupDiagnostics(container);
      final salesEngineEnabled = container.read(coreNextSalesEngineEnabledProvider);

      // Uygulama açılışı kullanıcıyı engellememeli, Legacy akışı devam etmelidir
      expect(diagResult.isSuccess, true);
      expect(await coordinator.getPersistentState(), CoreNextMigrationState.failedRecoverable);
      expect(salesEngineEnabled, false);
    });
  });

  group('STAGE 10.9.7 — B: Yedekleme ve Fiziksel Geri Yükleme (Full Recovery Drill)', () {
    test('4. WAL Aktifken Alınan Yedek Ana Veritabanı Kapatılıp Taşınsa Bile Birebir Geri Yüklenir', () async {
      final prefs = await SharedPreferences.getInstance();

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        autonomousMode: true,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          return MigrationBridgeEngine(coreDb).migrateFromLegacy(
            legacyDb,
            legacyFilePath: legacyFilePath,
            fullScope: fullScope,
          );
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, true);
      expect(result.backupPath, isNotNull);

      final backupFile = File(result.backupPath!);
      expect(await backupFile.exists(), true);

      // Ana veritabanını kapat ve dosyayı simüle edilmiş çökme/kayıp için sil/taşı
      await legacyDb.close();
      final originalFile = File(legacyDbPath);
      final movedOriginalPath = p.join(tempDir.path, 'serenut_pos_lost.db');
      await originalFile.rename(movedOriginalPath);
      expect(await originalFile.exists(), false, reason: 'Ana dosya erişilemez hale getirildi.');

      // Yedeği geri yükle: Yedeği yeni konuma kopyala ve aç
      final restoredDbPath = p.join(tempDir.path, 'serenut_pos_restored.db');
      await backupFile.copy(restoredDbPath);

      final restoredDb = await openDatabase(restoredDbPath);

      // PRAGMA integrity_check ve foreign_key_check
      final integrity = await restoredDb.rawQuery('PRAGMA integrity_check;');
      expect(integrity.first.values.first, 'ok');

      final fkCheck = await restoredDb.rawQuery('PRAGMA foreign_key_check;');
      expect(fkCheck.isEmpty, true);

      // Birebir veri doğrulaması
      final restoredProds = await restoredDb.query('products');
      expect(restoredProds.length, 1);
      expect(restoredProds.first['id'], 'p-ekmek');
      expect(restoredProds.first['quantity'], 100.0);

      final restoredCusts = await restoredDb.query('customers');
      expect(restoredCusts.length, 1);
      expect(restoredCusts.first['balance_minor'], 5000);

      final restoredSales = await restoredDb.query('sales');
      expect(restoredSales.length, 1);
      expect(restoredSales.first['id'], 's-1001');
      expect(restoredSales.first['total_amount_minor'], 5000);

      final restoredPayments = await restoredDb.query('sale_payments');
      expect(restoredPayments.length, 1);
      expect(restoredPayments.first['amount_minor'], 5000);

      final restoredOutbox = await restoredDb.query('sync_outbox_v4');
      expect(restoredOutbox.length, 1);
      expect(restoredOutbox.first['mutation_id'], 'mut-init-1');

      await restoredDb.close();
    });
  });

  group('STAGE 10.9.7 — C: Legacy Geri Dönüş ve Çift Yönlü Mutabakat (Rollback Drill)', () {
    test('5. Core Next Üzerindeki Yeni İşlemler ReverseMigrationEngine ile Legacy Tablolarına Kayıpsız Geri Aktarılır', () async {
      // 1. Önce Legacy'den Core Next'e geçiş
      final migrationReport = await MigrationBridgeEngine(coreDb).migrateFromLegacy(
        legacyDb,
        legacyFilePath: legacyDbPath,
        fullScope: true,
      );
      expect(migrationReport.isSuccess, true);

      // 2. Core Next üzerinde yeni bir satış ve ödeme yap
      final hwWorker = HardwareWorker();
      await hwWorker.initialize();
      final ledgerRepo = SqliteLedgerRepository(coreDb.db);
      final ledgerService = LedgerService(ledgerRepo);

      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        hardwareWorker: hwWorker,
        ledgerService: ledgerService,
        defaultActor: ActorContext.testManager,
      );

      final pEkmek = ProductEntity(
        id: 'p-ekmek',
        name: 'Somun Ekmek',
        barcode: '8690001',
        price: const MoneyCents(1000), // 10.00 TL
        costPrice: const MoneyCents(700),
        vatRate: 20,
        stockQuantity: 100,
        updatedAt: DateTime.now(),
      );

      final salesNotifier = CoreSalesFlowNotifier(checkoutUseCase);
      salesNotifier.addProduct(pEkmek, quantity: 2); // 20.00 TL
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.creditCard, amount: MoneyCents(2000)),
      ]);

      final newSale = await salesNotifier.completeCheckout(
        receiptNo: 'REC-CORE-999',
        storeTitle: 'Test Store',
      );
      expect(newSale.total.value, 2000);

      // 3. Rollback Tatbikatı: ReverseMigrationEngine.rollbackToLegacy çalıştır
      final rollbackReport = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreDb,
      );
      expect(rollbackReport.isSuccess, true);

      // 4. Legacy veritabanında Core Next üzerinde yapılan yeni satışın varlığını doğrula
      final legSales = await legacyDb.query('sales', where: 'receipt_no = ?', whereArgs: ['REC-CORE-999']);
      expect(legSales.isNotEmpty, true, reason: 'Yeni satış Legacy sales tablosuna aktarılmalıdır.');
      expect(legSales.first['total_amount_minor'], 2000);

      final legItems = await legacyDb.query('sale_items', where: 'sale_id = ?', whereArgs: [newSale.id]);
      expect(legItems.isNotEmpty, true);
      expect(legItems.first['quantity'], 2.0);

      // Stok 100'den 98'e güncellenmiş olmalıdır
      final legProd = await legacyDb.query('products', where: 'id = ?', whereArgs: ['p-ekmek']);
      expect(legProd.first['quantity'], 98.0);

      // 5. İkinci Kez Rollback Çalıştırıldığında Mükerrer Veri Oluşmamalıdır (Idempotency)
      final rollbackReport2 = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreDb,
      );
      expect(rollbackReport2.isSuccess, true);

      final legSalesCount = await legacyDb.rawQuery('SELECT COUNT(*) as cnt FROM sales;');
      expect((legSalesCount.first['cnt'] as num).toInt(), 2); // 1 orijinal + 1 yeni satış
    });
  });
}
