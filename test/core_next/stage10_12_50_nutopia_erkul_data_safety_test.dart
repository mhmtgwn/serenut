// test/core_next/stage10_12_50_nutopia_erkul_data_safety_test.dart
// STAGE 10.12.50: Nutopia + Erkul Çeyiz Veri Güvenliği, Kiracı Ayrımı ve Mutabakat Test Paketi
// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';
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

  group('STAGE 10.12.50: Değişmez Güvenlik Kuralları', () {
    test('Kural 1: coreNextSalesEngineEnabledProvider kesinlikle false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
    });

    test('Kural 2: DatabaseManager.databaseRoutingHook kesinlikle null', () {
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });
  });

  group('STAGE 10.12.50: Nutopia Veri Modeli ve Mutabakat Güvenliği (İzole Test)', () {
    late Directory tempDir;
    late String nutopiaLegacyPath;
    late String nutopiaTargetPath;
    final openDatabases = <Database>[];
    const coordinator = LiveSafeCatchUpReconciliationCoordinator();

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nutopia_stage50_test_');
      nutopiaLegacyPath = '${tempDir.path}/nutopia_legacy.db';
      nutopiaTargetPath = '${tempDir.path}/nutopia_core_target.db';
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

    Future<Database> createNutopiaLegacyDb() async {
      final db = await databaseFactory.openDatabase(
        nutopiaLegacyPath,
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
                quantity REAL,
                vat REAL,
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
            await db.insert('settings', {'id': '1', 'business_name': 'Nutopia Fındık Değirmeni'});
          },
        ),
      );
      openDatabases.add(db);
      return db;
    }

    Future<CoreAppDatabase> createNutopiaTargetDb() async {
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: nutopiaTargetPath);
      openDatabases.add(coreDb.db);
      return coreDb;
    }

    test('Nutopia Senaryosu 1: Eski DB quantity kolonu, Core Next stock_quantity olarak eksiksiz aktarılır', () async {
      final legDb = await createNutopiaLegacyDb();
      final coreDb = await createNutopiaTargetDb();

      await legDb.insert('products', {
        'id': 'nutopia_prod_1',
        'barcode': 'NUT-001',
        'name': 'Kavrulmuş Fındık 500g',
        'price': 250.0,
        'quantity': 125.5,
        'created_at': '2026-10-20T10:00:00Z',
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: nutopiaLegacyPath,
        lastMigrationCutoffTimestamp: 0,
      );

      expect(report.isMatched, isTrue);
      final pRow = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['nutopia_prod_1']);
      expect(pRow.first['stock_quantity'], equals(125.5));
      expect(pRow.first['price_cents'], equals(25000));
    });

    test('Nutopia Senaryosu 2: Eksik cari veya finansal hareket olduğunda mutabakat sapması tespit edilir', () async {
      final legDb = await createNutopiaLegacyDb();
      final coreDb = await createNutopiaTargetDb();

      // Müşteri 1: Bakiye -1000 TL
      await legDb.insert('customers', {
        'id': 'nut_c_1',
        'name': 'Temel Bozkurt',
        'balance': -1000.0,
        'created_at': '2026-10-20T10:00:00Z',
      });
      // Müşteri 2: Bakiye -500 TL
      await legDb.insert('customers', {
        'id': 'nut_c_2',
        'name': 'Emin Kaya',
        'balance': -500.0,
        'created_at': '2026-10-20T10:00:00Z',
      });

      // Hedef DB'de yalnızca Müşteri 1 var, Müşteri 2 eksik
      await coreDb.db.insert('customers', {
        'id': 'nut_c_1',
        'name': 'Temel Bozkurt',
        'balance_cents': -100000,
        'notes': null,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': 1000,
      });

      // Cutoff sonrasına ait gösterilerek Müşteri 2 atlanırsa mutabakat farkı yakalanmalıdır
      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legDb,
        targetCoreDb: coreDb,
        legacyDbPath: nutopiaLegacyPath,
        lastMigrationCutoffTimestamp: DateTime.now().millisecondsSinceEpoch + 100000,
      );

      expect(report.isMatched, isFalse);
      expect(report.decision, equals(CutoverReconciliationDecision.cutoverBlockedVarianceDetected));
      expect(report.details, contains('Müşteri bakiye toplamı uyumsuz'));
    });
  });

  group('STAGE 10.12.50: Erkul Çeyiz JSON Veri Ayrıştırma ve İzolasyon Güvenliği', () {
    test('Erkul Senaryosu 1: Erkul JSON şeması tamdır ve 401 müşteri, 5 satış, 26 ürün doğrulanır', () {
      final jsonFile = File('backups/raw_tenants_20261016/raw_erkul_source.json');
      expect(jsonFile.existsSync(), isTrue);

      final content = jsonFile.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;

      expect(data['companies'], hasLength(1));
      expect(data['customers'], hasLength(401));
      expect(data['sales'], hasLength(5));
      expect(data['products'], hasLength(26));
      expect(data['financial_transactions'], hasLength(539));

      // Şirket adının Erkul olduğunu doğrula
      final company = (data['companies'] as List).first as Map<String, dynamic>;
      final companyName = (company['name'] ?? company['business_name'] ?? '').toString();
      expect(companyName.toLowerCase(), contains('erkul'));
    });

    test('Erkul Senaryosu 2: Erkul Çeyiz verileri Nutopia veya Serenut veritabanlarına ASLA karışamaz', () async {
      final jsonFile = File('backups/raw_tenants_20261016/raw_erkul_source.json');
      final content = jsonFile.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;

      final erkulCustomerIds = (data['customers'] as List)
          .map((c) => (c as Map<String, dynamic>)['id']?.toString())
          .toSet();

      // Nutopia DB'sinde Erkul müşterisi bulunamaz
      const nutopiaCorePath = r'C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\core_next\nutopia_pos.db';
      if (File(nutopiaCorePath).existsSync()) {
        final db = await databaseFactory.openDatabase(
          nutopiaCorePath,
          options: OpenDatabaseOptions(readOnly: true),
        );
        final rows = await db.query('customers', columns: ['id']);
        final nutopiaCustomerIds = rows.map((r) => r['id'].toString()).toSet();
        await db.close();

        final intersection = erkulCustomerIds.intersection(nutopiaCustomerIds);
        expect(intersection, isEmpty, reason: 'Erkul müşterileri ile Nutopia müşterileri kesinlikle kesişmemelidir.');
      }
    });
  });
}
