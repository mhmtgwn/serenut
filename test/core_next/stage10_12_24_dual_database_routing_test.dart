// test/core_next/stage10_12_24_dual_database_routing_test.dart
// SERENUT OS — STAGE 10.12.24
// ÇİFT VERİTABANI MİMARİSİ VE GÜVENLİ CORE NEXT ROUTING TEST PAKETİ
// ignore_for_file: avoid_relative_lib_imports

@Timeout(Duration(minutes: 7))
library;

import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_customer_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_payment_repository.dart';
import 'package:serenutos/infrastructure/database/schema/db_schema.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart';
import '../../core_next/client_core/lib/infrastructure/database/schema_definitions.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_customer_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_product_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_financial_transaction_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const rawNutopiaPath = 'backups/raw_tenants_20261016/raw_nutopia_v60.db';
  const expectedSourceHash =
      'e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24';

  group('STAGE 10.12.24 — Bölüm 1: Değişmez Güvenlik & Kaynak Hash Doğrulaması', () {
    test('1.1: Kaynak Nutopia DB salt okunur ve SHA-256 imzası bozulmamış olmalı', () async {
      final sourceFile = File(rawNutopiaPath);
      expect(await sourceFile.exists(), isTrue, reason: 'Kaynak nutopia v60 DB mevcut olmalı');
      final bytes = await sourceFile.readAsBytes();
      final actualHash = sha256.convert(bytes).toString();
      expect(actualHash.toLowerCase(), equals(expectedSourceHash),
          reason: 'Kaynak DB SHA-256 hash değeri kesinlikle değişmemiş olmalıdır');
    });

    test('1.2: Üretim varsayılan bayrakları güvenle kapalı olmalı', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final runner = container.read(coreNextMigrationRunnerProvider);
      final salesEngine = container.read(coreNextSalesEngineEnabledProvider);

      expect(runner, isNull, reason: 'coreNextMigrationRunnerProvider varsayılanı NULL kalmalıdır');
      expect(DatabaseManager.databaseRoutingHook, isNull,
          reason: 'DatabaseManager.databaseRoutingHook varsayılanı NULL kalmalıdır');
      expect(salesEngine, isFalse,
          reason: 'coreNextSalesEngineEnabledProvider varsayılanı FALSE kalmalıdır');
    });
  });

  group('STAGE 10.12.24 — Bölüm 2: Çift Veritabanı Yönlendirme ve Şema Sınırı Doğrulaması', () {
    late Directory tempDir;
    late String isolatedLegacyPath;
    late String isolatedTargetPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage10_12_24_dual_db_');
      isolatedLegacyPath = p.join(tempDir.path, 'legacy_serenut_pos.db');
      isolatedTargetPath = p.join(tempDir.path, 'serenut_core_v2.db');

      // Authentic Nutopia source copy
      final sourceBytes = await File(rawNutopiaPath).readAsBytes();
      await File(isolatedLegacyPath).writeAsBytes(sourceBytes);

      DatabaseManager.instance.reset();
      DatabaseManager.overrideDatabasePath = null;
      DatabaseManager.databaseRoutingHook = null;
    });

    tearDown(() async {
      DatabaseManager.instance.reset();
      DatabaseManager.overrideDatabasePath = null;
      DatabaseManager.databaseRoutingHook = null;
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('2.1 (Senaryo 1): Varsayılan legacy açılışında mevcut şema sürümü ve repository davranışı korunur', () async {
      DatabaseManager.overrideDatabasePath = isolatedLegacyPath;
      final db = await DatabaseManager.instance.getDatabase();
      expect(db.isOpen, isTrue);

      // Verify PRAGMA user_version is 60
      final vRes = await db.rawQuery('PRAGMA user_version;');
      expect((vRes.first.values.first as num).toInt(), equals(60));

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final custRepo = await container.read(customerRepositoryProvider.future);
      expect(custRepo, isA<SqliteCustomerRepository>());

      final prodRepo = await container.read(productRepositoryProvider.future);
      expect(prodRepo, isA<SqliteProductRepository>());

      final finRepo = await container.read(financialTransactionRepositoryProvider.future);
      expect(finRepo, isA<SqliteFinancialTransactionRepository>());

      final saleRepo = await container.read(saleRepositoryProvider.future);
      expect(saleRepo, isA<SqliteSaleRepository>());

      // Authentic active customers in Nutopia DB
      final customers = await custRepo.findAll();
      expect(customers.length, equals(576));

      // Connected to isolated legacy path
      final dbList = await db.rawQuery('PRAGMA database_list;');
      final mainDbPath = dbList.first['file'] as String;
      expect(p.canonicalize(mainDbPath), equals(p.canonicalize(isolatedLegacyPath)));

      await db.close();
    });

    test('2.2 (Senaryo 2): Core Next hedefi doğru şema açılış yolundan açılır', () async {
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      expect(coreDb.db.isOpen, isTrue);

      final vRes = await coreDb.db.rawQuery('PRAGMA user_version;');
      expect((vRes.first.values.first as num).toInt(), equals(CoreSchemaDefinitions.schemaVersion));
      expect(CoreSchemaDefinitions.schemaVersion, equals(3));

      // Check required Core Next tables
      final tables = (await coreDb.db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'].toString())
          .toSet();

      expect(tables.contains('products'), isTrue);
      expect(tables.contains('customers'), isTrue);
      expect(tables.contains('sales'), isTrue);
      expect(tables.contains('ledger_entries'), isTrue);
      expect(tables.contains('sync_events'), isTrue);

      // Verify connected DB path
      final dbList = await coreDb.db.rawQuery('PRAGMA database_list;');
      final mainDbPath = dbList.first['file'] as String;
      expect(p.canonicalize(mainDbPath), equals(p.canonicalize(isolatedTargetPath)));

      await coreDb.close();
    });

    test('2.3 (Senaryo 3): Core Next açılışında legacy _onUpgrade çağrılmaz; DatabaseManager Core Next dosyasını fail-closed reddeder', () async {
      // 1. Core Next DB oluştur
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia',
        'updated_at': 1792100000,
      });
      await coreDb.close();

      // 2. Güvenlik Denetimi: DatabaseManager'a Core Next yolu verilirse
      // DatabaseManager _isCoreNextDatabase kontrolüyle dosyayı tespit edip IncompatibleDatabaseSchemaException fırlatmalıdır.
      DatabaseManager.overrideDatabasePath = isolatedTargetPath;
      expect(
        () async => await DatabaseManager.instance.getDatabase(),
        throwsA(isA<IncompatibleDatabaseSchemaException>()),
        reason: 'Legacy DatabaseManager Core Next veritabanını fail-closed IncompatibleDatabaseSchemaException ile reddetmelidir',
      );

      // 3. Dosyanın şema sürümünün bozulmadığını ve 3 olarak kaldığını doğrula (upgrade uygulanmadı)
      final inspectDb = await openDatabase(isolatedTargetPath, readOnly: true);
      final vRes = await inspectDb.rawQuery('PRAGMA user_version;');
      expect((vRes.first.values.first as num).toInt(), equals(3));

      // financial_transactions tablosunun OLMADIĞINI doğrula (_onUpgrade adımları hiç çalışmadı)
      final ftTable = await inspectDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='financial_transactions'",
      );
      expect(ftTable, isEmpty, reason: 'Migration 52 veya legacy tablolar Core Next DB içine yazılmamalıdır');
      await inspectDb.close();
    });

    test('2.4 (Senaryo 4): Core Next açılışında legacy trigger onarımı çalışmaz', () async {
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);

      // Verify no legacy financial triggers exist on Core Next DB
      final triggers = await coreDb.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger' AND sql LIKE '%financial_transactions%'",
      );
      expect(triggers, isEmpty, reason: 'Core Next DB üzerinde financial_transactions triggerları bulunmamalıdır');

      await coreDb.close();
    });

    test('2.5 (Senaryo 5): Legacy açılışında gerekli legacy migration ve kontroller hâlâ çalışır', () async {
      // Create a mock legacy database at version 59 with full legacy schema
      final v59Path = p.join(tempDir.path, 'legacy_v59.db');
      final legacyV59 = await openDatabase(
        v59Path,
        version: 59,
        onCreate: (db, version) async {
          await DatabaseSchema.createTables(db);
        },
      );
      await legacyV59.close();

      // Open via DatabaseManager -> should upgrade to 60 cleanly
      DatabaseManager.overrideDatabasePath = v59Path;
      final upgradedDb = await DatabaseManager.instance.getDatabase();
      final vRes = await upgradedDb.rawQuery('PRAGMA user_version;');
      expect((vRes.first.values.first as num).toInt(), equals(60),
          reason: 'Legacy DatabaseManager v59 veritabanını v60 sürümüne başarıyla yükseltmelidir');
      await upgradedDb.close();
    });

    test('2.6 (Senaryo 6): Yanlış şema veya bilinmeyen veritabanı kimliği reddedilir (Fail-Closed)', () async {
      // 1. Bilinmeyen/daha yüksek şema sürümü (v99)
      final v99Path = p.join(tempDir.path, 'unknown_v99.db');
      final v99Db = await openDatabase(
        v99Path,
        version: 99,
        onCreate: (db, v) async {
          await db.execute('CREATE TABLE dummy (id INT);');
        },
      );
      await v99Db.close();

      DatabaseManager.overrideDatabasePath = v99Path;
      expect(
        () async => await DatabaseManager.instance.getDatabase(),
        throwsA(isA<IncompatibleDatabaseSchemaException>()),
        reason: 'DatabaseManager şema sürümü 60 üzerinde olan bilinmeyen veritabanını reddetmelidir',
      );

      // 2. Legacy veritabanı CoreAppDatabase.open içine verilirse
      expect(
        () async => await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedLegacyPath),
        throwsA(isA<IncompatibleDatabaseSchemaException>()),
        reason: 'CoreAppDatabase legacy veritabanını fail-closed IncompatibleDatabaseSchemaException ile reddetmelidir',
      );
    });

    test('2.7 (Senaryo 7): Tamamlanmamış migration hedef veritabanını aktif kullanım için seçemez', () async {
      const coordinator = DualDatabaseRoutingCoordinator();

      // migrationStateCompleted = false
      final result = await coordinator.resolveAndOpen(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: isolatedTargetPath,
        migrationStateCompleted: false,
      );

      expect(result.decision, equals(RoutingDecision.legacyFallback));
      expect(result.isTargetSelected, isFalse);
      expect(result.targetDatabase, isNull);
      expect(result.isSuccess, isFalse);
      expect(result.resolvedPath, equals(isolatedLegacyPath));
    });

    test('2.8 (Senaryo 8): Tamamlanmış ve doğrulanmış hedef veritabanı doğru Core Next repository\'sine bağlanır', () async {
      // 1. Hedef DB'yi CoreAppDatabase ile oluştur ve doğrulanabilir kayıtları ekle
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia',
        'updated_at': 1792100000,
      });
      await coreDb.db.insert('customers', {
        'id': 'cust-corenext-autoroute-1',
        'name': 'CORE NEXT YÖNLENDİRİLMİŞ MÜŞTERİ',
        'phone': '05559876543',
        'balance_cents': 35000,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': 1792100000,
      });
      await coreDb.db.insert('products', {
        'id': 'prod-corenext-autoroute-1',
        'barcode': 'BC-123456',
        'name': 'CORE NEXT YÖNLENDİRİLMİŞ ÜRÜN',
        'price_cents': 15000,
        'stock_quantity': 42,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': 1792100000,
      });
      await coreDb.close();

      // 2. DualDatabaseRoutingCoordinator ile güvenli çöz ve aç
      const coordinator = DualDatabaseRoutingCoordinator();
      final result = await coordinator.resolveAndOpen(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: isolatedTargetPath,
        migrationStateCompleted: true,
      );

      expect(result.decision, equals(RoutingDecision.targetSelected));
      expect(result.isTargetSelected, isTrue);
      expect(result.isSuccess, isTrue);
      expect(result.targetDatabase, isNotNull);

      // 3. ProviderContainer oluştur ve repository override'larını bağla
      final container = ProviderContainer(
        overrides: DualDatabaseRoutingCoordinator.createRepositoryOverrides(
          coreDb: result.targetDatabase!,
          enableSalesEngine: false, // Satış motoru kapalı
        ),
      );
      addTearDown(container.dispose);

      // 4. Müşteri deposunun CoreNextCustomerRepository olduğunu doğrula
      final custRepo = await container.read(customerRepositoryProvider.future);
      expect(custRepo, isA<CoreNextCustomerRepository>());

      final customers = await custRepo.findAll();
      expect(customers.length, equals(1));
      expect(customers.first.name, equals('CORE NEXT YÖNLENDİRİLMİŞ MÜŞTERİ'));
      expect(customers.first.balance, equals(350.0)); // 35000 kuruş -> 350.0 TL

      // 5. Ürün deposunun CoreNextProductRepository olduğunu doğrula
      final prodRepo = await container.read(productRepositoryProvider.future);
      expect(prodRepo, isA<CoreNextProductRepository>());

      final products = await prodRepo.findAll();
      expect(products.length, equals(1));
      expect(products.first.name, equals('CORE NEXT YÖNLENDİRİLMİŞ ÜRÜN'));
      expect(products.first.price, equals(150.0)); // 15000 kuruş -> 150.0 TL

      // 6. Finans deposunun CoreNextFinancialTransactionRepository olduğunu doğrula
      final finRepo = await container.read(financialTransactionRepositoryProvider.future);
      expect(finRepo, isA<CoreNextFinancialTransactionRepository>());

      // 7. Satış motoru kapalı olduğundan satış reposunun SqliteSaleRepository (Legacy) olduğunu doğrula
      DatabaseManager.overrideDatabasePath = isolatedLegacyPath;
      final saleRepo = await container.read(saleRepositoryProvider.future);
      expect(saleRepo, isA<SqliteSaleRepository>());

      await result.targetDatabase!.close();
    });

    test('2.9 (Senaryo 9): Yanlış tenant seçimi engellenir (Fail-Closed)', () async {
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia',
        'updated_at': 1792100000,
      });
      await coreDb.close();

      const coordinator = DualDatabaseRoutingCoordinator();
      final result = await coordinator.resolveAndOpen(
        requestedTenantId: 'other-unauthorized-tenant', // Yanlış tenant!
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: isolatedTargetPath,
        migrationStateCompleted: true,
      );

      expect(result.decision, equals(RoutingDecision.blockedFailClosed));
      expect(result.isTargetSelected, isFalse);
      expect(result.targetDatabase, isNull);
      expect(result.reason, contains('Tenant ID uyuşmazlığı'));
    });

    test('2.10 (Senaryo 10): Açılış veya repository oluşturma hatasında fail-closed davranış korunur', () async {
      // Hedef dosyayı geçersiz veriyle boz
      await File(isolatedTargetPath).writeAsString('NOT A VALID SQLITE FILE');

      const coordinator = DualDatabaseRoutingCoordinator();
      final result = await coordinator.resolveAndOpen(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: isolatedTargetPath,
        migrationStateCompleted: true,
      );

      // Bozuk dosya asla sessizce açılmaz
      expect(result.decision, equals(RoutingDecision.blockedFailClosed));
      expect(result.targetDatabase, isNull);
      expect(result.isTargetSelected, isFalse);
    });

    test('2.11 (Senaryo 11): Aynı DB bağlantısı yanlışlıkla iki farklı şema yöneticisine verilmez', () async {
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      DatabaseManager.overrideDatabasePath = isolatedLegacyPath;
      final legacyDb = await DatabaseManager.instance.getDatabase();

      // İki bağlantı ve iki dosya yolu tamamen ayrı olmalı
      final legacyList = await legacyDb.rawQuery('PRAGMA database_list;');
      final coreList = await coreDb.db.rawQuery('PRAGMA database_list;');

      final legacyFilePath = legacyList.first['file'] as String;
      final coreFilePath = coreList.first['file'] as String;

      expect(p.canonicalize(legacyFilePath), isNot(equals(p.canonicalize(coreFilePath))));
      expect(p.canonicalize(legacyFilePath), equals(p.canonicalize(isolatedLegacyPath)));
      expect(p.canonicalize(coreFilePath), equals(p.canonicalize(isolatedTargetPath)));

      await legacyDb.close();
      await coreDb.close();
    });

    test('2.12 (Senaryo 12): İkinci açılışta migration tekrarı veya mükerrer veri oluşmaz (Idempotency)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final legacyDb = await openDatabase(isolatedLegacyPath);
      final targetAppDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: targetAppDb.db,
        customLegacyFilePath: isolatedLegacyPath,
        customBackupDirectory: tempDir.path,
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: ({
          required Database legacyDb,
          required Database targetDb,
          String? legacyFilePath,
          bool? fullScope,
        }) async {
          final engine = MigrationBridgeEngine(targetAppDb);
          return await engine.migrateFromLegacy(legacyDb, fullScope: true);
        },
      );

      // 1. İlk göç
      final res1 = await coordinator.coordinate();
      expect(res1.isSuccess, isTrue);

      final customerCount1 = (await targetAppDb.db.rawQuery('SELECT COUNT(*) as c FROM customers;')).first['c'] as int;
      expect(customerCount1, equals(584)); // Nutopia total customers

      // 2. İkinci açılış simülasyonu
      final coordinator2 = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: targetAppDb.db,
        customLegacyFilePath: isolatedLegacyPath,
        customBackupDirectory: tempDir.path,
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: ({
          required Database legacyDb,
          required Database targetDb,
          String? legacyFilePath,
          bool? fullScope,
        }) async {
          final engine = MigrationBridgeEngine(targetAppDb);
          return await engine.migrateFromLegacy(legacyDb, fullScope: true);
        },
      );

      final res2 = await coordinator2.coordinate();
      expect(res2.isSuccess, isTrue);
      expect(res2.isSkipped, isTrue, reason: 'İkinci açılışta daha önce tamamlandığı için atlanmalıdır');

      // Veri çoğalmamalı
      final customerCount2 = (await targetAppDb.db.rawQuery('SELECT COUNT(*) as c FROM customers;')).first['c'] as int;
      expect(customerCount2, equals(customerCount1), reason: 'İkinci açılışta mükerrer veri oluşmamalıdır');

      await legacyDb.close();
      await targetAppDb.close();
    });
  });

  group('STAGE 10.12.24 — Bölüm 3: Bitiş Hash Doğrulaması', () {
    test('3.1: Kaynak Nutopia DB SHA-256 hash değeri testler sonunda da değişmemiş olmalıdır', () async {
      final sourceFile = File(rawNutopiaPath);
      final bytes = await sourceFile.readAsBytes();
      final actualHash = sha256.convert(bytes).toString();
      expect(actualHash.toLowerCase(), equals(expectedSourceHash),
          reason: 'Kaynak DB SHA-256 hash değeri başlangıç ve bitişte birebir aynı kalmalıdır');
    });
  });
}
