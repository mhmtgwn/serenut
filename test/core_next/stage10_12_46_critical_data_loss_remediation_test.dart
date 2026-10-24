// test/core_next/stage10_12_46_critical_data_loss_remediation_test.dart
// SERENUT OS — STAGE 10.12.46
// Kritik Veri Kaybı Risklerini Giderme ve Cutover Öncesi Doğrulama Test Paketi
// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('SERENUT OS — STAGE 10.12.46 CRITICAL DATA LOSS REMEDIATION SUITE', () {
    late Directory tempDir;
    late String legacyDbPath;
    late String targetDbPath;
    final openDatabases = <Database>[];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('serenut_stage46_test_');
      legacyDbPath = '${tempDir.path}/legacy_pos.db';
      targetDbPath = '${tempDir.path}/serenut_core_v2.db';
      openDatabases.clear();
      SharedPreferences.setMockInitialValues({});
      CoreNextBootstrapCoordinator.resetExecutionLock();
    });

    tearDown(() async {
      for (final db in openDatabases) {
        if (db.isOpen) {
          await db.close();
        }
      }
      openDatabases.clear();
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    // Helper: Legacy DB kurulumu
    Future<Database> createLegacyDb() async {
      final db = await databaseFactory.openDatabase(
        legacyDbPath,
        options: OpenDatabaseOptions(
          version: 60,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE products (
                id TEXT PRIMARY KEY,
                barcode TEXT,
                name TEXT,
                price REAL,
                price_minor INTEGER,
                purchase_price REAL,
                purchase_price_minor INTEGER,
                stock_quantity REAL,
                quantity REAL,
                vat REAL,
                vat_rate REAL,
                min_stock REAL,
                is_active INTEGER DEFAULT 1,
                is_deleted INTEGER DEFAULT 0,
                created_at TEXT,
                updated_at TEXT
              );
            ''');
            await db.execute('''
              CREATE TABLE customers (
                id TEXT PRIMARY KEY,
                name TEXT,
                phone TEXT,
                balance REAL,
                balance_minor INTEGER,
                notes TEXT,
                is_active INTEGER DEFAULT 1,
                is_deleted INTEGER DEFAULT 0,
                created_at TEXT,
                updated_at TEXT
              );
            ''');
            await db.execute('''
              CREATE TABLE sales (
                id TEXT PRIMARY KEY,
                receipt_number TEXT,
                receipt_no TEXT,
                customer_id TEXT,
                total_amount REAL,
                total_amount_minor INTEGER,
                paid_amount REAL,
                paid_amount_minor INTEGER,
                discount_amount REAL,
                discount_amount_minor INTEGER,
                payment_method TEXT,
                cashier_name TEXT,
                fsm_state TEXT,
                status TEXT DEFAULT 'COMPLETED',
                refunded_amount REAL DEFAULT 0,
                is_deleted INTEGER DEFAULT 0,
                created_at TEXT,
                updated_at TEXT
              );
            ''');
            await db.execute('''
              CREATE TABLE sale_items (
                id TEXT PRIMARY KEY,
                sale_id TEXT,
                product_id TEXT,
                product_name TEXT,
                quantity REAL,
                unit_price REAL,
                subtotal REAL,
                created_at TEXT
              );
            ''');
            await db.execute('''
              CREATE TABLE sale_payments (
                id TEXT PRIMARY KEY,
                sale_id TEXT,
                payment_type TEXT,
                amount REAL,
                amount_minor INTEGER,
                reference_note TEXT,
                created_at TEXT
              );
            ''');
            await db.execute('''
              CREATE TABLE refunds (
                id TEXT PRIMARY KEY,
                sale_id TEXT,
                amount REAL,
                amount_minor INTEGER,
                refund_method TEXT,
                external_reference TEXT,
                reason TEXT,
                status TEXT DEFAULT 'completed',
                created_at TEXT
              );
            ''');
            await db.execute('''
              CREATE TABLE financial_transactions (
                id TEXT PRIMARY KEY,
                customer_id TEXT,
                type TEXT,
                amount REAL,
                reference_id TEXT,
                description TEXT,
                created_at TEXT
              );
            ''');
            await db.execute('''
              CREATE TABLE sync_outbox_v4 (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                mutation_id TEXT,
                entity_type TEXT,
                entity_id TEXT,
                operation TEXT,
                payload TEXT,
                base_revision INTEGER DEFAULT 0,
                state TEXT DEFAULT 'PENDING',
                attempts INTEGER DEFAULT 0,
                created_at TEXT
              );
            ''');
          },
        ),
      );
      openDatabases.add(db);
      return db;
    }

    Future<CoreAppDatabase> createCoreDb() async {
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      openDatabases.add(coreDb.db);
      return coreDb;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // GÜVENLİK DEĞİŞMEZLERİ (INVARIANTS)
    // ──────────────────────────────────────────────────────────────────────────
    test('Invariant 1: Canlı cutover kilitleri (coreNextSalesEngineEnabledProvider = false, databaseRoutingHook = null) kesinlikle korunmalıdır', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 1: İlk Aktarım Sırasında Yeni Satış
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 1: İlk aktarım sonrasında oluşan yeni satış zaman damgasıyla yakalanır ve mutabakata girer', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      // Başlangıç ürünü
      await legDb.insert('products', {
        'id': 'p1',
        'barcode': '111',
        'name': 'Fındık 500g',
        'price': 100.0,
        'stock_quantity': 50.0,
        'created_at': '2026-10-20T08:00:00Z',
        'updated_at': '2026-10-20T08:00:00Z',
      });
      // Target'a ilk ürün aktarımı
      await coreDb.db.insert('products', {
        'id': 'p1',
        'barcode': '111',
        'name': 'Fındık 500g',
        'price_cents': 10000,
        'stock_quantity': 50.0,
        'updated_at': 1000,
      });

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Aktarım anında yeni satış gerçekleşir
      final nowIso = DateTime.now().toIso8601String();
      await legDb.insert('sales', {
        'id': 'sale_new_01',
        'receipt_number': 'REC-101',
        'total_amount': 100.0,
        'paid_amount': 100.0,
        'payment_method': 'cash',
        'status': 'COMPLETED',
        'created_at': nowIso,
        'updated_at': nowIso,
      });
      await legDb.insert('sale_items', {
        'id': 'si_101',
        'sale_id': 'sale_new_01',
        'product_id': 'p1',
        'product_name': 'Fındık 500g',
        'quantity': 1.0,
        'unit_price': 100.0,
        'subtotal': 100.0,
        'created_at': nowIso,
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      expect(report.decision, CutoverReconciliationDecision.cutoverApproved);
      expect(report.coreSalesCount, 1);
      expect(report.coreTotalSalesCents, 10000);
      expect(report.statistics.salesMigrated, 1);
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 2: İlk Aktarım Sonrasında Eski Bir Satışın İptali
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 2: Eski bir satış sonradan iptal edildiğinde updated_at ile yakalanır ve hedefte CANCELLED olarak güncellenir', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      // Eski satış (cutoff öncesi)
      const oldSaleTime = '2026-10-20T07:00:00Z';
      await legDb.insert('sales', {
        'id': 'sale_old_01',
        'receipt_number': 'REC-OLD',
        'total_amount': 200.0,
        'paid_amount': 200.0,
        'payment_method': 'cash',
        'status': 'COMPLETED',
        'created_at': oldSaleTime,
        'updated_at': oldSaleTime,
      });
      // Target'a daha önce aktarılmış
      await coreDb.db.insert('sales', {
        'id': 'sale_old_01',
        'receipt_no': 'REC-OLD',
        'subtotal_cents': 20000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 20000,
        'paid_cents': 20000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'idem_old',
        'created_at': 1000,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'pay_old',
        'sale_id': 'sale_old_01',
        'payment_type': 'cash',
        'amount_cents': 20000,
        'created_at': 1000,
      });

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Cutoff sonrasında satış iptal ediliyor (is_deleted = 1 veya status = 'cancelled')
      final nowIso = DateTime.now().toIso8601String();
      await legDb.update('sales', {
        'status': 'cancelled',
        'updated_at': nowIso,
      }, where: 'id = ?', whereArgs: ['sale_old_01']);

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      final targetSale = await coreDb.db.query('sales', where: 'id = ?', whereArgs: ['sale_old_01']);
      expect(targetSale.first['status'], 'CANCELLED', reason: 'İptal edilen satış hedefte CANCELLED durumuna güncellenmelidir');
      expect(report.decision, CutoverReconciliationDecision.cutoverApproved);
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 3: Kısmi İade
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 3: Kısmi iade yapıldığında refunds tablosu taranır, satış durumu PARTIALLY_REFUNDED olur ve deftere işlenir', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      // 500 TL'lik satış
      await legDb.insert('sales', {
        'id': 'sale_partial_01',
        'receipt_number': 'REC-500',
        'total_amount': 500.0,
        'paid_amount': 500.0,
        'payment_method': 'cash',
        'status': 'COMPLETED',
        'created_at': '2026-10-20T08:00:00Z',
        'updated_at': '2026-10-20T08:00:00Z',
      });
      await coreDb.db.insert('sales', {
        'id': 'sale_partial_01',
        'receipt_no': 'REC-500',
        'subtotal_cents': 50000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 50000,
        'paid_cents': 50000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'idem_part',
        'created_at': 1000,
      });

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 150 TL kısmi iade işleniyor
      final nowIso = DateTime.now().toIso8601String();
      await legDb.insert('refunds', {
        'id': 'ref_01',
        'sale_id': 'sale_partial_01',
        'amount': 150.0,
        'refund_method': 'cash',
        'reason': 'Kusurlu ürün iadesi',
        'created_at': nowIso,
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      final targetSale = await coreDb.db.query('sales', where: 'id = ?', whereArgs: ['sale_partial_01']);
      expect(targetSale.first['status'], 'PARTIALLY_REFUNDED');
      expect(report.statistics.refundsMigrated, 1);

      final ledger = await coreDb.db.query('ledger_entries', where: 'reference_sale_id = ?', whereArgs: ['sale_partial_01']);
      expect(ledger, isNotEmpty);
      expect(ledger.first['entry_type'], 'REFUND');
      expect(ledger.first['amount_cents'], 15000);
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 4: Mevcut Ürünün Stok ve Fiyat Güncellemesi
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 4: Mevcut ürünün fiyatı ve stoğu değiştiğinde monoton zaman damgasıyla güncellenir, eski veri yeni veriyi ezemez', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      // Başlangıç: 100 TL ve 20 adet
      await legDb.insert('products', {
        'id': 'p_stok_1',
        'barcode': 'PSTOK',
        'name': 'Giresun Fındık',
        'price': 100.0,
        'stock_quantity': 20.0,
        'updated_at': '2026-10-20T08:00:00Z',
      });
      await coreDb.db.insert('products', {
        'id': 'p_stok_1',
        'barcode': 'PSTOK',
        'name': 'Giresun Fındık',
        'price_cents': 10000,
        'stock_quantity': 20.0,
        'updated_at': 1000,
      });

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Fiyat 120 TL yapıldı, stok satıldı 15'e düştü
      final nowIso = DateTime.now().toIso8601String();
      await legDb.update('products', {
        'price': 120.0,
        'stock_quantity': 15.0,
        'updated_at': nowIso,
      }, where: 'id = ?', whereArgs: ['p_stok_1']);

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      final targetProd = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p_stok_1']);
      expect(targetProd.first['price_cents'], 12000);
      expect(targetProd.first['stock_quantity'], 15.0);
      expect(report.statistics.productsUpdated, 1);
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 5: Mevcut Müşteri Bakiyesinin Değişmesi
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 5: Müşteri bakiyesi değiştiğinde hedef customers tablosunda kuruş hassasiyetinde güncellenir', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      await legDb.insert('customers', {
        'id': 'c_bal_1',
        'name': 'Ahmet Yılmaz',
        'balance': 0.0,
        'updated_at': '2026-10-20T08:00:00Z',
      });
      await coreDb.db.insert('customers', {
        'id': 'c_bal_1',
        'name': 'Ahmet Yılmaz',
        'balance_cents': 0,
        'updated_at': 1000,
      });

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Veresiye alışveriş ile 350 TL borçlandı
      final nowIso = DateTime.now().toIso8601String();
      await legDb.update('customers', {
        'balance': 350.0,
        'updated_at': nowIso,
      }, where: 'id = ?', whereArgs: ['c_bal_1']);

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      final targetCust = await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c_bal_1']);
      expect(targetCust.first['balance_cents'], 35000);
      expect(report.statistics.customersUpdated, 1);
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 6: Karma Ödemenin Gerçek Parçalarıyla Aktarılması
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 6: Karma ödemede sentetik tekil ödeme üretilmez; gerçek nakit ve kart parçaları kimlik ve tutarlarıyla aktarılır', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 300 TL'lik satış: 100 TL Nakit + 200 TL Kredi Kartı
      final nowIso = DateTime.now().toIso8601String();
      await legDb.insert('sales', {
        'id': 'sale_split_01',
        'receipt_number': 'REC-SPLIT',
        'total_amount': 300.0,
        'paid_amount': 300.0,
        'payment_method': 'mixed',
        'created_at': nowIso,
        'updated_at': nowIso,
      });
      await legDb.insert('sale_payments', {
        'id': 'sp_cash_1',
        'sale_id': 'sale_split_01',
        'payment_type': 'cash',
        'amount': 100.0,
        'reference_note': 'Nakit parça',
        'created_at': nowIso,
      });
      await legDb.insert('sale_payments', {
        'id': 'sp_card_1',
        'sale_id': 'sale_split_01',
        'payment_type': 'creditCard',
        'amount': 200.0,
        'reference_note': 'Kart parça',
        'created_at': nowIso,
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      final payments = await coreDb.db.query(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: ['sale_split_01'],
        orderBy: 'amount_cents ASC',
      );

      expect(payments.length, 2, reason: 'Sentetik tekil ödeme değil, 2 gerçek ödeme parçası aktarılmalıdır');
      expect(payments[0]['payment_type'], 'cash');
      expect(payments[0]['amount_cents'], 10000);
      expect(payments[1]['payment_type'], 'creditCard');
      expect(payments[1]['amount_cents'], 20000);
      expect(report.decision, CutoverReconciliationDecision.cutoverApproved);
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 7: Tahsilatın Aktarım Sırasında Oluşması
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 7: Aktarım anında oluşan tahsilat financial_transactions üzerinden ledger_entries tablosuna aktarılır', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      await legDb.insert('customers', {
        'id': 'c_tahsilat',
        'name': 'Mehmet Demir',
        'balance': 500.0,
        'updated_at': '2026-10-20T08:00:00Z',
      });
      await coreDb.db.insert('customers', {
        'id': 'c_tahsilat',
        'name': 'Mehmet Demir',
        'balance_cents': 50000,
        'updated_at': 1000,
      });

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 200 TL tahsilat yapıldı
      final nowIso = DateTime.now().toIso8601String();
      await legDb.insert('financial_transactions', {
        'id': 'ft_tahsilat_1',
        'customer_id': 'c_tahsilat',
        'type': 'collection',
        'amount': 200.0,
        'description': 'Kısmi borç tahsilatı',
        'created_at': nowIso,
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      final ledger = await coreDb.db.query('ledger_entries', where: 'id = ?', whereArgs: ['ft_tahsilat_1']);
      expect(ledger, isNotEmpty);
      expect(ledger.first['entry_type'], 'collection');
      expect(ledger.first['amount_cents'], 20000);
      expect(report.statistics.ledgerEntriesMigrated, 1);
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 8: Migration Ortasında Uygulamanın Kapanması (Crash Recovery)
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 8: Migration ortasında çökme yaşanırsa migrationStateCompleted = false kalır ve DatabaseRoutingResolver kesinlikle legacy fallback döner', () async {
      const resolver = DatabaseRoutingResolver();

      // migrationStateCompleted = false durumunda hedef dosya dolu olsa dahi açılamaz
      final file = File(targetDbPath);
      await file.writeAsBytes(List.filled(1024, 0)); // Dummy dosya

      final resolution = await resolver.resolve(
        requestedTenantId: 'tenant-default',
        legacyDbPath: legacyDbPath,
        targetDbPath: targetDbPath,
        migrationStateCompleted: false,
        dbFactory: databaseFactory,
      );

      expect(resolution.decision, RoutingDecision.legacyFallback);
      expect(resolution.isTargetSelected, isFalse);
      expect(resolution.resolvedPath, legacyDbPath);
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 9: Aynı Değişiklik Günlüğünün Tekrar Uygulanması (Idempotency)
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 9: Aynı catch-up koordinatörü iki kez peş peşe çalıştırıldığında mükerrer kayıt oluşturmaz, mutabakat bozulmaz', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      final nowIso = DateTime.now().toIso8601String();
      await legDb.insert('sales', {
        'id': 'sale_idem_1',
        'receipt_number': 'REC-IDEM',
        'total_amount': 75.0,
        'paid_amount': 75.0,
        'payment_method': 'cash',
        'created_at': nowIso,
        'updated_at': nowIso,
      });

      // 1. Çalıştırma
      final rep1 = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: 0,
      );
      expect(rep1.decision, CutoverReconciliationDecision.cutoverApproved);

      final salesCount1 = Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM sales'));
      final payCount1 = Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM sale_payments'));

      // 2. Çalıştırma (Aynı veri üzerinde tekrar)
      final rep2 = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: 0,
      );
      expect(rep2.decision, CutoverReconciliationDecision.cutoverApproved);

      final salesCount2 = Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM sales'));
      final payCount2 = Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM sale_payments'));

      expect(salesCount2, salesCount1, reason: 'Mükerrer satış oluşmamalıdır');
      expect(payCount2, payCount1, reason: 'Mükerrer ödeme kaydı oluşmamalıdır');
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 10: Senkronizasyon Kuyruğundaki İşlemler (Sync Outbox)
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 10: Çevrimdışı sync_outbox_v4 kuyruğundaki bekleyen mutasyonlar güvenle Core Next sync_events tablosuna aktarılır', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      final nowIso = DateTime.now().toIso8601String();
      await legDb.insert('sync_outbox_v4', {
        'mutation_id': 'mut_offline_1',
        'entity_type': 'sale',
        'entity_id': 'sale_off_1',
        'operation': 'UPSERT',
        'payload': '{"sale_id": "sale_off_1", "amount": 100}',
        'state': 'PENDING',
        'attempts': 0,
        'created_at': nowIso,
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: 0,
      );

      expect(report.statistics.syncEventsMigrated, 1);
      final events = await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut_offline_1']);
      expect(events, isNotEmpty);
      expect(events.first['sync_state'], 'PENDING');
      expect(events.first['entity_type'], 'sale');
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 11: Mutabakat Farkı Olduğunda Legacy Routing'in Korunması
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 11: Kaynak ile hedef arasında tutar sapması olduğunda cutover engellenir ve app_settings cutover_reconciliation_status = blocked yazılır', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      // Legacy'de 100 TL'lik satış
      await legDb.insert('sales', {
        'id': 'sale_var_1',
        'receipt_number': 'REC-VAR',
        'total_amount': 100.0,
        'paid_amount': 100.0,
        'payment_method': 'cash',
        'created_at': '2026-10-20T08:00:00Z',
      });
      // Target'a yapay olarak farklı tutar yerleştirilmiş (10 TL eksik!)
      await coreDb.db.insert('sales', {
        'id': 'sale_var_1',
        'receipt_no': 'REC-VAR',
        'subtotal_cents': 9000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 9000,
        'paid_cents': 9000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'idempotency_key': 'idem_var',
        'created_at': 1000,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'pay_var_1',
        'sale_id': 'sale_var_1',
        'payment_type': 'cash',
        'amount_cents': 9000,
        'created_at': 1000,
      });

      // Cutoff'u geleceğe koyarak bu satışın catch-up'ta ezilmesini simüle edelim (variance kalsın)
      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: DateTime.now().millisecondsSinceEpoch + 100000,
      );

      expect(report.decision, CutoverReconciliationDecision.cutoverBlockedVarianceDetected);
      expect(report.isMatched, isFalse);

      final statusRow = await coreDb.db.query('app_settings', where: "key = 'cutover_reconciliation_status'");
      expect(statusRow.first['value'], 'blocked');
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 12: Eksik Ödeme Olduğunda Sessiz Veri Kaybı Yerine Güvenli Engelleme
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 12: Bir satış için gerçek ödeme parçaları satış tutarıyla uyuşmadığında sessizce geçmek yerine cutoverBlockedIntegrityError ile durdurulur', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      final nowIso = DateTime.now().toIso8601String();
      // 500 TL'lik satış
      await legDb.insert('sales', {
        'id': 'sale_corrupt_1',
        'receipt_number': 'REC-CORRUPT',
        'total_amount': 500.0,
        'paid_amount': 500.0,
        'payment_method': 'mixed',
        'created_at': nowIso,
        'updated_at': nowIso,
      });
      // Ancak parçaların toplamı sadece 300 TL (200 TL eksik / bozuk veri)
      await legDb.insert('sale_payments', {
        'id': 'sp_corrupt_1',
        'sale_id': 'sale_corrupt_1',
        'payment_type': 'cash',
        'amount': 300.0,
        'created_at': nowIso,
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: 0,
      );

      expect(report.decision, CutoverReconciliationDecision.cutoverBlockedIntegrityError);
      expect(report.isMatched, isFalse);
      expect(report.details.toLowerCase().contains('ödeme'), isTrue);
    });
  });
}
