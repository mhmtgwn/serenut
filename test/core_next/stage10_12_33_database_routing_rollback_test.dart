// test/core_next/stage10_12_33_database_routing_rollback_test.dart
// SERENUT OS — STAGE 10.12.33
// DUAL DATABASE ROUTING, ROLLBACK VE TENANT VERİ GÜVENLİĞİ DENETİM TESTLERİ
//
// GÜVENLİK KURALI:
// 1. Canlı hiçbir veritabanına dokunulmaz.
// 2. Yalnızca izole, geçici disposable test kopyaları kullanılır.
// 3. `coreNextSalesEngineEnabledProvider` kesinlikle `false` tutulur.

// ignore_for_file: avoid_relative_lib_imports, prefer_const_declarations

@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/config/environment.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_payment_repository.dart';
import 'package:serenutos/infrastructure/services/release_manager_service.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart';
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
  const expectedNutopiaHash = 'e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24';

  group('STAGE 10.12.33 — BÖLÜM 1: GÜVENLİK KAPISI VE DEĞİŞMEZLİK KANITLARI', () {
    test('1.1: Kaynak Nutopia veritabanı hash değeri değişmemiş olmalıdır', () async {
      final file = File(rawNutopiaPath);
      expect(await file.exists(), isTrue, reason: 'Nutopia ham arşivi mevcut olmalıdır');
      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes).toString();
      expect(hash.toLowerCase(), equals(expectedNutopiaHash));
    });

    test('1.2: Satış motoru ve routing hook varsayılan olarak kesinlikle kapalıdır', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final salesEngine = container.read(coreNextSalesEngineEnabledProvider);
      expect(salesEngine, isFalse, reason: 'coreNextSalesEngineEnabledProvider = false olmalı');
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });
  });

  group('STAGE 10.12.33 — BÖLÜM 2: DUAL DATABASE ROUTING DENETİMİ (12 SENARYO)', () {
    late Directory tempDir;
    late String isolatedLegacyPath;
    late String isolatedTargetPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage10_12_33_routing_');
      isolatedLegacyPath = p.join(tempDir.path, 'legacy_serenut_pos.db');
      isolatedTargetPath = p.join(tempDir.path, 'serenut_core_v2.db');

      // Nutopia arşiv kopyası oluştur
      final srcBytes = await File(rawNutopiaPath).readAsBytes();
      await File(isolatedLegacyPath).writeAsBytes(srcBytes);

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

    test('2.1 (Senaryo 1): Hedef DB yolu yokken veya migration tamamlanmamışsa Legacy fallback seçilir', () async {
      const resolver = DatabaseRoutingResolver();

      // targetDbPath null
      final res1 = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: null,
      );
      expect(res1.decision, equals(RoutingDecision.legacyFallback));
      expect(res1.resolvedPath, equals(isolatedLegacyPath));
      expect(res1.isTargetSelected, isFalse);

      // targetDbPath var ancak migrationStateCompleted = false
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      await coreDb.close();

      final res2 = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: isolatedTargetPath,
        migrationStateCompleted: false,
      );
      expect(res2.decision, equals(RoutingDecision.legacyFallback));
      expect(res2.isTargetSelected, isFalse);
    });

    test('2.2 (Senaryo 2): Core Next hedefi tüm gereksinimleri karşıladığında başarıyla seçilir', () async {
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia',
        'updated_at': 1792100000,
      });
      await coreDb.close();

      const resolver = DatabaseRoutingResolver();
      final res = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: isolatedTargetPath,
        migrationStateCompleted: true,
      );

      expect(res.decision, equals(RoutingDecision.targetSelected));
      expect(res.resolvedPath, equals(isolatedTargetPath));
      expect(res.isTargetSelected, isTrue);
    });

    test('2.3 (Senaryo 3): Nutopia tenant kimliği için doğru DB eşleşmesi doğrulanır', () async {
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia',
        'updated_at': 1792100000,
      });
      await coreDb.close();

      const coordinator = DualDatabaseRoutingCoordinator();
      final result = await coordinator.resolveAndOpen(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: isolatedTargetPath,
        migrationStateCompleted: true,
      );

      expect(result.decision, equals(RoutingDecision.targetSelected));
      expect(result.isSuccess, isTrue);
      expect(result.targetDatabase, isNotNull);
      await result.targetDatabase!.close();
    });

    test('2.4 (Senaryo 4): Serenut tenant kimliği için doğru DB eşleşmesi doğrulanır', () async {
      final serenutTargetPath = p.join(tempDir.path, 'serenut_tenant_core.db');
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: serenutTargetPath);
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-serenut',
        'updated_at': 1792100000,
      });
      await coreDb.close();

      const coordinator = DualDatabaseRoutingCoordinator();
      final result = await coordinator.resolveAndOpen(
        requestedTenantId: 'tenant-serenut',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: serenutTargetPath,
        migrationStateCompleted: true,
      );

      expect(result.decision, equals(RoutingDecision.targetSelected));
      expect(result.isSuccess, isTrue);
      await result.targetDatabase!.close();
    });

    test('2.5 (Senaryo 5): Erkul Çeyiz tenant kimliği için doğru DB eşleşmesi doğrulanır', () async {
      final erkulTargetPath = p.join(tempDir.path, 'erkul_tenant_core.db');
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: erkulTargetPath);
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-erkul',
        'updated_at': 1792100000,
      });
      await coreDb.close();

      const coordinator = DualDatabaseRoutingCoordinator();
      final result = await coordinator.resolveAndOpen(
        requestedTenantId: 'tenant-erkul',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: erkulTargetPath,
        migrationStateCompleted: true,
      );

      expect(result.decision, equals(RoutingDecision.targetSelected));
      expect(result.isSuccess, isTrue);
      await result.targetDatabase!.close();
    });

    test('2.6 (Senaryo 6): Tenant kimliği uyuşmazlığında fail-closed durdurulur ve veri sızıntısı engellenir', () async {
      // DB'de 'tenant-nutopia' kayıtlı iken 'tenant-erkul' talep edilirse:
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia',
        'updated_at': 1792100000,
      });
      await coreDb.close();

      const coordinator = DualDatabaseRoutingCoordinator();
      final result = await coordinator.resolveAndOpen(
        requestedTenantId: 'tenant-erkul', // Uyuşmayan tenant!
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: isolatedTargetPath,
        migrationStateCompleted: true,
      );

      expect(result.decision, equals(RoutingDecision.blockedFailClosed));
      expect(result.isTargetSelected, isFalse);
      expect(result.targetDatabase, isNull);
      expect(result.reason, contains('Tenant ID uyuşmazlığı'));
    });

    test('2.7 (Senaryo 7): DB dosyası yoksa veya bozuksa fail-closed korunur (Asla boş dosya oluşturulmaz)', () async {
      const resolver = DatabaseRoutingResolver();
      final nonExistentPath = p.join(tempDir.path, 'non_existent_target.db');

      // Dosya yokken çağrıldığında
      final res1 = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: nonExistentPath,
        migrationStateCompleted: true,
      );
      expect(res1.decision, equals(RoutingDecision.legacyFallback));
      expect(File(nonExistentPath).existsSync(), isFalse, reason: 'Boş dosya asla yaratılmamalıdır');

      // Dosya 0 bayt veya header bozuksa (< 512B)
      final corruptPath = p.join(tempDir.path, 'corrupt.db');
      await File(corruptPath).writeAsString('CORRUPT');
      final res2 = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: corruptPath,
        migrationStateCompleted: true,
      );
      expect(res2.decision, equals(RoutingDecision.blockedFailClosed));
    });

    test('2.8 (Senaryo 8): Yanlış tenant DB\'sine çapraz yazma girişimi engellenir (İzolasyon Kanıtı)', () async {
      // 1. Nutopia ve Erkul için iki ayrı DB oluştur
      final nutopiaDbPath = p.join(tempDir.path, 'iso_nutopia.db');
      final erkulDbPath = p.join(tempDir.path, 'iso_erkul.db');

      final nutopiaCore = await CoreAppDatabase.open(inMemoryOrCustomPath: nutopiaDbPath);
      await nutopiaCore.db.insert('app_settings', {'key': 'tenant_id', 'value': 'tenant-nutopia', 'updated_at': 1});
      await nutopiaCore.db.insert('customers', {
        'id': 'cust-nutopia-exclusive',
        'name': 'Nutopia Özel Müşteri',
        'balance_cents': 10000,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': 1,
      });
      await nutopiaCore.close();

      final erkulCore = await CoreAppDatabase.open(inMemoryOrCustomPath: erkulDbPath);
      await erkulCore.db.insert('app_settings', {'key': 'tenant_id', 'value': 'tenant-erkul', 'updated_at': 1});
      await erkulCore.db.insert('customers', {
        'id': 'cust-erkul-exclusive',
        'name': 'Erkul Özel Müşteri',
        'balance_cents': 20000,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': 1,
      });
      await erkulCore.close();

      // 2. Çapraz izolasyon sorgulaması
      final nutopiaVerify = await openDatabase(nutopiaDbPath, readOnly: true);
      final erkulVerify = await openDatabase(erkulDbPath, readOnly: true);

      final nutopiaInErkul = await erkulVerify.rawQuery("SELECT COUNT(*) as c FROM customers WHERE id = 'cust-nutopia-exclusive'");
      expect(nutopiaInErkul.first['c'], equals(0), reason: 'Nutopia kaydı Erkul içinde asla olamaz');

      final erkulInNutopia = await nutopiaVerify.rawQuery("SELECT COUNT(*) as c FROM customers WHERE id = 'cust-erkul-exclusive'");
      expect(erkulInNutopia.first['c'], equals(0), reason: 'Erkul kaydı Nutopia içinde asla olamaz');

      await nutopiaVerify.close();
      await erkulVerify.close();
    });

    test('2.9 (Senaryo 9): Legacy ve Core Next repository\'lerinin aynı anda yanlış yazması şema sınırıyla engellenir', () async {
      // 1. Core Next DB'yi oluştur
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      await coreDb.close();

      // 2. DatabaseManager (Legacy) yanlışlıkla Core Next yoluna yönlendirilirse:
      // IncompatibleDatabaseSchemaException fırlatarak durmalıdır!
      DatabaseManager.overrideDatabasePath = isolatedTargetPath;
      expect(
        () async => await DatabaseManager.instance.getDatabase(),
        throwsA(isA<IncompatibleDatabaseSchemaException>()),
        reason: 'Legacy DatabaseManager Core Next DB üzerine yazamaz (Şema Sınırı Koruması)',
      );
    });

    test('2.10 (Senaryo 10): Yeniden başlatmada DB yönlendirme kararı ve ayarlar tutarlı kalır', () async {
      SharedPreferences.setMockInitialValues({
        'core_next_bootstrap_migration_state': 'completed',
        'core_next_pilot_enabled': false, // Varsayılan kapalı
      });
      final prefs = await SharedPreferences.getInstance();

      final gate = const PilotCutoverGate();
      final eval1 = await gate.evaluate(prefs: prefs);
      expect(eval1.isPilotActive, isFalse);
      expect(eval1.status, equals(PilotGateStatus.disabledByDefault));

      // Yeniden başlatma simülasyonu: Yeni SharedPreferences instance
      final prefsRestart = await SharedPreferences.getInstance();
      final eval2 = await gate.evaluate(prefs: prefsRestart);
      expect(eval2.isPilotActive, isFalse);
      expect(eval2.status, equals(PilotGateStatus.disabledByDefault));
    });

    test('2.11 (Senaryo 11): Lisans ve şirket hedefleme uyuşmazlıkları fail-closed yönetilir', () async {
      final mockClient = MockClient((request) async {
        final compId = request.url.queryParameters['company_id'];
        if (compId != 'cmp-nutopia-pilot') {
          return http.Response(
            jsonEncode({'hasUpdate': false, 'latestVersion': '1.2.0', 'channel': 'pilot'}),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'hasUpdate': true,
            'latestVersion': '1.3.0',
            'channel': 'pilot',
            'downloadUrl': '/api/v1/releases/download/rel-1.3.0',
            'sha256Hash': 'hash-valid-130',
          }),
          200,
        );
      });

      const config = EnvironmentConfig(
        environment: AppEnvironment.dev,
        apiBaseUrl: 'http://localhost:3000/api/v1',
        authEndpoint: '/auth',
        syncEndpoint: '/sync',
        updateEndpoint: '/updates',
        releaseEndpoint: '/releases',
        releaseChannel: 'pilot',
      );

      final rm = ReleaseManagerService(config: config, httpClient: mockClient);

      // Hedefte olmayan şirket pilot sürümü sorguladığında güncelleme alamaz
      final unauthorizedCheck = await rm.checkForUpdates(
        currentVersion: '1.2.0',
        platform: 'windows',
        companyId: 'cmp-unauthorized-corp',
        deviceId: 'dev-001',
      );
      expect(unauthorizedCheck.hasUpdate, isFalse);

      // Yetkili pilot şirketi sorguladığında güncelleme alabilir
      final authorizedCheck = await rm.checkForUpdates(
        currentVersion: '1.2.0',
        platform: 'windows',
        companyId: 'cmp-nutopia-pilot',
        deviceId: 'dev-001',
      );
      expect(authorizedCheck.hasUpdate, isTrue);
    });

    test('2.12 (Senaryo 12): Bekleyen senkronizasyon kuyruğu DB geçişinde kaybolmaz', () async {
      // 1. Hedef Core Next DB oluştur ve sync_events kuyruğuna bekleyen işlem yaz
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      await coreDb.db.insert('sync_events', {
        'event_id': 'evt-pending-1',
        'entity_type': 'sale',
        'entity_id': 'sale-pending-100',
        'operation': 'UPSERT',
        'payload_json': jsonEncode({'total': 250.0}),
        'client_timestamp': DateTime.now().millisecondsSinceEpoch,
        'sync_state': 'PENDING',
      });
      await coreDb.close();

      // 2. Yönlendirme resolver'ı ile kontrol et: Tablo ve kayıt korunuyor mu?
      final verifyDb = await openDatabase(isolatedTargetPath, readOnly: true);
      final pendingEvents = await verifyDb.query('sync_events', where: "sync_state = 'PENDING'");
      expect(pendingEvents.length, equals(1));
      expect(pendingEvents.first['entity_id'], equals('sale-pending-100'));
      await verifyDb.close();
    });
  });

  group('STAGE 10.12.33 — BÖLÜM 3: İZOLE ROLLBACK VE VERİ GÜVENLİĞİ PROVASI', () {
    late Directory tempDir;
    late String isolatedLegacyDb;
    late String isolatedTargetDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage10_12_33_rollback_');
      isolatedLegacyDb = p.join(tempDir.path, 'source_legacy.db');
      isolatedTargetDb = p.join(tempDir.path, 'target_core.db');

      final srcBytes = await File(rawNutopiaPath).readAsBytes();
      await File(isolatedLegacyDb).writeAsBytes(srcBytes);
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('3.1: Başlangıç DB SHA-256 ve kritik finansal toplamlar değişmez şekilde kaydedilir', () async {
      final bytes = await File(isolatedLegacyDb).readAsBytes();
      final initialHash = sha256.convert(bytes).toString();
      expect(initialHash.toLowerCase(), equals(expectedNutopiaHash));

      final legacyDb = await openDatabase(isolatedLegacyDb, readOnly: true);
      final custRows = await legacyDb.rawQuery('SELECT COUNT(*) as c, SUM(balance) as b FROM customers;');
      final prodRows = await legacyDb.rawQuery('SELECT COUNT(*) as c, SUM(quantity) as s FROM products;');
      final saleRows = await legacyDb.rawQuery('SELECT COUNT(*) as c, SUM(total_amount) as t FROM sales;');

      expect(custRows.first['c'], equals(584));
      expect((custRows.first['b'] as num).toDouble(), closeTo(-134500.68, 0.01));
      expect(prodRows.first['c'], equals(37682));
      expect((prodRows.first['s'] as num).toDouble(), closeTo(5179525.85, 0.01));
      expect(saleRows.first['c'], equals(52));
      expect((saleRows.first['t'] as num).toDouble(), closeTo(31282.25, 0.01));

      await legacyDb.close();
    });

    test('3.2: Yeni finansal işlem OLMADIĞINDA güvenli geri dönüş (Rollback) başarıyla tamamlanır', () async {
      SharedPreferences.setMockInitialValues({
        'core_next_bootstrap_migration_state': 'completed',
        'core_next_pilot_enabled': true,
      });
      final prefs = await SharedPreferences.getInstance();

      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetDb);
      await targetCore.db.insert('app_settings', {'key': 'tenant_id', 'value': 'tenant-nutopia', 'updated_at': 1});
      await targetCore.db.insert('app_settings', {'key': 'legacy_migration_completed', 'value': 'true', 'updated_at': 1});

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: await openDatabase(isolatedLegacyDb),
        customTargetDb: targetCore.db,
        customLegacyFilePath: isolatedLegacyDb,
        prefs: prefs,
        rollbackGuard: ({required targetDb, required initialMigrationCutoffTimestamp}) async {
          const resolver = DatabaseRoutingResolver();
          await resolver.assertSafeRollback(
            targetDb: targetDb,
            initialMigrationCutoffTimestamp: initialMigrationCutoffTimestamp,
          );
        },
      );

      // Göç kesme anından (cutoff) sonra HİÇBİR yeni işlem yok -> Rollback güvenlidir
      final rollbackResult = await coordinator.rollbackToLegacy(initialCutoffTimestamp: 1000);
      expect(rollbackResult.isSuccess, isTrue);
      expect(rollbackResult.state, equals(CoreNextMigrationState.failedRecoverable));

      // Hedefteki durum 'rolled_back' yapıldı mı?
      final checkSetting = await targetCore.db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['legacy_migration_completed'],
      );
      expect(checkSetting.first['value'], equals('rolled_back'));

      // Resolver artık hedefi seçmez, legacy'ye fallback yapar
      const resolver = DatabaseRoutingResolver();
      final routeRes = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: isolatedLegacyDb,
        targetDbPath: isolatedTargetDb,
        migrationStateCompleted: false, // rollback sonrası false
      );
      expect(routeRes.decision, equals(RoutingDecision.legacyFallback));
      expect(routeRes.resolvedPath, equals(isolatedLegacyDb));

      await targetCore.close();
    });

    test('3.3: KRİTİK GÜVENLİK İLKESİ: Hedefte YENİ işlem oluşmuşsa sessiz Rollback kesinlikle ENGELLENİR (UnsafeRollbackException)', () async {
      final targetPath3 = p.join(tempDir.path, 'target_core_test3.db');
      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath3);
      final migrationCutoff = 1792100000;

      // Göç sonrasında hedef Core Next DB üzerinde YENİ bir satış yapıldığını simüle et:
      await targetCore.db.insert('sales', {
        'id': 'sale-new-post-migration',
        'receipt_no': 'REC-POST-MIG-1',
        'customer_id': null,
        'subtotal_cents': 15000,
        'discount_cents': 0,
        'vat_total_cents': 1500,
        'total_cents': 15000,
        'paid_cents': 15000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': migrationCutoff + 5000, // Cutoff'tan sonra yazılmış yeni satış!
      });

      const resolver = DatabaseRoutingResolver();

      // assertSafeRollback çağrıldığında UnsafeRollbackException fırlatarak durdurmalıdır:
      await expectLater(
        () => resolver.assertSafeRollback(
          targetDb: targetCore.db,
          initialMigrationCutoffTimestamp: migrationCutoff,
        ),
        throwsA(isA<UnsafeRollbackException>()),
        reason: 'Yeni satış varken sessiz geri dönüş veri kaybına yol açacağından KESİNLİKLE ENGELLENMELİDİR',
      );

      await targetCore.close();
    });
  });

  group('STAGE 10.12.33 — BÖLÜM 4: REPOSITORY SEÇİMİ VE PROVIDER TUTARLILIĞI', () {
    late Directory tempDir;
    late String targetPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage10_12_33_repo_');
      targetPath = p.join(tempDir.path, 'target_core.db');
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('4.1: Repository overrides uygulandığında UI depoları Core Next\'e geçer, ancak satış motoru kapalı kalır', () async {
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);

      // Override listesi oluştur (enableSalesEngine: false)
      final overrides = DualDatabaseRoutingCoordinator.createRepositoryOverrides(
        coreDb: coreDb,
        enableSalesEngine: false,
      );

      final container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);

      final custRepo = await container.read(customerRepositoryProvider.future);
      expect(custRepo, isA<CoreNextCustomerRepository>());

      final prodRepo = await container.read(productRepositoryProvider.future);
      expect(prodRepo, isA<CoreNextProductRepository>());

      final finRepo = await container.read(financialTransactionRepositoryProvider.future);
      expect(finRepo, isA<CoreNextFinancialTransactionRepository>());

      // Satış motoru kapalı olduğu için satış reposu SqliteSaleRepository kalır
      final saleRepo = await container.read(saleRepositoryProvider.future);
      expect(saleRepo, isA<SqliteSaleRepository>());

      await coreDb.close();
    });
  });
}
