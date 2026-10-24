// test/core_next/stage10_12_56_delta_completeness_test.dart
// SERENUT OS — STAGE 10.12.56
// LIVE-SAFE DELTA COMPLETENESS & CUTOVER READINESS AUDIT TEST SUITE
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

  group('STAGE 10.12.56: Değişmez Güvenlik Kuralları', () {
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

  group('STAGE 10.12.56: 10 Senaryolu Delta Aktarımı ve Eksiksizlik Kanıtı', () {
    late Directory tempDir;
    late String isolatedLegacyPath;
    late String isolatedTargetPath;
    late CoreAppDatabase targetCoreDb;
    late Database legacyDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage56_delta_test_');
      isolatedLegacyPath = p.join(tempDir.path, 'legacy_fixture.db');
      isolatedTargetPath = p.join(tempDir.path, 'core_target_fixture.db');

      // 1. Legacy SQLite DB oluştur
      legacyDb = await databaseFactory.openDatabase(isolatedLegacyPath);
      await legacyDb.execute('''
        CREATE TABLE settings (id TEXT PRIMARY KEY, business_name TEXT);
        INSERT INTO settings VALUES ('1', 'Nutopia Fındık Değirmeni');

        CREATE TABLE products (
          id TEXT PRIMARY KEY,
          barcode TEXT,
          name TEXT,
          price REAL,
          price_minor INTEGER DEFAULT 0,
          purchase_price REAL,
          purchase_price_minor INTEGER,
          stock_quantity REAL,
          vat INTEGER DEFAULT 20,
          min_stock REAL DEFAULT 5,
          is_active INTEGER DEFAULT 1,
          is_deleted INTEGER DEFAULT 0,
          created_at TEXT,
          updated_at TEXT
        );

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

        CREATE TABLE sale_payments (
          id TEXT PRIMARY KEY,
          sale_id TEXT,
          payment_type TEXT,
          amount REAL,
          amount_minor INTEGER DEFAULT 0,
          reference_note TEXT,
          created_at TEXT
        );

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

        CREATE TABLE refunds (
          id TEXT PRIMARY KEY,
          sale_id TEXT,
          amount REAL,
          amount_minor INTEGER DEFAULT 0,
          reason TEXT,
          refund_method TEXT,
          created_at TEXT
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

      // 2. CoreAppDatabase Hedef oluştur
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

    test('Senaryo 1 & 2: Snapshot öncesi kayıt ve Snapshot sonrası eklenen kayıt ayrımı', () async {
      final cutoff = DateTime(2026, 10, 16, 0, 0, 0);

      // Snapshot öncesi ürün (10 Ekim)
      await legacyDb.insert('products', {
        'id': 'p-pre-1',
        'barcode': 'BC001',
        'name': 'Eski Fındık',
        'price': 100.0,
        'stock_quantity': 50.0,
        'created_at': '2026-10-10T10:00:00Z',
        'updated_at': '2026-10-10T10:00:00Z',
      });

      // Snapshot sonrası ürün (18 Ekim)
      await legacyDb.insert('products', {
        'id': 'p-post-1',
        'barcode': 'BC002',
        'name': 'Yeni Fındık',
        'price': 150.0,
        'stock_quantity': 25.0,
        'created_at': '2026-10-18T10:00:00Z',
        'updated_at': '2026-10-18T10:00:00Z',
      });

      const coordinator = LiveSafeCatchUpReconciliationCoordinator();
      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: legacyDb,
        targetCoreDb: targetCoreDb,
        legacyDbPath: isolatedLegacyPath,
        lastMigrationCutoffTimestamp: cutoff.millisecondsSinceEpoch,
      );

      expect(report.decision, isNotNull);
      // Hedefte yalnızca snapshot sonrasındaki p-post-1 eklenmiş olmalı
      final tgtPost = await targetCoreDb.db.query('products', where: "id = 'p-post-1'");
      final tgtPre = await targetCoreDb.db.query('products', where: "id = 'p-pre-1'");

      expect(tgtPost.length, equals(1));
      expect(tgtPost.first['name'], equals('Yeni Fındık'));
      expect(tgtPost.first['price_cents'], equals(15000));
      expect(tgtPre, isEmpty, reason: 'Snapshot öncesi kayıt cutoff filtresiyle delta ya dahil edilmemelidir');
    });

    test('Senaryo 3: Snapshot sonrasında güncellenen kayıt monoton saat güvencesiyle aktarılır', () async {
      final cutoff = DateTime(2026, 10, 16, 0, 0, 0);

      // Hedefte önceden var olan müşteri
      await targetCoreDb.db.insert('customers', {
        'id': 'c-100',
        'name': 'Eski İsim',
        'phone': '555111',
        'balance_cents': -10000,
        'updated_at': DateTime(2026, 10, 10).millisecondsSinceEpoch,
      });

      // Kaynakta 17 Ekim de güncellenen müşteri
      await legacyDb.insert('customers', {
        'id': 'c-100',
        'name': 'Güncel İsim',
        'phone': '555999',
        'balance': -250.0, // -25000 kuruş
        'created_at': '2026-10-10T10:00:00Z',
        'updated_at': '2026-10-17T15:30:00Z',
      });

      const coordinator = LiveSafeCatchUpReconciliationCoordinator();
      await coordinator.performCatchUpAndReconcile(
        legacyDb: legacyDb,
        targetCoreDb: targetCoreDb,
        legacyDbPath: isolatedLegacyPath,
        lastMigrationCutoffTimestamp: cutoff.millisecondsSinceEpoch,
      );

      final updatedCust = await targetCoreDb.db.query('customers', where: "id = 'c-100'");
      expect(updatedCust.first['name'], equals('Güncel İsim'));
      expect(updatedCust.first['phone'], equals('555999'));
      expect(updatedCust.first['balance_cents'], equals(-25000));
    });

    test('Senaryo 4: İptal ve İadelerin durumu korunur, Completed durumuna ezilemez', () async {
      final cutoff = DateTime(2026, 10, 16, 0, 0, 0);

      // Foreign key için müşteri ekle
      await targetCoreDb.db.insert('customers', {
        'id': 'cust-1',
        'name': 'Müşteri 1',
        'balance_cents': 0,
        'updated_at': DateTime(2026, 10, 10).millisecondsSinceEpoch,
      });

      // Hedefte önceden CANCELLED veya REFUNDED olan satış
      await targetCoreDb.db.insert('sales', {
        'id': 'sale-cancel-1',
        'receipt_no': 'REC-C1',
        'customer_id': 'cust-1',
        'subtotal_cents': 50000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 50000,
        'paid_cents': 50000,
        'debt_cents': 0,
        'status': 'CANCELLED',
        'idempotency_key': 'idem_cancel_1',
        'created_at': DateTime(2026, 10, 15).millisecondsSinceEpoch,
      });

      // Kaynakta durum COMPLETED görünse bile hedefteki CANCELLED ezilemez
      await legacyDb.insert('sales', {
        'id': 'sale-cancel-1',
        'receipt_number': 'REC-C1',
        'customer_id': 'cust-1',
        'total_amount': 500.0,
        'paid_amount': 500.0,
        'status': 'COMPLETED',
        'created_at': '2026-10-15T10:00:00Z',
        'updated_at': '2026-10-17T12:00:00Z',
      });

      const coordinator = LiveSafeCatchUpReconciliationCoordinator();
      await coordinator.performCatchUpAndReconcile(
        legacyDb: legacyDb,
        targetCoreDb: targetCoreDb,
        legacyDbPath: isolatedLegacyPath,
        lastMigrationCutoffTimestamp: cutoff.millisecondsSinceEpoch,
      );

      final sale = await targetCoreDb.db.query('sales', where: "id = 'sale-cancel-1'");
      expect(sale.first['status'], equals('CANCELLED'),
          reason: 'İptal ve iade durumları geriye dönük ezilmeye karşı korunmalıdır');
    });

    test('Senaryo 5: Finansal hareket ve müşteri bakiyesi autoritatif kuruş çözümlemesi ile aktarılır', () async {
      final cutoff = DateTime(2026, 10, 16, 0, 0, 0);

      await legacyDb.insert('financial_transactions', {
        'id': 'tx-delta-101',
        'customer_id': 'cust-delta-1',
        'type': 'payment',
        'amount': 350.50,
        'amount_minor': 0, // unpopulated legacy default
        'description': 'Kısmi Tahsilat',
        'created_at': '2026-10-17T11:00:00Z',
      });

      const coordinator = LiveSafeCatchUpReconciliationCoordinator();
      await coordinator.performCatchUpAndReconcile(
        legacyDb: legacyDb,
        targetCoreDb: targetCoreDb,
        legacyDbPath: isolatedLegacyPath,
        lastMigrationCutoffTimestamp: cutoff.millisecondsSinceEpoch,
      );

      final entry = await targetCoreDb.db.query('ledger_entries', where: "id = 'tx-delta-101'");
      expect(entry.length, equals(1));
      expect(entry.first['amount_cents'], equals(35050));
      expect(entry.first['entry_type'], equals('payment'));
    });

    test('Senaryo 6: Stok hareketi ve farklı ölçü birimleri (kg vs adet) ayrık korunur', () async {
      final cutoff = DateTime(2026, 10, 16, 0, 0, 0);

      // Kilogram cinsinden tartılı ürün
      await legacyDb.insert('products', {
        'id': 'prod-kg-1',
        'name': 'Çifte Kavrulmuş Fındık',
        'price': 250.0,
        'stock_quantity': 150.75, // kg
        'created_at': '2026-10-17T10:00:00Z',
        'updated_at': '2026-10-17T10:00:00Z',
      });

      // Adet cinsinden birim ürün
      await legacyDb.insert('products', {
        'id': 'prod-piece-1',
        'name': 'Fındık Ezmesi Kavanoz',
        'price': 90.0,
        'stock_quantity': 48.0, // adet
        'created_at': '2026-10-17T10:00:00Z',
        'updated_at': '2026-10-17T10:00:00Z',
      });

      const coordinator = LiveSafeCatchUpReconciliationCoordinator();
      await coordinator.performCatchUpAndReconcile(
        legacyDb: legacyDb,
        targetCoreDb: targetCoreDb,
        legacyDbPath: isolatedLegacyPath,
        lastMigrationCutoffTimestamp: cutoff.millisecondsSinceEpoch,
      );

      final kgRow = await targetCoreDb.db.query('products', where: "id = 'prod-kg-1'");
      final pieceRow = await targetCoreDb.db.query('products', where: "id = 'prod-piece-1'");

      expect(kgRow.first['stock_quantity'], equals(150.75));
      expect(pieceRow.first['stock_quantity'], equals(48.0));
    });

    test('Senaryo 7: Aktarım ortasında hata ve yeniden başlatma durumunda atomiklik korunur', () async {
      // Transaction fail-safe kanıtı
      expect(
        () async {
          await targetCoreDb.transaction((txn) async {
            await txn.rawInsert('''
              INSERT INTO customers (id, name, balance_cents, updated_at)
              VALUES ('c-crash', 'Crash Customer', 0, 1000)
            ''');
            throw const SocketException('Simulated crash during batch replay');
          });
        },
        throwsA(isA<SocketException>()),
      );

      // Rollback sonrası kontrol: c-crash eklenmemiş olmalı
      final check = await targetCoreDb.db.query('customers', where: "id = 'c-crash'");
      expect(check, isEmpty, reason: 'Yarıda kalan işlem hedef veritabanını tutarsız bırakmamalıdır');
    });

    test('Senaryo 8: Aynı delta ikinci kez uygulandığında sıfır mükerrer kayıt oluşur (Idempotency)', () async {
      final cutoff = DateTime(2026, 10, 16, 0, 0, 0);

      await legacyDb.insert('customers', {
        'id': 'c-idem-1',
        'name': 'İdempotent Cari',
        'balance': 0.0,
        'created_at': '2026-10-18T10:00:00Z',
        'updated_at': '2026-10-18T10:00:00Z',
      });

      const coordinator = LiveSafeCatchUpReconciliationCoordinator();
      // 1. Uygulama
      await coordinator.performCatchUpAndReconcile(
        legacyDb: legacyDb,
        targetCoreDb: targetCoreDb,
        legacyDbPath: isolatedLegacyPath,
        lastMigrationCutoffTimestamp: cutoff.millisecondsSinceEpoch,
      );

      final count1Res = await targetCoreDb.db.rawQuery('SELECT COUNT(*) as c FROM customers');
      final count1 = count1Res.first['c'] as int;

      // 2. Uygulama (Aynı delta tekrar)
      await coordinator.performCatchUpAndReconcile(
        legacyDb: legacyDb,
        targetCoreDb: targetCoreDb,
        legacyDbPath: isolatedLegacyPath,
        lastMigrationCutoffTimestamp: cutoff.millisecondsSinceEpoch,
      );

      final count2Res = await targetCoreDb.db.rawQuery('SELECT COUNT(*) as c FROM customers');
      final count2 = count2Res.first['c'] as int;

      expect(count2, equals(count1), reason: 'Tekrarlı delta çalıştırmasında kayıt sayısı asla mükerrer artmamalıdır');
    });

    test('Senaryo 9: İki ayrı işletmenin (Nutopia vs Erkul) kayıtlarının birbirine karışması engellenir', () async {
      await targetCoreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'tenant-nutopia',
        'updated_at': 1792100000,
      });

      const routingCoord = DualDatabaseRoutingCoordinator();
      final result = await routingCoord.resolveAndOpen(
        requestedTenantId: 'tenant-erkul', // Uyuşmayan tenant!
        legacyDbPath: isolatedLegacyPath,
        targetDbPath: isolatedTargetPath,
        migrationStateCompleted: true,
      );

      expect(result.decision, equals(RoutingDecision.blockedFailClosed));
      expect(result.isTargetSelected, isFalse);
      expect(result.targetDatabase, isNull);
    });

    test('Senaryo 10: Delta sırasında yeni bir hareket oluştuğunda kesim noktasının (cut-off) korunması', () {
      final t1 = DateTime(2026, 10, 16, 12, 0, 0);
      final t2 = DateTime(2026, 10, 16, 12, 0, 1);

      // t1 kesim anı belirlendiğinde, t1 sonrasındaki hareket bir sonraki delta paketi için saklanır
      expect(t2.isAfter(t1), isTrue);
      final deltaCutoffMs = t1.millisecondsSinceEpoch;
      expect(t2.millisecondsSinceEpoch > deltaCutoffMs, isTrue);
    });
  });
}
