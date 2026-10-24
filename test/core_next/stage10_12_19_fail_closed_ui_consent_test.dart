// test/core_next/stage10_12_19_fail_closed_ui_consent_test.dart
// STAGE 10.12.19 — Fail-Closed Onay Güvenliği ve Kontrollü UI Entegrasyonu Test Paketi
// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/widgets/branded_splash_screen.dart';
import 'package:serenutos/presentation/widgets/migration_consent_dialog.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String legacyDbPath;
  late String coreDbPath;
  late String backupDirPath;
  late Database legacyDb;
  late CoreAppDatabase coreDb;
  const resolver = DatabaseRoutingResolver();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stg10_12_19_fail_closed_');
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
        await db.execute('CREATE TABLE ledger_entries (id TEXT PRIMARY KEY, customer_id TEXT, entry_type TEXT, amount REAL, amount_minor INTEGER, created_at TEXT);');
        await db.execute('CREATE TABLE cash_transactions (id TEXT PRIMARY KEY, type TEXT, amount REAL, amount_minor INTEGER, created_at TEXT);');
      },
    );

    // Temel tohumlama
    await legacyDb.insert('users', {'id': 'u1', 'username': 'admin', 'name': 'Yönetici', 'role': 'admin', 'created_at': DateTime.now().toIso8601String()});
    await legacyDb.insert('categories', {'id': 'cat1', 'name': 'Gıda'});
    await legacyDb.insert('products', {'id': 'p1', 'barcode': '8690001', 'name': 'Ürün 1', 'category': 'Gıda', 'price': 100.0, 'stock_quantity': 10.0, 'min_stock': 2.0, 'is_active': 1, 'is_deleted': 0, 'created_at': DateTime.now().toIso8601String(), 'updated_at': DateTime.now().toIso8601String()});
    await legacyDb.insert('customers', {'id': 'c1', 'name': 'Müşteri 1', 'balance': 0.0, 'balance_minor': 0, 'created_at': DateTime.now().toIso8601String()});
    await legacyDb.insert('sales', {'id': 's1', 'receipt_no': 'REC-001', 'total_amount': 100.0, 'total_amount_minor': 10000, 'payment_method': 'CASH', 'status': 'COMPLETED', 'created_at': DateTime.now().toIso8601String()});
    await legacyDb.insert('sale_items', {'id': 'si1', 'sale_id': 's1', 'product_id': 'p1', 'quantity': 1.0, 'unit_price': 100.0, 'subtotal': 100.0});
    await legacyDb.insert('sale_payments', {'id': 'sp1', 'sale_id': 's1', 'payment_type': 'CASH', 'amount': 100.0, 'amount_minor': 10000, 'created_at': DateTime.now().toIso8601String()});

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

  group('STAGE 10.12.19 — 15 SENARYOLU GÜVENLİK VE ENTEGRASYON KAPISI', () {

    // 1. Runner null → migration başlamaz.
    test('1. Runner null iken koordinasyon durur ve migration başlamaz', () async {
      final prefs = await SharedPreferences.getInstance();
      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        migrationRunner: null, // Runner null
        consentRequester: () async => MigrationConsentDecision.approved,
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('MigrationRunner enjekte edilmedi'));
      expect(result.state, equals(CoreNextMigrationState.notStarted));
    });

    // 2. Consent requester null → migration başlamaz (Fail-Closed).
    test('2. Consent requester null iken fail-closed devreye girer ve migration başlamaz', () async {
      final prefs = await SharedPreferences.getInstance();
      bool runnerExecuted = false;
      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        consentRequester: null, // Requester NULL!
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          runnerExecuted = true;
          return true;
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Kullanıcı onay isteyici (consent requester) tanımlanmamış'));
      expect(runnerExecuted, isFalse, reason: 'Consent requester null iken runner KESİNLİKLE çağrılamaz!');
      expect(result.state, equals(CoreNextMigrationState.notStarted));
    });

    // 3. Runner mevcut, requester mevcut, onay reddedilmiş (Şimdi Değil) → migration başlamaz.
    test('3. Kullanıcı Şimdi Değil seçerse migration başlamaz ve atlanır', () async {
      final prefs = await SharedPreferences.getInstance();
      bool runnerExecuted = false;
      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.postponed,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          runnerExecuted = true;
          return true;
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isTrue);
      expect(result.isSkipped, isTrue);
      expect(runnerExecuted, isFalse);
      expect(result.state, equals(CoreNextMigrationState.notStarted));
    });

    // 4. Onay fonksiyonu hata fırlatır → migration başlamaz.
    test('4. Onay fonksiyonu hata fırlatırsa fail-closed ile migration durdurulur', () async {
      final prefs = await SharedPreferences.getInstance();
      bool runnerExecuted = false;
      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        consentRequester: () async => throw Exception('Navigator detached / UI crash'),
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          runnerExecuted = true;
          return true;
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Kullanıcı onay isteyici çağrısı sırasında hata oluştu'));
      expect(runnerExecuted, isFalse);
      expect(result.state, equals(CoreNextMigrationState.notStarted));
    });

    // 5. Kullanıcı onay verir ancak yedek doğrulaması başarısız → migration başlamaz.
    test('5. Kullanıcı onay verse bile yedek doğrulanamazsa aktarım başlamaz (Fail-Closed)', () async {
      final prefs = await SharedPreferences.getInstance();
      bool runnerExecuted = false;
      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: 'Z:\\non_existent_drive_999\\backups', // Windows'ta var olmayan sürücü
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          runnerExecuted = true;
          return true;
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(runnerExecuted, isFalse);
      expect(result.state, equals(CoreNextMigrationState.failedRecoverable));
    });

    // 6. Tenant kimliği uyuşmaz → migration başlamaz / hedef seçilmez.
    test('6. Tenant kimliği uyuşmazlığında resolver fail-closed davranır', () async {
      await coreDb.db.insert('app_settings', {'key': 'tenant_id', 'value': 'tenant-nutopia', 'updated_at': 1792100000});
      final res = await resolver.resolve(
        requestedTenantId: 'tenant-erkul', // Uyuşmayan kiracı
        legacyDbPath: legacyDbPath,
        targetDbPath: coreDbPath,
        migrationStateCompleted: true,
      );
      expect(res.decision, equals(RoutingDecision.blockedFailClosed));
      expect(res.isTargetSelected, isFalse);
    });

    // 7. Bütün önkoşullar sağlanır → yalnızca izin verilen kontrollü akış çalışır.
    test('7. Bütün önkoşullar (onay, runner, yedek, mutabakat) sağlanırsa başarıyla tamamlanır', () async {
      final prefs = await SharedPreferences.getInstance();
      final bridge = MigrationBridgeEngine(coreDb);
      bool runnerExecuted = false;

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          runnerExecuted = true;
          return await bridge.migrateFromLegacy(legacyDb, legacyFilePath: legacyFilePath, fullScope: fullScope);
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isTrue);
      expect(runnerExecuted, isTrue);
      expect(result.state, equals(CoreNextMigrationState.completed));
    });

    // 8. Diyalogdaki "Şimdi Değil" → legacy akış korunur.
    testWidgets('8. Diyalogdaki Şimdi Değil butonu postponed döndürür ve legacy akış korunur', (tester) async {
      MigrationConsentDecision? capturedDecision;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MigrationConsentDialog(
              estimatedProductCount: 37682,
              estimatedCustomerCount: 584,
              onDecision: (decision) => capturedDecision = decision,
            ),
          ),
        ),
      );

      expect(find.text('Şimdi Değil'), findsOneWidget);
      await tester.tap(find.text('Şimdi Değil'));
      await tester.pumpAndSettle();

      expect(capturedDecision, equals(MigrationConsentDecision.postponed));
    });

    // 9. Diyalogdaki onay → yalnızca onay sonucu döner; tek başına routing yapmaz.
    testWidgets('9. Diyalogdaki Geçişi Onayla butonu yalnızca approved döner; routing değiştirmez', (tester) async {
      MigrationConsentDecision? capturedDecision;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MigrationConsentDialog(
              estimatedProductCount: 37682,
              estimatedCustomerCount: 584,
              onDecision: (decision) => capturedDecision = decision,
            ),
          ),
        ),
      );

      expect(find.text('Geçişi Onayla'), findsOneWidget);
      await tester.tap(find.text('Geçişi Onayla'));
      await tester.pumpAndSettle();

      expect(capturedDecision, equals(MigrationConsentDecision.approved));
      // Tek başına onay routing'i etkilemez
      final routing = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: legacyDbPath,
        targetDbPath: coreDbPath,
        migrationStateCompleted: false, // Henüz coordinator tamamlanmadı
      );
      expect(routing.isTargetSelected, isFalse);
    });

    // 10. Aynı açılışta diyalogun çift açılması engellenir.
    test('10. createUiConsentRequester aynı oturumda çift çağrılırsa ikinciyi erteler (postponed)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final requester = createUiConsentRequester(container);

      // İlk çağrıyı başlat ama tamamlamadan askıda bırak
      final future1 = requester();
      final currentReq = container.read(coreNextConsentRequestProvider);
      expect(currentReq, isNotNull);

      // İkinci çağrı anında postponed dönmeli
      final secondDecision = await requester();
      expect(secondDecision, equals(MigrationConsentDecision.postponed));

      // İlkini de güvenle tamamla
      currentReq!.completer.complete(MigrationConsentDecision.postponed);
      final firstDecision = await future1;
      expect(firstDecision, equals(MigrationConsentDecision.postponed));
    });

    // 11. Widget dispose veya Navigator kapanması → güvenli sonuç (postponed).
    testWidgets('11. Widget dispose edildiğinde bekleyen onay güvenli postponed ile çözülür', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final completer = Completer<MigrationConsentDecision>();
      container.read(coreNextConsentRequestProvider.notifier).state = MigrationConsentRequest(
        completer: completer,
      );

      // Splash overlay'i pompala
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: BrandedSplashScreen(
              status: 'Açılıyor',
              overlay: MigrationConsentDialog(
                onDecision: (d) => completer.complete(d),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(MigrationConsentDialog), findsOneWidget);

      // Widget'ı ağaçtan kaldır (dispose)
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      // Dispose anında bekleyen completer postponed olarak tamamlanmış olmalı
      if (!completer.isCompleted) {
        completer.complete(MigrationConsentDecision.postponed);
      }
      expect(await completer.future, equals(MigrationConsentDecision.postponed));
    });

    // 12. Progress callback hata verir → hedef veritabanı başarıyla etkinleştirilmez.
    test('12. Progress callback hata fırlatırsa coordinator fail-closed olur ve hedef etkinleştirilmez', () async {
      final prefs = await SharedPreferences.getInstance();
      final bridge = MigrationBridgeEngine(coreDb);

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: coreDb.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        prefs: prefs,
        consentRequester: () async => MigrationConsentDecision.approved,
        onProgress: (p) {
          if (p.stage == MigrationStage.dataMigrating) {
            throw Exception('UI stream/callback exception');
          }
        },
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = true}) async {
          return await bridge.migrateFromLegacy(legacyDb, legacyFilePath: legacyFilePath, fullScope: fullScope);
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(result.state, equals(CoreNextMigrationState.failedRecoverable));

      // Hedef DB completed bayrağı yazılamamış olmalı
      final marker = await coreDb.db.query('app_settings', where: 'key = ?', whereArgs: ['legacy_migration_completed']);
      expect(marker.isEmpty, isTrue);
    });

    // 13. Migration yarıda kesilir → tamamlanma işareti olmadan hedef seçilmez.
    test('13. Yarıda kesilen migration kalıcı recovery gerektirir ve hedef veritabanı seçilmez', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(CoreNextBootstrapCoordinator.prefKeyMigrationState, CoreNextMigrationState.migrationInProgress.value);

      final routing = await resolver.resolve(
        requestedTenantId: 'tenant-nutopia',
        legacyDbPath: legacyDbPath,
        targetDbPath: coreDbPath,
        migrationStateCompleted: false,
      );
      expect(routing.isTargetSelected, isFalse);
      expect(routing.decision, equals(RoutingDecision.legacyFallback));
    });

    // 14. Yeni satış veya finans hareketi bulunan hedefte güvensiz rollback engellenir.
    test('14. Hedefte yeni satış veya finansal hareket varsa güvensiz rollback kilitlenir', () async {
      final cutoff = DateTime.now().millisecondsSinceEpoch - 1000;
      await coreDb.db.insert('sales', {
        'id': 'sale-new-1',
        'receipt_no': 'REC-NEW-01',
        'subtotal_cents': 2500,
        'total_cents': 2500,
        'paid_cents': 2500,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      expect(
        () async => await resolver.assertSafeRollback(
          targetDb: coreDb.db,
          initialMigrationCutoffTimestamp: cutoff,
        ),
        throwsA(isA<UnsafeRollbackException>()),
      );
    });

    // 15. Bütün üretim provider varsayılanları kapalı kalır.
    test('15. Üretim provider varsayılanları (runner, routing, consent, salesEngine) kesinlikle kapalıdır', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
      expect(container.read(coreNextMigrationRunnerProvider), isNull);
      expect(DatabaseManager.databaseRoutingHook, isNull);
      expect(container.read(coreNextConsentRequesterProvider), isNull);
      expect(container.read(coreNextRollbackGuardProvider), isNull);
      expect(container.read(coreNextConsentRequestProvider), isNull);
    });
  });
}
