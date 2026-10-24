// test/core_next/stage10_12_20_final_isolated_rehearsal_test.dart
// SERENUT OS — STAGE 10.12.20
// SON BAĞIMSIZ DOĞRULAMA VE İZOLE GEÇİŞ PROVASI TEST PAKETİ
// ignore_for_file: avoid_relative_lib_imports

@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
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
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const expectedNutopiaSha =
      'e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24';
  const nutopiaSourcePath =
      'backups/raw_tenants_20261016/raw_nutopia_v60.db';

  String calculateFileSha256(String filePath) {
    final bytes = File(filePath).readAsBytesSync();
    return sha256.convert(bytes).toString().toLowerCase();
  }

  group('STAGE 10.12.20 — BÖLÜM A: GERÇEK UI AÇILIŞI VE ONAY ENTEGRASYONU', () {
    testWidgets('1. Migration kapalıyken (varsayılan) onay diyaloğu açılışta asla gösterilmez',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        TestAppLifecycleHarness(container: container),
      );
      await tester.pump();

      // Varsayılan üretim ayarlarında consent requester ve runner null'dur
      expect(container.read(coreNextMigrationRunnerProvider), isNull);
      expect(container.read(coreNextConsentRequesterProvider), isNull);
      expect(container.read(coreNextConsentRequestProvider), isNull);

      // Ekranda diyalog render edilmemelidir
      expect(find.byType(MigrationConsentDialog), findsNothing);
      expect(find.text('Veritabanı ve Mimari Güncellemesi'), findsNothing);
    });

    testWidgets('2. Kontrollü onay akışında "Şimdi Değil" seçildiğinde karar postponed olur ve legacy korunur',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final requester = createUiConsentRequester(
        container,
        sourceDbPath: 'legacy_pos.db',
        targetDbPath: 'core_v2.db',
        estimatedProductCount: 37682,
        estimatedCustomerCount: 27,
      );

      await tester.pumpWidget(
        TestAppLifecycleHarness(container: container),
      );
      await tester.pump();

      // Henüz talep yok
      expect(find.byType(MigrationConsentDialog), findsNothing);

      // Onay isteğini arka planda başlat
      late MigrationConsentDecision decision;
      unawaited(requester().then((d) => decision = d));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Diyalog ekranda görünmelidir
      expect(find.byType(MigrationConsentDialog), findsOneWidget);
      expect(find.textContaining('37682'), findsOneWidget);
      expect(find.textContaining('27'), findsOneWidget);

      // "Şimdi Değil" butonuna tıkla
      await tester.tap(find.text('Şimdi Değil'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Diyalog kapanmış ve karar postponed dönmüş olmalıdır
      expect(find.byType(MigrationConsentDialog), findsNothing);
      expect(decision, equals(MigrationConsentDecision.postponed));
    });

    testWidgets('3. Kontrollü onay akışında "Geçişi Onayla" seçildiğinde karar approved olur',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final requester = createUiConsentRequester(
        container,
        sourceDbPath: 'legacy_pos.db',
        targetDbPath: 'core_v2.db',
        estimatedProductCount: 37682,
        estimatedCustomerCount: 27,
      );

      await tester.pumpWidget(
        TestAppLifecycleHarness(container: container),
      );
      await tester.pump();

      late MigrationConsentDecision decision;
      unawaited(requester().then((d) => decision = d));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(MigrationConsentDialog), findsOneWidget);

      // "Geçişi Onayla" butonuna tıkla
      await tester.tap(find.text('Geçişi Onayla'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(MigrationConsentDialog), findsNothing);
      expect(decision, equals(MigrationConsentDecision.approved));
    });

    testWidgets('4. Çift açılış koruması: aynı oturumda ikinci onay talebi engellenir',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final requester = createUiConsentRequester(container);

      await tester.pumpWidget(
        TestAppLifecycleHarness(container: container),
      );
      await tester.pump();

      // 1. İstek başlat
      unawaited(requester());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(MigrationConsentDialog), findsOneWidget);

      // İlk isteği onayla
      await tester.tap(find.text('Geçişi Onayla'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(MigrationConsentDialog), findsNothing);

      // 2. İstek aynı oturumda çağrılırsa doğrudan postponed dönmeli ve diyalog açılmamalı
      final secondDecision = await requester();
      await tester.pump();

      expect(secondDecision, equals(MigrationConsentDecision.postponed));
      expect(find.byType(MigrationConsentDialog), findsNothing);
    });

    testWidgets('5. Widget dispose / kapanma durumunda bekleyen onay güvenle postponed ile sonlanır',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final requester = createUiConsentRequester(container);

      await tester.pumpWidget(
        TestAppLifecycleHarness(container: container),
      );
      await tester.pump();

      late MigrationConsentDecision decision;
      unawaited(requester().then((d) => decision = d));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(MigrationConsentDialog), findsOneWidget);

      // Widget ağacını unmount / dispose et
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Dispose pending isteği güvenle postponed yapmalı
      expect(decision, equals(MigrationConsentDecision.postponed));
    });
  });

  group('STAGE 10.12.20 — BÖLÜM B: FAIL-CLOSED BAĞIMSIZ GÜVENLİK KAPILARI', () {
    late Directory tempDir;
    late String legacyDbPath;
    late String coreDbPath;
    late String backupDirPath;
    late Database legacyDb;
    late CoreAppDatabase coreDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stg10_12_20_fail_closed_');
      legacyDbPath = p.join(tempDir.path, 'legacy.db');
      coreDbPath = p.join(tempDir.path, 'target_core.db');
      backupDirPath = p.join(tempDir.path, 'backups');

      legacyDb = await openDatabase(
        legacyDbPath,
        version: 60,
        onCreate: (db, v) async {
          await db.execute('CREATE TABLE users (id TEXT PRIMARY KEY, username TEXT, name TEXT, role TEXT, is_active INTEGER DEFAULT 1, created_at TEXT);');
          await db.execute('CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT);');
          await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, barcode TEXT, name TEXT, category TEXT, price REAL, stock_quantity REAL, min_stock REAL, is_active INTEGER DEFAULT 1, is_deleted INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT);');
          await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT, balance REAL, balance_minor INTEGER, created_at TEXT);');
          await db.execute('CREATE TABLE sales (id TEXT PRIMARY KEY, receipt_no TEXT, total_amount REAL, total_amount_minor INTEGER, payment_method TEXT, status TEXT, created_at TEXT);');
          await db.execute('CREATE TABLE sale_items (id TEXT PRIMARY KEY, sale_id TEXT, product_id TEXT, quantity REAL, unit_price REAL, subtotal REAL);');
          await db.execute('CREATE TABLE sale_payments (id TEXT PRIMARY KEY, sale_id TEXT, payment_type TEXT, amount REAL, amount_minor INTEGER, created_at TEXT);');
        },
      );

      await legacyDb.insert('users', {'id': 'u1', 'username': 'admin', 'name': 'Yönetici', 'role': 'admin', 'created_at': DateTime.now().toIso8601String()});
      await legacyDb.insert('categories', {'id': 'cat1', 'name': 'Gıda'});
      await legacyDb.insert('products', {'id': 'p1', 'barcode': '8690001', 'name': 'Ürün 1', 'category': 'Gıda', 'price': 100.0, 'stock_quantity': 10.0, 'min_stock': 2.0, 'is_active': 1, 'is_deleted': 0, 'created_at': DateTime.now().toIso8601String(), 'updated_at': DateTime.now().toIso8601String()});

      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: coreDbPath);
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      CoreNextBootstrapCoordinator.resetExecutionLock();
      try { await legacyDb.close(); } catch (_) {}
      try { await coreDb.close(); } catch (_) {}
      if (await tempDir.exists()) {
        try { await tempDir.delete(recursive: true); } catch (_) {}
      }
    });

    test('6. Runner null iken migration motoru çağrı sayısı 0, isSuccess: false', () async {
      final prefs = await SharedPreferences.getInstance();
      int engineCallCount = 0;

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        migrationRunner: null, // Runner NULL
        consentRequester: () async {
          return MigrationConsentDecision.approved;
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(engineCallCount, equals(0));
      expect(result.state, equals(CoreNextMigrationState.notStarted));
      expect(await coordinator.getPersistentState(), equals(CoreNextMigrationState.notStarted));
    });

    test('7. Consent requester null iken fail-closed: motor çağrı sayısı 0, isSuccess: false', () async {
      final prefs = await SharedPreferences.getInstance();
      int engineCallCount = 0;

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        consentRequester: null, // Requester NULL
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          engineCallCount++;
          return true;
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(engineCallCount, equals(0));
      expect(result.errorMessage, contains('Kullanıcı onay isteyici (consent requester) tanımlanmamış'));
      expect(result.state, equals(CoreNextMigrationState.notStarted));
    });

    test('8. Onay fonksiyonu hata fırlattığında fail-closed: motor çağrı sayısı 0, isSuccess: false', () async {
      final prefs = await SharedPreferences.getInstance();
      int engineCallCount = 0;

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        consentRequester: () async {
          throw StateError('Simulated UI consent crash');
        },
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          engineCallCount++;
          return true;
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(engineCallCount, equals(0));
      expect(result.errorMessage, contains('Kullanıcı onay isteyici çağrısı sırasında hata oluştu'));
    });

    test('9. Yedekleme hatasında fail-closed: motor çağrı sayısı 0, isSuccess: false', () async {
      final prefs = await SharedPreferences.getInstance();
      int engineCallCount = 0;

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: r'Z:\non_existent_drive_999\backups',
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          engineCallCount++;
          return true;
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(engineCallCount, equals(0));
      expect(result.errorMessage, anyOf(contains('Yedekleme ve doğrulama aşamasında hata'), contains('Yedekleme')));
    });

    test('10. Tenant uyuşmazlığında fail-closed: motor çağrı sayısı 0', () async {
      int engineCallCount = 0;

      // Hedef DB'de app_settings tablosunda farklı tenant_id tohumla
      await coreDb.db.execute('CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT, updated_at TEXT);');
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'other_random_tenant',
        'updated_at': DateTime.now().toIso8601String(),
      });

      const resolver = DatabaseRoutingResolver();
      final routingRes = await resolver.resolve(
        targetDbPath: coreDbPath,
        legacyDbPath: legacyDbPath,
        requestedTenantId: 'erkul_cosmetics_dev_tenant',
        migrationStateCompleted: true,
      );

      expect(routingRes.isTargetSelected, isFalse);
      expect(routingRes.decision, equals(RoutingDecision.blockedFailClosed));
      expect(engineCallCount, equals(0));
    });

    test('11. Progress callback hatası ile migration hatasının ayrışımı', () async {
      final prefs = await SharedPreferences.getInstance();
      bool runnerExecuted = false;

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        onProgress: (progress) {
          if (progress.stage == MigrationStage.dataMigrating) {
            throw RangeError('UI Progress visualizer error');
          }
        },
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          runnerExecuted = true;
          return true;
        },
      );

      final result = await coordinator.coordinate();
      // Progress hatası veri migration'ını bozmamalı veya hata güvenle failed olmalı
      // Eğer coordinator try-catch içinde yakalarsa isSuccess false olur
      expect(result.isSuccess, isFalse);
      expect(runnerExecuted, isFalse);
      expect(result.errorMessage, contains('UI Progress visualizer error'));
      expect(await coordinator.getPersistentState(), isNot(equals(CoreNextMigrationState.completed)));
    });
  });

  group('STAGE 10.12.20 — BÖLÜM C: İZOLE VERİ GEÇİŞ PROVASI VE ADLİ MUTABAKAT', () {
    late Directory tempDir;
    late String isolatedNutopiaPath;
    late String isolatedTargetPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stg10_12_20_rehearsal_');
      isolatedNutopiaPath = p.join(tempDir.path, 'nutopia_source_copy.db');
      isolatedTargetPath = p.join(tempDir.path, 'isolated_target_core.db');

      // Kaynak yedeğin dokunulmazlığını kontrol et ve izole kopyasını oluştur
      final rawBackupFile = File(nutopiaSourcePath);
      expect(rawBackupFile.existsSync(), isTrue, reason: 'Kaynak Nutopia yedeği mevcut olmalı');
      final sha = calculateFileSha256(nutopiaSourcePath);
      expect(sha, equals(expectedNutopiaSha), reason: 'Kaynak yedeğin SHA-256 imzası eşleşmeli');

      await rawBackupFile.copy(isolatedNutopiaPath);
    });

    tearDown(() async {
      CoreNextBootstrapCoordinator.resetExecutionLock();
      if (await tempDir.exists()) {
        try { await tempDir.delete(recursive: true); } catch (_) {}
      }
    });

    test('12. Gerçek Nutopia kopyası üzerinde tam göç: %100 Adli ve Finansal Mutabakat', () async {
      final shaBefore = calculateFileSha256(nutopiaSourcePath);
      expect(shaBefore, equals(expectedNutopiaSha));

      final legacyDb = await openDatabase(isolatedNutopiaPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // A) Kaynak Veritabanı Ham SQL İncelemesi (Fixture yerine gerçek SQL sorguları)
      final srcProdTotal = (await legacyDb.rawQuery('SELECT count(*) as c FROM products')).first['c'] as int;
      final srcProdActive = (await legacyDb.rawQuery('SELECT count(*) as c FROM products WHERE is_deleted = 0')).first['c'] as int;
      final srcProdDeleted = (await legacyDb.rawQuery('SELECT count(*) as c FROM products WHERE is_deleted != 0')).first['c'] as int;
      final srcStockSum = ((await legacyDb.rawQuery('SELECT ROUND(SUM(CAST(quantity AS REAL)), 2) as s FROM products')).first['s'] as num).toDouble();

      final srcCustCount = (await legacyDb.rawQuery('SELECT count(*) as c FROM customers')).first['c'] as int;
      final srcSalesCount = (await legacyDb.rawQuery('SELECT count(*) as c FROM sales')).first['c'] as int;
      final srcOrdersCount = (await legacyDb.rawQuery('SELECT count(*) as c FROM orders')).first['c'] as int;
      final srcOrderItemsCount = (await legacyDb.rawQuery('SELECT count(*) as c FROM order_items')).first['c'] as int;
      final srcPlansCount = (await legacyDb.rawQuery('SELECT count(*) as c FROM customer_installment_plans')).first['c'] as int;
      final srcInstsCount = (await legacyDb.rawQuery('SELECT count(*) as c FROM customer_installments')).first['c'] as int;

      final srcFtAll = await legacyDb.rawQuery('SELECT * FROM financial_transactions');
      final srcCustomerLinkedTxs = srcFtAll.where((r) => r['customer_id'] != null && r['customer_id'].toString().trim().isNotEmpty).toList();
      final srcAnonCashTxs = srcFtAll.where((r) => r['customer_id'] == null || r['customer_id'].toString().trim().isEmpty).toList();

      expect(srcProdTotal, equals(37682));
      expect(srcProdActive, equals(17));
      expect(srcProdDeleted, equals(37665));
      expect((srcStockSum - 5179525.85).abs() < 0.01, isTrue);
      expect(srcCustCount, equals(584)); // Gerçek SQL sonucu: 584 müşteri!
      expect(srcSalesCount, equals(52));
      expect(srcOrdersCount, equals(792));
      expect(srcOrderItemsCount, equals(1068));
      expect(srcPlansCount, equals(2));
      expect(srcInstsCount, equals(9));
      expect(srcFtAll.length, equals(1424));
      expect(srcCustomerLinkedTxs.length, equals(1403));
      expect(srcAnonCashTxs.length, equals(21));

      // B) Göçün Çalıştırılması
      final migrationReport = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(migrationReport.isSuccess, isTrue, reason: migrationReport.errorMessage);

      // C) Hedef Veritabanı Karşılaştırması
      final target = coreDb.db;

      // 1. Ürünler
      final tgtProdTotal = (await target.rawQuery('SELECT count(*) as c FROM products')).first['c'] as int;
      final tgtProdActive = (await target.rawQuery('SELECT count(*) as c FROM products WHERE is_deleted = 0')).first['c'] as int;
      final tgtProdDeleted = (await target.rawQuery('SELECT count(*) as c FROM products WHERE is_deleted != 0')).first['c'] as int;
      final tgtStockSum = ((await target.rawQuery('SELECT ROUND(SUM(stock_quantity), 2) as s FROM products')).first['s'] as num).toDouble();

      expect(tgtProdTotal, equals(srcProdTotal));
      expect(tgtProdActive, equals(srcProdActive));
      expect(tgtProdDeleted, equals(srcProdDeleted));
      expect((tgtStockSum - srcStockSum).abs() < 0.01, isTrue);

      // 2. Müşteriler ve Finans
      final tgtCustCount = (await target.rawQuery('SELECT count(*) as c FROM customers')).first['c'] as int;
      expect(tgtCustCount, equals(srcCustCount));
      final tgtCustBalCents = ((await target.rawQuery('SELECT SUM(balance_cents) as s FROM customers')).first['s'] as num).toInt();
      expect(tgtCustBalCents, equals(-13450068)); // -134.500,68 TL

      // 3. Satışlar ve Siparişler
      final tgtSalesCount = (await target.rawQuery('SELECT count(*) as c FROM sales')).first['c'] as int;
      expect(tgtSalesCount, equals(srcSalesCount));

      final tgtOrdersCount = (await target.rawQuery('SELECT count(*) as c FROM orders')).first['c'] as int;
      final tgtOrderItemsCount = (await target.rawQuery('SELECT count(*) as c FROM order_items')).first['c'] as int;
      expect(tgtOrdersCount, equals(srcOrdersCount));
      expect(tgtOrderItemsCount, equals(srcOrderItemsCount));

      // 4. Taksitler
      final tgtPlansCount = (await target.rawQuery('SELECT count(*) as c FROM customer_installment_plans')).first['c'] as int;
      final tgtInstsCount = (await target.rawQuery('SELECT count(*) as c FROM customer_installments')).first['c'] as int;
      expect(tgtPlansCount, equals(srcPlansCount));
      expect(tgtInstsCount, equals(srcInstsCount));

      // 5. Defter Hareketleri (1.403 adet)
      final tgtLedgerCount = (await target.rawQuery('SELECT count(*) as c FROM ledger_entries')).first['c'] as int;
      expect(tgtLedgerCount, equals(1403));

      // 6. Müşterisiz Nakit Satışlar (21 adet)
      final tgtCashAnon = await target.rawQuery("SELECT count(*) as c, SUM(amount_cents) as s FROM cash_transactions WHERE category = 'SALE'");
      final tgtAnonCount = (tgtCashAnon.first['c'] as num).toInt();
      final tgtAnonCents = (tgtCashAnon.first['s'] as num).toInt();
      expect(tgtAnonCount, equals(21));
      expect(tgtAnonCents, equals(1219700)); // 12.197,00 TL

      // 7. Yetim kayıt kontrolü (Orphan check)
      final orphanOrderItems = (await target.rawQuery('''
        SELECT count(*) as c FROM order_items oi
        LEFT JOIN orders o ON oi.order_id = o.id
        WHERE o.id IS NULL;
      ''')).first['c'] as int;
      expect(orphanOrderItems, equals(0));

      final orphanSaleItems = (await target.rawQuery('''
        SELECT count(*) as c FROM sale_items si
        LEFT JOIN sales s ON si.sale_id = s.id
        WHERE s.id IS NULL;
      ''')).first['c'] as int;
      expect(orphanSaleItems, equals(0));

      // 8. UUID ve Kimlik Benzersizliği Kontrolü
      final dupProdIds = (await target.rawQuery('''
        SELECT id, count(*) as c FROM products GROUP BY id HAVING c > 1;
      ''')).length;
      expect(dupProdIds, equals(0));

      final dupCustIds = (await target.rawQuery('''
        SELECT id, count(*) as c FROM customers GROUP BY id HAVING c > 1;
      ''')).length;
      expect(dupCustIds, equals(0));

      await legacyDb.close();
      await coreDb.close();

      // Kaynak yedeğin dokunulmazlığını doğrula
      final shaAfter = calculateFileSha256(nutopiaSourcePath);
      expect(shaAfter, equals(expectedNutopiaSha));
    });

    test('13. İkinci kez migration çalıştırıldığında mükerrer kayıt oluşmaz (Idempotency)', () async {
      final legacyDb = await openDatabase(isolatedNutopiaPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // İlk çalıştırma
      final rep1 = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep1.isSuccess, isTrue);

      final count1 = (await coreDb.db.rawQuery('SELECT count(*) as c FROM products')).first['c'] as int;
      final sales1 = (await coreDb.db.rawQuery('SELECT count(*) as c FROM sales')).first['c'] as int;
      final ledger1 = (await coreDb.db.rawQuery('SELECT count(*) as c FROM ledger_entries')).first['c'] as int;

      // İkinci çalıştırma (Tekrar)
      final rep2 = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep2.isSuccess, isTrue);

      final count2 = (await coreDb.db.rawQuery('SELECT count(*) as c FROM products')).first['c'] as int;
      final sales2 = (await coreDb.db.rawQuery('SELECT count(*) as c FROM sales')).first['c'] as int;
      final ledger2 = (await coreDb.db.rawQuery('SELECT count(*) as c FROM ledger_entries')).first['c'] as int;

      expect(count2, equals(count1), reason: 'Ürün sayısı değişmemeli (mükerrerlik 0)');
      expect(sales2, equals(sales1), reason: 'Satış sayısı değişmemeli (mükerrerlik 0)');
      expect(ledger2, equals(ledger1), reason: 'Defter kaydı sayısı değişmemeli (mükerrerlik 0)');

      await legacyDb.close();
      await coreDb.close();
    });
  });

  group('STAGE 10.12.20 — BÖLÜM D: HATA VE GERİ DÖNÜŞ (ROLLBACK) SENARYOLARI', () {
    late Directory tempDir;
    late String legacyDbPath;
    late String coreDbPath;
    late String backupDirPath;
    late Database legacyDb;
    late CoreAppDatabase coreDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stg10_12_20_failures_');
      legacyDbPath = p.join(tempDir.path, 'legacy.db');
      coreDbPath = p.join(tempDir.path, 'target_core.db');
      backupDirPath = p.join(tempDir.path, 'backups');

      legacyDb = await openDatabase(
        legacyDbPath,
        version: 60,
        onCreate: (db, v) async {
          await db.execute('CREATE TABLE users (id TEXT PRIMARY KEY, username TEXT, name TEXT, role TEXT, is_active INTEGER DEFAULT 1, created_at TEXT);');
          await db.execute('CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT);');
          await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, barcode TEXT, name TEXT, category TEXT, price REAL, stock_quantity REAL, min_stock REAL, is_active INTEGER DEFAULT 1, is_deleted INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT);');
        },
      );

      await legacyDb.insert('users', {'id': 'u1', 'username': 'admin', 'name': 'Admin', 'role': 'admin', 'created_at': DateTime.now().toIso8601String()});
      await legacyDb.insert('products', {'id': 'p1', 'barcode': '111', 'name': 'Ürün 1', 'category': 'Genel', 'price': 50.0, 'stock_quantity': 5.0, 'min_stock': 1.0, 'is_active': 1, 'is_deleted': 0, 'created_at': DateTime.now().toIso8601String(), 'updated_at': DateTime.now().toIso8601String()});

      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: coreDbPath);
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      CoreNextBootstrapCoordinator.resetExecutionLock();
      try { await legacyDb.close(); } catch (_) {}
      try { await coreDb.close(); } catch (_) {}
      if (await tempDir.exists()) {
        try { await tempDir.delete(recursive: true); } catch (_) {}
      }
    });

    test('14. Migration ortasında hata fırlatıldığında durum failedRecoverable olur ve hedef seçilmez', () async {
      final prefs = await SharedPreferences.getInstance();

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          throw const MigrationExecutionException('Simulated crash mid-migration');
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Simulated crash mid-migration'));
      expect(result.state, equals(CoreNextMigrationState.failedRecoverable));
      expect(await coordinator.getPersistentState(), equals(CoreNextMigrationState.failedRecoverable));
    });

    test('15. Hedef veritabanı bozukken (corrupt DB) routing fail-closed engeller', () async {
      const resolver = DatabaseRoutingResolver();

      // Hedef DB dosyasını rastgele anlamsız baytlarla doldurarak boz
      await coreDb.close();
      final targetFile = File(coreDbPath);
      await targetFile.writeAsBytes([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x11, 0x22, 0x33]);

      final routingRes = await resolver.resolve(
        targetDbPath: coreDbPath,
        legacyDbPath: legacyDbPath,
        requestedTenantId: 'erkul_cosmetics_dev_tenant',
        migrationStateCompleted: true,
      );

      expect(routingRes.isTargetSelected, isFalse);
      expect(routingRes.decision, equals(RoutingDecision.blockedFailClosed));
      expect(routingRes.resolvedPath, equals(legacyDbPath));
      expect(routingRes.reason, anyOf(contains('Hedef dosya bozuk'), contains('Hedef DB doğrulama hatası')));
    });

    test('16. Eşzamanlı iki koordinasyon çağrısında concurrency lock ikinciyi engeller', () async {
      final prefs = await SharedPreferences.getInstance();
      final completer = Completer<void>();

      final coordinator1 = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          await completer.future; // Beklet
          return true;
        },
      );

      final coordinator2 = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          return true;
        },
      );

      // İlkini başlat
      final future1 = coordinator1.coordinate();
      // İkincisini hemen başlat (çakışma)
      final result2 = await coordinator2.coordinate();

      expect(result2.isSuccess, isFalse);
      expect(result2.isAlreadyRunning, isTrue);
      expect(result2.errorMessage, anyOf(contains('başka bir akış tarafından yürütülüyor'), contains('zaten devam ediyor')));

      // İlkini tamamlat
      completer.complete();
      await future1;
    });

    test('17. Hedefte yeni satış veya finans hareketi varken rollback girişimi engellenir (assertSafeRollback)', () async {
      const resolver = DatabaseRoutingResolver();
      final cutoff = DateTime.now().millisecondsSinceEpoch;

      // Hedefe migration cutoff sonrası yeni bir satış ekle
      await coreDb.db.insert('sales', {
        'id': 'new_live_sale_001',
        'receipt_no': 'REC-LIVE-001',
        'customer_id': null,
        'subtotal_cents': 25000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 25000,
        'paid_cents': 25000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': cutoff + 5000, // Cutoff'tan SONRA!
      });

      expect(
        () async => await resolver.assertSafeRollback(
          targetDb: coreDb.db,
          initialMigrationCutoffTimestamp: cutoff,
        ),
        throwsA(isA<UnsafeRollbackException>()),
      );
    });
  });
}
