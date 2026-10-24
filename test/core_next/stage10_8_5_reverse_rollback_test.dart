// ignore_for_file: avoid_relative_lib_imports
// test/core_next/stage10_8_5_reverse_rollback_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String legacyDbPath;
  late String coreDbPath;
  late CoreAppDatabase coreDb;
  late Database legacyDb;
  late MigrationBridgeEngine bridgeEngine;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stage10_8_5_rollback_');
    legacyDbPath = '${tempDir.path}${Platform.pathSeparator}serenut_pos_stage1085.db';
    coreDbPath = '${tempDir.path}${Platform.pathSeparator}serenut_core_v2_stage1085.db';

    // 1. Hedef Core Next veritabanını oluştur (v3)
    coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: coreDbPath);
    bridgeEngine = MigrationBridgeEngine(coreDb);

    // 2. Kaynak Legacy veritabanını oluştur (Tam Şema v60 simülasyonu)
    legacyDb = await openDatabase(
      legacyDbPath,
      version: 60,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id TEXT PRIMARY KEY,
            username TEXT,
            name TEXT NOT NULL,
            email TEXT,
            password_hash TEXT,
            pin_hash TEXT,
            role TEXT NOT NULL DEFAULT 'cashier',
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            color_hex TEXT,
            sort_order INTEGER DEFAULT 0,
            is_active INTEGER DEFAULT 1
          );
        ''');

        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            barcode TEXT,
            sku TEXT,
            name TEXT NOT NULL,
            category TEXT,
            category_id TEXT,
            price REAL NOT NULL,
            price_minor INTEGER,
            purchase_price REAL,
            purchase_price_minor INTEGER,
            cost_price REAL,
            vat INTEGER DEFAULT 20,
            quantity REAL NOT NULL DEFAULT 0,
            min_stock INTEGER DEFAULT 5,
            sale_type TEXT DEFAULT 'piece',
            unit TEXT DEFAULT 'adet',
            image_url TEXT,
            is_active INTEGER DEFAULT 1,
            is_deleted INTEGER DEFAULT 0,
            updated_at TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT,
            email TEXT,
            tax_number TEXT,
            tax_office TEXT,
            balance REAL NOT NULL DEFAULT 0,
            balance_minor INTEGER,
            credit_limit REAL,
            credit_limit_minor INTEGER,
            notes TEXT,
            is_active INTEGER DEFAULT 1,
            is_deleted INTEGER DEFAULT 0,
            updated_at TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE sales (
            id TEXT PRIMARY KEY,
            receipt_no TEXT,
            customer_id TEXT NOT NULL,
            total_amount REAL NOT NULL,
            total_amount_minor INTEGER,
            paid_amount REAL NOT NULL DEFAULT 0,
            paid_amount_minor INTEGER,
            discount_amount REAL DEFAULT 0,
            discount_amount_minor INTEGER,
            payment_method TEXT,
            status TEXT DEFAULT 'completed',
            idempotency_key TEXT UNIQUE,
            created_at TEXT NOT NULL,
            updated_at TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE sale_items (
            id TEXT PRIMARY KEY,
            sale_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            product_name TEXT,
            barcode TEXT,
            quantity REAL NOT NULL,
            unit_price REAL NOT NULL,
            unit_price_minor INTEGER,
            subtotal REAL NOT NULL,
            subtotal_minor INTEGER,
            created_at TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE financial_transactions (
            id TEXT PRIMARY KEY,
            customer_id TEXT NOT NULL,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            amount_minor INTEGER,
            paid_amount REAL DEFAULT 0,
            debt_amount REAL DEFAULT 0,
            description TEXT,
            created_at TEXT NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE sync_outbox_v4 (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mutation_id TEXT NOT NULL UNIQUE,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            operation TEXT NOT NULL,
            payload TEXT NOT NULL,
            base_revision INTEGER DEFAULT 0,
            state TEXT NOT NULL DEFAULT 'PENDING',
            attempts INTEGER DEFAULT 0,
            created_at TEXT NOT NULL
          );
        ''');

        await db.execute('''
          CREATE VIEW v_customer_ledger_effect AS
          SELECT id as customer_id, balance as balance_effect
          FROM customers;
        ''');
      },
    );
  });

  tearDown(() async {
    await legacyDb.close();
    await coreDb.close();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Stage 10.8.5 — Migration Completeness & Reverse-Rollback Proof', () {
    test('1. Tam Kapsam Geçişi: Kullanıcılar, Kategoriler, Ürünler, Satış Kalemleri, Defter ve Outbox Kayıpsız Taşınır', () async {
      // 1. Kullanıcı Ekle
      await legacyDb.insert('users', {
        'id': 'usr-admin-1',
        'username': 'yonetici',
        'name': 'Ahmet Yılmaz',
        'email': 'ahmet@serenut.com',
        'pin_hash': 'pin_hash_1234',
        'role': 'admin',
        'is_active': 1,
        'created_at': '2026-10-14T08:00:00Z',
      });

      // 2. Kategori Ekle
      await legacyDb.insert('categories', {
        'id': 'cat-sut',
        'name': 'Süt & Kahvaltılık',
        'color_hex': '#3498DB',
        'sort_order': 1,
      });

      // 3. Ürün Ekle
      await legacyDb.insert('products', {
        'id': 'prod-tam-sut',
        'barcode': '8690001001',
        'sku': 'SKU-SUT-1',
        'name': 'Serenut Doğal Tam Yağlı Süt 1L',
        'category_id': 'cat-sut',
        'category': 'Süt & Kahvaltılık',
        'price': 32.50,
        'price_minor': 3250,
        'purchase_price': 22.00,
        'purchase_price_minor': 2200,
        'quantity': 150,
        'min_stock': 10,
        'unit': 'adet',
      });

      // 4. Müşteri Ekle
      await legacyDb.insert('customers', {
        'id': 'cust-market-1',
        'name': 'Kardeşler Süpermarket Ltd.',
        'phone': '05339998877',
        'email': 'kardesler@market.com',
        'balance': -1250.75, // 1.250,75 TL borç
        'balance_minor': -125075,
        'credit_limit': 10000.0,
      });

      // 5. Satış ve Satış Kalemi Ekle
      await legacyDb.insert('sales', {
        'id': 'sale-legacy-100',
        'receipt_no': 'REC-100',
        'customer_id': 'cust-market-1',
        'total_amount': 65.00,
        'total_amount_minor': 6500,
        'paid_amount': 30.00,
        'paid_amount_minor': 3000,
        'discount_amount': 5.00,
        'discount_amount_minor': 500,
        'payment_method': 'cash',
        'idempotency_key': 'idemp-leg-100',
        'created_at': '2026-10-14T09:30:00Z',
      });

      await legacyDb.insert('sale_items', {
        'id': 'item-100-1',
        'sale_id': 'sale-legacy-100',
        'product_id': 'prod-tam-sut',
        'product_name': 'Serenut Doğal Tam Yağlı Süt 1L',
        'barcode': '8690001001',
        'quantity': 2.0,
        'unit_price': 35.00,
        'unit_price_minor': 3500,
        'subtotal': 70.00,
        'subtotal_minor': 7000,
        'created_at': '2026-10-14T09:30:00Z',
      });

      // 6. Finansal Hareket Ekle
      await legacyDb.insert('financial_transactions', {
        'id': 'ft-leg-1',
        'customer_id': 'cust-market-1',
        'type': 'SALE',
        'amount': 35.00,
        'amount_minor': 3500,
        'debt_amount': 35.00,
        'description': 'Vadeli Satış Kalanı',
        'created_at': '2026-10-14T09:30:00Z',
      });

      // 7. Bekleyen Offline Outbox Olayı Ekle
      await legacyDb.insert('sync_outbox_v4', {
        'mutation_id': 'mut-offline-999',
        'entity_type': 'sale',
        'entity_id': 'sale-legacy-100',
        'operation': 'CREATE',
        'payload': '{"sale_id": "sale-legacy-100", "offline": true}',
        'base_revision': 1,
        'state': 'PENDING',
        'attempts': 0,
        'created_at': '2026-10-14T09:30:00Z',
      });

      // Tam Kapsam Geçişini Çalıştır
      final report = await bridgeEngine.migrateFromLegacy(
        legacyDb,
        legacyFilePath: legacyDbPath,
        fullScope: true,
      );

      expect(report.isSuccess, true, reason: report.errorMessage);
      expect(report.usersMigrated, 1);
      expect(report.categoriesMigrated, 1);
      expect(report.productsMigrated, 1);
      expect(report.customersMigrated, 1);
      expect(report.salesMigrated, 1);
      expect(report.saleItemsMigrated, 1);
      expect(report.ledgerEntriesMigrated, 1);
      expect(report.syncEventsMigrated, 1);

      // Hedef Core Next Tablolarını Doğrula
      final u = (await coreDb.db.query('users', where: 'id = ?', whereArgs: ['usr-admin-1'])).first;
      expect(u['username'], 'yonetici');
      expect(u['role'], 'admin');

      final cat = (await coreDb.db.query('categories', where: 'id = ?', whereArgs: ['cat-sut'])).first;
      expect(cat['name'], 'Süt & Kahvaltılık');

      final p = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-tam-sut'])).first;
      expect(p['category_id'], 'cat-sut');
      expect(p['price_cents'], 3250);

      final it = (await coreDb.db.query('sale_items', where: 'id = ?', whereArgs: ['item-100-1'])).first;
      expect(it['sale_id'], 'sale-legacy-100');
      expect(it['barcode'], '8690001001');
      expect(it['total_cents'], 7000);

      final le = (await coreDb.db.query('ledger_entries', where: 'id = ?', whereArgs: ['ft-leg-1'])).first;
      expect(le['customer_id'], 'cust-market-1');
      expect(le['amount_cents'], 3500);

      final se = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut-offline-999'])).first;
      expect(se['sync_state'], 'PENDING');
      expect(se['entity_type'], 'sale');
    });

    test('2. İdempotency ve Tekrarlanabilirlik: İkinci kez çalıştırma mükerrer veri üretmez', () async {
      await legacyDb.insert('users', {
        'id': 'usr-1',
        'username': 'kasiyer1',
        'name': 'Mehmet Demir',
        'role': 'cashier',
        'created_at': '2026-10-14T08:00:00Z',
      });
      await legacyDb.insert('products', {
        'id': 'p-idem-1',
        'barcode': '111222',
        'name': 'Çikolata 50g',
        'price': 10.00,
        'quantity': 20,
      });
      await legacyDb.insert('customers', {
        'id': 'c-idem-1',
        'name': 'Ali Can',
        'balance': 0.0,
      });

      // İlk çalıştırma
      final rep1 = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep1.isSuccess, true);

      // İkinci çalıştırma
      final rep2 = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep2.isSuccess, true);

      // Sayıları doğrula
      final pCount = Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM products'));
      final cCount = Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM customers'));
      final uCount = Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM users'));

      expect(pCount, 1);
      expect(cCount, 1);
      expect(uCount, 1);
    });

    test('3. REVERSE-ROLLBACK PROVASI: Cutover sonrası Core Next üzerinde yapılan yeni işlemler Legacy sistemine kayıpsız geri aktarılır', () async {
      // 1. Başlangıçta Legacy'ye temel katalog ve müşteri yerleştir
      await legacyDb.insert('products', {
        'id': 'prod-un',
        'barcode': '8690555',
        'name': 'Hekimoğlu Un 5kg',
        'price': 95.00,
        'price_minor': 9500,
        'quantity': 100, // 100 adet stok
      });
      await legacyDb.insert('customers', {
        'id': 'cust-firin-1',
        'name': 'Bereket Ekmek Fırını',
        'balance': -500.0, // 500,00 TL borç
        'balance_minor': -50000,
      });

      // 2. Core Next'e ilk migrasyonu yap (Cutover anı)
      final initMig = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(initMig.isSuccess, true);

      // 3. CANLI GEÇİŞ SONRASI CORE NEXT'TE İŞLEMLER YAPILIYOR:
      // A. Yeni Satış (Core Next v3 üzerinde)
      await coreDb.db.insert('sales', {
        'id': 'sale-v2-cutover-1',
        'receipt_no': 'REC-V2-001',
        'customer_id': 'cust-firin-1',
        'subtotal_cents': 19000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 19000, // 190,00 TL
        'paid_cents': 9000,   // 90,00 TL peşin
        'debt_cents': 10000,  // 100,00 TL veresiye
        'status': 'COMPLETED',
        'idempotency_key': 'idemp-v2-cutover-1',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Satış Kalemi: 2 adet un satıldı
      await coreDb.db.insert('sale_items', {
        'id': 'item-v2-1',
        'sale_id': 'sale-v2-cutover-1',
        'product_id': 'prod-un',
        'barcode': '8690555',
        'product_name': 'Hekimoğlu Un 5kg',
        'unit_price_cents': 9500,
        'quantity': 2,
        'discount_cents': 0,
        'vat_rate': 1,
        'total_cents': 19000,
      });

      // Ödeme Dağılımı: 90 TL Nakit, 100 TL Veresiye
      await coreDb.db.insert('sale_payments', {
        'id': 'pay-v2-1',
        'sale_id': 'sale-v2-cutover-1',
        'payment_type': 'cash',
        'amount_cents': 9000,
        'reference_note': 'Peşin Ödeme',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'pay-v2-2',
        'sale_id': 'sale-v2-cutover-1',
        'payment_type': 'onAccount',
        'amount_cents': 10000,
        'reference_note': 'Kalan Borç',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // B. Stok Düşümü: 100 adetten 2 adet satıldı -> 98 adet kaldı
      await coreDb.db.update(
        'products',
        {'stock_quantity': 98},
        where: 'id = ?',
        whereArgs: ['prod-un'],
      );

      // C. Cari Borç Artışı: -500,00 TL borç vardı, 100,00 TL daha eklendi -> -600,00 TL (-60000 kuruş)
      await coreDb.db.update(
        'customers',
        {'balance_cents': -60000},
        where: 'id = ?',
        whereArgs: ['cust-firin-1'],
      );

      // D. Cari Defter Kaydı (ledger_entries)
      await coreDb.db.insert('ledger_entries', {
        'id': 'le-v2-cutover-1',
        'customer_id': 'cust-firin-1',
        'reference_sale_id': 'sale-v2-cutover-1',
        'entry_type': 'SALE',
        'amount_cents': 10000,
        'balance_after_cents': -60000,
        'description': 'Yeni Sistem Vadeli Satış',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // E. Bekleyen Senkronizasyon Kuyruğuna Yeni Olay
      await coreDb.db.insert('sync_events', {
        'event_id': 'sync-v2-event-1',
        'entity_type': 'sale',
        'entity_id': 'sale-v2-cutover-1',
        'operation': 'UPSERT',
        'payload_json': '{"sale_id": "sale-v2-cutover-1", "synced": false}',
        'base_revision': 2,
        'client_timestamp': DateTime.now().millisecondsSinceEpoch,
        'sync_state': 'PENDING',
        'attempts': 0,
        'causal_sequence': 10,
      });

      // 4. GERİ DÖNÜŞ (REVERSE-ROLLBACK) ÇALIŞTIRILIYOR
      final rollbackReport = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreDb,
      );

      expect(rollbackReport.isSuccess, true, reason: rollbackReport.errorMessage);
      expect(rollbackReport.salesExported, 1);
      expect(rollbackReport.saleItemsExported, 1);
      expect(rollbackReport.productsUpdated, 1);
      expect(rollbackReport.customersUpdated, 1);
      expect(rollbackReport.ledgerEntriesExported, 1);
      expect(rollbackReport.syncEventsExported, 1);

      // 5. ADLİ MUTABAKAT: Legacy Veritabanındaki Değerlerin Eksiksizliğini Doğrula
      // A. Yeni Satış Legacy'de Var mı?
      final legSale = (await legacyDb.query('sales', where: 'id = ?', whereArgs: ['sale-v2-cutover-1'])).first;
      expect(legSale['receipt_no'], 'REC-V2-001');
      expect((legSale['total_amount'] as num).toDouble(), 190.00);
      expect((legSale['total_amount_minor'] as num).toInt(), 19000);
      expect((legSale['paid_amount'] as num).toDouble(), 90.00);
      expect((legSale['paid_amount_minor'] as num).toInt(), 9000);

      // B. Satış Kalemi Legacy'de Var mı?
      final legItem = (await legacyDb.query('sale_items', where: 'id = ?', whereArgs: ['item-v2-1'])).first;
      expect(legItem['sale_id'], 'sale-v2-cutover-1');
      expect(legItem['product_id'], 'prod-un');
      expect((legItem['quantity'] as num).toDouble(), 2.0);
      expect((legItem['unit_price'] as num).toDouble(), 95.00);
      expect((legItem['subtotal'] as num).toDouble(), 190.00);

      // C. Stok Miktarı Legacy'de 98 Oldu mu?
      final legProd = (await legacyDb.query('products', where: 'id = ?', whereArgs: ['prod-un'])).first;
      expect((legProd['quantity'] as num).toDouble(), 98.0);

      // D. Müşteri Bakiyesi Legacy'de -600.00 TL Oldu mu?
      final legCust = (await legacyDb.query('customers', where: 'id = ?', whereArgs: ['cust-firin-1'])).first;
      expect((legCust['balance'] as num).toDouble(), -600.00);

      // E. Finansal Hareket Defteri Legacy'ye Eklendi mi?
      final legFt = (await legacyDb.query('financial_transactions', where: 'id = ?', whereArgs: ['le-v2-cutover-1'])).first;
      expect(legFt['customer_id'], 'cust-firin-1');
      expect((legFt['amount'] as num).toDouble(), 100.00);

      // F. Bekleyen Sync Olayı Legacy sync_outbox_v4'e Aktarıldı mı?
      final legOutbox = (await legacyDb.query('sync_outbox_v4', where: 'mutation_id = ?', whereArgs: ['sync-v2-event-1'])).first;
      expect(legOutbox['state'], 'PENDING');
      expect(legOutbox['entity_id'], 'sale-v2-cutover-1');

      // G. Core Next'te Rollback Bayrağı İşaretlendi mi?
      final setting = (await coreDb.db.query('app_settings', where: 'key = ?', whereArgs: ['legacy_migration_completed'])).first;
      expect(setting['value'], 'rolled_back');
    });

    test('4. Parasal Hassasiyet ve Kuruş Sınır Değerleri Mutabakatı (0.01 TL, 0.1+0.2 Rounding, 999.999,99 TL)', () async {
      await legacyDb.insert('customers', {
        'id': 'c-boundary-1',
        'name': 'Hassas Hesap A.Ş.',
        'balance': 0.0,
      });

      // Kuruş sınır değerleri: 0.01 TL (1 kuruş), 0.30 TL (0.1 + 0.2 floating point hatası riski), 999999.99 TL
      final testCases = [
        {'id': 's-cent-1', 'total': 0.01, 'paid': 0.01, 'expectedCents': 1},
        {'id': 's-float-2', 'total': 0.1 + 0.2, 'paid': 0.30, 'expectedCents': 30},
        {'id': 's-huge-3', 'total': 999999.99, 'paid': 999999.99, 'expectedCents': 99999999},
      ];

      for (final tc in testCases) {
        await legacyDb.insert('sales', {
          'id': tc['id'] as String,
          'receipt_no': 'R-${tc['id']}',
          'customer_id': 'c-boundary-1',
          'total_amount': tc['total'] as double,
          'paid_amount': tc['paid'] as double,
          'created_at': '2026-10-14T10:00:00Z',
        });
      }

      final report = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, true);

      for (final tc in testCases) {
        final row = (await coreDb.db.query('sales', where: 'id = ?', whereArgs: [tc['id']])).first;
        expect(row['total_cents'], tc['expectedCents'], reason: 'Hassasiyet sapması: ${tc['id']}');
        expect(row['paid_cents'], tc['expectedCents']);
      }
    });

    test('5. SQLite Veritabanı Bütünlüğü ve Yabancı Anahtar Kontrolleri (integrity_check & foreign_key_check)', () async {
      // Her iki veritabanında PRAGMA kontrollerini çalıştır
      final coreIntegrity = await coreDb.db.rawQuery('PRAGMA integrity_check;');
      expect(coreIntegrity.first['integrity_check'], 'ok');

      final coreFkCheck = await coreDb.db.rawQuery('PRAGMA foreign_key_check;');
      expect(coreFkCheck.isEmpty, true, reason: 'Core Next veritabanında yabancı anahtar ihlali tespit edildi: $coreFkCheck');

      final legacyIntegrity = await legacyDb.rawQuery('PRAGMA integrity_check;');
      expect(legacyIntegrity.first['integrity_check'], 'ok');
    });
  });
}
