// ignore_for_file: avoid_relative_lib_imports
// test/core_next/stage10_8_6_adversarial_audit_test.dart
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
    tempDir = await Directory.systemTemp.createTemp('stage10_8_6_audit_');
    legacyDbPath = '${tempDir.path}${Platform.pathSeparator}serenut_pos_adv.db';
    coreDbPath = '${tempDir.path}${Platform.pathSeparator}serenut_core_v2_adv.db';

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

  group('Stage 10.8.6 — Independent Adversarial Audit', () {
    test('Senaryo 1: Migration İki Kez Çalıştırıldığında Mükerrer Kayıt Oluşmaz (Idempotency)', () async {
      await legacyDb.insert('users', {
        'id': 'u-1',
        'username': 'user1',
        'name': 'Kasiyer 1',
        'created_at': '2026-10-14T08:00:00Z',
      });
      await legacyDb.insert('categories', {
        'id': 'cat-1',
        'name': 'Gıda',
      });
      await legacyDb.insert('products', {
        'id': 'p-1',
        'barcode': '123456',
        'name': 'Ekmek',
        'category_id': 'cat-1',
        'price': 10.0,
        'quantity': 50,
      });
      await legacyDb.insert('customers', {
        'id': 'c-1',
        'name': 'Ahmet',
        'balance': 0.0,
      });
      await legacyDb.insert('sales', {
        'id': 's-1',
        'receipt_no': 'REC-1',
        'customer_id': 'c-1',
        'total_amount': 20.0,
        'paid_amount': 20.0,
        'created_at': '2026-10-14T10:00:00Z',
      });
      await legacyDb.insert('sale_items', {
        'id': 'si-1',
        'sale_id': 's-1',
        'product_id': 'p-1',
        'barcode': '123456',
        'quantity': 2.0,
        'unit_price': 10.0,
        'subtotal': 20.0,
      });

      // 1. Çalıştırma
      final rep1 = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep1.isSuccess, true);

      // 2. Çalıştırma
      final rep2 = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);

      // DÜZELTME DOĞRULAMASI: ConflictAlgorithm.ignore sayesinde FK kısıtına takılmadan ikinci çalıştırma başarılı olur!
      expect(rep2.isSuccess, true, reason: rep2.errorMessage);

      // Doğrulama: Hedef DB'de kayıt sayıları iki katına ÇIKMAMALI
      expect(Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM users')), 1);
      expect(Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM categories')), 1);
      expect(Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM products')), 1);
      expect(Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM customers')), 1);
      expect(Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM sales')), 1);
      expect(Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM sale_items')), 1);
      expect(Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM sale_payments')), 1);
    });

    test('Senaryo 2: Tablo Aktarımının Ortasında Hata Oluşursa Transaction Bütünüyle Geri Alınır (Fail-Closed)', () async {
      // Geçerli bir ürün ekle
      await legacyDb.insert('products', {
        'id': 'p-valid',
        'barcode': '111',
        'name': 'Çikolata',
        'price': 15.0,
        'quantity': 10,
      });

      // Hata Enjeksiyonu: customers tablosuna balance ile v_customer_ledger_effect arasında 50 kuruşluk bilerek fark koy
      await legacyDb.insert('customers', {
        'id': 'c-corrupt',
        'name': 'Hileli Müşteri',
        'balance': 100.0, // 100 TL
      });
      // Görünümü manipüle et: defter toplamı 99.50 TL olsun
      await legacyDb.execute('DROP VIEW v_customer_ledger_effect');
      await legacyDb.execute('''
        CREATE VIEW v_customer_ledger_effect AS
        SELECT 'c-corrupt' as customer_id, 99.50 as balance_effect;
      ''');

      // Migrasyon çalıştırıldığında müşteri bakiye sapması hatası fırlatmalı
      final report = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, false);
      expect(report.errorMessage!.contains('MÜŞTERİ BAKİYE SAPMASI TESPİT EDİLDİ'), true);

      // ADLİ KANIT: Transaction tamamen geri alınmış olmalı!
      // Müşterilerden önce gelen products ve users tablolarına yazılan kayıtlar da ROLLBACK olmalı:
      final pCount = Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM products'));
      final cCount = Sqflite.firstIntValue(await coreDb.db.rawQuery('SELECT COUNT(*) FROM customers'));
      expect(pCount, 0, reason: 'Transaction yarıda kesildiğinde ürünler rollback edilmedi (Kısmi yazma sızıntısı)');
      expect(cCount, 0);
    });

    test('Senaryo 3 & 4: Reverse Rollback Çoklu Ödeme, İptal, İade ve İkinci Kez Çalıştırma Güvenliği', () async {
      // 1. Temel migrasyon
      await legacyDb.insert('products', {
        'id': 'p-100',
        'barcode': '888',
        'name': 'Peynir 500g',
        'price': 120.0,
        'quantity': 50,
      });
      await legacyDb.insert('customers', {
        'id': 'c-100',
        'name': 'Marketçi Ali',
        'balance': 0.0,
      });

      await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);

      // 2. Core Next'te Çoklu Ödemeli (Karma) Yeni Satış Oluştur
      await coreDb.db.insert('sales', {
        'id': 'sale-multi-pay',
        'receipt_no': 'REC-MULTI-1',
        'customer_id': 'c-100',
        'subtotal_cents': 24000,
        'total_cents': 24000,
        'paid_cents': 14000,
        'debt_cents': 10000,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      // 2 Ödeme: 140 TL Nakit + 100 TL Veresiye
      await coreDb.db.insert('sale_payments', {
        'id': 'sp-1',
        'sale_id': 'sale-multi-pay',
        'payment_type': 'cash',
        'amount_cents': 14000,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'sp-2',
        'sale_id': 'sale-multi-pay',
        'payment_type': 'onAccount',
        'amount_cents': 10000,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // İptal Edilen Satış (CANCELLED)
      await coreDb.db.insert('sales', {
        'id': 'sale-cancelled-1',
        'receipt_no': 'REC-CANC-1',
        'customer_id': 'c-100',
        'subtotal_cents': 5000,
        'total_cents': 5000,
        'paid_cents': 5000,
        'status': 'CANCELLED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Stok değişimi (50 -> 48)
      await coreDb.db.update('products', {'stock_quantity': 48}, where: 'id = ?', whereArgs: ['p-100']);

      // 3. İlk Reverse Rollback Çalıştır
      final repRollback1 = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreDb,
      );
      expect(repRollback1.isSuccess, true);
      expect(repRollback1.salesExported, 2);

      // 4. İkinci Reverse Rollback Çalıştır (Idempotency Denetimi)
      final repRollback2 = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreDb,
      );
      expect(repRollback2.isSuccess, true);
      // İkinci çalıştırmada yeni satış aktarılmamalı (0 yeni satış)
      expect(repRollback2.salesExported, 0);

      // Stok kontrolü: İkinci kez çalıştırıldı diye stok 48'den daha aşağı düşmemeli
      final legP = (await legacyDb.query('products', where: 'id = ?', whereArgs: ['p-100'])).first;
      expect((legP['quantity'] as num).toDouble(), 48.0);

      // İptal edilen satış kontrolü: Status 'CANCELLED' olarak legacy'e geçti mi?
      final legCanc = (await legacyDb.query('sales', where: 'id = ?', whereArgs: ['sale-cancelled-1'])).first;
      expect(legCanc['status'], 'CANCELLED');
    });

    test('Senaryo 5: Outbox Durum İzolasyonu (PENDING vs IN_FLIGHT vs SYNCED)', () async {
      // Legacy outbox'a farklı statülerde kayıtlar koy
      await legacyDb.insert('sync_outbox_v4', {
        'mutation_id': 'mut-pending',
        'entity_type': 'sale',
        'entity_id': 's-1',
        'operation': 'CREATE',
        'payload': '{}',
        'state': 'PENDING',
        'created_at': '2026-10-14T10:00:00Z',
      });
      await legacyDb.insert('sync_outbox_v4', {
        'mutation_id': 'mut-synced',
        'entity_type': 'sale',
        'entity_id': 's-2',
        'operation': 'CREATE',
        'payload': '{}',
        'state': 'SYNCED',
        'created_at': '2026-10-14T10:00:00Z',
      });
      await legacyDb.insert('sync_outbox_v4', {
        'mutation_id': 'mut-inflight',
        'entity_type': 'sale',
        'entity_id': 's-3',
        'operation': 'CREATE',
        'payload': '{}',
        'state': 'IN_FLIGHT',
        'created_at': '2026-10-14T10:00:00Z',
      });

      // Migrasyon çalıştır
      final report = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, true);

      // DÜZELTME DOĞRULAMASI: Güvenli Cutover Politikası gereğince hem PENDING hem de IN_FLIGHT taşınır (2 kayıt); SYNCED kayıt ise kuyruğa sokulmaz
      final coreSyncs = await coreDb.db.query('sync_events');
      expect(coreSyncs.length, 2);
      final eventIds = coreSyncs.map((e) => e['event_id']).toSet();
      expect(eventIds.contains('mut-pending'), true);
      expect(eventIds.contains('mut-inflight'), true);
      expect(eventIds.contains('mut-synced'), false);
    });

    test('Senaryo 6: Idempotency Anahtarı Tekilliği (Mükerrer Satış Girişimi)', () async {
      await legacyDb.insert('customers', {
        'id': 'c-idem',
        'name': 'Cari Idem',
        'balance': 0.0,
      });

      await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);

      // Core Next üzerinde ilk satış
      await coreDb.db.insert('sales', {
        'id': 's-idem-1',
        'receipt_no': 'REC-IDEM-1',
        'customer_id': 'c-idem',
        'subtotal_cents': 1000,
        'total_cents': 1000,
        'paid_cents': 1000,
        'idempotency_key': 'KEY-UNIQUE-12345',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Aynı idempotency_key ile ikinci satış denemesi
      expect(
        () async => await coreDb.db.insert('sales', {
          'id': 's-idem-DUPLICATE',
          'receipt_no': 'REC-IDEM-2',
          'customer_id': 'c-idem',
          'subtotal_cents': 1000,
          'total_cents': 1000,
          'paid_cents': 1000,
          'idempotency_key': 'KEY-UNIQUE-12345',
          'created_at': DateTime.now().millisecondsSinceEpoch,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('Senaryo 7: Silinmiş Ürünler İçin Placeholder Kayıtların Katalog ve Satış Raporlarına Etkisi', () async {
      await legacyDb.insert('products', {
        'id': 'p-active',
        'barcode': 'ACT-1',
        'name': 'Aktif Ürün',
        'price': 50.0,
        'quantity': 10,
        'is_active': 1,
        'is_deleted': 0,
      });

      await legacyDb.insert('sales', {
        'id': 's-hist',
        'receipt_no': 'REC-HIST-1',
        'customer_id': 'customer-pesin-default',
        'total_amount': 80.0,
        'paid_amount': 80.0,
        'created_at': '2026-10-14T10:00:00Z',
      });

      // Silinmiş / yetim ürün kalemini legacyDb'ye ekle
      await legacyDb.insert('sale_items', {
        'id': 'item-orphan-1',
        'sale_id': 's-hist',
        'product_id': 'p-deleted-from-legacy',
        'product_name': 'Eski Silinen Ürün',
        'barcode': 'DEL-999',
        'quantity': 1.0,
        'unit_price': 80.0,
        'subtotal': 80.0,
      });

      final report = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, true);

      // 1. Kasiyer Satış Ekranı Katalog Sorgusu (is_deleted = 0 AND is_active = 1): Placeholder görünmemeli!
      final cashierCatalog = await coreDb.db.query(
        'products',
        where: 'is_deleted = 0 AND is_active = 1',
      );
      expect(cashierCatalog.length, 1);
      expect(cashierCatalog.first['id'], 'p-active');

      // 2. Geçmiş Satış Raporu (sale_items): Toplam ciro eksiksiz korunmalı!
      final totalSalesRevenue = Sqflite.firstIntValue(
        await coreDb.db.rawQuery('SELECT SUM(total_cents) FROM sale_items'),
      );
      expect(totalSalesRevenue, 8000); // 80,00 TL (8.000 kuruş) tam korunmuş
    });

    test('Senaryo 8: Türkçe Karakterler, Tırnak İşaretleri ve Özel Karakter İzolasyonu', () async {
      const trickyName = "Öz Şükrü Çetin & Oğulları Gıda 'Köy Sofrası' San. Tic. Ltd. Şti.";
      const trickyProductName = 'Çamlıca Şekersiz Çilekli & Böğürtlenli 1,5L (Iğdır Üzümü Özel Seri)';

      await legacyDb.insert('customers', {
        'id': 'c-tricky',
        'name': trickyName,
        'balance': 0.0,
      });
      await legacyDb.insert('products', {
        'id': 'p-tricky',
        'barcode': 'TR-8699',
        'name': trickyProductName,
        'price': 42.50,
        'quantity': 20,
      });

      final report = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, true);

      final c = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-tricky'])).first;
      expect(c['name'], trickyName);

      final p = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-tricky'])).first;
      expect(p['name'], trickyProductName);
    });

    test('Senaryo 9: Müşteri Bakiyesi vs Defter Hareketleri Tarihsel Sapma Denetimi', () async {
      // Müşteri bakiyesi 200 TL borç iken, defter hareketleri sadece 150 TL borç gösteriyor olsun (50 TL açıklanamayan sapma)
      await legacyDb.insert('customers', {
        'id': 'c-discrepancy',
        'name': 'Borçlu Cari',
        'balance': -200.0,
      });
      // v_customer_ledger_effect defter görünümü -150.0 dönsün
      await legacyDb.execute('DROP VIEW v_customer_ledger_effect');
      await legacyDb.execute('''
        CREATE VIEW v_customer_ledger_effect AS
        SELECT 'c-discrepancy' as customer_id, -150.0 as balance_effect;
      ''');

      final report = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, false);
      expect(report.errorMessage!.contains('MÜŞTERİ BAKİYE SAPMASI TESPİT EDİLDİ'), true);
    });

    test('Senaryo 10: SQLite Bütünlük Denetimi (PRAGMA integrity_check & foreign_key_check)', () async {
      final intCheck = await coreDb.db.rawQuery('PRAGMA integrity_check;');
      expect(intCheck.first['integrity_check'], 'ok');

      final fkCheck = await coreDb.db.rawQuery('PRAGMA foreign_key_check;');
      expect(fkCheck.isEmpty, true);
    });
  });
}
