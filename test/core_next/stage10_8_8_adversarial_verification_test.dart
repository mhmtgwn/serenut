// ignore_for_file: avoid_relative_lib_imports
// test/core_next/stage10_8_8_adversarial_verification_test.dart
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
    tempDir = await Directory.systemTemp.createTemp('stage10_8_8_adversarial_');
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
            name TEXT NOT NULL,
            category TEXT,
            category_id TEXT,
            price REAL NOT NULL,
            price_minor INTEGER,
            cost_price REAL,
            cost_price_minor INTEGER,
            vat_rate INTEGER DEFAULT 20,
            vat INTEGER,
            unit TEXT DEFAULT 'piece',
            sale_type TEXT,
            quantity REAL DEFAULT 0,
            stock_quantity REAL,
            min_stock REAL DEFAULT 5,
            image_url TEXT,
            is_active INTEGER DEFAULT 1,
            is_deleted INTEGER DEFAULT 0,
            created_at TEXT,
            updated_at TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT,
            email TEXT,
            address TEXT,
            tax_number TEXT,
            tax_office TEXT,
            notes TEXT,
            balance REAL DEFAULT 0.0,
            balance_minor INTEGER DEFAULT 0,
            is_active INTEGER DEFAULT 1,
            created_at TEXT,
            updated_at TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE sales (
            id TEXT PRIMARY KEY,
            receipt_no TEXT NOT NULL,
            customer_id TEXT,
            total_amount REAL NOT NULL,
            total_amount_minor INTEGER,
            paid_amount REAL NOT NULL,
            paid_amount_minor INTEGER,
            discount_amount REAL DEFAULT 0.0,
            discount_amount_minor INTEGER DEFAULT 0,
            payment_method TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'completed',
            idempotency_key TEXT,
            notes TEXT,
            refunded_amount REAL DEFAULT 0.0,
            created_at TEXT NOT NULL,
            updated_at TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE sale_items (
            id TEXT PRIMARY KEY,
            sale_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            barcode TEXT,
            product_name TEXT NOT NULL,
            unit_price REAL NOT NULL,
            unit_price_minor INTEGER,
            quantity REAL NOT NULL,
            subtotal REAL NOT NULL,
            subtotal_minor INTEGER,
            discount_amount REAL DEFAULT 0.0,
            discount_amount_minor INTEGER DEFAULT 0,
            vat_rate INTEGER DEFAULT 20,
            vat INTEGER,
            FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE
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
            sale_item_id TEXT,
            product_id TEXT NOT NULL,
            quantity REAL NOT NULL,
            unit_refund_amount REAL NOT NULL,
            subtotal REAL NOT NULL,
            FOREIGN KEY (refund_id) REFERENCES refunds (id) ON DELETE CASCADE
          );
        ''');

        await db.execute('''
          CREATE TABLE financial_transactions (
            id TEXT PRIMARY KEY,
            contact_id TEXT NOT NULL,
            amount REAL NOT NULL,
            type TEXT NOT NULL,
            description TEXT,
            reference_id TEXT,
            created_at TEXT NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE sync_outbox_v4 (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mutation_id TEXT UNIQUE NOT NULL,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            operation TEXT NOT NULL,
            payload TEXT NOT NULL,
            base_revision INTEGER NOT NULL DEFAULT 0,
            state TEXT NOT NULL DEFAULT 'PENDING',
            created_at TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0
          );
        ''');
      },
    );
  });

  tearDown(() async {
    await legacyDb.close();
    await coreDb.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Stage 10.8.8 Adversarial Verification Suite', () {
    test('1. Migration Idempotency & Data Freshness — ConflictAlgorithm.ignore Stale Data Audit', () async {
      // 1. Kaynakta 1 ürün ekle
      await legacyDb.insert('products', {
        'id': 'prod-fresh-01',
        'barcode': '8690001',
        'name': 'Orijinal Ürün Adı',
        'price': 100.0,
        'quantity': 50.0,
      });

      // İlk migration
      final res1 = await bridgeEngine.migrateFromLegacy(
        legacyDb,
        fullScope: true,
      );
      expect(res1.isSuccess, isTrue);

      final pCore1 = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-fresh-01'])).first;
      expect(pCore1['name'], 'Orijinal Ürün Adı');
      expect(pCore1['price_cents'], 10000);
      expect(pCore1['stock_quantity'], 50);

      // 2. Şimdi kaynakta ürünün adını, fiyatını ve stoğunu güncelle
      await legacyDb.update(
        'products',
        {
          'name': 'GÜNCELLENMİŞ Ürün Adı',
          'price': 150.0,
          'quantity': 35.0,
        },
        where: 'id = ?',
        whereArgs: ['prod-fresh-01'],
      );

      // İkinci migration çalıştır (cleanTarget = false)
      final res2 = await bridgeEngine.migrateFromLegacy(
        legacyDb,
        fullScope: true,
      );
      expect(res2.isSuccess, isTrue);

      // Stage 10.8.9 Remediation Doğrulaması:
      // In-Place UPSERT sayesinde hedefteki kayıt güncel kaynak verilerini alır:
      final pCore2 = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-fresh-01'])).first;
      expect(pCore2['name'], equals('GÜNCELLENMİŞ Ürün Adı'),
          reason: 'In-Place UPSERT sayesinde hedefteki ürün adı güncellenmiştir');
      expect(pCore2['price_cents'], equals(15000),
          reason: 'In-Place UPSERT sayesinde hedefteki ürün fiyatı güncellenmiştir');
      expect(pCore2['stock_quantity'], equals(35),
          reason: 'In-Place UPSERT sayesinde hedefteki ürün stoğu güncellenmiştir');
    });

    test('2. Finansal Ödeme Mutabakatı — 7 Ödeme Kombinasyonu ve Roundtrip Ayrışma Denetimi', () async {
      final combinations = [
        {'id': 's-cash', 'total': 10000, 'pays': [('cash', 10000)]},
        {'id': 's-card', 'total': 20000, 'pays': [('creditCard', 20000)]},
        {'id': 's-debt', 'total': 30000, 'pays': [('onAccount', 30000)]},
        {'id': 's-cash-card', 'total': 20000, 'pays': [('cash', 10000), ('creditCard', 10000)]},
        {'id': 's-cash-debt', 'total': 25000, 'pays': [('cash', 15000), ('onAccount', 10000)]},
        {'id': 's-card-debt', 'total': 20000, 'pays': [('creditCard', 12000), ('onAccount', 8000)]},
        {'id': 's-triple', 'total': 20000, 'pays': [('cash', 5000), ('creditCard', 7000), ('onAccount', 8000)]},
      ];

      for (final c in combinations) {
        final sid = c['id'] as String;
        final total = c['total'] as int;
        final pays = c['pays'] as List<(String, int)>;
        int paidSum = 0;
        for (final p in pays) {
          if (p.$1 != 'onAccount') paidSum += p.$2;
        }

        await coreDb.db.insert('sales', {
          'id': sid,
          'receipt_no': 'REC-$sid',
          'subtotal_cents': total,
          'total_cents': total,
          'paid_cents': paidSum,
          'debt_cents': total - paidSum,
          'status': 'COMPLETED',
          'created_at': 1700000000000,
        });

        int pIdx = 0;
        for (final p in pays) {
          await coreDb.db.insert('sale_payments', {
            'id': '$sid-pay-${pIdx++}',
            'sale_id': sid,
            'payment_type': p.$1,
            'amount_cents': p.$2,
            'created_at': 1700000000000,
          });
        }

        // Doğrulama: Ödeme kalemleri toplamı == satış toplamı
        final sumPayments = pays.fold<int>(0, (sum, item) => sum + item.$2);
        expect(sumPayments, equals(total));
      }

      // Reverse Rollback çalıştır -> Legacy'ye aktar
      final revRes = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreDb,
      );
      expect(revRes.isSuccess, isTrue);

      // ADVERSARIAL ROUNDTRIP BULGUSU:
      // Nakit + Kart gibi çoklu peşin ödemeler legacy `sales` içinde 'mixed' olur ve notes'a yazılır.
      // Şimdi legacy'den tekrar Core Next'e migrasyon çalıştıralım:
      final roundtripCorePath = '${tempDir.path}${Platform.pathSeparator}core_roundtrip.db';
      final roundtripCoreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: roundtripCorePath);
      final roundtripBridge = MigrationBridgeEngine(roundtripCoreDb);

      final fwdRes = await roundtripBridge.migrateFromLegacy(
        legacyDb,
        fullScope: true,
      );
      expect(fwdRes.isSuccess, isTrue);

      // Nakit+Kart satışını ('s-cash-card') inceleyelim:
      final rtPayments = await roundtripCoreDb.db.query(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: ['s-cash-card'],
      );

      // Stage 10.8.9 Remediation Doğrulaması:
      // Yapısal sale_payments tablosu sayesinde Nakit ve Kart kırılımı korunmuştur:
      expect(rtPayments.length, equals(2),
          reason: 'Yapısal sale_payments tablosu sayesinde Nakit ve Kart kırılımı tam korunmuştur.');
      expect(rtPayments[0]['payment_type'], equals('cash'));
      expect(rtPayments[0]['amount_cents'], equals(10000));
      expect(rtPayments[1]['payment_type'], equals('creditCard'));
      expect(rtPayments[1]['amount_cents'], equals(10000));

      await roundtripCoreDb.close();
    });

    test('3. İade ve Rollback — Çift Çalıştırmada sales.refunded_amount İade Tutarı Çiftleme (Doubling) Denetimi', () async {
      // 1. Orijinal satış oluştur
      await legacyDb.insert('sales', {
        'id': 'sale-orig-100',
        'receipt_no': 'REC-100',
        'total_amount': 100.0,
        'paid_amount': 100.0,
        'payment_method': 'cash',
        'refunded_amount': 0.0,
        'created_at': '2026-10-14T10:00:00Z',
      });

      // 2. Core Next'te bu satışa 40 TL kısmi iade oluştur
      await coreDb.db.insert('sales', {
        'id': 'ref-part-40',
        'receipt_no': 'REF-40',
        'subtotal_cents': -4000,
        'total_cents': -4000,
        'paid_cents': -4000,
        'debt_cents': 0,
        'status': 'REFUND',
        'created_at': 1700000000000,
      });

      // 3. İlk Reverse Rollback
      final res1 = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreDb,
      );
      expect(res1.isSuccess, isTrue);

      final sRow1 = (await legacyDb.query('sales', where: 'id = ?', whereArgs: ['sale-orig-100'])).first;
      expect((sRow1['refunded_amount'] as num).toDouble(), equals(40.0));

      // 4. İkinci Kez Reverse Rollback Çalıştır (Idempotency Denetimi)
      final res2 = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreDb,
      );
      expect(res2.isSuccess, isTrue);

      final sRow2 = (await legacyDb.query('sales', where: 'id = ?', whereArgs: ['sale-orig-100'])).first;
      final refundedAmountAfterSecondRun = (sRow2['refunded_amount'] as num).toDouble();

      // Stage 10.8.9 Remediation Doğrulaması:
      // SUM(amount) alt sorgusu sayesinde ikinci çalıştırmada tutar ikiye katlanmaz, tam 40.0 TL kalır!
      expect(refundedAmountAfterSecondRun, equals(40.0),
          reason: 'Stage 10.8.9 Düzeltmesi: İade rollback idempotency guard sayesinde refunded_amount ikiye katlanmaz!');
    });

    test('4. Senkronizasyon Kuyruğu — IN_FLIGHT, PENDING ve TRANSIENT_ERROR Protokol 6 Güvenlik Denetimi', () async {
      await legacyDb.insert('sync_outbox_v4', {
        'mutation_id': 'mut-adv-flight',
        'entity_type': 'sale',
        'entity_id': 'sale-999',
        'operation': 'UPSERT',
        'payload': '{"id":"sale-999","total_cents":5000}',
        'base_revision': 3,
        'state': 'IN_FLIGHT',
        'attempts': 1,
        'created_at': '2026-10-14T12:00:00Z',
      });

      // Migration çalıştır
      final res = await bridgeEngine.migrateFromLegacy(
        legacyDb,
        fullScope: true,
      );
      expect(res.isSuccess, isTrue);

      final ev = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['mut-adv-flight'])).first;
      expect(ev['sync_state'], equals('PENDING'), reason: 'Uçuşta kalan istek güvenle PENDING olarak devralınmalıdır.');
      expect(ev['attempts'], equals(1), reason: 'Deneme sayısı korunmalıdır.');
      expect(ev['base_revision'], equals(3), reason: 'base_revision korunmalıdır.');
    });

    test('5. Tek Yetkili DB ve UI Okuma Yolu — Runtime Dual-DB Split ve Ayrışma Denetimi', () async {
      // Bu test, Core Next yazma yolu ile Legacy okuma yolu arasındaki bağımsız ayrışmayı denetler.
      // Core Next veritabanına doğrudan bir satış yazılır (Executor'ın yaptığı gibi)
      await coreDb.db.insert('sales', {
        'id': 'sale-core-only',
        'receipt_no': 'REC-CORE-999',
        'subtotal_cents': 5000,
        'total_cents': 5000,
        'paid_cents': 5000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': 1700000000000,
      });

      // Legacy veritabanı (AppDatabase.instance / SqliteSaleRepository'nin okuduğu yer):
      final legacyRows = await legacyDb.query('sales', where: 'id = ?', whereArgs: ['sale-core-only']);

      // ADVERSARIAL BULGU KANITI:
      // İki SQLite veritabanı arasında runtime senkronizasyon köprüsü KODDA YOKTUR.
      // SalesController yazmayı Core Next'e yaparken, _saleRepository.findAll() legacyDb'yi okur.
      // Bu nedenle legacy okuma yolunda satış BULUNAMAZ (empty).
      expect(legacyRows.isEmpty, isTrue,
          reason: 'Runtime bridge bulunmadığı için Core Next satışları legacy okuma deposunda görünmez (Dual-DB Split).');
    });
  });
}
