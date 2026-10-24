// ignore_for_file: avoid_relative_lib_imports
// test/core_next/stage10_8_10_runtime_audit_test.dart
// SERENUT OS — STAGE 10.8.10
// Independent Runtime Audit, Full Data-Flow Verification & Cutover Readiness Gate

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
    tempDir = await Directory.systemTemp.createTemp('serenut_stage10_8_10_');
    legacyDbPath = '${tempDir.path}/legacy_audit.db';
    coreDbPath = '${tempDir.path}/core_audit.db';

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
          CREATE TABLE sale_payments (
            id TEXT PRIMARY KEY,
            sale_id TEXT NOT NULL,
            payment_type TEXT NOT NULL,
            amount REAL NOT NULL,
            amount_minor INTEGER,
            reference_note TEXT,
            status TEXT DEFAULT 'completed',
            created_at TEXT NOT NULL
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
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('STAGE 10.8.10 — INDEPENDENT RUNTIME AUDIT', () {
    test('1. ADV-01 Bağımsız Denetimi: 1., 2. ve 3. Migration In-Place UPSERT ve FK RESTRICT Koruması', () async {
      await legacyDb.insert('categories', {
        'id': 'cat-1',
        'name': 'Gıda',
      });
      await legacyDb.insert('products', {
        'id': 'prod-audit-1',
        'barcode': '869000100',
        'name': 'Organik Zeytinyağı 1L',
        'category_id': 'cat-1',
        'price': 300.0,
        'cost_price': 200.0,
        'vat_rate': 10,
        'stock_quantity': 40.0,
        'unit': 'piece',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // 1. Migration
      final m1 = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(m1.isSuccess, isTrue);

      // Hedefte bu ürüne bağlı satış kaydı aç (FK kısıtını sınamak için)
      await coreDb.db.insert('sales', {
        'id': 'sale-audit-fk-1',
        'receipt_no': 'REC-AUD-1',
        'subtotal_cents': 30000,
        'total_cents': 30000,
        'paid_cents': 30000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_items', {
        'id': 'item-audit-fk-1',
        'sale_id': 'sale-audit-fk-1',
        'product_id': 'prod-audit-1',
        'barcode': '869000100',
        'product_name': 'Organik Zeytinyağı 1L',
        'unit_price_cents': 30000,
        'quantity': 1,
        'vat_rate': 10,
        'total_cents': 30000,
      });

      // Kaynak ürünü güncelle: Fiyat 350 TL, Stok 35, Ad "Organik Zeytinyağı Sızma 1L"
      await legacyDb.update(
        'products',
        {
          'name': 'Organik Zeytinyağı Sızma 1L',
          'price': 350.0,
          'stock_quantity': 35.0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: ['prod-audit-1'],
      );

      // 2. Migration: In-Place UPSERT FK RESTRICT hatası fırlatmamalıdır
      final m2 = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(m2.isSuccess, isTrue);

      final pAfter2 = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-audit-1'])).first;
      expect(pAfter2['name'], equals('Organik Zeytinyağı Sızma 1L'));
      expect(pAfter2['price_cents'], equals(35000));
      expect(pAfter2['stock_quantity'], equals(35));

      final itemsAfter2 = await coreDb.db.query('sale_items', where: 'sale_id = ?', whereArgs: ['sale-audit-fk-1']);
      expect(itemsAfter2.length, equals(1));
      expect(itemsAfter2.first['product_id'], equals('prod-audit-1'));

      // 3. Migration: Tekrar çalıştırma (Idempotency) veri değiştirmemeli
      final m3 = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(m3.isSuccess, isTrue);
      final pAfter3 = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['prod-audit-1'])).first;
      expect(pAfter3['name'], equals('Organik Zeytinyağı Sızma 1L'));
      expect(pAfter3['price_cents'], equals(35000));
    });

    test('2. ADV-02 Bağımsız Denetimi: İade Rollback Idempotency ve Çoklu Kısmi İade', () async {
      // Legacy'de 100 TL'lik satış kaydı
      await legacyDb.insert('sales', {
        'id': 'sale-ref-orig',
        'receipt_no': 'REC-ORIG-100',
        'total_amount': 100.0,
        'paid_amount': 100.0,
        'refunded_amount': 0.0,
        'payment_method': 'cash',
        'status': 'completed',
        'created_at': '2026-10-14T10:00:00Z',
        'updated_at': '2026-10-14T10:00:00Z',
      });

      // Core Next DB'de 40 TL iade oluştur
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

      // 1. Rollback
      final r1 = await ReverseMigrationEngine.rollbackToLegacy(legacyDb: legacyDb, coreDb: coreDb);
      if (!r1.isSuccess) {
        fail('Rollback 1 failed: ${r1.errorMessage}');
      }
      expect(r1.isSuccess, isTrue);

      final s1 = (await legacyDb.query('sales', where: 'id = ?', whereArgs: ['sale-ref-orig'])).first;
      expect((s1['refunded_amount'] as num).toDouble(), equals(40.0));

      // 2. Rollback (Idempotency Kontrolü)
      final r2 = await ReverseMigrationEngine.rollbackToLegacy(legacyDb: legacyDb, coreDb: coreDb);
      if (!r2.isSuccess) {
        fail('Rollback 2 failed: ${r2.errorMessage}');
      }
      expect(r2.isSuccess, isTrue);

      final s2 = (await legacyDb.query('sales', where: 'id = ?', whereArgs: ['sale-ref-orig'])).first;
      expect((s2['refunded_amount'] as num).toDouble(), equals(40.0),
          reason: 'İade rollback tekrar çalıştığında asla 80 TL veya üstüne katlanmamalıdır!');
    });

    test('3. ADV-03 Bağımsız Denetimi: Karma ve Çoklu Ödeme Roundtrip Korunumu', () async {
      // Satış: 50 TL Cash + 30 TL Card + 20 TL onAccount = 100 TL
      await coreDb.db.insert('sales', {
        'id': 'sale-trip-1',
        'receipt_no': 'REC-TRIP-1',
        'subtotal_cents': 10000,
        'total_cents': 10000,
        'paid_cents': 8000,
        'debt_cents': 2000,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'p-trip-1',
        'sale_id': 'sale-trip-1',
        'payment_type': 'cash',
        'amount_cents': 5000,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'p-trip-2',
        'sale_id': 'sale-trip-1',
        'payment_type': 'creditCard',
        'amount_cents': 3000,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'p-trip-3',
        'sale_id': 'sale-trip-1',
        'payment_type': 'onAccount',
        'amount_cents': 2000,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Reverse Rollback: Core Next -> Legacy
      final rev = await ReverseMigrationEngine.rollbackToLegacy(legacyDb: legacyDb, coreDb: coreDb);
      if (!rev.isSuccess) {
        fail('Rollback failed in ADV-03: ${rev.errorMessage}');
      }
      expect(rev.isSuccess, isTrue);

      final legPays = await legacyDb.query('sale_payments', where: 'sale_id = ?', whereArgs: ['sale-trip-1'], orderBy: 'amount DESC');
      expect(legPays.length, equals(3));
      expect(legPays[0]['amount'], equals(50.0));
      expect(legPays[1]['amount'], equals(30.0));
      expect(legPays[2]['amount'], equals(20.0));

      // Core Next DB kayıtlarını temizle ve ileri taşı
      await coreDb.db.delete('sale_payments');
      await coreDb.db.delete('sales');

      final fwd = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(fwd.isSuccess, isTrue);

      final restoredPays = await coreDb.db.query('sale_payments', where: 'sale_id = ?', whereArgs: ['sale-trip-1'], orderBy: 'amount_cents DESC');
      expect(restoredPays.length, equals(3));
      expect(restoredPays[0]['payment_type'], equals('cash'));
      expect(restoredPays[0]['amount_cents'], equals(5000));
      expect(restoredPays[1]['payment_type'], equals('creditCard'));
      expect(restoredPays[1]['amount_cents'], equals(3000));
      expect(restoredPays[2]['payment_type'], equals('onAccount'));
      expect(restoredPays[2]['amount_cents'], equals(2000));
    });

    test('4. ADV-04 Bağımsız Denetimi: CoreNextSaleRepository ve UI Provider Köprüsü', () async {
      // Ürün kaydı ekle (FK kısıtı için)
      await coreDb.db.insert('products', {
        'id': 'p-ba-1',
        'barcode': '869000999',
        'name': 'Test Ürün BA',
        'price_cents': 25000,
        'vat_rate': 20,
        'unit': 'piece',
        'stock_quantity': 10,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Core Next DB'ye bir satış ekle
      await coreDb.db.insert('sales', {
        'id': 'sale-bridge-audit-1',
        'receipt_no': 'REC-BA-1',
        'subtotal_cents': 25000,
        'total_cents': 25000,
        'paid_cents': 25000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_items', {
        'id': 'item-ba-1',
        'sale_id': 'sale-bridge-audit-1',
        'product_id': 'p-ba-1',
        'barcode': '869000999',
        'product_name': 'Test Ürün BA',
        'unit_price_cents': 25000,
        'quantity': 1,
        'vat_rate': 20,
        'total_cents': 25000,
      });

      final container = ProviderContainer(
        overrides: [
          coreNextSaleRepositoryProvider.overrideWithValue(
            CoreNextSaleRepository(coreDb.db),
          ),
        ],
      );
      addTearDown(container.dispose);

      final saleRepo = await container.read(saleRepositoryProvider.future);
      final allSales = await saleRepo.findAll();

      expect(allSales.length, equals(1));
      expect(allSales.first.id, equals('sale-bridge-audit-1'));
      expect(allSales.first.totalAmount, equals(250.0));
      expect(allSales.first.items.length, equals(1));

      final singleSale = await saleRepo.findById('sale-bridge-audit-1');
      expect(singleSale, isNotNull);
      expect(singleSale!.id, equals('sale-bridge-audit-1'));
    });
  });
}
