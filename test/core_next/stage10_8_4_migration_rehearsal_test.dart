// ignore_for_file: avoid_relative_lib_imports
// test/core_next/stage10_8_4_migration_rehearsal_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
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
    tempDir = await Directory.systemTemp.createTemp('stage10_8_4_rehearsal_');
    legacyDbPath = '${tempDir.path}${Platform.pathSeparator}serenut_pos_rehearsal.db';
    coreDbPath = '${tempDir.path}${Platform.pathSeparator}serenut_core_v2_rehearsal.db';

    // 1. Hedef Core Next veritabanını oluştur
    coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: coreDbPath);
    bridgeEngine = MigrationBridgeEngine(coreDb);

    // 2. Kaynak Legacy veritabanını oluştur (Şema v60 simülasyonu)
    legacyDb = await openDatabase(
      legacyDbPath,
      version: 60,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            barcode TEXT,
            sku TEXT,
            name TEXT NOT NULL,
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
            is_deleted INTEGER DEFAULT 0
          );
        ''');

        await db.execute('''
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT,
            email TEXT,
            balance REAL NOT NULL DEFAULT 0,
            balance_minor INTEGER,
            credit_limit REAL,
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
            total_amount REAL NOT NULL,
            total_amount_minor INTEGER,
            paid_amount REAL NOT NULL DEFAULT 0,
            paid_amount_minor INTEGER,
            discount_amount REAL DEFAULT 0,
            discount_amount_minor INTEGER,
            payment_method TEXT,
            status TEXT DEFAULT 'completed',
            idempotency_key TEXT UNIQUE,
            created_at TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE sale_items (
            id TEXT PRIMARY KEY,
            sale_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            product_name TEXT,
            quantity REAL NOT NULL,
            unit_price REAL NOT NULL,
            subtotal REAL NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE financial_transactions (
            id TEXT PRIMARY KEY,
            customer_id TEXT NOT NULL,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            paid_amount REAL DEFAULT 0,
            debt_amount REAL DEFAULT 0,
            created_at TEXT
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
            created_at TEXT
          );
        ''');

        // Bakiye doğrulama görünümü
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

  group('Stage 10.8.4 — Migration Bridge Denetimi ve Veri Geçişi Provası', () {
    test('1. Türkçe Karakterler, Kuruş Hassasiyeti ve Farklı Ödeme Türleri Kayıpsız Aktarılır', () async {
      // Türkçe karakterli ve ondalıklı ürünler
      await legacyDb.insert('products', {
        'id': 'p-tr-1',
        'barcode': '869001',
        'name': 'Çamlıca Şekersiz Çilekli İçecek 1L',
        'price': 24.99,
        'purchase_price': 15.50,
        'quantity': 50,
      });
      await legacyDb.insert('products', {
        'id': 'p-tr-2',
        'barcode': '869002',
        'name': 'Öztürkler Taze Öğütülmüş Türk Kahvesi',
        'price': 79.95,
        'purchase_price': 50.00,
        'quantity': 100,
      });

      // Türkçe karakterli müşteriler
      await legacyDb.insert('customers', {
        'id': 'c-tr-1',
        'name': 'Şükrü Çetin & Oğulları Gıda San. Tic. Ltd. Şti.',
        'phone': '05321112233',
        'balance': -350.75, // 350.75 TL borç
      });
      await legacyDb.insert('customers', {
        'id': 'c-tr-2',
        'name': 'İsmail Hakkı Özen',
        'phone': '05442223344',
        'balance': 0.0,
      });

      // Farklı ödeme tiplerinde satışlar
      await legacyDb.insert('sales', {
        'id': 's-1',
        'receipt_no': 'FIS-001',
        'customer_id': 'c-tr-1',
        'total_amount': 350.75,
        'paid_amount': 0.0,
        'payment_method': 'veresiye',
        'idempotency_key': 'idemp-s1',
        'created_at': '2026-10-14T10:00:00Z',
      });
      await legacyDb.insert('sales', {
        'id': 's-2',
        'receipt_no': 'FIS-002',
        'customer_id': null,
        'total_amount': 104.94,
        'paid_amount': 104.94,
        'payment_method': 'credit_card',
        'idempotency_key': 'idemp-s2',
        'created_at': '2026-10-14T11:00:00Z',
      });
      await legacyDb.insert('sales', {
        'id': 's-3',
        'receipt_no': 'FIS-003',
        'customer_id': null,
        'total_amount': 200.0,
        'paid_amount': 150.0,
        'payment_method': 'mixed', // Karma ödeme
        'idempotency_key': 'idemp-s3',
        'created_at': '2026-10-14T12:00:00Z',
      });

      // Geçişi fiziksel yedekleme ile çalıştır
      final report = await bridgeEngine.migrateFromLegacy(
        legacyDb,
        legacyFilePath: legacyDbPath,
      );

      expect(report.isSuccess, true, reason: report.errorMessage);
      expect(report.productsMigrated, 2);
      expect(report.customersMigrated, 2);
      expect(report.salesMigrated, 3);

      // Fiziksel .backup dosyasının oluştuğunu ve boyutunun sıfır olmadığını doğrula
      final backupFile = File('$legacyDbPath.backup');
      expect(backupFile.existsSync(), true);
      expect(backupFile.lengthSync() > 0, true);

      // Türkçe karakter doğrulaması
      final p1 = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-tr-1'])).first;
      expect(p1['name'], 'Çamlıca Şekersiz Çilekli İçecek 1L');
      expect(p1['price_cents'], 2499);
      expect(p1['cost_price_cents'], 1550);

      final c1 = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-tr-1'])).first;
      expect(c1['name'], 'Şükrü Çetin & Oğulları Gıda San. Tic. Ltd. Şti.');
      expect(c1['balance_cents'], -35075);

      // Karma ödeme doğrulaması
      final s3Payments = await coreDb.db.query('sale_payments', where: 'sale_id = ?', whereArgs: ['s-3']);
      expect(s3Payments.length, 2); // 150 TL paid + 50 TL debt
      final paidSplit = s3Payments.firstWhere((p) => p['id'] == 's-3-pay-legacy-paid');
      expect(paidSplit['payment_type'], 'mixed');
      expect(paidSplit['amount_cents'], 15000);
      final debtSplit = s3Payments.firstWhere((p) => p['id'] == 's-3-pay-legacy-debt');
      expect(debtSplit['payment_type'], 'onAccount');
      expect(debtSplit['amount_cents'], 5000);
    });

    test('2. Finansal Parasal Toplamlar ve Kayıt Sayısı Mutabakatı', () async {
      // Ürünler
      await legacyDb.insert('products', {
        'id': 'p-1',
        'barcode': 'B1',
        'name': 'Ürün 1',
        'price': 10.50,
        'quantity': 10,
      });
      await legacyDb.insert('products', {
        'id': 'p-2',
        'barcode': 'B2',
        'name': 'Ürün 2',
        'price': 20.25,
        'quantity': 5,
      });

      // Müşteri
      await legacyDb.insert('customers', {
        'id': 'c-1',
        'name': 'Müşteri 1',
        'balance': -150.00,
      });

      // Satış
      await legacyDb.insert('sales', {
        'id': 's-1',
        'receipt_no': 'REC-1',
        'customer_id': 'c-1',
        'total_amount': 206.25,
        'paid_amount': 56.25,
        'discount_amount': 10.0,
        'payment_method': 'cash',
        'idempotency_key': 'idemp-1',
      });

      // Kaynak parasal toplamları
      final legacyProductSum = (await legacyDb.rawQuery('SELECT SUM(price * quantity) as s FROM products')).first['s'] as num;
      // 10.50 * 10 + 20.25 * 5 = 105.0 + 101.25 = 206.25 TL
      expect(legacyProductSum, 206.25);

      final legacySalesSum = (await legacyDb.rawQuery('SELECT SUM(total_amount) as s FROM sales')).first['s'] as num;
      expect(legacySalesSum, 206.25);

      // Migrasyon
      final report = await bridgeEngine.migrateFromLegacy(legacyDb);
      expect(report.isSuccess, true);

      // Hedef kuruş toplamları
      final coreProductCents = (await coreDb.db.rawQuery('SELECT SUM(price_cents * stock_quantity) as s FROM products')).first['s'] as int;
      expect(coreProductCents, 20625); // 206.25 TL == 20625 kuruş

      final coreSalesCents = (await coreDb.db.rawQuery('SELECT SUM(total_cents) as s FROM sales')).first['s'] as int;
      expect(coreSalesCents, 20625);

      final coreCustBalanceCents = (await coreDb.db.rawQuery('SELECT SUM(balance_cents) as s FROM customers')).first['s'] as int;
      expect(coreCustBalanceCents, -15000); // -150.00 TL == -15000 kuruş
    });

    test('3. İdempotency ve Tekrar Çalıştırılabilirlik: İkinci çalıştırma çift kayıt üretmez', () async {
      await legacyDb.insert('products', {'id': 'p-idem-1', 'barcode': 'BI1', 'name': 'P1', 'price': 10.0, 'quantity': 5});
      await legacyDb.insert('customers', {'id': 'c-idem-1', 'name': 'C1', 'balance': 0.0});
      await legacyDb.insert('sales', {
        'id': 's-idem-1',
        'receipt_no': 'R1',
        'customer_id': 'c-idem-1',
        'total_amount': 50.0,
        'paid_amount': 50.0,
        'payment_method': 'cash',
        'idempotency_key': 'idem-s1',
      });

      // 1. Çalıştırma
      final rep1 = await bridgeEngine.migrateFromLegacy(legacyDb);
      expect(rep1.isSuccess, true);
      expect(rep1.productsMigrated, 1);
      expect(rep1.customersMigrated, 1);
      expect(rep1.salesMigrated, 1);

      // 2. Çalıştırma (Rerun)
      final rep2 = await bridgeEngine.migrateFromLegacy(legacyDb);
      expect(rep2.isSuccess, true);

      // Tablolardaki nihai sayıların birebir 1 olduğunu teyit et (Çift kayıt yok)
      final pCount = (await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM products')).first['c'] as int;
      final cCount = (await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM customers')).first['c'] as int;
      final sCount = (await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      final payCount = (await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM sale_payments')).first['c'] as int;

      expect(pCount, 1);
      expect(cCount, 1);
      expect(sCount, 1);
      expect(payCount, 1);
    });

    test('4. Hedef Veritabanında SQLite Bütünlüğü ve Foreign Key Denetimi', () async {
      await legacyDb.insert('products', {'id': 'p-fk-1', 'barcode': 'BFK', 'name': 'Ürün', 'price': 10.0, 'quantity': 1});
      await legacyDb.insert('customers', {'id': 'c-fk-1', 'name': 'Müşteri', 'balance': 0.0});
      await legacyDb.insert('sales', {
        'id': 's-fk-1',
        'receipt_no': 'RFK',
        'customer_id': 'c-fk-1',
        'total_amount': 10.0,
        'paid_amount': 10.0,
        'payment_method': 'cash',
        'idempotency_key': 'fk-key',
      });

      await bridgeEngine.migrateFromLegacy(legacyDb);

      // SQLite Bütünlük Denetimi
      final integrityCheck = await coreDb.db.rawQuery('PRAGMA integrity_check');
      expect(integrityCheck.first.values.first, 'ok');

      // Foreign Key Denetimi (Hedefte yetim veya kopuk FK olmamalı)
      final fkCheck = await coreDb.db.rawQuery('PRAGMA foreign_key_check');
      expect(fkCheck.isEmpty, true, reason: 'Tüm yabancı anahtarlar geçerli olmalı, kopuk kayıt bulunmamalıdır');
    });

    test('5. Eksik Kapsam Adli Denetimi: Taşınmayan tablolar ve veriler kanıtlanır', () async {
      // Legacy veritabanına taşınması gereken ek tablolar doldur
      await legacyDb.insert('sale_items', {
        'id': 'item-1',
        'sale_id': 's-1',
        'product_id': 'p-1',
        'product_name': 'Kalem Ürün',
        'quantity': 2.0,
        'unit_price': 10.0,
        'subtotal': 20.0,
      });

      await legacyDb.insert('financial_transactions', {
        'id': 'tx-1',
        'customer_id': 'c-1',
        'type': 'PAYMENT',
        'amount': 50.0,
        'paid_amount': 50.0,
        'debt_amount': 0.0,
        'created_at': '2026-10-14T12:00:00Z',
      });

      await legacyDb.insert('sync_outbox_v4', {
        'mutation_id': 'mut-outbox-1',
        'entity_type': 'sale',
        'entity_id': 's-1',
        'operation': 'CREATE',
        'payload': '{"test": true}',
        'base_revision': 5,
        'state': 'PENDING',
        'created_at': '2026-10-14T12:00:00Z',
      });

      // Migrasyonu çalıştır
      final report = await bridgeEngine.migrateFromLegacy(legacyDb);
      expect(report.isSuccess, true);

      // ADLİ KANIT: MigrationBridgeEngine bu tabloları henüz taşımamaktadır!
      // 1. sale_items hedef veritabanında boştur
      final coreSaleItems = await coreDb.db.query('sale_items');
      expect(coreSaleItems.isEmpty, true, reason: 'MigrationBridgeEngine sale_items tablosunu taşımamaktadır (Eksik Kapsam)');

      // 2. ledger_entries hedef veritabanında boştur (yalnızca müşterinin anlık bakiyesi taşındı, hareket defteri taşınmadı)
      final coreLedger = await coreDb.db.query('ledger_entries');
      expect(coreLedger.isEmpty, true, reason: 'MigrationBridgeEngine ledger_entries hareketlerini taşımamaktadır (Eksik Kapsam)');

      // 3. sync_events hedef veritabanında boştur (legacy sync_outbox_v4 mutasyonları taşınmadı)
      final coreSyncEvents = await coreDb.db.query('sync_events');
      expect(coreSyncEvents.isEmpty, true, reason: 'Legacy sync_outbox_v4 kayıtları sync_events kuyruğuna taşınmamaktadır (Eksik Kapsam)');
    });
  });
}
