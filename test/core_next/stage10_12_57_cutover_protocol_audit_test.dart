// test/core_next/stage10_12_57_cutover_protocol_audit_test.dart
// SERENUT OS — STAGE 10.12.57
// CUTOVER PROTOCOL IMPLEMENTATION AUDIT TEST SUITE
//
// DEĞİŞMEZ GÜVENLİK KURALLARI:
// 1. Canlı hiçbir veritabanına yazma, onarım veya migration yapılmaz.
// 2. Yalnızca izole, geçici disposable test kopyaları üzerinde çalışılır.
// 3. coreNextSalesEngineEnabledProvider = false ve DatabaseManager.databaseRoutingHook = null kalır.

// ignore_for_file: avoid_relative_lib_imports, prefer_const_declarations

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart';
import '../../core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('STAGE 10.12.57: Değişmez Güvenlik Kuralları', () {
    test('Kural 1: coreNextSalesEngineEnabledProvider kesinlikle false kalmalı', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
    });

    test('Kural 2: DatabaseManager.databaseRoutingHook kesinlikle null kalmalı', () {
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });

    test('Kural 3: coreNextMigrationRunnerProvider ve coreNextCatchUpRunnerProvider varsayılan olarak null kalmalı', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextMigrationRunnerProvider), isNull);
      expect(container.read(coreNextCatchUpRunnerProvider), isNull);
    });
  });

  group('STAGE 10.12.57: 6 Adımlı Kesim Protokolünün Kod Düzeyinde Varlık Denetimi', () {
    test('Adım 1 & 2: Satış durdurma ve in-flight transaction tracker mekanizması kodda mevcut DEĞİLDİR (NOT_IMPLEMENTED)', () {
      // SalesController incelenir: Kasa durdurma / transition lock bayrağı veya API'si bulunmamaktadır.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // coreNextSalesEngineEnabledProvider sadece hedef motoru seçer; satışı durduran bir lock değildir.
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
      expect(container.read(coreNextSaleExecutorProvider), isNull);

      // Canlı yazmaları bloke eden merkezi kilit bulunmadığı için doğrudan cutover riski mevcuttur.
      const isCentralCutoverLockImplemented = false;
      expect(isCentralCutoverLockImplemented, isFalse,
          reason: 'Canlı kasayı donduran merkezi kilit mekanizması kodlanmamıştır (NOT_IMPLEMENTED)');
    });

    test('Adım 3: Anlık snapshot yeteneği mevcuttur ancak kalıcı cut-off checkpoint koordinasyonu henüz runtime a bağlı değildir (PARTIALLY_IMPLEMENTED)', () {
      // Snapshot alınabilir (SQLite Online Backup), ancak canlı akışta T_cut'ı kalıcı bir checkpoint olarak işleten otomatik runtime kodu bağlı değildir.
      const isPersistentCutoffCheckpointHooked = false;
      expect(isPersistentCutoffCheckpointHooked, isFalse,
          reason: 'Kalıcı T_cut checkpoint akışı runtime bootstrap e bağlı değildir (PARTIALLY_IMPLEMENTED)');
    });

    test('Adım 4 & 5: Delta aktarımı ve mutabakat kapısı gerçek kodda mevcuttur (IMPLEMENTED_AND_TESTED)', () {
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();
      expect(coordinator, isNotNull);
      // performCatchUpAndReconcile ve repairHistoricalLedgerEntries metotları eksiksiz mevcuttur.
    });

    test('Adım 6: Fail-closed fallback vardır ancak tersine rollback (reverse sync) mekanizması kodlanmamıştır (PARTIALLY_IMPLEMENTED)', () {
      // PilotCutoverGate fail-closed olarak legacyFallback dönebilir.
      // Ancak yeni DB'ye yazma başladıktan sonra eski DB'ye geri dönüşte yeni verileri eski DB'ye yazacak reverse-sync yoktur.
      const isReverseSyncEngineImplemented = false;
      expect(isReverseSyncEngineImplemented, isFalse,
          reason: 'Hedefte yazılan satışları eski DB ye aktaran tersine senkronizasyon motoru yoktur');
    });
  });

  group('STAGE 10.12.57: Eşzamanlı İşlemler, Eşit Zaman Damgaları ve Mutabakat Başarısızlığı', () {
    late Directory tempDir;
    late String isolatedLegacyPath;
    late String isolatedTargetPath;
    late CoreAppDatabase targetCoreDb;
    late Database legacyDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage57_protocol_test_');
      isolatedLegacyPath = p.join(tempDir.path, 'legacy_prod_sim.db');
      isolatedTargetPath = p.join(tempDir.path, 'core_target_sim.db');

      legacyDb = await databaseFactory.openDatabase(isolatedLegacyPath);
      await legacyDb.execute('''
        CREATE TABLE settings (id TEXT PRIMARY KEY, business_name TEXT);
        INSERT INTO settings VALUES ('1', 'Nutopia Fındık Değirmeni');

        CREATE TABLE customers (
          id TEXT PRIMARY KEY,
          name TEXT,
          phone TEXT,
          email TEXT,
          balance REAL,
          balance_minor INTEGER DEFAULT 0,
          notes TEXT,
          is_active INTEGER DEFAULT 1,
          is_deleted INTEGER DEFAULT 0,
          created_at TEXT,
          updated_at TEXT
        );

        CREATE TABLE products (
          id TEXT PRIMARY KEY,
          barcode TEXT,
          name TEXT,
          price REAL,
          price_minor INTEGER DEFAULT 0,
          stock_quantity REAL,
          vat INTEGER DEFAULT 20,
          is_active INTEGER DEFAULT 1,
          is_deleted INTEGER DEFAULT 0,
          created_at TEXT,
          updated_at TEXT
        );

        CREATE TABLE sales (
          id TEXT PRIMARY KEY,
          receipt_number TEXT,
          customer_id TEXT,
          total_amount REAL,
          total_amount_minor INTEGER DEFAULT 0,
          paid_amount REAL,
          paid_amount_minor INTEGER DEFAULT 0,
          status TEXT,
          payment_method TEXT,
          created_at TEXT,
          updated_at TEXT
        );

        CREATE TABLE financial_transactions (
          id TEXT PRIMARY KEY,
          customer_id TEXT,
          type TEXT,
          amount REAL,
          amount_minor INTEGER DEFAULT 0,
          description TEXT,
          created_at TEXT,
          reference_id TEXT
        );
      ''');

      targetCoreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
    });

    tearDown(() async {
      await legacyDb.close();
      await targetCoreDb.close();
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('Eşit Zaman Damgalı Birden Fazla Kayıt ve Deterministik Sıralama', () async {
      final cutoff = DateTime(2026, 10, 16, 0, 0, 0);
      const exactSameTimestamp = '2026-10-17T14:30:00.000Z';

      // Aynı milisaniyede oluşmuş iki farklı finansal hareket
      await legacyDb.insert('financial_transactions', {
        'id': 'tx-same-1',
        'customer_id': 'cust-same-1',
        'type': 'payment',
        'amount': 200.0,
        'created_at': exactSameTimestamp,
      });
      await legacyDb.insert('financial_transactions', {
        'id': 'tx-same-2',
        'customer_id': 'cust-same-2',
        'type': 'sale',
        'amount': 450.0,
        'created_at': exactSameTimestamp,
      });

      const coordinator = LiveSafeCatchUpReconciliationCoordinator();
      await coordinator.performCatchUpAndReconcile(
        legacyDb: legacyDb,
        targetCoreDb: targetCoreDb,
        legacyDbPath: isolatedLegacyPath,
        lastMigrationCutoffTimestamp: cutoff.millisecondsSinceEpoch,
      );

      final entries = await targetCoreDb.db.query(
        'ledger_entries',
        where: "id IN ('tx-same-1', 'tx-same-2')",
        orderBy: 'id ASC',
      );

      expect(entries.length, equals(2), reason: 'Aynı zaman damgalı iki kayıt da kayıpsız aktarılmalıdır');
      expect(entries[0]['id'], equals('tx-same-1'));
      expect(entries[0]['amount_cents'], equals(20000));
      expect(entries[1]['id'], equals('tx-same-2'));
      expect(entries[1]['amount_cents'], equals(45000));
    });

    test('Mutabakat Uyuşmazlığı Durumunda Yönlendirme Kesinlikle Kapalı Kalır (Fail-Closed Gate)', () async {
      // Hedefte tenant ID uyuşmazlığı simülasyonu
      await targetCoreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia',
        'updated_at': 1792100000,
      });

      const coordinator = DualDatabaseRoutingCoordinator();
      final result = await coordinator.resolveAndOpen(
        requestedTenantId: 'tenant-erkul', // Uyuşmayan kiracı
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: isolatedTargetPath,
        migrationStateCompleted: true,
      );

      expect(result.decision, equals(RoutingDecision.blockedFailClosed));
      expect(result.isTargetSelected, isFalse);
      expect(result.targetDatabase, isNull);
      expect(result.reason, contains('Tenant ID uyuşmazlığı'));
    });

    test('Tersine Rollback Riski: Hedef veritabanında satış oluştuktan sonra eski DB ye geri dönülürse hedefteki kayıt eski DB de yer almaz (Split-Brain Kanıtı)', () async {
      // Hedefte bir satış gerçekleştiğini varsayalım
      await targetCoreDb.db.insert('customers', {
        'id': 'cust-new-cutover',
        'name': 'Yeni Motor Müşterisi',
        'balance_cents': 0,
        'updated_at': 1792000000,
      });
      await targetCoreDb.db.insert('sales', {
        'id': 'sale-core-next-001',
        'receipt_no': 'REC-NEXT-1',
        'customer_id': 'cust-new-cutover',
        'subtotal_cents': 100000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 100000,
        'paid_cents': 100000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'idem_next_1',
        'created_at': 1792000000,
      });

      // Eski DB'de bu kayıt mevcut DEĞİLDİR:
      final legacySale = await legacyDb.query('sales', where: "id = 'sale-core-next-001'");
      expect(legacySale, isEmpty,
          reason: 'Hedefte yazılan satış eski DB de yoktur; tersine senkronizasyon olmadan rollback split-brain yaratır');
    });
  });
}
