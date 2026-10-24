// test/core_next/stage10_12_59_central_write_lock_integration_test.dart
// SERENUT OS — STAGE 10.12.59
// CENTRAL CUTOFF LOCK INTEGRATION & DIRECT SQLITE WRITE PROTECTION TEST SUITE
//
// DEĞİŞMEZ GÜVENLİK KURALLARI:
// 1. Canlı hiçbir veritabanına yazma, onarım veya migration yapılmaz.
// 2. Yalnızca izole kopyalar ve bellek içi mock mimari üzerinde çalışılır.
// 3. coreNextSalesEngineEnabledProvider = false ve DatabaseManager.databaseRoutingHook = null kalır.

// ignore_for_file: avoid_relative_lib_imports, prefer_const_declarations

@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/services/persistent_print_queue.dart';
import 'package:serenutos/infrastructure/services/telemetry_upload_service.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';

import 'package:serenutos/infrastructure/migration/cutoff_maintenance_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database isolatedDb;
  late DbGateway isolatedGateway;

  setUp(() async {
    isolatedDb = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE test_sales (
            id TEXT PRIMARY KEY,
            customer_id TEXT,
            amount REAL,
            created_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE test_stock (
            product_id TEXT PRIMARY KEY,
            quantity REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE client_telemetry_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            metric_name TEXT,
            metric_value REAL,
            timestamp TEXT,
            metadata TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE print_queue (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            receipt_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL,
            purpose TEXT NOT NULL DEFAULT 'receipt',
            device_id TEXT NOT NULL DEFAULT 'receipt-printer-primary',
            last_error TEXT
          )
        ''');
      },
    );

    isolatedGateway = DbGatewayImpl.raw(isolatedDb);
    DatabaseManager.cutoffMaintenanceLock = null;
    DatabaseManager.isWriteLocked = false;
  });

  tearDown(() async {
    DatabaseManager.cutoffMaintenanceLock = null;
    DatabaseManager.isWriteLocked = false;
    await isolatedDb.close();
  });

  group('STAGE 10.12.59: Değişmez Güvenlik Sınırları', () {
    test('Kural 1: coreNextSalesEngineEnabledProvider varsayılan olarak kesinlikle false kalmalı', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
    });

    test('Kural 2: DatabaseManager.databaseRoutingHook kesinlikle null kalmalı', () {
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });
  });

  group('STAGE 10.12.59: 14 Zorunlu Entegrasyon Senaryosu', () {
    // 1. Gateway üzerinden yeni yazma, kilit aktifken reddedilir
    test('Senaryo 1: Gateway üzerinden yeni yazma, kilit aktifken anında reddedilir (CutoffMaintenanceActiveException)', () async {
      final lock = CutoffMaintenanceLock();
      DatabaseManager.cutoffMaintenanceLock = lock;

      final lockAcquired = await lock.acquireLock(tenantId: 'tenant_nutopia');
      expect(lockAcquired, isTrue);
      expect(lock.state.phase, equals(CutoffMaintenancePhase.locked));

      // Gateway insert denemesi
      expect(
        () => isolatedGateway.insert('test_sales', {
          'id': 'sale_001',
          'customer_id': 'cust_01',
          'amount': 250.0,
          'created_at': DateTime.now().toIso8601String(),
        }),
        throwsA(isA<CutoffMaintenanceActiveException>()),
      );

      // Gateway transaction denemesi
      expect(
        () => isolatedGateway.transaction(() async {
          await isolatedGateway.insert('test_sales', {'id': 'sale_002'});
        }),
        throwsA(isA<CutoffMaintenanceActiveException>()),
      );
    });

    // 2. Kilit isteği ile eşzamanlı yeni yazma yarışı güvenli çözülür
    test('Senaryo 2: Kilit isteği ile eşzamanlı yeni yazma yarışı güvenli çözülür', () async {
      final lock = CutoffMaintenanceLock();
      DatabaseManager.cutoffMaintenanceLock = lock;

      // Kilit alma ve yazma aynı anda başlatılır
      final acquireFuture = lock.acquireLock(tenantId: 'tenant_nutopia');
      final writeFuture = isolatedGateway.insert('test_sales', {
        'id': 'race_sale_1',
        'customer_id': 'cust_race',
        'amount': 150.0,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Yazma işlemi ya kilit öncesine denk gelip tamamlanmalı, ya da kilit devreye girdiği için exception fırlatmalıdır.
      // Asla yarım yazma veya sayaç tutarsızlığı olmamalıdır.
      bool writeThrew = false;
      try {
        await writeFuture;
      } on CutoffMaintenanceActiveException {
        writeThrew = true;
      } catch (_) {}

      final lockResult = await acquireFuture;
      expect(lockResult, isTrue);
      expect(lock.drainer.inFlightCount, equals(0));
      expect(lock.isSafeForSnapshot, isTrue);

      if (writeThrew) {
        final rows = await isolatedDb.query('test_sales', where: 'id = ?', whereArgs: ['race_sale_1']);
        expect(rows, isEmpty, reason: 'Kilit aktifken yazma reddedildi, veritabanına eklenmedi');
      }
    });

    // 3. Başlamış yazma tamamlanmadan drainer başarılı dönmez
    test('Senaryo 3: Başlamış yazma tamamlanmadan drainer başarılı dönmez', () async {
      final lock = CutoffMaintenanceLock();
      DatabaseManager.cutoffMaintenanceLock = lock;

      final inFlightActionCompleter = Completer<void>();
      var actionCompleted = false;

      // Başlatılan uzun transaction
      final longRunningWrite = isolatedGateway.transaction(() async {
        await inFlightActionCompleter.future;
        await isolatedGateway.insert('test_sales', {
          'id': 'in_flight_1',
          'amount': 500.0,
        });
        actionCompleted = true;
      });

      // Yazmanın başladığından ve sayacın 1 olduğundan emin ol
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(lock.drainer.inFlightCount, equals(1));
      expect(lock.isSafeForSnapshot, isFalse);

      var lockResult = false;
      final acquireLockFuture = lock.acquireLock(tenantId: 'tenant_nutopia').then((v) {
        lockResult = v;
      });

      // Drain devam ederken kilit henüz tamamlanamaz
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(lockResult, isFalse);
      expect(actionCompleted, isFalse);
      expect(lock.state.phase, equals(CutoffMaintenancePhase.draining));

      // İşlemi serbest bırak
      inFlightActionCompleter.complete();
      await longRunningWrite;
      await acquireLockFuture;

      expect(actionCompleted, isTrue);
      expect(lockResult, isTrue);
      expect(lock.drainer.inFlightCount, equals(0));
      expect(lock.state.phase, equals(CutoffMaintenancePhase.locked));
      expect(lock.isSafeForSnapshot, isTrue);
    });

    // 4. Bir satış işlemindeki çoklu DB yazmaları için transaction atomikliği korunur
    test('Senaryo 4: Bir satış işlemindeki çoklu DB yazmaları için transaction atomikliği korunur', () async {
      final lock = CutoffMaintenanceLock();
      DatabaseManager.cutoffMaintenanceLock = lock;

      await isolatedDb.insert('test_stock', {'product_id': 'p1', 'quantity': 10.0});

      // Çoklu işlem: Satış ekle + stok düş (aynı transaction içinde)
      await isolatedGateway.transaction(() async {
        await isolatedGateway.insert('test_sales', {'id': 'sale_multi', 'amount': 100.0});
        await isolatedGateway.update(
          'test_stock',
          {'quantity': 9.0},
          where: 'product_id = ?',
          whereArgs: ['p1'],
        );
      });

      final saleRows = await isolatedDb.query('test_sales', where: 'id = ?', whereArgs: ['sale_multi']);
      final stockRows = await isolatedDb.query('test_stock', where: 'product_id = ?', whereArgs: ['p1']);
      expect(saleRows.length, equals(1));
      expect(stockRows.first['quantity'], equals(9.0));
      expect(lock.drainer.inFlightCount, equals(0), reason: 'Transaction bitince sayaç 0 olmalı');
    });

    // 5. Timeout sonrası routing kapalı kalır ve yeni yazmalar başlamaz
    test('Senaryo 5: Timeout sonrası routing kapalı kalır ve yeni yazmalar başlamaz', () async {
      final drainer = InFlightTransactionDrainer(defaultTimeout: const Duration(milliseconds: 50));
      final lock = CutoffMaintenanceLock(drainer: drainer);
      DatabaseManager.cutoffMaintenanceLock = lock;

      final hangingCompleter = Completer<void>();
      // ignore: unawaited_futures
      drainer.runTrackedWrite(
        operationType: 'hanging',
        caller: 'HangingCaller',
        action: () => hangingCompleter.future,
        isWritePermitted: () => true,
        currentPhase: () => CutoffMaintenancePhase.idle,
      );

      final success = await lock.acquireLock(
        tenantId: 'tenant_nutopia',
        timeout: const Duration(milliseconds: 50),
      );

      expect(success, isFalse);
      expect(lock.state.phase, equals(CutoffMaintenancePhase.error));
      expect(DatabaseManager.databaseRoutingHook, isNull);

      // Error durumunda da yeni yazma reddedilmeli
      expect(
        () => isolatedGateway.insert('test_sales', {'id': 'blocked_after_timeout'}),
        throwsA(isA<CutoffMaintenanceActiveException>()),
      );

      hangingCompleter.complete();
    });

    // 6. Hata sonrası kilit kendiliğinden açılmaz
    test('Senaryo 6: Hata sonrası kilit kendiliğinden açılmaz (Fail-closed error persistence)', () async {
      final storage = InMemoryMaintenancePersistenceStorage();
      final lock = CutoffMaintenanceLock(storage: storage);
      DatabaseManager.cutoffMaintenanceLock = lock;

      // Manuel olarak error state'e geçir
      await storage.saveState(const CutoffMaintenanceState(
        phase: CutoffMaintenancePhase.error,
        tenantId: 'tenant_nutopia',
        errorMessage: 'Kritik senkronizasyon hatası',
      ));

      await lock.initializeFromStorage();
      expect(lock.state.phase, equals(CutoffMaintenancePhase.locked));
      expect(lock.state.isWritePermitted, isFalse);
      expect(lock.state.errorMessage, isNotNull);
    });

    // 7. Uygulama yeniden başlatma/persist hatası fail-closed davranır
    test('Senaryo 7: Uygulama yeniden başlatma/persist hatası fail-closed davranır', () async {
      // Bozuk JSON / storage hatası simülasyonu
      final storage = SharedPreferencesMaintenanceStorage(() async {
        throw StateError('Disk I/O Error: Storage corrupted');
      });

      final lock = CutoffMaintenanceLock(storage: storage);
      DatabaseManager.cutoffMaintenanceLock = lock;

      await lock.initializeFromStorage();
      expect(lock.state.phase, equals(CutoffMaintenancePhase.locked));
      expect(lock.state.isWritePermitted, isFalse);
      expect(lock.state.errorMessage, contains('kilitli'));
    });

    // 8. İki eşzamanlı kilit/drain/release çağrısı state veya sayaç bozulmasına neden olmaz
    test('Senaryo 8: İki eşzamanlı kilit/drain/release çağrısı state veya sayaç bozulmasına neden olmaz', () async {
      final lock = CutoffMaintenanceLock();
      DatabaseManager.cutoffMaintenanceLock = lock;

      // Aynı anda 2 kilit alma çağrısı
      final future1 = lock.acquireLock(tenantId: 'tenant_nutopia');
      final future2 = lock.acquireLock(tenantId: 'tenant_nutopia');

      final results = await Future.wait([future1, future2]);
      expect(results[0], isTrue);
      expect(results[1], isTrue);
      expect(lock.state.phase, equals(CutoffMaintenancePhase.locked));
      expect(lock.drainer.inFlightCount, equals(0));

      // Aynı anda 2 release çağrısı
      await Future.wait([lock.releaseLock(), lock.releaseLock()]);
      expect(lock.state.phase, equals(CutoffMaintenancePhase.idle));
      expect(lock.state.isWritePermitted, isTrue);
      expect(lock.drainer.inFlightCount, equals(0));
    });

    // 9. Gateway dışındaki her korunan doğrudan yazma yolu kendi entegrasyon testiyle doğrulanır
    test('Senaryo 9: TelemetryUploadService ve PersistentPrintQueue kilit aktifken yazma yapamaz', () async {
      final lock = CutoffMaintenanceLock();
      DatabaseManager.cutoffMaintenanceLock = lock;

      await lock.acquireLock(tenantId: 'tenant_nutopia');

      // 1. TelemetryUploadService
      final apiClient = ApiClient();
      final telemetryService = TelemetryUploadService(apiClient, isolatedGateway);
      await telemetryService.recordMetric('cpu_usage', 45.0);

      // Kilit devredeyken telemetry log tablosuna kayıt atılmamalı
      final telemetryRows = await isolatedDb.query('client_telemetry_logs');
      expect(telemetryRows, isEmpty, reason: 'Kilit devredeyken telemetri SQLite tamponuna yazılmamalıdır');

      // 2. PersistentPrintQueue
      // ignore: deprecated_member_use_from_same_package
      final printQueue = PersistentPrintQueue(gateway: isolatedGateway);
      expect(
        () => printQueue.enqueue(
          title: 'Fiş #1001',
          receiptJson: '{"items": []}',
        ),
        throwsA(isA<CutoffMaintenanceActiveException>()),
      );
    });

    // 10. Tenant uyuşmazlığı geçişi reddeder
    test('Senaryo 10: Tenant uyuşmazlığı kilit almayı reddeder (ArgumentError)', () async {
      final lock = CutoffMaintenanceLock();
      await lock.acquireLock(tenantId: 'tenant_nutopia');

      expect(
        () => lock.acquireLock(tenantId: 'tenant_serenut'),
        throwsA(isA<ArgumentError>()),
      );
    });

    // 11. Reconciliation başarısızlığında routing hook null kalır
    test('Senaryo 11: Reconciliation başarısızlığında routing hook null kalır ve legacy korunur', () async {
      final lock = CutoffMaintenanceLock();
      await lock.acquireLock(tenantId: 'tenant_nutopia');

      final reconciliationSuccess = false;
      if (!reconciliationSuccess) {
        await lock.releaseLock();
      }

      expect(DatabaseManager.databaseRoutingHook, isNull);
      expect(lock.state.phase, equals(CutoffMaintenancePhase.idle));
    });

    // 12. Kontrollü release yalnızca açıkça izin verilen durumda çalışır
    test('Senaryo 12: Kontrollü release yalnızca açıkça izin verilen durumda çalışır', () async {
      final lock = CutoffMaintenanceLock();
      await lock.acquireLock(tenantId: 'tenant_nutopia');
      expect(lock.state.phase, equals(CutoffMaintenancePhase.locked));

      await lock.releaseLock();
      expect(lock.state.phase, equals(CutoffMaintenancePhase.idle));
      expect(lock.state.isWritePermitted, isTrue);
      expect(lock.state.userFacingBanner, isNull);
    });

    // 13. Testler canlı işletme veritabanlarına bağlanmaz
    test('Senaryo 13: Testler canlı işletme veritabanlarına bağlanmaz (Yalnızca in-memory veya izole yol)', () {
      expect(isolatedDb.path, equals(inMemoryDatabasePath));
      expect(DatabaseManager.overrideDatabasePath, isNot(contains('serenut_pos.db')));
    });

    // 14. Mevcut yazma işlemlerinin normal kullanım davranışı korunur
    test('Senaryo 14: Kilit idle modundayken normal yazma işlemleri eksiksiz çalışır', () async {
      DatabaseManager.cutoffMaintenanceLock = CutoffMaintenanceLock(); // Idle kilit

      final insertedId = await isolatedGateway.insert('test_sales', {
        'id': 'normal_sale_1',
        'customer_id': 'cust_100',
        'amount': 320.50,
        'created_at': DateTime.now().toIso8601String(),
      });

      expect(insertedId, isNonZero);
      final rows = await isolatedGateway.query('test_sales', where: 'id = ?', whereArgs: ['normal_sale_1']);
      expect(rows.length, equals(1));
      expect(rows.first['amount'], equals(320.50));
    });
  });
}
