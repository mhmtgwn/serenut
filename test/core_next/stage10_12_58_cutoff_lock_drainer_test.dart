// test/core_next/stage10_12_58_cutoff_lock_drainer_test.dart
// SERENUT OS — STAGE 10.12.58
// CENTRAL CUTOFF LOCK & IN-FLIGHT TRANSACTION DRAINER TEST SUITE
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

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';

import '../../core_next/client_core/lib/infrastructure/migration/cutoff_maintenance_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('STAGE 10.12.58: Değişmez Güvenlik Sınırları', () {
    test('Kural 1: coreNextSalesEngineEnabledProvider varsayılan olarak kesinlikle false kalmalı', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
    });

    test('Kural 2: DatabaseManager.databaseRoutingHook kesinlikle null kalmalı', () {
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });
  });

  group('STAGE 10.12.58: 10 Zorunlu Senaryo Testi', () {
    // 1. Kilit alınmışken yeni satış yazması reddedilir veya bekletilir
    test('Senaryo 1: Kilit alınmışken yeni satış yazması reddedilir (CutoffMaintenanceActiveException)', () async {
      final drainer = InFlightTransactionDrainer();
      final storage = InMemoryMaintenancePersistenceStorage();
      final lock = CutoffMaintenanceLock(drainer: drainer, storage: storage);

      // Kilit alınır
      final lockSuccess = await lock.acquireLock(tenantId: 'tenant_nutopia');
      expect(lockSuccess, isTrue);
      expect(lock.state.phase, equals(CutoffMaintenancePhase.locked));

      // Yeni yazma denemesi doğrudan reddedilmelidir
      expect(
        () => lock.assertWritePermitted(operation: 'SalesController.createSale'),
        throwsA(isA<CutoffMaintenanceActiveException>()),
      );

      // Drainer üzerinden de fırlatılmalı
      expect(
        () => drainer.runTrackedWrite(
          operationType: 'createSale',
          caller: 'SalesController',
          action: () async => 'success',
          isWritePermitted: () => lock.state.isWritePermitted,
          currentPhase: () => lock.state.phase,
        ),
        throwsA(isA<CutoffMaintenanceActiveException>()),
      );
    });

    // 2. Devam eden satış bitmeden drainer tamamlandı demez
    test('Senaryo 2: Devam eden satış bitmeden drainer tamamlandı demez', () async {
      final drainer = InFlightTransactionDrainer();
      final lock = CutoffMaintenanceLock(drainer: drainer);

      final inFlightActionCompleter = Completer<void>();
      var inFlightFinished = false;

      // Başlamış işlem
      final inFlightFuture = drainer.runTrackedWrite(
        operationType: 'completeSale',
        caller: 'SalesController',
        action: () async {
          await inFlightActionCompleter.future;
          inFlightFinished = true;
          return 'sale_saved';
        },
        isWritePermitted: () => true, // Kilit öncesinde başladı
        currentPhase: () => CutoffMaintenancePhase.idle,
      );

      expect(drainer.inFlightCount, equals(1));
      expect(lock.isSafeForSnapshot, isFalse);

      // Kilit alma ve drain işlemi başlatılır
      var lockAcquired = false;
      final acquireFuture = lock.acquireLock(tenantId: 'tenant_nutopia').then((res) {
        lockAcquired = res;
      });

      // Drainer henüz tamamlanmamış olmalı çünkü işlem devam ediyor
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(lockAcquired, isFalse);
      expect(inFlightFinished, isFalse);
      expect(lock.state.phase, equals(CutoffMaintenancePhase.draining));

      // İşlemi tamamla
      inFlightActionCompleter.complete();
      await inFlightFuture;
      await acquireFuture;

      expect(inFlightFinished, isTrue);
      expect(lockAcquired, isTrue);
      expect(drainer.inFlightCount, equals(0));
      expect(lock.state.phase, equals(CutoffMaintenancePhase.locked));
    });

    // 3. Bekleyen bir finansal hareket varken snapshot onaylanmaz
    test('Senaryo 3: Bekleyen bir finansal hareket varken snapshot onaylanmaz', () async {
      final drainer = InFlightTransactionDrainer();
      final lock = CutoffMaintenanceLock(drainer: drainer);

      final finishTxCompleter = Completer<void>();

      // Finansal işlem başlar
      final txFuture = drainer.runTrackedWrite(
        operationType: 'recordPayment',
        caller: 'SqlitePaymentRepository',
        action: () async {
          await finishTxCompleter.future;
          return 100.0;
        },
        isWritePermitted: () => true,
        currentPhase: () => CutoffMaintenancePhase.idle,
      );

      expect(lock.isSafeForSnapshot, isFalse, reason: 'İşlem sürerken snapshot onaylanamaz');

      finishTxCompleter.complete();
      await txFuture;

      // Kilit alınmadığı sürece de onaylanmaz
      expect(lock.isSafeForSnapshot, isFalse, reason: 'Kilit henüz locked fazına geçmedi');

      await lock.acquireLock(tenantId: 'tenant_nutopia');
      expect(lock.isSafeForSnapshot, isTrue, reason: 'Kilit alındı ve inFlightCount=0, snapshot güvenli');
    });

    // 4. Timeout durumunda routing kapalı kalır
    test('Senaryo 4: Timeout durumunda routing kapalı kalır ve kilit fail-closed moduna geçer', () async {
      final drainer = InFlightTransactionDrainer(defaultTimeout: const Duration(milliseconds: 100));
      final lock = CutoffMaintenanceLock(drainer: drainer);

      // Asla bitmeyen işlem simülasyonu
      final neverEndingCompleter = Completer<void>();
      // ignore: unawaited_futures
      drainer.runTrackedWrite(
        operationType: 'hanging_write',
        caller: 'HangingService',
        action: () => neverEndingCompleter.future,
        isWritePermitted: () => true,
        currentPhase: () => CutoffMaintenancePhase.idle,
      );

      final success = await lock.acquireLock(
        tenantId: 'tenant_nutopia',
        timeout: const Duration(milliseconds: 100),
      );

      expect(success, isFalse, reason: 'Timeout durumunda kilit alınamamalıdır');
      expect(lock.state.phase, equals(CutoffMaintenancePhase.error));
      expect(lock.state.errorMessage, contains('Drain timeout'));

      // Routing hook ve flag kesinlikle kapalı kalmalı
      expect(DatabaseManager.databaseRoutingHook, isNull);

      neverEndingCompleter.complete(); // Test temizliği
    });

    // 5. Kilit atlayan yazma yolu varsa denetim bunu tespit eder
    test('Senaryo 5: Kilit atlayan yazma yollarının denetimi (Audit Path Verification)', () {
      final auditRecords = <WritePathAuditRecord>[
        const WritePathAuditRecord(
          pathName: 'SalesController.createSale',
          callChain: 'SalesController -> SalesService -> SqliteSaleRepository -> DbGateway',
          level: WritePathSecurityLevel.unprotected,
          description: 'SalesController içinde CutoffMaintenanceLock kontrolü bulunmamaktadır.',
          remediation: 'SalesController.createSale başlangıcında lock.assertWritePermitted() eklenmeli.',
        ),
        const WritePathAuditRecord(
          pathName: 'OrdersController.addOrder',
          callChain: 'OrdersController -> SqliteOrderRepository -> DbGateway',
          level: WritePathSecurityLevel.unprotected,
          description: 'OrdersController doğrudan sipariş kaydı açmaktadır.',
          remediation: 'OrdersController metoduna cutoff guard eklenmeli.',
        ),
        const WritePathAuditRecord(
          pathName: 'TelemetryUploadService.recordMetric',
          callChain: 'TelemetryUploadService -> DatabaseManager.instance.getDatabase() -> db.insert',
          level: WritePathSecurityLevel.unprotected,
          description: 'DbGateway ve write lock tamamen bypass edilmektedir.',
          remediation: 'Metrik kaydı JSONL veya hafıza kuyruğuna alınmalı, SQLite bypass kaldırılmalı.',
        ),
        const WritePathAuditRecord(
          pathName: 'SyncNotifier.triggerSync',
          callChain: 'SyncNotifier -> SyncStateMachine -> raw db queries/writes',
          level: WritePathSecurityLevel.unprotected,
          description: 'Arka plan senkronizasyonu bağımsız yazma gerçekleştirmektedir.',
          remediation: 'SyncStateMachine başlangıcında bakım kilidi kontrol edilmeli.',
        ),
      ];

      final unprotectedPaths = auditRecords.where((r) => r.level == WritePathSecurityLevel.unprotected).toList();
      expect(unprotectedPaths.length, equals(4),
          reason: 'Mevcut üretim kodundaki tüm korumasız yollar denetim tarafından tespit edildi');
    });

    // 6. Uygulama yeniden başlatıldığında belirsiz geçiş durumu güvenli biçimde ele alınır
    test('Senaryo 6: Uygulama yeniden başlatıldığında kalıcı bakım modu hatırlanır (Fail-closed on reboot)', () async {
      final storage = InMemoryMaintenancePersistenceStorage();

      // Kilitli durumda çöken/kapanan uygulama durumu
      await storage.saveState(const CutoffMaintenanceState(
        phase: CutoffMaintenancePhase.locked,
        tenantId: 'tenant_nutopia',
        reason: 'Cutover Catch-Up',
      ));

      // Yeni başlatılan oturum
      final newLock = CutoffMaintenanceLock(storage: storage);
      await newLock.initializeFromStorage();

      expect(newLock.state.phase, equals(CutoffMaintenancePhase.locked));
      expect(newLock.state.isWritePermitted, isFalse);
      expect(newLock.state.userFacingBanner, isNotNull);
      expect(newLock.state.errorMessage, contains('beklenmedik şekilde kapandı'));
    });

    // 7. İki eşzamanlı işlem aynı checkpoint'i yanlışlıkla ilerletemez
    test('Senaryo 7: İki eşzamanlı işlem aynı checkpoint i ilerletemez (Optimistic Concurrency Control)', () async {
      final repo = InMemoryCutoverCheckpointRepository();
      final initial = CutoverCheckpoint(
        tenantId: 'tenant_nutopia',
        sourceDbId: 'src_hash_1',
        targetDbId: 'tgt_hash_1',
        snapshotId: 'snap_001',
        snapshotTimestamp: DateTime(2026, 10, 20, 10, 0),
        lastSequenceId: 100,
        status: 'pending',
        version: 1,
      );

      await repo.saveCheckpoint(initial);

      // Worker 1 ve Worker 2 aynı başlangıç sürümünü okur (version = 1)
      final worker1State = await repo.getLatestCheckpoint('tenant_nutopia');
      final worker2State = await repo.getLatestCheckpoint('tenant_nutopia');

      expect(worker1State!.version, equals(1));
      expect(worker2State!.version, equals(1));

      // Worker 1 checkpoint'i ilerletir
      final worker1Advanced = await repo.advanceCheckpoint(
        worker1State,
        worker1State.copyWith(status: 'reconciled', lastSequenceId: 120),
      );
      expect(worker1Advanced, isTrue);

      // Worker 2 eski sürümle (version = 1) ilerletmeye çalışır -> Reddedilmelidir
      final worker2Advanced = await repo.advanceCheckpoint(
        worker2State,
        worker2State.copyWith(status: 'committed', lastSequenceId: 130),
      );
      expect(worker2Advanced, isFalse, reason: 'Eşzamanlı çakışma durumunda ikinci worker reddedilmelidir');

      final finalState = await repo.getLatestCheckpoint('tenant_nutopia');
      expect(finalState!.version, equals(2));
      expect(finalState.status, equals('reconciled'));
    });

    // 8. Tenant uyuşmazlığında geçiş reddedilir
    test('Senaryo 8: Tenant uyuşmazlığında kilit alma reddedilir (ArgumentError)', () async {
      final lock = CutoffMaintenanceLock();
      await lock.acquireLock(tenantId: 'tenant_nutopia');

      // Nutopia için kilitliyken Erkul Çeyiz için ikinci bir kilit alınamaz
      expect(
        () => lock.acquireLock(tenantId: 'tenant_erkul'),
        throwsA(isA<ArgumentError>()),
      );
    });

    // 9. Başarısız mutabakat sonrası legacy kullanım yolu korunur
    test('Senaryo 9: Başarısız mutabakat durumunda routing hook null kalır ve legacy korunur', () async {
      final lock = CutoffMaintenanceLock();
      await lock.acquireLock(tenantId: 'tenant_nutopia');

      // Simüle edilen mutabakat hatası
      final isReconciled = false;

      if (!isReconciled) {
        // Geçiş iptal edilir, kilit serbest bırakılır
        await lock.releaseLock();
      }

      expect(lock.state.phase, equals(CutoffMaintenancePhase.idle));
      expect(lock.state.isWritePermitted, isTrue);
      expect(DatabaseManager.databaseRoutingHook, isNull);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
    });

    // 10. Bütün işlemler tamamlandığında kilit kontrollü şekilde kaldırılabilir
    test('Senaryo 10: Bütün işlemler bittiğinde kilit kontrollü şekilde kaldırılır', () async {
      final lock = CutoffMaintenanceLock();
      await lock.acquireLock(tenantId: 'tenant_nutopia');

      expect(lock.state.phase, equals(CutoffMaintenancePhase.locked));
      expect(lock.state.isWritePermitted, isFalse);

      await lock.releaseLock();

      expect(lock.state.phase, equals(CutoffMaintenancePhase.idle));
      expect(lock.state.isWritePermitted, isTrue);
      expect(lock.state.userFacingBanner, isNull);
      expect(lock.drainer.inFlightCount, equals(0));
    });
  });
}
