// test/core_next/stage10_12_48_shadow_observation_readiness_test.dart
// STAGE 10.12.48: Shadow Observation Güvenlik ve Hata Senaryoları Doğrulama Test Paketi
// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('STAGE 10.12.48: Değişmez Güvenlik Kuralları', () {
    test('Kural 1: coreNextSalesEngineEnabledProvider varsayılan olarak kesinlikle false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
    });

    test('Kural 2: DatabaseManager.databaseRoutingHook kesinlikle null', () {
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });
  });

  group('STAGE 10.12.48: Gölge Gözlem Güvenli Hata Senaryoları (İzole Test)', () {
    late Directory tempDir;
    late String legacyDbPath;
    late String targetDbPath;
    final openDatabases = <Database>[];
    const coordinator = LiveSafeCatchUpReconciliationCoordinator();

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('serenut_stage48_test_');
      legacyDbPath = '${tempDir.path}/legacy_pos.db';
      targetDbPath = '${tempDir.path}/serenut_core_v2.db';
      openDatabases.clear();
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

    test('Senaryo 1: Kaynak veritabanına ASLA yazılmadığı (Salt Okunurluk) kanıtlanır', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();

      await legDb.insert('products', {
        'id': 'p1',
        'barcode': 'BC1',
        'name': 'Ürün 1',
        'price': 100.0,
        'stock_quantity': 50.0,
        'created_at': '2026-10-20T10:00:00Z',
      });
      await legDb.insert('customers', {
        'id': 'c1',
        'name': 'Müşteri 1',
        'balance': 0.0,
        'created_at': '2026-10-20T10:00:00Z',
      });

      // Kaynak tablonun parmak izini al
      final beforeRows = await legDb.rawQuery('SELECT * FROM products ORDER BY id');
      final beforeHash = sha256.convert(utf8.encode(jsonEncode(beforeRows))).toString();

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: 0,
      );

      final afterRows = await legDb.rawQuery('SELECT * FROM products ORDER BY id');
      final afterHash = sha256.convert(utf8.encode(jsonEncode(afterRows))).toString();

      expect(report.isMatched, isTrue);
      expect(afterHash, equals(beforeHash), reason: 'Kaynak veritabanı içeriği 1 bit dahi değişmemelidir.');
    });

    test('Senaryo 2: Eksik ödeme parçası tespit edildiğinde cutoverBlockedIntegrityError döner', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();

      const now = '2026-10-20T12:00:00Z';
      await legDb.insert('customers', {
        'id': 'c_pay_err',
        'name': 'Müşteri Eksik Ödeme',
        'balance': 0.0,
        'created_at': now,
      });
      await legDb.insert('sales', {
        'id': 's_pay_err',
        'receipt_number': 'REC-ERR-1',
        'customer_id': 'c_pay_err',
        'total_amount': 100.0,
        'paid_amount': 100.0,
        'payment_method': 'cash',
        'status': 'COMPLETED',
        'created_at': now,
      });
      // Gerçek sale_payments tablosunda yalnızca 80 TL var (20 TL eksik parça)
      await legDb.insert('sale_payments', {
        'id': 'sp_err_1',
        'sale_id': 's_pay_err',
        'payment_type': 'cash',
        'amount': 80.0,
        'created_at': now,
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: 0,
      );

      expect(report.isMatched, isFalse);
      expect(report.decision, equals(CutoverReconciliationDecision.cutoverBlockedIntegrityError));
      expect(report.details, contains('gerçek ödeme parçaları'));
    });

    test('Senaryo 3: Bozuk hedef veritabanında PRAGMA yabancı anahtar ihlali varsa fail-closed bloklanır', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();

      const now = '2026-10-20T12:00:00Z';
      await legDb.insert('products', {
        'id': 'p_ok',
        'barcode': 'B_OK',
        'name': 'Ürün OK',
        'price': 10.0,
        'stock_quantity': 5.0,
        'created_at': now,
      });

      // Hedef DB'de FK kontrolünü geçici kapatıp yetim bir satış kalemi enjekte et
      await coreDb.db.execute('PRAGMA foreign_keys = OFF;');
      await coreDb.db.insert('sale_items', {
        'id': 'orphan_item',
        'sale_id': 'non_existent_sale',
        'product_id': 'p_ok',
        'barcode': 'B_OK',
        'product_name': 'Ürün OK',
        'unit_price_cents': 1000,
        'quantity': 1.0,
        'discount_cents': 0,
        'vat_rate': 20,
        'total_cents': 1000,
      });
      await coreDb.db.execute('PRAGMA foreign_keys = ON;');

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: 0,
      );

      expect(report.isMatched, isFalse);
      expect(report.decision, equals(CutoverReconciliationDecision.cutoverBlockedIntegrityError));
    });

    test('Senaryo 4: Kısmi iade ve karma ödeme kuruşu kuruşuna doğrulanır', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();

      const now = '2026-10-20T12:00:00Z';
      await legDb.insert('customers', {
        'id': 'c_split',
        'name': 'Müşteri Karma Ödeme',
        'balance': 0.0,
        'created_at': now,
      });
      await legDb.insert('sales', {
        'id': 's_split',
        'receipt_number': 'REC-SPLIT',
        'customer_id': 'c_split',
        'total_amount': 150.75,
        'paid_amount': 150.75,
        'payment_method': 'mixed',
        'status': 'COMPLETED',
        'created_at': now,
      });
      // 50.25 Nakit + 100.50 Kart = 150.75
      await legDb.insert('sale_payments', {
        'id': 'sp_s1',
        'sale_id': 's_split',
        'payment_type': 'cash',
        'amount': 50.25,
        'created_at': now,
      });
      await legDb.insert('sale_payments', {
        'id': 'sp_s2',
        'sale_id': 's_split',
        'payment_type': 'creditCard',
        'amount': 100.50,
        'created_at': now,
      });
      // 25.50 TL Kısmi İade
      await legDb.insert('refunds', {
        'id': 'ref_split',
        'sale_id': 's_split',
        'amount': 25.50,
        'reason': 'Kusurlu ürün',
        'refund_method': 'cash',
        'created_at': now,
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: 0,
      );

      expect(report.isMatched, isTrue);
      final coreSale = await coreDb.db.query('sales', where: 'id = ?', whereArgs: ['s_split']);
      expect(coreSale.first['status'], equals('PARTIALLY_REFUNDED'));
      expect(coreSale.first['total_cents'], equals(15075));
    });

    test('Senaryo 5: Tekrarlanan (Idempotent) catch-up veri tekrarı yapmaz', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();

      const now = '2026-10-20T12:00:00Z';
      await legDb.insert('products', {
        'id': 'p_idem',
        'barcode': 'B_IDEM',
        'name': 'Ürün İdem',
        'price': 20.0,
        'stock_quantity': 10.0,
        'created_at': now,
      });

      // 1. Çalıştırma
      await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: 0,
      );

      // 2. Çalıştırma
      final rep2 = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: 0,
      );

      // 3. Çalıştırma
      final rep3 = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: 0,
      );

      expect(rep2.isMatched, isTrue);
      expect(rep3.isMatched, isTrue);

      final pCount = (await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM products;')).first['c'];
      expect(pCount, equals(1));
    });

    test('Senaryo 6: sync_outbox_v4 kuyruğundaki bekleyen paketler hatasız aktarılır', () async {
      final legDb = await createLegacyDb();
      final coreDb = await createCoreDb();

      await legDb.insert('sync_outbox_v4', {
        'mutation_id': 'mut_1001',
        'entity_type': 'sale',
        'entity_id': 's_sync_1',
        'operation': 'CREATE',
        'payload': '{"amount": 500}',
        'base_revision': 1,
        'state': 'PENDING',
        'attempts': 0,
        'created_at': '2026-10-20T14:00:00Z',
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: 0,
      );

      expect(report.isMatched, isTrue);
      final events = await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut_1001']);
      expect(events.length, equals(1));
      expect(events.first['entity_type'], equals('sale'));
      expect(events.first['sync_state'], equals('PENDING'));
    });
  });
}
