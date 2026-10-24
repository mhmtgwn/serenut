// test/core_next/fault_injection_migration_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late CoreAppDatabase coreDb;
  late Database legacyDb;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fault_injection_test_');

    final coreDbPath = '${tempDir.path}/core.db';
    coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: coreDbPath);

    final legacyDbPath = '${tempDir.path}/legacy.db';
    legacyDb = await openDatabase(
      legacyDbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            barcode TEXT,
            name TEXT,
            price REAL,
            cost_price REAL,
            vat_rate INTEGER,
            quantity REAL,
            is_active INTEGER DEFAULT 1,
            is_deleted INTEGER DEFAULT 0
          );
        ''');

        await db.execute('''
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            name TEXT,
            phone TEXT,
            email TEXT,
            balance REAL,
            balance_minor INTEGER,
            credit_limit_minor INTEGER,
            is_active INTEGER DEFAULT 1,
            is_deleted INTEGER DEFAULT 0
          );
        ''');

        await db.execute('''
          CREATE TABLE sales (
            id TEXT PRIMARY KEY,
            receipt_no TEXT,
            customer_id TEXT,
            total_amount REAL,
            paid_amount REAL,
            status TEXT,
            created_at TEXT
          );
        ''');
      },
    );

    // 5 örnek ürün, 3 cari, 2 satış ekle
    for (int i = 1; i <= 5; i++) {
      await legacyDb.insert('products', {
        'id': 'prod-$i',
        'barcode': 'BAR-$i',
        'name': 'Ürün $i',
        'price': 10.0 * i,
        'quantity': 100,
      });
    }

    for (int i = 1; i <= 3; i++) {
      await legacyDb.insert('customers', {
        'id': 'cust-$i',
        'name': 'Müşteri $i',
        'balance': -100.0 * i,
      });
    }

    for (int i = 1; i <= 2; i++) {
      await legacyDb.insert('sales', {
        'id': 'sale-$i',
        'receipt_no': 'REC-$i',
        'customer_id': 'cust-1',
        'total_amount': 50.0 * i,
        'paid_amount': 50.0 * i,
      });
    }
  });

  tearDown(() async {
    await legacyDb.close();
    await coreDb.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Migration Fault Injection & Atomic Rollback Tests', () {
    test('Hata Enjeksiyonu: Cari aşamasında beklenmeyen sapma olursa tüm ürünler ve tablolar ROLLBACK olmalıdır', () async {
      // Beklenmeyen bakiye sapması yarat (Defter görünümünde -999 TL ama customers tablosunda -100 TL)
      await legacyDb.execute('''
        CREATE VIEW v_customer_ledger_effect AS
        SELECT 'cust-1' as customer_id, -999.00 as balance_effect;
      ''');

      final bridge = MigrationBridgeEngine(coreDb);
      expect(await bridge.isMigrationCompleted(), false);

      // Migrasyon çalıştırılır
      final report = await bridge.migrateFromLegacy(legacyDb);

      // Başarısız olmalı ve hata mesajı dönmeli
      expect(report.isSuccess, false);
      expect(report.errorMessage, contains('MÜŞTERİ BAKİYE SAPMASI TESPİT EDİLDİ'));
      expect(await bridge.isMigrationCompleted(), false);

      // ATOMIC TRANSACTION KANITI: Ürünler ilk adımda eklenmiş olmasına rağmen,
      // cari adımındaki hata yüzünden targetDb'deki products tablosu TAMAMEN BOŞ OLMALIDIR (Rollback kanıtı)
      final prodRows = await coreDb.db.query('products');
      expect(prodRows.isEmpty, true, reason: 'Rollback sonrası products tablosu temiz kalmalıdır!');

      final custRows = await coreDb.db.query('customers');
      expect(custRows.isEmpty, true, reason: 'Rollback sonrası customers tablosu temiz kalmalıdır!');

      final salesRows = await coreDb.db.query('sales');
      expect(salesRows.isEmpty, true, reason: 'Rollback sonrası sales tablosu temiz kalmalıdır!');
    });

    test('Hata Giderildikten Sonra Yeniden Başlatma (Resumption): Sistem sıfır hata ile tamamlanmalıdır', () async {
      // Hatalı defter görünümünü düzelt
      await legacyDb.execute('DROP VIEW IF EXISTS v_customer_ledger_effect;');
      await legacyDb.execute('''
        CREATE VIEW v_customer_ledger_effect AS
        SELECT 'cust-1' as customer_id, -100.00 as balance_effect
        UNION ALL
        SELECT 'cust-2' as customer_id, -200.00 as balance_effect
        UNION ALL
        SELECT 'cust-3' as customer_id, -300.00 as balance_effect;
      ''');

      final bridge = MigrationBridgeEngine(coreDb);

      // Yeniden çalıştır
      final report = await bridge.migrateFromLegacy(legacyDb);

      expect(report.isSuccess, true);
      expect(report.productsMigrated, 5);
      expect(report.customersMigrated, 3);
      expect(report.salesMigrated, 2);
      expect(await bridge.isMigrationCompleted(), true);

      // Veritabanını doğrula
      final prodRows = await coreDb.db.query('products');
      expect(prodRows.length, 5);

      final custRows = await coreDb.db.query('customers');
      expect(custRows.length, 3);

      final salesRows = await coreDb.db.query('sales');
      expect(salesRows.length, 2);

      // İdempotency: Üçüncü kez çalıştırıldığında veri bozulmamalı
      final report3 = await bridge.migrateFromLegacy(legacyDb);
      expect(report3.isSuccess, true);
      final custRowsAfter = await coreDb.db.query('customers');
      expect(custRowsAfter.length, 3);
    });
  });
}
