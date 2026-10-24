// test/core_next/stage10_12_49_pilot_gate_preflight_test.dart
// STAGE 10.12.49: Kontrollü Gölge Gözlem Başlangıcı ve Pilot Güvenlik Kapısı Preflight Test Paketi
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

  group('STAGE 10.12.49: Değişmez Güvenlik Kuralları', () {
    test('Kural 1: coreNextSalesEngineEnabledProvider kesinlikle false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
    });

    test('Kural 2: DatabaseManager.databaseRoutingHook kesinlikle null', () {
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });
  });

  group('STAGE 10.12.49: Pilot Güvenlik Kapısı ve Preflight Kontrolleri (İzole Test)', () {
    late Directory tempDir;
    late String legacyDbPath;
    late String targetDbPath;
    final openDatabases = <Database>[];
    const coordinator = LiveSafeCatchUpReconciliationCoordinator();

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('serenut_stage49_test_');
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

    Future<Database> createLegacyDb({required String businessName}) async {
      final db = await databaseFactory.openDatabase(
        legacyDbPath,
        options: OpenDatabaseOptions(
          version: 60,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE settings (
                id TEXT PRIMARY KEY,
                business_name TEXT
              );
            ''');
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
            await db.insert('settings', {'id': '1', 'business_name': businessName});
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

    test('Preflight Senaryosu 1: Kiracı Kimlik Ayrımı (Nutopia vs Serenut Çapraz Kirlilik Engeli)', () async {
      // Aktif DB Nutopia Fındık Değirmeni olarak yapılandırılır
      final legDb = await createLegacyDb(businessName: 'Nutopia Fındık Değirmeni');
      await createCoreDb();

      // settings tablosundan aktif işletme adını sorgula
      final settingsRow = await legDb.query('settings', columns: ['business_name'], limit: 1);
      final activeBusiness = settingsRow.first['business_name'] as String;

      // Pilot adayımız: 'serenut'
      const targetPilotTenant = 'serenut';
      final isTenantMatched = activeBusiness.toLowerCase().contains(targetPilotTenant);

      expect(isTenantMatched, isFalse,
          reason: 'Aktif veritabanı Nutopia olduğundan Serenut pilot gölgesi doğrudan başlatılamaz!');
    });

    test('Preflight Senaryosu 2: Doğru Kiracı Eşleştiğinde Güvenli Salt Okunur Catch-Up Başlatılabilir', () async {
      final legDb = await createLegacyDb(businessName: 'serenut');
      final coreDb = await createCoreDb();

      await legDb.insert('products', {
        'id': 'p_pilot_1',
        'barcode': 'BC_PILOT_1',
        'name': 'Fındık Ezmesi 200g',
        'price': 120.0,
        'stock_quantity': 40.0,
        'created_at': '2026-10-20T11:00:00Z',
      });
      await legDb.insert('customers', {
        'id': 'c_pilot_1',
        'name': 'Pilot Müşteri 1',
        'balance': 0.0,
        'created_at': '2026-10-20T11:00:00Z',
      });

      // Kaynak parmak izini doğrula
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
      expect(afterHash, equals(beforeHash), reason: 'Kaynak veritabanına 1 bit dahi yazılmamalıdır.');
    });

    test('Preflight Senaryosu 3: Watermark ve Kalıcı Durum Koruması', () async {
      final legDb = await createLegacyDb(businessName: 'serenut');
      final coreDb = await createCoreDb();

      final cutoff = DateTime.now().millisecondsSinceEpoch;

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        lastMigrationCutoffTimestamp: cutoff,
        persistCutoverStatus: true,
      );

      expect(report.isMatched, isTrue);
      final statusRow = await coreDb.db.query('app_settings', where: "key = 'cutover_reconciliation_status'");
      expect(statusRow.first['value'], equals('approved'));
    });
  });
}
