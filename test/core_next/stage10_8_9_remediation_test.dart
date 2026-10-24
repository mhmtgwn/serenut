// ignore_for_file: avoid_relative_lib_imports
// test/core_next/stage10_8_9_remediation_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/providers/repository_providers.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_sale_repository.dart';

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
    tempDir = await Directory.systemTemp.createTemp('stage10_8_9_remediation_');
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
            sale_item_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            quantity INTEGER NOT NULL CHECK(quantity > 0),
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

  group('Stage 10.8.9 — Defect Remediation & Single Source of Truth Verification', () {
    test('1. ADV-01 Düzeltme Doğrulaması: In-Place UPSERT ile Veri Güncelliği ve FK Güvenliği', () async {
      // 1. Kaynakta ürün ve satış kalemi ekle
      await legacyDb.insert('products', {
        'id': 'prod-upsert-1',
        'barcode': '869000100',
        'name': 'Orijinal Çay',
        'price': 100.0,
        'quantity': 50.0,
      });
      await legacyDb.insert('sales', {
        'id': 'sale-fk-1',
        'receipt_no': 'REC-FK-1',
        'total_amount': 200.0,
        'paid_amount': 200.0,
        'payment_method': 'cash',
        'created_at': '2026-10-14T10:00:00Z',
      });
      await legacyDb.insert('sale_items', {
        'id': 'item-fk-1',
        'sale_id': 'sale-fk-1',
        'product_id': 'prod-upsert-1',
        'barcode': '869000100',
        'product_name': 'Orijinal Çay',
        'unit_price': 100.0,
        'quantity': 2.0,
        'subtotal': 200.0,
      });

      // 1. Migration
      final res1 = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(res1.isSuccess, isTrue);

      final p1 = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-upsert-1'])).first;
      expect(p1['name'], 'Orijinal Çay');
      expect(p1['price_cents'], 10000);
      expect(p1['stock_quantity'], 50);

      // 2. Kaynak legacy veritabanında ürün adı, fiyatı ve stoğunu güncelle
      await legacyDb.update(
        'products',
        {
          'name': 'Organik Rize Çay (GÜNCELLENDİ)',
          'price': 160.0,
          'quantity': 35.0,
        },
        where: 'id = ?',
        whereArgs: ['prod-upsert-1'],
      );

      // 2. Migration çalıştır (Hedefte sale_items çocuk kayıtları varken!)
      final res2 = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(res2.isSuccess, isTrue, reason: 'In-Place UPSERT FK kısıtını bozmadan başarılı olmalıdır');

      // Doğrulama: Hedefteki kayıt güncellendi mi? (ADV-01 Çözümü Kanıtı)
      final p2 = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-upsert-1'])).first;
      expect(p2['name'], equals('Organik Rize Çay (GÜNCELLENDİ)'), reason: 'Ürün adı güncellenmelidir');
      expect(p2['price_cents'], equals(16000), reason: 'Ürün fiyatı güncellenmelidir');
      expect(p2['stock_quantity'], equals(35), reason: 'Ürün stoğu güncellenmelidir');

      // Çocuk sale_items sağlam mı?
      final items = await coreDb.db.query('sale_items', where: 'id = ?', whereArgs: ['item-fk-1']);
      expect(items.length, equals(1), reason: 'Çocuk satış kalemi silinmemeli ve korunmalıdır');
    });

    test('2. ADV-02 Düzeltme Doğrulaması: İade Rollback Idempotency (refunded_amount Asla Çiftlenmez)', () async {
      // 1. Orijinal 100 TL satış oluştur
      await legacyDb.insert('sales', {
        'id': 'sale-ref-orig',
        'receipt_no': 'REC-ORIG-100',
        'total_amount': 100.0,
        'paid_amount': 100.0,
        'payment_method': 'cash',
        'refunded_amount': 0.0,
        'created_at': '2026-10-14T10:00:00Z',
      });

      // 2. Core Next'te 40 TL iade oluştur
      await coreDb.db.insert('sales', {
        'id': 'refund-40-id',
        'receipt_no': 'REF-REC-ORIG-100',
        'subtotal_cents': -4000,
        'total_cents': -4000,
        'paid_cents': -4000,
        'debt_cents': 0,
        'status': 'REFUND',
        'created_at': 1700000000000,
      });

      // 3. İlk Rollback
      final r1 = await ReverseMigrationEngine.rollbackToLegacy(legacyDb: legacyDb, coreDb: coreDb);
      expect(r1.isSuccess, isTrue);

      final s1 = (await legacyDb.query('sales', where: 'id = ?', whereArgs: ['sale-ref-orig'])).first;
      expect((s1['refunded_amount'] as num).toDouble(), equals(40.0));

      // 4. İkinci Rollback (Idempotency Denetimi)
      final r2 = await ReverseMigrationEngine.rollbackToLegacy(legacyDb: legacyDb, coreDb: coreDb);
      expect(r2.isSuccess, isTrue);

      final s2 = (await legacyDb.query('sales', where: 'id = ?', whereArgs: ['sale-ref-orig'])).first;
      // ADV-02 DÜZELTME KANITI: 80 TL'ye çıkmaz, tam 40.0 TL kalır!
      expect((s2['refunded_amount'] as num).toDouble(), equals(40.0),
          reason: 'ADV-02 Düzeltmesi: İade rollback tekrar çalıştırıldığında refunded_amount ikiye katlanmaz!');
    });

    test('3. ADV-03 Düzeltme Doğrulaması: Parçalı ve Çoklu Ödemelerin Roundtrip Boyunca Korunması', () async {
      // 7 Ödeme kombinasyonu:
      final scenarios = [
        {'id': 'sc-cash', 'total': 10000, 'pays': [('cash', 10000)]},
        {'id': 'sc-card', 'total': 20000, 'pays': [('creditCard', 20000)]},
        {'id': 'sc-debt', 'total': 30000, 'pays': [('onAccount', 30000)]},
        {'id': 'sc-cash-card', 'total': 20000, 'pays': [('cash', 10000), ('creditCard', 10000)]},
        {'id': 'sc-cash-debt', 'total': 25000, 'pays': [('cash', 15000), ('onAccount', 10000)]},
        {'id': 'sc-card-debt', 'total': 20000, 'pays': [('creditCard', 12000), ('onAccount', 8000)]},
        {'id': 'sc-triple', 'total': 20000, 'pays': [('cash', 5000), ('creditCard', 7000), ('onAccount', 8000)]},
      ];

      for (final sc in scenarios) {
        final sid = sc['id'] as String;
        final total = sc['total'] as int;
        final pays = sc['pays'] as List<(String, int)>;
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

        int idx = 0;
        for (final p in pays) {
          await coreDb.db.insert('sale_payments', {
            'id': '$sid-pay-${idx++}',
            'sale_id': sid,
            'payment_type': p.$1,
            'amount_cents': p.$2,
            'created_at': 1700000000000,
          });
        }
      }

      // 1. Reverse Rollback: Core Next -> Legacy
      final rb = await ReverseMigrationEngine.rollbackToLegacy(legacyDb: legacyDb, coreDb: coreDb);
      expect(rb.isSuccess, isTrue);

      // Legacy sale_payments tablosu oluştu mu ve dolduruldu mu?
      final legPayments = await legacyDb.query('sale_payments');
      expect(legPayments.isNotEmpty, isTrue, reason: 'Yapısal sale_payments tablosu legacy DB üzerinde oluşmalı');

      // 2. Forward Roundtrip: Legacy -> Yeni bir izole Core Next DB
      final roundtripPath = '${tempDir.path}${Platform.pathSeparator}core_roundtrip_adv3.db';
      final roundtripDb = await CoreAppDatabase.open(inMemoryOrCustomPath: roundtripPath);
      final roundtripBridge = MigrationBridgeEngine(roundtripDb);

      final fwd = await roundtripBridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(fwd.isSuccess, isTrue);

      // ADV-03 DÜZELTME KANITI:
      // Nakit + Kart satışı ('sc-cash-card') roundtrip sonrasında hala 2 ayrı ödeme satırına mı sahip?
      final rtPayments = await roundtripDb.db.query(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: ['sc-cash-card'],
        orderBy: 'payment_type ASC',
      );

      expect(rtPayments.length, equals(2), reason: 'Nakit ve Kart kırılımı tek satır mixed ödemeye ÇÖKMEZ; 2 ayrı satır olarak korunur');
      expect(rtPayments[0]['payment_type'], equals('cash'));
      expect(rtPayments[0]['amount_cents'], equals(10000));
      expect(rtPayments[1]['payment_type'], equals('creditCard'));
      expect(rtPayments[1]['amount_cents'], equals(10000));

      // Üçlü karma ödeme ('sc-triple') kontrolü:
      final triplePayments = await roundtripDb.db.query(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: ['sc-triple'],
      );
      expect(triplePayments.length, equals(3), reason: 'Üçlü karma ödemede Nakit, Kart ve Veresiye tam korunmalıdır');

      await roundtripDb.close();
    });

    test('4. ADV-04 Düzeltme Doğrulaması: CoreNextSaleRepository ile Tek Yetkili UI Okuma Yolu', () async {
      // Ürün kataloğu kaydı oluştur
      await coreDb.db.insert('products', {
        'id': 'p-test',
        'barcode': '123',
        'name': 'Test Ürün',
        'price_cents': 15000,
        'vat_rate': 20,
        'unit': 'piece',
        'stock_quantity': 10,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Core Next veritabanına doğrudan bir satış ekle
      await coreDb.db.insert('sales', {
        'id': 'sale-authoritative-1',
        'receipt_no': 'REC-AUTH-1',
        'subtotal_cents': 15000,
        'total_cents': 15000,
        'paid_cents': 15000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_items', {
        'id': 'item-auth-1',
        'sale_id': 'sale-authoritative-1',
        'product_id': 'p-test',
        'barcode': '123',
        'product_name': 'Test Ürün',
        'unit_price_cents': 15000,
        'quantity': 1,
        'vat_rate': 20,
        'total_cents': 15000,
      });

      // Riverpod ProviderContainer: CoreNextSaleRepository enjekte edilir
      final container = ProviderContainer(
        overrides: [
          coreNextSaleRepositoryProvider.overrideWithValue(
            CoreNextSaleRepository(coreDb.db),
          ),
        ],
      );
      addTearDown(container.dispose);

      // UI'ın izlediği saleRepositoryProvider'ı oku
      final saleRepo = await container.read(saleRepositoryProvider.future);
      final allSales = await saleRepo.findAll();

      // ADV-04 DÜZELTME KANITI:
      // UI okuma yolu Core Next veritabanından okuduğu için yeni satış eksiksiz görünür!
      expect(allSales.length, equals(1));
      expect(allSales.first.id, equals('sale-authoritative-1'));
      expect(allSales.first.totalAmount, equals(150.0));
      expect(allSales.first.items.length, equals(1));

      // findById kontrolü
      final singleSale = await saleRepo.findById('sale-authoritative-1');
      expect(singleSale, isNotNull);
      expect(singleSale!.receiptNoOrId, isNotEmpty);
    });
  });
}

extension on SaleEntity {
  String get receiptNoOrId => id;
}
