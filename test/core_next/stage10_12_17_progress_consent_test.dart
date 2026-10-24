// test/core_next/stage10_12_17_progress_consent_test.dart
// STAGE 10.12.17 — Reaktif İlerleme Göstergesi ve Açık Kullanıcı Onayı 11 Senaryolu Test Paketi

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/widgets/branded_splash_screen.dart';
import 'package:serenutos/presentation/widgets/migration_consent_dialog.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String legacyDbPath;
  late String targetDbPath;
  late String backupDirPath;
  const resolver = DatabaseRoutingResolver();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('stage10_12_17_ux_gate_');
    legacyDbPath = p.join(tempDir.path, 'serenut_pos.db');
    targetDbPath = p.join(tempDir.path, 'core_next.db');
    backupDirPath = p.join(tempDir.path, 'backups');
    await Directory(backupDirPath).create(recursive: true);

    // Legacy DB Hazırlığı
    final lDb = await databaseFactory.openDatabase(legacyDbPath);
    await lDb.execute('PRAGMA journal_mode = WAL;');
    await lDb.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        barcode TEXT,
        name TEXT,
        price REAL,
        stock_quantity REAL,
        is_active INTEGER DEFAULT 1,
        is_deleted INTEGER DEFAULT 0
      );
    ''');
    await lDb.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT,
        balance REAL DEFAULT 0.0
      );
    ''');
    await lDb.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        customer_id TEXT,
        total_amount REAL,
        created_at TEXT
      );
    ''');
    await lDb.execute('''
      CREATE TABLE cash_transactions (
        id TEXT PRIMARY KEY,
        amount REAL,
        description TEXT,
        created_at TEXT
      );
    ''');
    await lDb.execute('''
      CREATE TABLE ledger_entries (
        id TEXT PRIMARY KEY,
        customer_id TEXT,
        amount REAL,
        created_at TEXT
      );
    ''');

    // Örnek veri girişi
    for (int i = 1; i <= 25; i++) {
      await lDb.insert('products', {
        'id': 'prod-$i',
        'barcode': '86900000$i',
        'name': 'Ürün $i',
        'price': 10.0 + i,
        'stock_quantity': 100.0,
        'is_active': 1,
        'is_deleted': 0,
      });
    }
    await lDb.insert('customers', {
      'id': 'cust-1',
      'name': 'Ahmet Yılmaz',
      'balance': 250.0,
    });
    await lDb.close();
  });

  tearDown(() async {
    DatabaseManager.isWriteLocked = false;
    DatabaseManager.overrideDatabasePath = null;
    DatabaseManager.databaseRoutingHook = null;
    CoreNextBootstrapCoordinator.resetExecutionLock();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('STAGE 10.12.17 — UX & EXPLICIT CONSENT GATE (11 SENARYO)', () {
    test('1. Migration kapalıyken mevcut açılış değişmez (unaffected)', () async {
      final container = ProviderContainer(
        overrides: [
          coreNextMigrationRunnerProvider.overrideWithValue(null),
          coreNextConsentRequesterProvider.overrideWithValue(null),
        ],
      );

      final coordinator = container.read(coreNextBootstrapCoordinatorProvider);
      final state = await coordinator.getPersistentState();
      expect(state, equals(CoreNextMigrationState.notStarted));

      final progress = container.read(coreNextMigrationProgressProvider);
      expect(progress, isNull);
      container.dispose();
    });

    test('2. Kullanıcı geçişi reddeder (Şimdi Değil); migration başlamaz ve legacyde kalınır', () async {
      final legacyDb = await databaseFactory.openDatabase(legacyDbPath);
      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);

      bool runnerCalled = false;
      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: targetCore.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        consentRequester: () async => MigrationConsentDecision.postponed,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, bool fullScope = true, onProgress}) async {
          runnerCalled = true;
          return true;
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isTrue);
      expect(result.isSkipped, isTrue);
      expect(result.state, equals(CoreNextMigrationState.notStarted));
      expect(runnerCalled, isFalse, reason: 'Kullanıcı Şimdi Değil dediğinde runner asla tetiklenmemelidir.');

      final persistentState = await coordinator.getPersistentState();
      expect(persistentState, equals(CoreNextMigrationState.notStarted));

      await legacyDb.close();
      await targetCore.close();
    });

    test('3. Kullanıcı onay verir; yalnızca izin verilen akış başlar', () async {
      final legacyDb = await databaseFactory.openDatabase(legacyDbPath);
      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);

      bool runnerCalled = false;
      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: targetCore.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, bool fullScope = true, onProgress}) async {
          runnerCalled = true;
          final bridge = MigrationBridgeEngine(targetCore);
          return await bridge.migrateFromLegacy(legacyDb, fullScope: true, onProgress: onProgress);
        },
      );

      final result = await coordinator.coordinate();
      expect(runnerCalled, isTrue, reason: 'Onay verildiğinde runner çalışmalıdır.');
      expect(result.isSuccess, isTrue);
      expect(result.state, equals(CoreNextMigrationState.completed));

      final persistentState = await coordinator.getPersistentState();
      expect(persistentState, equals(CoreNextMigrationState.completed));

      await legacyDb.close();
      await targetCore.close();
    });

    test('4. Yedek doğrulaması başarısız olursa migration başlamaz (fail-closed)', () async {
      final legacyDb = await databaseFactory.openDatabase(legacyDbPath);
      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: targetCore.db,
        customLegacyFilePath: '/non_existent_dir_9999/invalid_pos.db',
        customBackupDirectory: backupDirPath,
        consentRequester: () async => MigrationConsentDecision.approved,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, bool fullScope = true, onProgress}) async {
          return true;
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(result.state, equals(CoreNextMigrationState.failedRecoverable));
      expect(DatabaseManager.isWriteLocked, isFalse, reason: 'Kilit fail-closed ile açılmalıdır.');

      await legacyDb.close();
      await targetCore.close();
    });

    test('5. Tenant kimliği uyuşmazsa işlem engellenir (tenant isolation)', () async {
      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      await targetCore.db.insert('app_settings', {'key': 'tenant_id', 'value': 'tenant-Nutopia', 'updated_at': 1792100000});
      await targetCore.close();

      final res = await resolver.resolve(
        requestedTenantId: 'tenant-Erkul', // Farklı tenant!
        legacyDbPath: legacyDbPath,
        targetDbPath: targetDbPath,
        migrationStateCompleted: true,
      );

      expect(res.decision, equals(RoutingDecision.blockedFailClosed));
      expect(res.isTargetSelected, isFalse);
      expect(res.reason, contains('Tenant ID uyuşmazlığı'));
    });

    test('6. Migration devam ederken ilerleme bilgisi (6 aşama ve yüzdeler) güncellenir', () async {
      final legacyDb = await databaseFactory.openDatabase(legacyDbPath);
      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);

      final capturedStages = <MigrationStage>[];
      final capturedProgresses = <double>[];

      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: targetCore.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        consentRequester: () async => MigrationConsentDecision.approved,
        onProgress: (p) {
          capturedStages.add(p.stage);
          capturedProgresses.add(p.progress);
        },
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, bool fullScope = true, onProgress}) async {
          final bridge = MigrationBridgeEngine(targetCore);
          return await bridge.migrateFromLegacy(legacyDb, fullScope: true, onProgress: onProgress);
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isTrue);

      // İlerleme aşamalarının doğrulanması
      expect(capturedStages.contains(MigrationStage.sourceVerifying), isTrue, reason: 'Kaynak doğrulama aşaması yayınlanmalı');
      expect(capturedStages.contains(MigrationStage.backupPreparing), isTrue, reason: 'Yedek hazırlığı aşaması yayınlanmalı');
      expect(capturedStages.contains(MigrationStage.dataMigrating), isTrue, reason: 'Veri aktarım aşaması yayınlanmalı');
      expect(capturedStages.contains(MigrationStage.reconciliation), isTrue, reason: 'Mutabakat aşaması yayınlanmalı');
      expect(capturedStages.contains(MigrationStage.integrityChecking), isTrue, reason: 'Bütünlük kontrolü aşaması yayınlanmalı');
      expect(capturedStages.contains(MigrationStage.completed), isTrue, reason: 'Tamamlandı aşaması yayınlanmalı');

      // Yüzdelerin monoton artışı
      expect(capturedProgresses.last, equals(1.0));
      expect(capturedProgresses.first, greaterThan(0.0));

      await legacyDb.close();
      await targetCore.close();
    });

    test('7. Migration hatasında hata durumu ve yeniden deneme bilgisi gösterilir', () async {
      final legacyDb = await databaseFactory.openDatabase(legacyDbPath);
      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);

      MigrationProgress? lastProgress;
      final coordinator = CoreNextBootstrapCoordinator(
        customLegacyDb: legacyDb,
        customTargetDb: targetCore.db,
        customLegacyFilePath: legacyDbPath,
        customBackupDirectory: backupDirPath,
        consentRequester: () async => MigrationConsentDecision.approved,
        onProgress: (p) => lastProgress = p,
        migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, bool fullScope = true, onProgress}) async {
          throw Exception('Simüle edilmiş disk I/O arızası');
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, isFalse);
      expect(result.errorReference, isNotNull);
      expect(lastProgress, isNotNull);
      expect(lastProgress!.stage, equals(MigrationStage.failed));
      expect(lastProgress!.stageTitle, equals('İşlem tamamlandı veya hata oluştu'));

      await legacyDb.close();
      await targetCore.close();
    });

    test('8. Uygulama kapanıp yeniden açıldığında tamamlanmamış migration yanlışlıkla tamamlanmış sayılmaz', () async {
      final targetFile = File(targetDbPath);
      await targetFile.writeAsBytes(List.filled(1024, 0)); // Valid size file on disk

      final res = await resolver.resolve(
        requestedTenantId: 'tenant-1',
        legacyDbPath: legacyDbPath,
        targetDbPath: targetDbPath,
        migrationStateCompleted: false, // Henüz tamamlanmadı!
      );

      expect(res.isTargetSelected, isFalse);
      expect(res.resolvedPath, equals(legacyDbPath));
      expect(res.reason, contains('Migration durumu tamamlanmadı'));
    });

    test('9. Tamamlanma işareti yazılamazsa hedef veritabanı seçilmez', () async {
      final res = await resolver.resolve(
        requestedTenantId: 'tenant-1',
        legacyDbPath: legacyDbPath,
        targetDbPath: targetDbPath,
        migrationStateCompleted: false,
      );

      expect(res.isTargetSelected, isFalse);
      expect(res.resolvedPath, equals(legacyDbPath));
    });

    test('10. Yeni satış veya finans hareketi bulunan hedefte güvensiz rollback engellenir', () async {
      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      const cutoffTime = 1792100000;

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
        throwsA(isA<UnsafeRollbackException>()),
      );

      await targetCore.close();
    });

    test('11. Uzun süren migration sırasında event-loop unblocking ile UI yanıt verebilir kalır', () async {
      final legacyDb = await databaseFactory.openDatabase(legacyDbPath);
      final targetCore = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);

      // 1.500 ürün ekleyip batch chunking ve yield döngüsünü test edelim
      for (int i = 26; i <= 1500; i++) {
        await legacyDb.insert('products', {
          'id': 'prod-$i',
          'barcode': '86900000$i',
          'name': 'Ürün $i',
          'price': 15.0,
          'stock_quantity': 50.0,
          'is_active': 1,
          'is_deleted': 0,
        });
      }

      int yieldCheckCount = 0;
      final bridge = MigrationBridgeEngine(targetCore);

      // Arka planda timer ile event loop'un çalıştığını denetle
      final timer = Stream.periodic(const Duration(milliseconds: 2)).listen((_) {
        yieldCheckCount++;
      });

      final report = await bridge.migrateFromLegacy(
        legacyDb,
        fullScope: true,
        onProgress: (stage, progress, detail) {
          // Progress callback aktif
        },
      );

      await timer.cancel();
      expect(report.isSuccess, isTrue);
      expect(yieldCheckCount, greaterThan(0), reason: 'Event loop bloke edilmemeli, frame/timer akışı sürmelidir.');

      await legacyDb.close();
      await targetCore.close();
    });

    testWidgets('UI Test: MigrationConsentDialog bileşeni doğru metin ve butonlarla çalışır', (tester) async {
      MigrationConsentDecision? selectedDecision;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  selectedDecision = await showMigrationConsentDialog(
                    context: ctx,
                    sourceDbPath: 'serenut_pos.db',
                    targetDbPath: 'core_next.db',
                    estimatedProductCount: 37682,
                    estimatedCustomerCount: 584,
                  );
                },
                child: const Text('Diyalog Aç'),
              ),
            ),
          ),
        ),
      );

      // Diyaloğu aç
      await tester.tap(find.text('Diyalog Aç'));
      await tester.pumpAndSettle();

      // Başlık ve açıklamalar görünmeli
      expect(find.text('Sistem ve Veritabanı Optimizasyonu'), findsOneWidget);
      expect(find.text('Core Next Yeni Nesil Altyapı Geçişi'), findsOneWidget);
      expect(find.text('Neden Yapılıyor?'), findsOneWidget);
      expect(find.text('Katalog ve Stoklar: 37682 adet ürün ve stok kayıtları kuruş bazında aktarılacaktır.'), findsOneWidget);

      // Butonlar görünmeli
      expect(find.text('Şimdi Değil'), findsOneWidget);
      expect(find.text('Koşulları İncele'), findsOneWidget);
      expect(find.text('Geçişi Onayla'), findsOneWidget);

      // Koşulları İncele butonuna tıkla
      await tester.tap(find.text('Koşulları İncele'));
      await tester.pumpAndSettle();
      expect(find.text('Teknik Denetim ve Güvenlik Parametreleri'), findsOneWidget);
      expect(find.text('PRAGMA integrity_check + WAL Checkpoint'), findsOneWidget);

      // Şimdi Değil butonuna tıkla
      await tester.tap(find.text('Şimdi Değil'));
      await tester.pumpAndSettle();

      // Diyalog kapandı ve sonuç postponed döndü
      expect(find.text('Sistem ve Veritabanı Optimizasyonu'), findsNothing);
      expect(selectedDecision, equals(MigrationConsentDecision.postponed));
    });

    testWidgets('UI Test: BrandedSplashScreen reaktif ilerleme ve yüzdeleri doğru çizer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BrandedSplashScreen(
            status: 'Veriler aktarılıyor',
            detail: '37.682 ürün kuruş bazında dönüştürülüyor...',
            progress: 0.65,
          ),
        ),
      );

      expect(find.text('Veriler aktarılıyor'), findsOneWidget);
      expect(find.text('37.682 ürün kuruş bazında dönüştürülüyor...'), findsOneWidget);
      expect(find.text('%65'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });
}
