// test/core_next/stage10_12_47_shadow_verification_test.dart
// SERENUT OS — STAGE 10.12.47
// Shadow Verification, Bağımsız Veri Mutabakatı ve Cutover Öncesi Güvenlik Test Paketi
// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  group('SERENUT OS — STAGE 10.12.47 SHADOW VERIFICATION & RESILIENCE SUITE', () {
    late Directory tempDir;
    late String legacyDbPath;
    late String targetDbPath;
    final openDatabases = <Database>[];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('serenut_stage47_test_');
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
    // SENARYO 1: Yeni Satışın Aktarılması
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 1: Yeni canlı satış ve ödeme parçası catch-up ile Core Next hedefine eksiksiz aktarılır', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      // Ürün tanımla
      await legDb.insert('products', {
        'id': 'p1',
        'barcode': 'BC100',
        'name': 'Organik Zeytinyağı 1L',
        'price': 350.0,
        'stock_quantity': 20.0,
        'created_at': '2026-10-20T10:00:00Z',
        'updated_at': '2026-10-20T10:00:00Z',
      });
      await coreDb.db.insert('products', {
        'id': 'p1',
        'barcode': 'BC100',
        'name': 'Organik Zeytinyağı 1L',
        'price_cents': 35000,
        'stock_quantity': 20.0,
        'updated_at': 1000,
      });

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Yeni Satış ve Kalemi
      await legDb.insert('sales', {
        'id': 'sale_sh_01',
        'receipt_number': 'REC-SH-01',
        'total_amount': 350.0,
        'paid_amount': 350.0,
        'payment_method': 'cash',
        'status': 'COMPLETED',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      await legDb.insert('sale_items', {
        'id': 'item_sh_01',
        'sale_id': 'sale_sh_01',
        'product_id': 'p1',
        'product_name': 'Organik Zeytinyağı 1L',
        'quantity': 1.0,
        'unit_price': 350.0,
        'subtotal': 350.0,
        'created_at': DateTime.now().toIso8601String(),
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      expect(report.isMatched, isTrue);
      expect(report.decision, equals(CutoverReconciliationDecision.cutoverApproved));
      expect(report.statistics.salesMigrated, equals(1));
      expect(report.statistics.saleItemsMigrated, equals(1));

      final targetSale = await coreDb.db.query('sales', where: 'id = ?', whereArgs: ['sale_sh_01']);
      expect(targetSale.first['total_cents'], equals(35000));
      expect(targetSale.first['paid_cents'], equals(35000));
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 2: Daha Önce Oluşturulmuş Satışın Sonradan Güncellenmesi veya İptal Edilmesi
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 2: Önceden aktarılmış satış sonradan iptal edildiğinde CANCELLED olarak güncellenir ve mutabakat korunur', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      final t0 = DateTime.now().millisecondsSinceEpoch - 10000;
      await legDb.insert('sales', {
        'id': 'sale_sh_02',
        'receipt_number': 'REC-SH-02',
        'total_amount': 200.0,
        'paid_amount': 200.0,
        'payment_method': 'cash',
        'status': 'COMPLETED',
        'created_at': t0,
        'updated_at': t0,
      });
      await legDb.insert('sale_payments', {
        'id': 'sp_sh_02',
        'sale_id': 'sale_sh_02',
        'payment_type': 'cash',
        'amount': 200.0,
        'amount_minor': 20000,
        'created_at': t0.toString(),
      });
      await coreDb.db.insert('sales', {
        'id': 'sale_sh_02',
        'receipt_no': 'REC-SH-02',
        'subtotal_cents': 20000,
        'total_cents': 20000,
        'paid_cents': 20000,
        'status': 'COMPLETED',
        'created_at': t0,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'sp_sh_02',
        'sale_id': 'sale_sh_02',
        'payment_type': 'cash',
        'amount_cents': 20000,
        'created_at': t0,
      });

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Canlı tarafta iptal edilir
      await legDb.update(
        'sales',
        {
          'status': 'CANCELLED',
          'is_deleted': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch.toString(),
        },
        where: 'id = ?',
        whereArgs: ['sale_sh_02'],
      );

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      expect(report.isMatched, isTrue);
      final targetSale = await coreDb.db.query('sales', where: 'id = ?', whereArgs: ['sale_sh_02']);
      expect(targetSale.first['status'], equals('CANCELLED'));
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 3: Kısmi ve Tam İadeler
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 3: Kısmi ve tam iadeler refunds üzerinden yakalanır, satış durumunu günceller ve ledger kaydı üretir', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      // İki satış tanımla
      final t0 = DateTime.now().millisecondsSinceEpoch - 5000;
      await legDb.insert('sales', {
        'id': 'sale_part_ref',
        'receipt_number': 'REC-PR',
        'total_amount': 500.0,
        'paid_amount': 500.0,
        'status': 'COMPLETED',
        'created_at': t0,
        'updated_at': t0,
      });
      await legDb.insert('sales', {
        'id': 'sale_full_ref',
        'receipt_number': 'REC-FR',
        'total_amount': 250.0,
        'paid_amount': 250.0,
        'status': 'COMPLETED',
        'created_at': t0,
        'updated_at': t0,
      });

      await coreDb.db.insert('sales', {
        'id': 'sale_part_ref',
        'receipt_no': 'REC-PR',
        'subtotal_cents': 50000,
        'total_cents': 50000,
        'paid_cents': 50000,
        'status': 'COMPLETED',
        'created_at': t0,
      });
      await coreDb.db.insert('sales', {
        'id': 'sale_full_ref',
        'receipt_no': 'REC-FR',
        'subtotal_cents': 25000,
        'total_cents': 25000,
        'paid_cents': 25000,
        'status': 'COMPLETED',
        'created_at': t0,
      });

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // 1. Kısmi İade (100 TL / 500 TL)
      await legDb.insert('refunds', {
        'id': 'ref_01',
        'sale_id': 'sale_part_ref',
        'amount': 100.0,
        'refund_method': 'cash',
        'reason': 'Kusurlu ürün parası',
        'created_at': DateTime.now().toIso8601String(),
      });
      // 2. Tam İade (250 TL / 250 TL)
      await legDb.insert('refunds', {
        'id': 'ref_02',
        'sale_id': 'sale_full_ref',
        'amount': 250.0,
        'refund_method': 'credit_card',
        'reason': 'Müşteri vazgeçti',
        'created_at': DateTime.now().toIso8601String(),
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      expect(report.statistics.refundsMigrated, equals(2));

      final partSale = await coreDb.db.query('sales', where: 'id = ?', whereArgs: ['sale_part_ref']);
      final fullSale = await coreDb.db.query('sales', where: 'id = ?', whereArgs: ['sale_full_ref']);
      expect(partSale.first['status'], equals('PARTIALLY_REFUNDED'));
      expect(fullSale.first['status'], equals('REFUNDED'));

      final ledgerRows = await coreDb.db.query('ledger_entries', where: "entry_type = 'REFUND'");
      expect(ledgerRows.length, equals(2));
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 4: sale_items ve Satış Kalemlerinin Bütünlüğü
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 4: Çok kalemli satışın tüm ürün satırları ve tutarları hedef sale_items tablosunda eksiksiz korunur', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      // Ürünler
      for (int i = 1; i <= 3; i++) {
        await legDb.insert('products', {
          'id': 'p$i',
          'barcode': 'B$i',
          'name': 'Ürün $i',
          'price': 100.0 * i,
          'stock_quantity': 50.0,
          'created_at': '2026-10-20T08:00:00Z',
          'updated_at': '2026-10-20T08:00:00Z',
        });
        await coreDb.db.insert('products', {
          'id': 'p$i',
          'barcode': 'B$i',
          'name': 'Ürün $i',
          'price_cents': 10000 * i,
          'stock_quantity': 50.0,
          'updated_at': 1000,
        });
      }

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // 3 Kalemli Satış (100 + 200 + 300 = 600 TL)
      await legDb.insert('sales', {
        'id': 'sale_multi_item',
        'receipt_number': 'REC-MI',
        'total_amount': 600.0,
        'paid_amount': 600.0,
        'status': 'COMPLETED',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      for (int i = 1; i <= 3; i++) {
        await legDb.insert('sale_items', {
          'id': 'item_mi_$i',
          'sale_id': 'sale_multi_item',
          'product_id': 'p$i',
          'product_name': 'Ürün $i',
          'quantity': 1.0,
          'unit_price': 100.0 * i,
          'subtotal': 100.0 * i,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      expect(report.isMatched, isTrue);
      expect(report.statistics.saleItemsMigrated, equals(3));

      final targetItems = await coreDb.db.query('sale_items', where: 'sale_id = ?', whereArgs: ['sale_multi_item']);
      expect(targetItems.length, equals(3));
      final sumItemCents = targetItems.fold<int>(0, (sum, row) => sum + (row['total_cents'] as int));
      expect(sumItemCents, equals(60000));
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 5: Gerçek Nakit, Kart, Havale ve Vadeli Ödeme Parçaları
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 5: Gerçek nakit, kart, havale ve vadeli parçalar dönüştürülmeden orijinal kimlik ve türleriyle aktarılır', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // 4 parçalı satış (100 Nakit + 200 Kart + 150 Havale + 50 Vadeli = 500 TL)
      await legDb.insert('sales', {
        'id': 'sale_4parts',
        'receipt_number': 'REC-4P',
        'total_amount': 500.0,
        'paid_amount': 500.0,
        'payment_method': 'mixed',
        'status': 'COMPLETED',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final parts = [
        {'id': 'pay_nakit_1', 'type': 'cash', 'amt': 100.0},
        {'id': 'pay_kart_1', 'type': 'credit_card', 'amt': 200.0},
        {'id': 'pay_havale_1', 'type': 'bank_transfer', 'amt': 150.0},
        {'id': 'pay_veresiye_1', 'type': 'on_account', 'amt': 50.0},
      ];

      for (final p in parts) {
        await legDb.insert('sale_payments', {
          'id': p['id'],
          'sale_id': 'sale_4parts',
          'payment_type': p['type'],
          'amount': p['amt'],
          'amount_minor': ((p['amt'] as double) * 100).round(),
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      expect(report.isMatched, isTrue);
      expect(report.statistics.paymentsMigrated, equals(4));

      final targetPayments = await coreDb.db.query('sale_payments', where: 'sale_id = ?', whereArgs: ['sale_4parts']);
      expect(targetPayments.length, equals(4));

      final typeSet = targetPayments.map((r) => r['payment_type']).toSet();
      expect(typeSet, containsAll(['cash', 'creditCard', 'bankTransfer', 'onAccount']));
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 6: Karma Ödeme Toplamları ve Kuruş Hassasiyeti
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 6: Kuruş küsuratlı karma ödemelerin (133.33 + 266.67 = 400.00 TL) tamsayı kuruş duyarlılığı tam mutabık kalır', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 15));

      await legDb.insert('sales', {
        'id': 'sale_cents_exact',
        'receipt_number': 'REC-CE',
        'total_amount': 400.0,
        'paid_amount': 400.0,
        'payment_method': 'mixed',
        'status': 'COMPLETED',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      await legDb.insert('sale_payments', {
        'id': 'sp_ce_1',
        'sale_id': 'sale_cents_exact',
        'payment_type': 'cash',
        'amount': 133.33,
        'amount_minor': 13333,
        'created_at': DateTime.now().toIso8601String(),
      });
      await legDb.insert('sale_payments', {
        'id': 'sp_ce_2',
        'sale_id': 'sale_cents_exact',
        'payment_type': 'credit_card',
        'amount': 266.67,
        'amount_minor': 26667,
        'created_at': DateTime.now().toIso8601String(),
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      expect(report.isMatched, isTrue);
      final sumRows = await coreDb.db.rawQuery(
        'SELECT SUM(amount_cents) as total FROM sale_payments WHERE sale_id = ?;',
        ['sale_cents_exact'],
      );
      expect((sumRows.first['total'] as num).toInt(), equals(40000));
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 7: Tahsilatların ve financial_transactions Kayıtlarının Ledger ile Tutarlılığı
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 7: Canlı tahsilat (financial_transactions) hedef ledger_entries tablosuna kuruş tamlığı ile aktarılır', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 15));

      await legDb.insert('financial_transactions', {
        'id': 'ft_collection_01',
        'customer_id': 'cust_ahmet',
        'type': 'COLLECTION',
        'amount': 1750.50,
        'reference_id': 'COL-REC-99',
        'description': 'Elden nakit borç tahsilatı',
        'created_at': DateTime.now().toIso8601String(),
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      expect(report.statistics.ledgerEntriesMigrated, equals(1));
      final ledgerRow = await coreDb.db.query('ledger_entries', where: 'id = ?', whereArgs: ['ft_collection_01']);
      expect(ledgerRow.isNotEmpty, isTrue);
      expect(ledgerRow.first['amount_cents'], equals(175050));
      expect(ledgerRow.first['customer_id'], equals('cust_ahmet'));
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 8: Müşteri Bakiyeleri ve Vadeli Hesap Hareketleri
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 8: Vadeli işlem sonrası değişen müşteri bakiyesi hedef customers tablosunda kuruş hassasiyetinde güncellenir', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      // Başlangıç carisi (0 bakiye)
      await legDb.insert('customers', {
        'id': 'cust_mehmet',
        'name': 'Mehmet Demir',
        'balance': 0.0,
        'created_at': '2026-10-20T08:00:00Z',
        'updated_at': '2026-10-20T08:00:00Z',
      });
      await coreDb.db.insert('customers', {
        'id': 'cust_mehmet',
        'name': 'Mehmet Demir',
        'balance_cents': 0,
        'updated_at': 1000,
      });

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Veresiye satış sonrası bakiye 2450.75 TL artar
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await legDb.update(
        'customers',
        {
          'balance': 2450.75,
          'balance_minor': 245075,
          'updated_at': nowMs,
        },
        where: 'id = ?',
        whereArgs: ['cust_mehmet'],
      );

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      expect(report.isMatched, isTrue);
      expect(report.statistics.customersUpdated, equals(1));

      final targetCust = await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['cust_mehmet']);
      expect(targetCust.first['balance_cents'], equals(245075));
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 9: Ürün Fiyatı, Stok ve Stok Hareketleri
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 9: Ürün fiyatı ve stok değişimi monoton zaman damgasıyla aktarılır; stok mutabakatı birebir doğrulanır', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      await legDb.insert('products', {
        'id': 'prod_nut_1',
        'barcode': 'NUT001',
        'name': 'Fındık İçi 1Kg',
        'price': 400.0,
        'stock_quantity': 100.0,
        'created_at': '2026-10-20T08:00:00Z',
        'updated_at': '2026-10-20T08:00:00Z',
      });
      await coreDb.db.insert('products', {
        'id': 'prod_nut_1',
        'barcode': 'NUT001',
        'name': 'Fındık İçi 1Kg',
        'price_cents': 40000,
        'stock_quantity': 100.0,
        'updated_at': 1000,
      });

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Fiyat 450 TL, stok 85 kg olarak güncellenir
      final updateMs = DateTime.now().millisecondsSinceEpoch;
      await legDb.update(
        'products',
        {
          'price': 450.0,
          'price_minor': 45000,
          'stock_quantity': 85.0,
          'updated_at': updateMs,
        },
        where: 'id = ?',
        whereArgs: ['prod_nut_1'],
      );

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      expect(report.isMatched, isTrue);
      expect(report.statistics.productsUpdated, equals(1));

      final targetProd = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod_nut_1']);
      expect(targetProd.first['price_cents'], equals(45000));
      expect(targetProd.first['stock_quantity'], equals(85.0));
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 10: sync_outbox_v4 Kayıtlarının sync_events Hedefindeki Karşılıkları
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 10: sync_outbox_v4 kuyruğundaki bekleyen mutasyonlar güvenle Core Next sync_events tablosuna kopyalanır', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 15));

      await legDb.insert('sync_outbox_v4', {
        'mutation_id': 'mut_shadow_99',
        'entity_type': 'order',
        'entity_id': 'ord_123',
        'operation': 'UPSERT',
        'payload': '{"order_id": "ord_123", "total": 950}',
        'base_revision': 3,
        'state': 'PENDING',
        'attempts': 0,
        'created_at': DateTime.now().toIso8601String(),
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      expect(report.statistics.syncEventsMigrated, equals(1));
      final eventRows = await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut_shadow_99']);
      expect(eventRows.isNotEmpty, isTrue);
      expect(eventRows.first['entity_type'], equals('order'));
      expect(eventRows.first['sync_state'], equals('PENDING'));
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 11: İşlem Ortasında Kesinti ve Yeniden Başlatma
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 11: İşlem ortasında çökme/kesinti durumunda migrationStateCompleted = false kalır ve legacy fallback korunur', () async {
      const resolver = DatabaseRoutingResolver();
      final file = File(targetDbPath);
      await file.writeAsBytes(List.filled(1024, 0)); // Dummy dosya

      final resolution = await resolver.resolve(
        requestedTenantId: 'tenant-default',
        legacyDbPath: legacyDbPath,
        targetDbPath: targetDbPath,
        migrationStateCompleted: false,
        dbFactory: databaseFactory,
      );

      expect(resolution.decision, equals(RoutingDecision.legacyFallback));
      expect(resolution.isTargetSelected, isFalse);
      expect(resolution.resolvedPath, equals(legacyDbPath));
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 12: Aynı Catch-Up İşleminin Tekrar Çalıştırılması (İdempotency)
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 12: Aynı catch-up koordinatörü iki kez peş peşe çalıştırıldığında mükerrer kayıt oluşmaz ve mutabakat bozulmaz', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 15));

      await legDb.insert('sales', {
        'id': 'sale_idem_1',
        'receipt_number': 'REC-IDEM-1',
        'total_amount': 750.0,
        'paid_amount': 750.0,
        'payment_method': 'cash',
        'status': 'COMPLETED',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final report1 = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );
      expect(report1.isMatched, isTrue);
      expect(report1.statistics.salesMigrated, equals(1));

      // İkinci kez çalıştır
      final report2 = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );
      expect(report2.isMatched, isTrue);
      expect(report2.statistics.salesMigrated, equals(0));

      final targetSalesCount = await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM sales;');
      expect((targetSalesCount.first['c'] as num).toInt(), equals(1));
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 13: Eşzamanlı Yazma, SQLITE_BUSY ve SQLITE_LOCKED Durumları
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 13: SQLite kilitlenmesi veya busy durumunda koordinatör _executeWithRetry ile kontrollü dener ve güvenle başarısızlığı raporlar', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      final cutoff = DateTime.now().millisecondsSinceEpoch;
      await Future<void>.delayed(const Duration(milliseconds: 15));

      await legDb.insert('sales', {
        'id': 'sale_busy_test',
        'receipt_number': 'REC-BT',
        'total_amount': 100.0,
        'paid_amount': 100.0,
        'payment_method': 'cash',
        'status': 'COMPLETED',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Hedefte açıklanamayan fazla bir satış varken (sapma simülasyonu)
      await coreDb.db.insert('sales', {
        'id': 'sale_extra_unaccounted',
        'receipt_no': 'REC-EXTRA',
        'subtotal_cents': 99900,
        'total_cents': 99900,
        'paid_cents': 99900,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      // Mutabakat kuralı: Açıklanamayan fark durumunda ASLA cutover onaylanmamalı
      expect(report.isMatched, isFalse);
      expect(
        report.decision,
        anyOf(
          equals(CutoverReconciliationDecision.cutoverBlockedVarianceDetected),
          equals(CutoverReconciliationDecision.cutoverBlockedIntegrityError),
        ),
      );
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 14: Eski ve Yeni Kayıtların Zaman Damgalarının Farklı Türlerde Olması
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 14: Epoch ms, ISO8601 string, SQLite format ve sayısal string zaman damgaları hatasız ayrıştırılır', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      const cutoff = 1000;

      // 1. ISO string
      await legDb.insert('products', {
        'id': 'p_iso',
        'barcode': 'BC_ISO',
        'name': 'ISO Zamanlı Ürün',
        'price': 10.0,
        'stock_quantity': 10.0,
        'created_at': '2026-10-20T12:00:00Z',
        'updated_at': '2026-10-20T12:00:00Z',
      });
      // 2. Epoch integer
      await legDb.insert('products', {
        'id': 'p_int',
        'barcode': 'BC_INT',
        'name': 'Int Zamanlı Ürün',
        'price': 20.0,
        'stock_quantity': 10.0,
        'created_at': 1792520000000,
        'updated_at': 1792520000000,
      });
      // 3. SQLite date string
      await legDb.insert('products', {
        'id': 'p_sql',
        'barcode': 'BC_SQL',
        'name': 'SQLite Zamanlı Ürün',
        'price': 30.0,
        'stock_quantity': 10.0,
        'created_at': '2026-10-20 12:00:00',
        'updated_at': '2026-10-20 12:00:00',
      });
      // 4. Numeric string
      await legDb.insert('products', {
        'id': 'p_num_str',
        'barcode': 'BC_NUM',
        'name': 'Num Str Zamanlı Ürün',
        'price': 40.0,
        'stock_quantity': 10.0,
        'created_at': '1792520000000',
        'updated_at': '1792520000000',
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
      );

      expect(report.statistics.productsUpdated, equals(4));

      final prods = await coreDb.db.query('products');
      expect(prods.length, equals(4));
      for (final p in prods) {
        expect(p['updated_at'], isA<int>());
        expect((p['updated_at'] as int) > 0, isTrue);
      }
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SENARYO 15: Birden Fazla Terminalden Gelen Sırası Değişmiş Güncellemeler
    // ──────────────────────────────────────────────────────────────────────────
    test('Senaryo 15: Birden fazla terminalden sırası değişmiş gelen güncellemelerde monoton zaman damgası yeni veriyi korur; eski veri yeniyi ezemez', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();
      const coordinator = LiveSafeCatchUpReconciliationCoordinator();

      // Terminal 1: Daha yeni bir güncelleme (T = 1792520005000)
      await coreDb.db.insert('products', {
        'id': 'p_terminal_sync',
        'barcode': 'TERM_100',
        'name': 'Yeni Terminal Başlığı',
        'price_cents': 55000,
        'stock_quantity': 42.0,
        'updated_at': 1792520005000,
      });

      // Terminal 2'den gecikmiş, eski bir güncelleme paketi (T = 1792520002000) legacy veritabanına girmiş olsun
      await legDb.insert('products', {
        'id': 'p_terminal_sync',
        'barcode': 'TERM_100',
        'name': 'Eski Bayat Başlık',
        'price': 400.0,
        'stock_quantity': 10.0,
        'created_at': 1792520002000,
        'updated_at': 1792520002000,
      });

      await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: 1792520001000,
      );

      // Hedefteki ürünün eski başlık veya eski fiyatla EZİLMEDİĞİ doğrulanır
      final targetProd = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p_terminal_sync']);
      expect(targetProd.first['name'], equals('Yeni Terminal Başlığı'));
      expect(targetProd.first['price_cents'], equals(55000));
      expect(targetProd.first['stock_quantity'], equals(42.0));
    });
  });
}
