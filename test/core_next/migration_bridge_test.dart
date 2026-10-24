// test/core_next/migration_bridge_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

import 'dart:io';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late CoreAppDatabase coreDb;
  late Database legacyDb;
  late MigrationBridgeEngine bridgeEngine;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bridge_test_');

    // 1. Yeni hedef veritabanını temiz dosyada aç
    final coreDbPath = '${tempDir.path}/core.db';
    coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: coreDbPath);
    bridgeEngine = MigrationBridgeEngine(coreDb);

    // 2. Eski veritabanını (v60 taklidi) ayrı dosyada oluştur
    final legacyDbPath = '${tempDir.path}/legacy.db';
    legacyDb = await openDatabase(
      legacyDbPath,
      version: 1,
      onCreate: (db, version) async {
        // Eski 'products' tablosu (double price ve double quantity)
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

        // Eski 'customers' tablosu (double balance ve v60 minor columns)
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

      },
    );
  });

  tearDown(() async {
    await legacyDb.close();
    await coreDb.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('MigrationBridgeEngine (Eski SQLite -> Yeni Kuruş Şeması) Tests', () {
    test('Eski tablolardaki double fiyat ve bakiyeler kuruş tamsayısına kayıpsız dönüştürülmelidir', () async {
      // Eski verileri ekle
      await legacyDb.insert('products', {
        'id': 'legacy-p1',
        'barcode': '8690123456789',
        'name': 'Organik Zeytinyağı 1L',
        'price': 249.99, // 249,99 TL -> 24999 kuruş olmalı
        'cost_price': 180.50, // 180,50 TL -> 18050 kuruş
        'vat_rate': 10,
        'quantity': 25.0,
      });

      await legacyDb.insert('customers', {
        'id': 'legacy-c1',
        'name': 'Fatma Hanım (Veresiye)',
        'phone': '05559876543',
        'balance': -175.50, // -175,50 TL Borç -> -17550 kuruş olmalı
      });

      // Geçiş öncesi kontrol
      expect(await bridgeEngine.isMigrationCompleted(), false);

      // Migrasyonu çalıştır
      final report = await bridgeEngine.migrateFromLegacy(legacyDb);

      expect(report.isSuccess, true);
      expect(report.productsMigrated, 1);
      expect(report.customersMigrated, 1);
      expect(await bridgeEngine.isMigrationCompleted(), true);

      // Yeni veritabanını doğrula
      final newProducts = await coreDb.db.query('products');
      expect(newProducts.length, 1);
      expect(newProducts.first['price_cents'], 24999);
      expect(newProducts.first['cost_price_cents'], 18050);
      expect(newProducts.first['stock_quantity'], 25);

      final newCustomers = await coreDb.db.query('customers');
      expect(newCustomers.length, 1);
      expect(newCustomers.first['balance_cents'], -17550);

      // İdempotency Testi: Migrasyon ikinci kez çalıştırıldığında hata vermemeli ve veri bozulmamalı
      final secondReport = await bridgeEngine.migrateFromLegacy(legacyDb);
      expect(secondReport.isSuccess, true);
      expect(secondReport.productsMigrated, 1);
      expect(secondReport.customersMigrated, 1);

      final recheckedCustomers = await coreDb.db.query('customers');
      expect(recheckedCustomers.length, 1);
      expect(recheckedCustomers.first['balance_cents'], -17550);
    });

    test('Bayat balance_minor değeri yetkili bakiye ile uyuşmadığında fark listelenmeli ve yetkili bakiye aktarılmalıdır', () async {
      await legacyDb.insert('customers', {
        'id': 'legacy-stale-c1',
        'name': 'Ahmet Bey',
        'balance': -2266.68, // Yetkili defter bakiyesi: -226668 kuruş (Borç)
        'balance_minor': 93332, // Bayat trigger değeri: +93332 kuruş (Alacak)
      });

      final report = await bridgeEngine.migrateFromLegacy(legacyDb);
      expect(report.isSuccess, true);
      expect(report.customerDiscrepancies.length, 1);

      final discrepancy = report.customerDiscrepancies.first;
      expect(discrepancy.customerId, 'legacy-stale-c1');
      expect(discrepancy.authoritativeBalanceCents, -226668);
      expect(discrepancy.staleMinorCents, 93332);
      expect(discrepancy.discrepancyCents, 320000); // 3.200 TL fark yakalandı!

      // Yeni veritabanında bayat değer yerine YETKİLİ bakiye (-226668) kaydedilmiş olmalıdır
      final rows = await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['legacy-stale-c1']);
      expect(rows.first['balance_cents'], -226668);
    });

    test('Defter görünümü ile customers.balance arasında beklenmeyen sapma varsa migrasyon durdurulmalıdır', () async {
      // Defter görünümü oluştur
      await legacyDb.execute('''
        CREATE VIEW v_customer_ledger_effect AS
        SELECT 'legacy-corrupt-c1' as customer_id, -500.00 as balance_effect;
      ''');

      // customers tablosunda balance defterle uyuşmasın (-100 TL kayıtlı, ama defterde -500 TL var)
      await legacyDb.insert('customers', {
        'id': 'legacy-corrupt-c1',
        'name': 'Uyuşmaz Müşteri',
        'balance': -100.00,
      });

      final report = await bridgeEngine.migrateFromLegacy(legacyDb);
      expect(report.isSuccess, false);
      expect(report.errorMessage, contains('MÜŞTERİ BAKİYE SAPMASI TESPİT EDİLDİ'));
    });

    test('Eski satışlar aktarıldığında idempotency_key ve sale_payments kayıtları kuruşu kuruşuna oluşturulmalıdır', () async {
      await legacyDb.execute('''
        CREATE TABLE sales (
          id TEXT PRIMARY KEY,
          receipt_no TEXT,
          customer_id TEXT,
          total_amount REAL,
          paid_amount REAL,
          discount_amount REAL,
          payment_method TEXT,
          status TEXT,
          idempotency_key TEXT,
          created_at TEXT
        );
      ''');

      await legacyDb.insert('sales', {
        'id': 'sale-legacy-test-1',
        'receipt_no': 'FIS-LEG-001',
        'customer_id': null,
        'total_amount': 150.0,
        'paid_amount': 100.0,
        'discount_amount': 0.0,
        'payment_method': 'credit_card',
        'status': 'completed',
        'idempotency_key': 'idemp-leg-key-001',
        'created_at': DateTime.now().toIso8601String(),
      });

      final report = await bridgeEngine.migrateFromLegacy(legacyDb);
      expect(report.isSuccess, true);
      expect(report.salesMigrated, 1);

      // Yeni Core DB sales tablosunu doğrula
      final salesRows = await coreDb.db.query('sales', where: 'id = ?', whereArgs: ['sale-legacy-test-1']);
      expect(salesRows.length, 1);
      expect(salesRows.first['idempotency_key'], 'idemp-leg-key-001');
      expect(salesRows.first['total_cents'], 15000);
      expect(salesRows.first['paid_cents'], 10000);
      expect(salesRows.first['debt_cents'], 5000);

      // Yeni Core DB sale_payments tablosunu doğrula
      final paymentRows = await coreDb.db.query(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: ['sale-legacy-test-1'],
        orderBy: 'amount_cents DESC',
      );
      expect(paymentRows.length, 2);
      expect(paymentRows[0]['payment_type'], 'creditCard');
      expect(paymentRows[0]['amount_cents'], 10000);
      expect(paymentRows[1]['payment_type'], 'onAccount');
      expect(paymentRows[1]['amount_cents'], 5000);
    });

    test('Eski satışta tahsilat toplam tutarı aştığında migrasyon güvenle durdurulmalıdır (Reconciliation Failure)', () async {
      await legacyDb.execute('''
        CREATE TABLE IF NOT EXISTS sales (
          id TEXT PRIMARY KEY,
          receipt_no TEXT,
          customer_id TEXT,
          total_amount REAL,
          paid_amount REAL,
          discount_amount REAL,
          payment_method TEXT,
          status TEXT,
          idempotency_key TEXT,
          created_at TEXT
        );
      ''');

      // 100 TL satış ama 150 TL tahsilat (matematiksel tutarsızlık)
      await legacyDb.insert('sales', {
        'id': 'sale-invalid-bal-1',
        'receipt_no': 'FIS-INV-001',
        'customer_id': null,
        'total_amount': 100.0,
        'paid_amount': 150.0,
        'payment_method': 'cash',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
      });

      final report = await bridgeEngine.migrateFromLegacy(legacyDb);
      expect(report.isSuccess, false);
      expect(report.errorMessage, contains('GEÇMİŞ SATIŞ MUTABAKAT HATASI'));
    });

    test('Eski karma ödeme aktarılırken sahte nakit/kart tahmini üretilmemeli, denetlenebilir "mixed" türüyle kaydedilmelidir', () async {
      await legacyDb.execute('''
        CREATE TABLE IF NOT EXISTS sales (
          id TEXT PRIMARY KEY,
          receipt_no TEXT,
          customer_id TEXT,
          total_amount REAL,
          paid_amount REAL,
          discount_amount REAL,
          payment_method TEXT,
          status TEXT,
          idempotency_key TEXT,
          created_at TEXT
        );
      ''');

      await legacyDb.insert('sales', {
        'id': 'sale-legacy-mixed-1',
        'receipt_no': 'FIS-MIX-001',
        'customer_id': null,
        'total_amount': 200.0,
        'paid_amount': 200.0,
        'payment_method': 'karma_odeme', // Geçmişte detay tablosu tutulmayan karma ödeme
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
      });

      final report = await bridgeEngine.migrateFromLegacy(legacyDb);
      expect(report.isSuccess, true);

      final payments = await coreDb.db.query(
        'sale_payments',
        where: 'sale_id = ?',
        whereArgs: ['sale-legacy-mixed-1'],
      );
      expect(payments.length, 1);
      expect(payments.first['payment_type'], 'mixed');
      expect(payments.first['amount_cents'], 20000);
      expect(payments.first['reference_note'], contains('Tarihsel Parçalı Kırılım Bilinmiyor'));
    });
  });
}

