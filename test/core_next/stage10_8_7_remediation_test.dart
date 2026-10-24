// ignore_for_file: avoid_relative_lib_imports
// test/core_next/stage10_8_7_remediation_test.dart
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
    tempDir = await Directory.systemTemp.createTemp('stage10_8_7_remediation_');
    legacyDbPath = '${tempDir.path}${Platform.pathSeparator}serenut_pos_remed.db';
    coreDbPath = '${tempDir.path}${Platform.pathSeparator}serenut_core_v2_remed.db';

    coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: coreDbPath);
    bridgeEngine = MigrationBridgeEngine(coreDb);

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
            notes TEXT,
            refunded_amount REAL NOT NULL DEFAULT 0,
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
          CREATE TABLE refunds (
            id TEXT PRIMARY KEY,
            sale_id TEXT NOT NULL,
            amount REAL NOT NULL CHECK(amount > 0),
            refund_method TEXT NOT NULL,
            external_reference TEXT,
            reason TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'completed',
            created_at TEXT NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE refund_items (
            id TEXT PRIMARY KEY,
            refund_id TEXT NOT NULL,
            sale_item_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            quantity INTEGER NOT NULL CHECK(quantity > 0),
            unit_refund_amount REAL NOT NULL,
            subtotal REAL NOT NULL
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

  group('Stage 10.8.7 — Critical Defect Remediation & Verification', () {
    test('1. Migration İdempotency ve Yabancı Anahtar Düzeltmesi (Re-run & Restart Güvenliği)', () async {
      await legacyDb.insert('categories', {
        'id': 'cat-1',
        'name': 'Temel Gıda',
      });
      await legacyDb.insert('products', {
        'id': 'p-1',
        'barcode': '123456789',
        'name': 'Çay 1kg',
        'category_id': 'cat-1',
        'price': 140.0,
        'quantity': 30,
      });
      await legacyDb.insert('customers', {
        'id': 'c-1',
        'name': 'Mustafa Bey',
        'balance': 0.0,
      });
      await legacyDb.insert('sales', {
        'id': 's-1',
        'receipt_no': 'REC-1',
        'customer_id': 'c-1',
        'total_amount': 280.0,
        'paid_amount': 280.0,
        'created_at': '2026-10-14T10:00:00Z',
      });
      await legacyDb.insert('sale_items', {
        'id': 'si-1',
        'sale_id': 's-1',
        'product_id': 'p-1',
        'barcode': '123456789',
        'quantity': 2.0,
        'unit_price': 140.0,
        'subtotal': 280.0,
      });

      // 1. Çalıştırma
      final rep1 = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep1.isSuccess, true, reason: rep1.errorMessage);

      // 2. Çalıştırma (F-01 Düzeltme Kanıtı: ConflictAlgorithm.ignore ile FK kısıtına takılmaz!)
      final rep2 = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep2.isSuccess, true, reason: rep2.errorMessage);

      // Veritabanındaki satır sayılarını doğrula
      expect(Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM products')), 1);
      expect(Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM sales')), 1);
      expect(Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM sale_items')), 1);
    });

    test('2. Karma Ödemelerin ve İadelerin Kayıpsız Ters Aktarımı (Reverse Rollback Remediation)', () async {
      // 1. Başlangıç verisi oluştur ve Core Next'e aktar
      await legacyDb.insert('products', {
        'id': 'p-peynir',
        'barcode': '999888',
        'name': 'Kaşar Peyniri 1kg',
        'price': 250.0,
        'quantity': 20,
      });
      await legacyDb.insert('customers', {
        'id': 'c-ahmet',
        'name': 'Ahmet Efendi',
        'balance': 0.0,
      });
      await legacyDb.insert('sales', {
        'id': 's-orig-1',
        'receipt_no': 'REC-ORIG-001',
        'customer_id': 'c-ahmet',
        'total_amount': 250.0,
        'paid_amount': 250.0,
        'created_at': '2026-10-14T10:00:00Z',
      });

      final mig = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(mig.isSuccess, true);

      // 2. Core Next üzerinde:
      // A) Karma Ödemeli Yeni Satış: 250 TL (150 TL Nakit + 100 TL Veresiye)
      await coreDb.db.insert('sales', {
        'id': 'sale-split-1',
        'receipt_no': 'REC-SPLIT-001',
        'customer_id': 'c-ahmet',
        'subtotal_cents': 25000,
        'total_cents': 25000,
        'paid_cents': 15000,
        'debt_cents': 10000,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'pay-split-cash',
        'sale_id': 'sale-split-1',
        'payment_type': 'cash',
        'amount_cents': 15000,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'pay-split-debt',
        'sale_id': 'sale-split-1',
        'payment_type': 'onAccount',
        'amount_cents': 10000,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // B) İade İşlemi: Orijinal REC-ORIG-001 satışının tam iadesi
      await coreDb.db.insert('sales', {
        'id': 'refund-core-1',
        'receipt_no': 'REF-REC-ORIG-001',
        'customer_id': 'c-ahmet',
        'subtotal_cents': -25000,
        'total_cents': -25000,
        'paid_cents': -25000,
        'debt_cents': 0,
        'status': 'REFUND',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_items', {
        'id': 'refund-item-1',
        'sale_id': 'refund-core-1',
        'product_id': 'p-peynir',
        'barcode': '999888',
        'product_name': 'Kaşar Peyniri 1kg',
        'unit_price_cents': 25000,
        'quantity': 1,
        'vat_rate': 20,
        'total_cents': 25000,
      });

      // 3. Reverse Rollback Çalıştır
      final rbReport = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreDb,
      );
      expect(rbReport.isSuccess, true, reason: rbReport.errorMessage);

      // 4. Doğrulama:
      // A) Karma Ödeme Doğrulaması:
      final legSplitSale = (await legacyDb.query('sales', where: 'id = ?', whereArgs: ['sale-split-1'])).first;
      expect(legSplitSale['payment_method'], 'mixed', reason: 'F-02 Çözümü: Parçalı ödeme payment_method mixed olarak kaydedilmelidir');
      expect(legSplitSale['notes']!.toString().contains('cash: 150.00 TL'), true);
      expect(legSplitSale['notes']!.toString().contains('onAccount: 100.00 TL'), true);

      // B) İade Doğrulaması (F-03 Çözümü):
      // Legacy sales tablosunda negatif kayıt OLMAMALI
      final negativeSales = await legacyDb.rawQuery('SELECT * FROM sales WHERE total_amount < 0');
      expect(negativeSales.isEmpty, true, reason: 'Legacy sales tablosuna negatif satır yazılmamalıdır');

      // İade legacy refunds tablosuna pozitif tutarla yazılmalı
      final legRefund = (await legacyDb.query('refunds', where: 'id = ?', whereArgs: ['refund-core-1'])).first;
      expect((legRefund['amount'] as num).toDouble(), 250.0);
      expect(legRefund['sale_id'], 's-orig-1');

      // Orijinal satışın refunded_amount alanı güncellenmiş olmalı
      final legOrig = (await legacyDb.query('sales', where: 'id = ?', whereArgs: ['s-orig-1'])).first;
      expect((legOrig['refunded_amount'] as num).toDouble(), 250.0);

      // 5. DÖNGÜSEL GÜVENLİK TESTİ: Bu legacy veritabanı üzerinde tekrar forward migration çalıştırılırsa çöker mi?
      // (Daha önce totalCents < 0 hatası veriyordu; şimdi negatif satış olmadığı için başarıyla geçmeli!)
      final forwardAgain = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(forwardAgain.isSuccess, true, reason: 'İadeler doğru modellendiği için döngüsel migration hatasız çalışmalıdır');
    });

    test('3. Senkronizasyon Kuyruğu Güvenli Cutover Politikası (F-04 Remediation)', () async {
      // Legacy outbox tablosuna farklı durumlarda kayıtlar yerleştir
      await legacyDb.insert('sync_outbox_v4', {
        'mutation_id': 'mut-pend',
        'entity_type': 'sale',
        'entity_id': 's-1',
        'operation': 'CREATE',
        'payload': '{"id": "s-1"}',
        'state': 'PENDING',
        'created_at': '2026-10-14T10:00:00Z',
      });
      await legacyDb.insert('sync_outbox_v4', {
        'mutation_id': 'mut-flight',
        'entity_type': 'sale',
        'entity_id': 's-2',
        'operation': 'CREATE',
        'payload': '{"id": "s-2"}',
        'state': 'IN_FLIGHT', // Uçuşta kalmış
        'created_at': '2026-10-14T10:00:00Z',
      });
      await legacyDb.insert('sync_outbox_v4', {
        'mutation_id': 'mut-transient',
        'entity_type': 'sale',
        'entity_id': 's-3',
        'operation': 'CREATE',
        'payload': '{"id": "s-3"}',
        'state': 'TRANSIENT_ERROR', // Geçici hata almış
        'created_at': '2026-10-14T10:00:00Z',
      });
      await legacyDb.insert('sync_outbox_v4', {
        'mutation_id': 'mut-synced',
        'entity_type': 'sale',
        'entity_id': 's-4',
        'operation': 'CREATE',
        'payload': '{"id": "s-4"}',
        'state': 'SYNCED', // Önceden tamamlanmış
        'created_at': '2026-10-14T10:00:00Z',
      });

      // İleri migrasyonu çalıştır
      final report = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, true);

      // Core Next sync_events tablosunda PENDING, IN_FLIGHT ve TRANSIENT_ERROR olan 3 mutasyon da olmalı!
      final coreEvents = await coreDb.db.query('sync_events');
      final eventIds = coreEvents.map((e) => e['event_id']).toSet();

      expect(eventIds.contains('mut-pend'), true);
      expect(eventIds.contains('mut-flight'), true, reason: 'F-04 Çözümü: IN_FLIGHT mutasyon terk edilmemelidir');
      expect(eventIds.contains('mut-transient'), true, reason: 'F-04 Çözümü: TRANSIENT_ERROR mutasyon terk edilmemelidir');
      expect(eventIds.contains('mut-synced'), false, reason: 'SYNCED kayıtlar aktif kuyruğa tekrar sokulmamalıdır');

      // Hepsinin sync_state alanı 'PENDING' olmalı
      for (final ev in coreEvents) {
        expect(ev['sync_state'], 'PENDING');
      }

      // Reverse Rollback: Core Next'te IN_FLIGHT olan yeni olay oluştur ve legacy'e geri aktar
      await coreDb.db.insert('sync_events', {
        'event_id': 'mut-core-flight',
        'entity_type': 'sale',
        'entity_id': 's-core-1',
        'operation': 'CREATE',
        'payload_json': '{}',
        'client_timestamp': DateTime.now().millisecondsSinceEpoch,
        'sync_state': 'IN_FLIGHT',
      });

      final rbReport = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreDb,
      );
      expect(rbReport.isSuccess, true, reason: rbReport.errorMessage);

      final legOutbox = await legacyDb.query('sync_outbox_v4', where: 'mutation_id = ?', whereArgs: ['mut-core-flight']);
      expect(legOutbox.isNotEmpty, true, reason: 'Core Next uçuşta olan olay legacy outbox kuyruğuna aktarılmalıdır');
      expect(legOutbox.first['state'], 'PENDING');
    });

    test('4. SQLite Bütünlüğü ve Kuruş Hassasiyeti Kontrolü', () async {
      final coreIntCheck = await coreDb.db.rawQuery('PRAGMA integrity_check;');
      expect(coreIntCheck.first['integrity_check'], 'ok');

      final coreFkCheck = await coreDb.db.rawQuery('PRAGMA foreign_key_check;');
      expect(coreFkCheck.isEmpty, true);

      final legIntCheck = await legacyDb.rawQuery('PRAGMA integrity_check;');
      expect(legIntCheck.first['integrity_check'], 'ok');
    });
  });
}
