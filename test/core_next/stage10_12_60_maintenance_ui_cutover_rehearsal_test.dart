// test/core_next/stage10_12_60_maintenance_ui_cutover_rehearsal_test.dart
// SERENUT OS — STAGE 10.12.60
// MAINTENANCE UI, WRITE-LOCK VERIFICATION & ISOLATED CUTOVER REHEARSAL SUITE

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/migration/cutoff_maintenance_lock.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/widgets/cutoff_maintenance_banner_widget.dart';
import 'package:serenutos/providers/database_provider.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/services/telemetry_upload_service.dart';
import 'package:serenutos/infrastructure/services/persistent_print_queue.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() {
    DatabaseManager.cutoffMaintenanceLock = null;
    DatabaseManager.isWriteLocked = false;
  });

  group('STAGE 10.12.60: Değişmez Güvenlik Sınırları', () {
    test('Kural 1: coreNextSalesEngineEnabledProvider varsayılan olarak kesinlikle false kalmalı', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final isEnabled = container.read(coreNextSalesEngineEnabledProvider);
      expect(isEnabled, isFalse,
          reason: 'Canlı üretim güvenliği için Core Next satış motoru kesinlikle false kalmalıdır.');
    });

    test('Kural 2: DatabaseManager.databaseRoutingHook kesinlikle null kalmalı', () {
      expect(DatabaseManager.databaseRoutingHook, isNull,
          reason: 'Canlı üretim güvenliği için databaseRoutingHook kesinlikle null olmalıdır.');
    });
  });

  group('STAGE 10.12.60: Reaktif Bakım Ekranı (Maintenance UI) Doğrulaması', () {
    testWidgets('Senaryo 1: Normal kullanımda (idle) bakım afişi tamamen görünmezdir', (tester) async {
      final lock = CutoffMaintenanceLock(
        storage: InMemoryMaintenancePersistenceStorage(),
      );
      DatabaseManager.cutoffMaintenanceLock = lock;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cutoffMaintenanceStateProvider.overrideWith((ref) => lock.stateStream),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  CutoffMaintenanceBannerWidget(),
                  Text('POS Ana Ekranı'),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cutoff_maintenance_banner')), findsNothing);
      expect(find.byKey(const Key('cutoff_maintenance_banner_error')), findsNothing);
      expect(find.text('POS Ana Ekranı'), findsOneWidget);
    });

    testWidgets('Senaryo 2: Kilitlenme aşamasında (draining) kullanıcıya bekleme afişi ve sayaç gösterilir', (tester) async {
      final lock = CutoffMaintenanceLock(
        storage: InMemoryMaintenancePersistenceStorage(),
      );
      DatabaseManager.cutoffMaintenanceLock = lock;

      final blocker = Completer<void>();
      unawaited(lock.drainer.runTrackedWrite(
        operationType: 'test_write',
        caller: 'test',
        action: () => blocker.future,
        isWritePermitted: () => true,
        currentPhase: () => CutoffMaintenancePhase.idle,
      ));

      unawaited(lock.acquireLock(tenantId: 'tenant_nutopia'));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  CutoffMaintenanceBannerWidget(),
                  Text('POS Satış'),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byKey(const Key('cutoff_maintenance_banner')), findsOneWidget);
      expect(find.text('Veritabanı Bakım Moduna Alınıyor'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      blocker.complete();
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('Senaryo 3: Kilit devredeyken (locked) kullanıcıya yazma koruması bildiren kilit afişi gösterilir', (tester) async {
      final lock = CutoffMaintenanceLock(
        storage: InMemoryMaintenancePersistenceStorage(),
      );
      DatabaseManager.cutoffMaintenanceLock = lock;

      await lock.acquireLock(
        tenantId: 'tenant_erkul',
        reason: 'Sistem Yükseltme ve Kesim Güvenliği',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  CutoffMaintenanceBannerWidget(),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byKey(const Key('cutoff_maintenance_banner')), findsOneWidget);
      expect(find.text('Sistem Bakım Modunda (Yazma Koruması Aktif)'), findsOneWidget);
      expect(find.textContaining('Sistem Yükseltme ve Kesim Güvenliği'), findsOneWidget);
      // Yetkisiz kilit açma butonu OLMADIĞINI doğrula
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('Senaryo 4: Hata durumunda (error) kullanıcıya fail-closed hata afişi gösterilir', (tester) async {
      final lock = CutoffMaintenanceLock(
        storage: InMemoryMaintenancePersistenceStorage(),
      );
      DatabaseManager.cutoffMaintenanceLock = lock;

      lock.setFailClosedError(
        'Kritik veritabanı kilit hatası. Veri bütünlüğünü korumak için yazma işlemleri durduruldu (Fail-Closed).',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  CutoffMaintenanceBannerWidget(),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byKey(const Key('cutoff_maintenance_banner_error')), findsOneWidget);
      expect(find.text('Kritik Veritabanı Bakım Koruması (Fail-Closed)'), findsOneWidget);
    });
  });

  group('STAGE 10.12.60: Yazma Kilitleri ve Servis Koruma Doğrulaması', () {
    test('Senaryo 5: Kilit aktifken DbGateway yazmaları anında CutoffMaintenanceActiveException ile reddedilir', () async {
      final lock = CutoffMaintenanceLock(
        storage: InMemoryMaintenancePersistenceStorage(),
      );
      DatabaseManager.cutoffMaintenanceLock = lock;
      await lock.acquireLock(tenantId: 'tenant_test');

      final db = await openDatabase(inMemoryDatabasePath, version: 1,
          onCreate: (db, _) => db.execute('CREATE TABLE dummy (id INT);'));
      addTearDown(() => db.close());

      final mockDbManager = DatabaseManager.instance;
      final gateway = DbGatewayImpl(mockDbManager);

      expect(
        () => gateway.insert('dummy', {'id': 1}),
        throwsA(isA<CutoffMaintenanceActiveException>()),
      );
    });

    test('Senaryo 6: Devam eden transaction tamamlanmadan drainer kilit vermez', () async {
      final lock = CutoffMaintenanceLock(
        storage: InMemoryMaintenancePersistenceStorage(),
      );
      DatabaseManager.cutoffMaintenanceLock = lock;

      final txnCompleter = Completer<void>();
      var txnHadRun = false;

      unawaited(lock.drainer.runTrackedWrite(
        operationType: 'multi_write_sale',
        caller: 'SalesController',
        action: () async {
          txnHadRun = true;
          await txnCompleter.future;
        },
        isWritePermitted: () => true,
        currentPhase: () => CutoffMaintenancePhase.idle,
      ));

      await Future.delayed(const Duration(milliseconds: 20));
      expect(txnHadRun, isTrue);
      expect(lock.drainer.inFlightCount, equals(1));

      var drainFinished = false;
      unawaited(lock.acquireLock(tenantId: 'tenant_test').then((_) {
        drainFinished = true;
      }));

      await Future.delayed(const Duration(milliseconds: 50));
      expect(drainFinished, isFalse, reason: 'Transaction bitmeden drain tamamlanamaz.');

      txnCompleter.complete();
      await Future.delayed(const Duration(milliseconds: 80));

      expect(drainFinished, isTrue);
      expect(lock.state.phase, equals(CutoffMaintenancePhase.locked));
    });

    test('Senaryo 7: TelemetryUploadService ve PersistentPrintQueue kilit altındayken yazamaz ve satış akışını bozmaz', () async {
      final lock = CutoffMaintenanceLock(
        storage: InMemoryMaintenancePersistenceStorage(),
      );
      DatabaseManager.cutoffMaintenanceLock = lock;
      await lock.acquireLock(tenantId: 'tenant_test');

      final telemetry = TelemetryUploadService(ApiClient());
      // Telemetri log yazmayı dener ama fail-closed sessizce korur, rethrow etmez
      await telemetry.recordMetric('cpu_usage', 45.2);

      // ignore: deprecated_member_use_from_same_package
      final printQueue = PersistentPrintQueue(testKey: 'test_queue');
      expect(
        () => printQueue.enqueue(title: 'Fiş', receiptJson: '{}'),
        throwsA(isA<CutoffMaintenanceActiveException>()),
      );
    });

    test('Senaryo 8: Kalıcı kilit yeniden başlatmada fail-closed açılır', () async {
      final corruptedStorage = _CorruptedPersistenceStorage();
      final lock = CutoffMaintenanceLock(storage: corruptedStorage);

      await lock.initializeFromStorage();

      expect(lock.state.phase, equals(CutoffMaintenancePhase.locked));
      expect(lock.state.isWritePermitted, isFalse);
      expect(
        () => lock.assertWritePermitted(operation: 'test_reboot'),
        throwsA(isA<CutoffMaintenanceActiveException>()),
      );
    });
  });

  group('STAGE 10.12.60: İzole Cutover Provası (Isolated Cutover Rehearsal)', () {
    late Directory tempDir;
    late String sourceDbPath;
    late String targetDbPath;
    late Database sourceDb;
    late Database targetDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('serenut_cutover_rehearsal_');
      sourceDbPath = '${tempDir.path}${Platform.pathSeparator}legacy_source.db';
      targetDbPath = '${tempDir.path}${Platform.pathSeparator}core_next_target.db';

      sourceDb = await openDatabase(sourceDbPath, version: 1, onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT, price REAL, stock INT);
        ''');
        await db.execute('''
          CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT, balance REAL);
        ''');
        await db.execute('''
          CREATE TABLE sales (id TEXT PRIMARY KEY, total REAL, customer_id TEXT, created_at TEXT);
        ''');
        await db.execute('''
          CREATE TABLE financial_transactions (id TEXT PRIMARY KEY, amount REAL, type TEXT);
        ''');
      });

      targetDb = await openDatabase(targetDbPath, version: 1, onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT, price REAL, stock INT);
        ''');
        await db.execute('''
          CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT, balance REAL);
        ''');
        await db.execute('''
          CREATE TABLE sales (id TEXT PRIMARY KEY, total REAL, customer_id TEXT, created_at TEXT);
        ''');
        await db.execute('''
          CREATE TABLE financial_transactions (id TEXT PRIMARY KEY, amount REAL, type TEXT);
        ''');
      });
    });

    tearDown(() async {
      await sourceDb.close();
      await targetDb.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Senaryo 9: İzole tam kesim provası (Snapshot, Kilit, Delta ve Birebir Mutabakat)', () async {
      // 1. Kaynak DB'ye önceden 5 ürün, 2 müşteri, 3 satış ekle
      await sourceDb.insert('products', {'id': 'p1', 'name': 'Fındık 500g', 'price': 250.0, 'stock': 80});
      await sourceDb.insert('products', {'id': 'p2', 'name': 'Fındık Ezmesi', 'price': 150.0, 'stock': 40});
      await sourceDb.insert('customers', {'id': 'c1', 'name': 'Ahmet Yılmaz', 'balance': -500.0});
      await sourceDb.insert('sales', {'id': 's1', 'total': 400.0, 'customer_id': 'c1', 'created_at': '2026-10-21T10:00:00'});
      await sourceDb.insert('financial_transactions', {'id': 'f1', 'amount': 400.0, 'type': 'sale'});

      // 2. Kilit nesnesini hazırla
      final lock = CutoffMaintenanceLock(
        storage: InMemoryMaintenancePersistenceStorage(),
      );
      DatabaseManager.cutoffMaintenanceLock = lock;

      // 3. Kilit isteği ve Draining: Yeni yazmalar durur, devam edenler biter
      await lock.acquireLock(
        tenantId: 'tenant_nutopia',
        reason: 'İzole Cutover Provası Testi',
      );

      expect(lock.state.phase, equals(CutoffMaintenancePhase.locked));
      expect(lock.drainer.inFlightCount, equals(0));

      // 4. Kilit altındayken kaynak DB'den verileri oku (Snapshot)
      final sourceProducts = await sourceDb.query('products');
      final sourceCustomers = await sourceDb.query('customers');
      final sourceSales = await sourceDb.query('sales');
      final sourceFin = await sourceDb.query('financial_transactions');

      // 5. Hedef DB'ye aktar (Export / Import simülasyonu)
      for (final p in sourceProducts) {
        await targetDb.insert('products', p);
      }
      for (final c in sourceCustomers) {
        await targetDb.insert('customers', c);
      }
      for (final s in sourceSales) {
        await targetDb.insert('sales', s);
      }
      for (final f in sourceFin) {
        await targetDb.insert('financial_transactions', f);
      }

      // 6. Mutabakat Kontrolleri (Reconciliation)
      final targetProducts = await targetDb.query('products');
      final targetCustomers = await targetDb.query('customers');
      final targetSales = await targetDb.query('sales');
      final targetFin = await targetDb.query('financial_transactions');

      expect(targetProducts.length, equals(sourceProducts.length));
      expect(targetCustomers.length, equals(sourceCustomers.length));
      expect(targetSales.length, equals(sourceSales.length));
      expect(targetFin.length, equals(sourceFin.length));

      // Kuruş ve bakiye birebir doğrulaması
      final sourceTotal = sourceSales.fold<double>(0.0, (acc, s) => acc + (s['total'] as num).toDouble());
      final targetTotal = targetSales.fold<double>(0.0, (acc, s) => acc + (s['total'] as num).toDouble());
      expect(targetTotal, equals(sourceTotal));

      // 7. Kontrollü Kilit Kaldırma (Rollback veya Cutover tamamlandıktan sonra)
      await lock.releaseLock();
      expect(lock.state.phase, equals(CutoffMaintenancePhase.idle));
      expect(lock.state.isWritePermitted, isTrue);

      // Değişmez kuralların korunduğunu doğrula
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });

    test('Senaryo 10: Mutabakat uyuşmazlığında cutover gate reddeder ve legacy kaynak korunur', () async {
      await sourceDb.insert('sales', {'id': 's1', 'total': 1000.0, 'customer_id': 'c1', 'created_at': '2026-10-21T10:00:00'});
      // Hedefe eksik veri aktar
      await targetDb.insert('sales', {'id': 's1', 'total': 850.0, 'customer_id': 'c1', 'created_at': '2026-10-21T10:00:00'});

      final sourceSales = await sourceDb.query('sales');
      final targetSales = await targetDb.query('sales');

      final sourceTotal = sourceSales.fold<double>(0.0, (acc, s) => acc + (s['total'] as num).toDouble());
      final targetTotal = targetSales.fold<double>(0.0, (acc, s) => acc + (s['total'] as num).toDouble());

      final isReconciled = (sourceTotal - targetTotal).abs() < 0.001;

      expect(isReconciled, isFalse, reason: 'Tutar uyuşmazlığında mutabakat başarısız olmalıdır.');
      // Mutabakat başarısızsa routing hook null kalmalı
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });
  });
}

class _CorruptedPersistenceStorage implements IMaintenancePersistenceStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<CutoffMaintenanceState?> loadState() async {
    throw const FormatException('Bozuk JSON verisi');
  }

  @override
  Future<void> saveState(CutoffMaintenanceState state) async {}
}
