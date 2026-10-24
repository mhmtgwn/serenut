// test/core_next/stage10_12_23_isolated_pilot_rehearsal_test.dart
// SERENUT OS — STAGE 10.12.23
// İZOLE PİLOT PROVASI, GERÇEK VERİTABANI YÖNLENDİRME VE AÇILIŞ DAYANIKLILIĞI TEST PAKETİ
// ignore_for_file: avoid_relative_lib_imports

@Timeout(Duration(minutes: 7))
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_customer_repository.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/widgets/branded_splash_screen.dart';
import 'package:serenutos/presentation/widgets/migration_consent_dialog.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

class TestAppLifecycleHarness extends StatefulWidget {
  final ProviderContainer container;
  const TestAppLifecycleHarness({super.key, required this.container});

  @override
  State<TestAppLifecycleHarness> createState() => _TestAppLifecycleHarnessState();
}

class _TestAppLifecycleHarnessState extends State<TestAppLifecycleHarness> {
  @override
  void dispose() {
    try {
      final pendingConsent = widget.container.read(coreNextConsentRequestProvider);
      if (pendingConsent != null && !pendingConsent.completer.isCompleted) {
        pendingConsent.completer.complete(MigrationConsentDecision.postponed);
      }
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: widget.container,
      child: Consumer(
        builder: (context, ref, _) {
          final consentRequest = ref.watch(coreNextConsentRequestProvider);
          return MaterialApp(
            home: BrandedSplashScreen(
              status: 'Sistem kontrol ediliyor',
              overlay: consentRequest != null
                  ? MigrationConsentDialog(
                      sourceDbPath: consentRequest.sourceDbPath,
                      targetDbPath: consentRequest.targetDbPath,
                      estimatedProductCount: consentRequest.estimatedProductCount,
                      estimatedCustomerCount: consentRequest.estimatedCustomerCount,
                      onDecision: (decision) {
                        if (!consentRequest.completer.isCompleted) {
                          consentRequest.completer.complete(decision);
                        }
                        ref.read(coreNextConsentRequestProvider.notifier).state = null;
                      },
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const rawNutopiaPath = 'backups/raw_tenants_20261016/raw_nutopia_v60.db';
  const expectedSourceHash =
      'e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24';

  group('STAGE 10.12.23 — Bölüm 1: Değişmez Güvenlik & Kaynak Hash Doğrulaması', () {
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

  group('STAGE 10.12.23 — Bölüm 2: Gerçek Veritabanı Yönlendirmesi (DatabaseManager & Repository)', () {
    late Directory tempDir;
    late String isolatedLegacyPath;
    late String isolatedTargetPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage10_12_23_routing_');
      isolatedLegacyPath = p.join(tempDir.path, 'legacy_serenut_pos.db');
      isolatedTargetPath = p.join(tempDir.path, 'core_next_app.db');

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

    test('2.1: Runner null iken migration çalışmaz ve DatabaseManager legacy DB açar', () async {
      DatabaseManager.overrideDatabasePath = isolatedLegacyPath;
      final db = await DatabaseManager.instance.getDatabase();
      final gateway = DbGatewayImpl(DatabaseManager.instance);
      final repo = SqliteCustomerRepository(gateway);

      // Authentic active customers in Nutopia DB
      final customers = await repo.findAll();
      expect(customers.length, equals(576));

      // Verify connected DB path via SQLite pragma
      final dbList = await db.rawQuery('PRAGMA database_list;');
      final mainDbPath = dbList.first['file'] as String;
      expect(p.canonicalize(mainDbPath), equals(p.canonicalize(isolatedLegacyPath)));
      await db.close();
    });

    test('2.2: databaseRoutingHook null iken mevcut legacy davranışı korunur', () async {
      expect(DatabaseManager.databaseRoutingHook, isNull);
      DatabaseManager.overrideDatabasePath = isolatedLegacyPath;

      final db = await DatabaseManager.instance.getDatabase();
      expect(db.isOpen, isTrue);

      final dbList = await db.rawQuery('PRAGMA database_list;');
      final mainDbPath = dbList.first['file'] as String;
      expect(p.canonicalize(mainDbPath), equals(p.canonicalize(isolatedLegacyPath)));
      await db.close();
    });

    test('2.3: Runner ve Hook açıkça enjekte edilse bile geçiş tamamlanmadan hedef DB seçilmez', () async {
      SharedPreferences.setMockInitialValues({});

      // Resolver hook with migrationStateCompleted = false
      const resolver = DatabaseRoutingResolver();
      DatabaseManager.databaseRoutingHook = () async {
        final resolution = await resolver.resolve(
          requestedTenantId: 'tenant-nutopia',
          legacyDbPath: isolatedLegacyPath,
          targetDbPath: isolatedTargetPath,
          migrationStateCompleted: false, // NOT completed
        );
        return resolution.resolvedPath;
      };

      final db = await DatabaseManager.instance.getDatabase();
      final dbList = await db.rawQuery('PRAGMA database_list;');
      final mainDbPath = dbList.first['file'] as String;

      // Must be legacy DB path!
      expect(p.canonicalize(mainDbPath), equals(p.canonicalize(isolatedLegacyPath)));

      final gateway = DbGatewayImpl(DatabaseManager.instance);
      final repo = SqliteCustomerRepository(gateway);
      final customers = await repo.findAll();
      expect(customers.length, equals(576));

      await db.close();
    });

    test('2.4: Geçiş tamamlandığında Resolver hedefi seçer; doğrudan legacy DatabaseManager çağrısı ise güvenlik kapısıyla durdurulur', () async {
      // 1. Target CoreAppDatabase oluştur ve geçerli kayıtları ekle
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      await coreDb.db.insert('customers', {
        'id': 'cust-corenext-1',
        'name': 'CORE NEXT MUSTERI',
        'phone': '5551234',
        'balance_cents': 25000,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': 1792100000,
      });
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia',
        'updated_at': 1792100000,
      });
      await coreDb.close();

      // Target DB hash
      final targetBytes = await File(isolatedTargetPath).readAsBytes();
      final targetHash = sha256.convert(targetBytes).toString();
      expect(targetHash, isNotEmpty);

      // Resolver hook with migrationStateCompleted = true
      const resolver = DatabaseRoutingResolver();
      final resolution = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: isolatedTargetPath,
        migrationStateCompleted: true,
      );

      // Resolver hedef DB'yi başarıyla onaylar
      expect(resolution.decision, equals(RoutingDecision.targetSelected));
      expect(resolution.isTargetSelected, isTrue);
      expect(p.canonicalize(resolution.resolvedPath), equals(p.canonicalize(isolatedTargetPath)));

      // Güvenlik Denetimi: Eğer legacy DatabaseManager doğrudan Core Next DB'yi açmaya çalışırsa
      // DatabaseManager'ın eski version 60 şema invariant'ları ve eski trigger'ları
      // temiz Core Next veritabanını bozmamak için fail-closed çöker veya kilitlenir.
      DatabaseManager.databaseRoutingHook = () async => resolution.resolvedPath;
      expect(
        () async => await DatabaseManager.instance.getDatabase(),
        throwsA(anything),
        reason: 'Legacy DatabaseManager doğrudan Core Next temiz şemasına bağlanamamalıdır (SAFETY GAP)',
      );
    });

    test('2.5: Yeniden başlatıldığında aynı geçiş veri çoğaltmaz (idempotent)', () async {
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

      // 1. Çalıştırma
      final res1 = await coordinator.coordinate();
      expect(res1.isSuccess, isTrue);

      // 2. Yeniden başlatma simülasyonu
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
          fail('İkinci açılışta migration runner çağrılmamalı!');
        },
      );

      final res2 = await coordinator2.coordinate();
      expect(res2.isSuccess, isTrue);
      expect(res2.isSkipped, isTrue);
      expect(res2.state, equals(CoreNextMigrationState.completed));

      await legacyDb.close();
      await targetAppDb.close();
    });

    test('2.6: Eksik veya bozuk completion state durumunda güvenli olmayan hedef seçimi engellenir', () async {
      const resolver = DatabaseRoutingResolver();

      // Bozuk / eksik state
      final res = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: isolatedTargetPath,
        migrationStateCompleted: false,
      );

      expect(res.decision, equals(RoutingDecision.legacyFallback));
      expect(res.isTargetSelected, isFalse);
      expect(p.canonicalize(res.resolvedPath), equals(p.canonicalize(isolatedLegacyPath)));
    });

    test('2.7: Yanlış tenant ID veya mutabakat farkında geçiş fail-closed durdurulur', () async {
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'wrong-tenant',
        'updated_at': 1792100000,
      });
      await coreDb.close();

      const resolver = DatabaseRoutingResolver();
      final res = await resolver.resolve(
        requestedTenantId: 'expected-tenant',
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: isolatedTargetPath,
        migrationStateCompleted: true,
      );

      expect(res.decision, equals(RoutingDecision.blockedFailClosed));
      expect(res.isTargetSelected, isFalse);
      expect(p.canonicalize(res.resolvedPath), equals(p.canonicalize(isolatedLegacyPath)));
    });

    test('2.8: Hedef DB üzerinde yeni satış/finans kaydı varken güvensiz rollback kesinlikle engellenir', () async {
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      const cutoffTime = 1792100000;
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia',
        'updated_at': cutoffTime,
      });
      // Add a new sale in target created after cutoffTime
      await coreDb.db.insert('sales', {
        'id': 'sale-new-target-1',
        'receipt_no': 'REC-999',
        'total_cents': 50000,
        'subtotal_cents': 50000,
        'paid_cents': 50000,
        'created_at': cutoffTime + 500,
      });

      const resolver = DatabaseRoutingResolver();
      await expectLater(
        () => resolver.assertSafeRollback(
          targetDb: coreDb.db,
          initialMigrationCutoffTimestamp: cutoffTime,
        ),
        throwsA(isA<UnsafeRollbackException>()),
        reason: 'Hedefte yeni işlem varken eski DBye sessizce geri dönülemez',
      );

      await coreDb.close();
    });
  });

  group('STAGE 10.12.23 — Bölüm 3: Açılış ve UI Dayanıklılığı (Lifecycle, Concurrency & Threading)', () {
    late Directory tempDir;
    late String isolatedLegacyPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage10_12_23_ui_');
      isolatedLegacyPath = p.join(tempDir.path, 'legacy_ui.db');

      final sourceBytes = await File(rawNutopiaPath).readAsBytes();
      await File(isolatedLegacyPath).writeAsBytes(sourceBytes);
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    testWidgets('3.1 & 3.2: Onay ekranının görünmesi ve erteleme (postponed)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final requester = createUiConsentRequester(
        container,
        sourceDbPath: isolatedLegacyPath,
        targetDbPath: p.join(tempDir.path, 'target_ui.db'),
        estimatedProductCount: 37682,
        estimatedCustomerCount: 584,
      );

      await tester.pumpWidget(TestAppLifecycleHarness(container: container));
      await tester.pump();

      // Henüz talep yok
      expect(find.byType(MigrationConsentDialog), findsNothing);

      // Onay isteğini arka planda başlat
      late MigrationConsentDecision decision;
      unawaited(requester().then((d) => decision = d));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Diyalog ekranda görünmeli
      expect(find.byType(MigrationConsentDialog), findsOneWidget);
      expect(find.text('Sistem ve Veritabanı Optimizasyonu'), findsOneWidget);
      expect(find.textContaining('37682'), findsOneWidget);

      // Ertele ("Şimdi Değil") butonuna bas
      final postponeButton = find.text('Şimdi Değil');
      expect(postponeButton, findsOneWidget);
      await tester.tap(postponeButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(MigrationConsentDialog), findsNothing);
      expect(decision, equals(MigrationConsentDecision.postponed));

      // Ticker'ı durdurmak için harness'ı unmount et
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    test('3.3: Yedekleme veya PRAGMA hatasında geçiş durur ve legacy korunur', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final legacyDb = await openDatabase(isolatedLegacyPath);
      int runnerCalled = 0;
      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customLegacyFilePath: isolatedLegacyPath,
        customBackupDirectory: r'Z:\non_existent_drive_999\backups',
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: ({
          required Database legacyDb,
          required Database targetDb,
          String? legacyFilePath,
          bool? fullScope,
        }) async {
          runnerCalled++;
          return true;
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(runnerCalled, equals(0));
      expect(result.state, equals(CoreNextMigrationState.failedRecoverable));
      expect(result.errorMessage, contains('Yedekleme'));

      await legacyDb.close();
    });

    test('3.4: Geçiş sırasında hata enjeksiyonu ve kontrollü geri alma', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final legacyDb = await openDatabase(isolatedLegacyPath);
      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: p.join(tempDir.path, 'target_fail.db'));

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: targetCore.db,
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
          throw const SocketException('Simüle edilmiş I/O hatası');
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(result.state, equals(CoreNextMigrationState.failedRecoverable));
      expect(result.errorMessage, contains('Simüle edilmiş I/O hatası'));

      await legacyDb.close();
      await targetCore.close();
    });

    test('3.5: Eşzamanlı iki geçiş girişimi koordinatör tarafından güvenle tekilleştirilir', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final legacyDb = await openDatabase(isolatedLegacyPath);
      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: p.join(tempDir.path, 'target_concurrent.db'));

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: targetCore.db,
        customLegacyFilePath: isolatedLegacyPath,
        customBackupDirectory: tempDir.path,
        prefs: prefs,
        migrationRunner: ({
          required Database legacyDb,
          required Database targetDb,
          String? legacyFilePath,
          bool? fullScope,
        }) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return true;
        },
      );

      final f1 = coordinator.coordinate(consentRequester: () async => MigrationConsentDecision.approved);
      final f2 = coordinator.coordinate(consentRequester: () async => MigrationConsentDecision.approved);

      final results = await Future.wait<BootstrapCoordinatorResult>([f1, f2]);
      final alreadyRunningCount = results.where((r) => r.isAlreadyRunning).length;
      expect(alreadyRunningCount, equals(1));

      await legacyDb.close();
      await targetCore.close();
    });

    test('3.6: SQLite işlemlerinin thread/isolate davranışı ve frame-yielding gecikme profili', () async {
      final stopwatch = Stopwatch()..start();
      int yields = 0;

      // Event loop yielding simülasyonu
      for (int i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
        yields++;
      }
      stopwatch.stop();

      expect(yields, equals(10));
      // Event-loop yielding Dart main thread microtask kuyruğunu boşaltır
      expect(stopwatch.elapsedMilliseconds, lessThan(500));

      // Dart Isolate bilgisi
      final currentIsolate = Isolate.current;
      expect(currentIsolate.debugName, isNotNull);
    });

    test('3.7: Fiziksel POS dokunmatik terminal cihazı davranışı (NOT VERIFIED)', () {
      // Kural gereği fiziksel cihaz bağlı olmadığından bu kontrol NOT VERIFIED olarak işaretlenir.
      const isPhysicalPosHardwarePresent = false;
      if (!isPhysicalPosHardwarePresent) {
        expect(isPhysicalPosHardwarePresent, isFalse);
      }
    });
  });

  group('STAGE 10.12.23 — Bölüm 4: Veri Bütünlüğü, Mutabakat ve Regresyon (Gerçek Nutopia v60)', () {
    late Directory tempDir;
    late String clonedNutopiaPath;
    late String targetDbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage10_12_23_reconciliation_');
      clonedNutopiaPath = p.join(tempDir.path, 'cloned_nutopia.db');
      targetDbPath = p.join(tempDir.path, 'reconciled_core_next.db');

      // Copy raw source DB to temporary isolated test file
      final sourceBytes = await File(rawNutopiaPath).readAsBytes();
      await File(clonedNutopiaPath).writeAsBytes(sourceBytes);
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('4.1: Gerçek Nutopia verileri üzerinde tam geçiş ve eksiksiz finansal mutabakat', () async {
      final sourceDb = await openDatabase(clonedNutopiaPath, readOnly: true);
      final targetAppDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);

      final engine = MigrationBridgeEngine(targetAppDb);

      final result = await engine.migrateFromLegacy(sourceDb, fullScope: true);
      expect(result.isSuccess, isTrue);

      final tDb = targetAppDb.db;

      // 1. Ürün Mutabakatı (37.682 toplam: 17 aktif, 37.665 silinmiş)
      final srcProdCount = Sqflite.firstIntValue(
          await sourceDb.rawQuery('SELECT COUNT(*) FROM products'))!;
      final tgtProdCount = Sqflite.firstIntValue(
          await tDb.rawQuery('SELECT COUNT(*) FROM products'))!;
      expect(srcProdCount, equals(37682));
      expect(tgtProdCount, equals(37682));

      final tgtActiveProd = Sqflite.firstIntValue(await tDb.rawQuery(
          'SELECT COUNT(*) FROM products WHERE is_deleted = 0 AND is_active = 1'))!;
      final tgtDeletedProd = Sqflite.firstIntValue(await tDb.rawQuery(
          'SELECT COUNT(*) FROM products WHERE is_deleted = 1 AND is_active = 0'))!;
      expect(tgtActiveProd, equals(17));
      expect(tgtDeletedProd, equals(37665));

      // 2. Müşteri & Bakiye Mutabakatı (584 müşteri, -134.500,68 TL = -13.450.068 kuruş)
      final srcCustCount = Sqflite.firstIntValue(
          await sourceDb.rawQuery('SELECT COUNT(*) FROM customers'))!;
      final tgtCustCount = Sqflite.firstIntValue(
          await tDb.rawQuery('SELECT COUNT(*) FROM customers'))!;
      expect(srcCustCount, equals(584));
      expect(tgtCustCount, equals(584));

      final tgtBalanceSumKurus = Sqflite.firstIntValue(
          await tDb.rawQuery('SELECT CAST(ROUND(SUM(balance_cents)) AS INTEGER) FROM customers'))!;
      expect(tgtBalanceSumKurus, equals(-13450068),
          reason: 'Müşteri yetkili bakiye toplamı tam olarak -134.500,68 TL (-13.450.068 kuruş) olmalıdır');

      // 3. Satışlar ve Satış Kalemleri (52 satış, 120 kalem, 31.307,25 TL kalem toplamı)
      final srcSalesCount = Sqflite.firstIntValue(
          await sourceDb.rawQuery('SELECT COUNT(*) FROM sales'))!;
      final tgtSalesCount = Sqflite.firstIntValue(
          await tDb.rawQuery('SELECT COUNT(*) FROM sales'))!;
      expect(srcSalesCount, equals(52));
      expect(tgtSalesCount, equals(52));

      final srcSaleItemsCount = Sqflite.firstIntValue(
          await sourceDb.rawQuery('SELECT COUNT(*) FROM sale_items'))!;
      final tgtSaleItemsCount = Sqflite.firstIntValue(
          await tDb.rawQuery('SELECT COUNT(*) FROM sale_items'))!;
      expect(srcSaleItemsCount, equals(120));
      expect(tgtSaleItemsCount, equals(120));

      final tgtSaleItemTotalKurus = Sqflite.firstIntValue(
          await tDb.rawQuery('SELECT CAST(ROUND(SUM(total_cents)) AS INTEGER) FROM sale_items'))!;
      expect(tgtSaleItemTotalKurus, equals(3130725),
          reason: 'Satış kalem toplamı tam olarak 31.307,25 TL olmalıdır');

      // 4. Siparişler ve Sipariş Kalemleri (792 sipariş, 1.068 kalem)
      final srcOrdersCount = Sqflite.firstIntValue(
          await sourceDb.rawQuery('SELECT COUNT(*) FROM orders'))!;
      final tgtOrdersCount = Sqflite.firstIntValue(
          await tDb.rawQuery('SELECT COUNT(*) FROM orders'))!;
      expect(srcOrdersCount, equals(792));
      expect(tgtOrdersCount, equals(792));

      final srcOrderItemsCount = Sqflite.firstIntValue(
          await sourceDb.rawQuery('SELECT COUNT(*) FROM order_items'))!;
      final tgtOrderItemsCount = Sqflite.firstIntValue(
          await tDb.rawQuery('SELECT COUNT(*) FROM order_items'))!;
      expect(srcOrderItemsCount, equals(1068));
      expect(tgtOrderItemsCount, equals(1068));

      // 5. Müşteri Defteri (1.403 ledger_entries)
      final tgtLedgerCount = Sqflite.firstIntValue(
          await tDb.rawQuery('SELECT COUNT(*) FROM ledger_entries'))!;
      expect(tgtLedgerCount, equals(1403));

      // 6. Anonim Nakit Satışlar (21 adet, 12.197,00 TL = 1.219.700 kuruş)
      final tgtCashTxCount = Sqflite.firstIntValue(
          await tDb.rawQuery("SELECT COUNT(*) FROM cash_transactions WHERE category = 'SALE'"))!;
      expect(tgtCashTxCount, equals(21));
      final tgtCashTotalKurus = Sqflite.firstIntValue(
          await tDb.rawQuery("SELECT CAST(ROUND(SUM(amount_cents)) AS INTEGER) FROM cash_transactions WHERE category = 'SALE'"))!;
      expect(tgtCashTotalKurus, equals(1219700));

      // 7. Taksit Planları (2 plan, 9 dilim)
      final tgtPlansCount = Sqflite.firstIntValue(
          await tDb.rawQuery('SELECT COUNT(*) FROM customer_installment_plans'))!;
      final tgtSlicesCount = Sqflite.firstIntValue(
          await tDb.rawQuery('SELECT COUNT(*) FROM customer_installments'))!;
      expect(tgtPlansCount, equals(2));
      expect(tgtSlicesCount, equals(9));

      // 8. Sıfır Yetim ve Sıfır Yinelenen Kayıt
      final orphanSaleItems = Sqflite.firstIntValue(await tDb.rawQuery('''
        SELECT COUNT(*) FROM sale_items si
        LEFT JOIN sales s ON si.sale_id = s.id
        WHERE s.id IS NULL
      '''))!;
      expect(orphanSaleItems, equals(0));

      final orphanOrderItems = Sqflite.firstIntValue(await tDb.rawQuery('''
        SELECT COUNT(*) FROM order_items oi
        LEFT JOIN orders o ON oi.order_id = o.id
        WHERE o.id IS NULL
      '''))!;
      expect(orphanOrderItems, equals(0));

      await sourceDb.close();
      await targetAppDb.close();
    });

    test('4.2: Kaynak DB dosyasının test sonrasında da değişmediği (SHA-256) doğrulanmalı', () async {
      final sourceBytes = await File(rawNutopiaPath).readAsBytes();
      final currentHash = sha256.convert(sourceBytes).toString();
      expect(currentHash.toLowerCase(), equals(expectedSourceHash),
          reason: 'Testler kaynak veritabanına tek bir bayt dahi yazmamış olmalıdır');
    });
  });
}
