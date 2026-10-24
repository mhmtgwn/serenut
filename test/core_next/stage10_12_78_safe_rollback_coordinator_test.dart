// test/core_next/stage10_12_78_safe_rollback_coordinator_test.dart
// STAGE 10.12.78: Safe Rollback Coordinator, Guarded Kill-Switch & Reconciliation Tests
// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/infrastructure/migration/cutoff_maintenance_lock.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/safe_rollback_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String legacyDbPath;
  late String targetDbPath;
  late Database legacyDb;
  late CoreAppDatabase coreDb;

  Future<void> setupDatabases() async {
    tempDir = await Directory.systemTemp.createTemp('serenut_rollback_test_');
    legacyDbPath = p.join(tempDir.path, 'legacy_mock.db');
    targetDbPath = p.join(tempDir.path, 'core_mock.db');

    // 1. Legacy Schema & Baseline Data
    legacyDb = await openDatabase(
      legacyDbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            balance REAL NOT NULL DEFAULT 0.0,
            balance_minor INTEGER DEFAULT 0,
            is_active INTEGER DEFAULT 1,
            created_at TEXT,
            updated_at TEXT
          );
        ''');
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            quantity REAL NOT NULL DEFAULT 0.0,
            price REAL NOT NULL DEFAULT 0.0,
            price_minor INTEGER DEFAULT 0,
            barcode TEXT,
            created_at TEXT,
            updated_at TEXT
          );
        ''');
        await db.execute('''
          CREATE TABLE sales (
            id TEXT PRIMARY KEY,
            customer_id TEXT,
            total_amount REAL NOT NULL,
            total_amount_minor INTEGER,
            paid_amount REAL DEFAULT 0.0,
            paid_amount_minor INTEGER DEFAULT 0,
            payment_method TEXT,
            status TEXT,
            receipt_no TEXT,
            refunded_amount REAL DEFAULT 0.0,
            created_at TEXT,
            updated_at TEXT
          );
        ''');
        await db.execute('''
          CREATE TABLE sale_items (
            id TEXT PRIMARY KEY,
            sale_id TEXT,
            product_id TEXT,
            quantity REAL NOT NULL,
            unit_price REAL NOT NULL,
            subtotal REAL NOT NULL,
            created_at TEXT
          );
        ''');
        await db.execute('''
          CREATE TABLE sale_payments (
            id TEXT PRIMARY KEY,
            sale_id TEXT,
            payment_type TEXT,
            amount REAL,
            amount_minor INTEGER,
            reference_note TEXT,
            created_at TEXT
          );
        ''');
        await db.execute('''
          CREATE TABLE refunds (
            id TEXT PRIMARY KEY,
            sale_id TEXT,
            amount REAL,
            refund_method TEXT,
            reason TEXT,
            status TEXT,
            created_at TEXT
          );
        ''');
        await db.execute('''
          CREATE TABLE refund_items (
            id TEXT PRIMARY KEY,
            refund_id TEXT,
            sale_item_id TEXT,
            product_id TEXT,
            quantity REAL,
            unit_refund_amount REAL,
            subtotal REAL
          );
        ''');
        await db.execute('''
          CREATE TABLE financial_transactions (
            id TEXT PRIMARY KEY,
            customer_id TEXT,
            type TEXT,
            amount REAL,
            created_at TEXT
          );
        ''');
        await db.execute('''
          CREATE TABLE customer_installment_plans (
            id TEXT PRIMARY KEY,
            customer_id TEXT,
            total_amount REAL,
            down_payment REAL,
            installment_count INTEGER,
            description TEXT,
            status TEXT,
            created_at TEXT,
            updated_at TEXT,
            is_synced INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0
          );
        ''');
        await db.execute('''
          CREATE TABLE customer_installments (
            id TEXT PRIMARY KEY,
            plan_id TEXT,
            customer_id TEXT,
            installment_no INTEGER,
            amount REAL,
            paid_amount REAL,
            due_date TEXT,
            status TEXT,
            paid_at TEXT,
            financial_transaction_id TEXT,
            created_at TEXT,
            updated_at TEXT,
            is_synced INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0
          );
        ''');
        await db.execute('''
          CREATE TABLE settings (
            id INTEGER PRIMARY KEY,
            business_name TEXT,
            tenant_id TEXT
          );
        ''');
      },
    );

    // Baseline müşteri ve ürün
    await legacyDb.insert('customers', {
      'id': 'cust-01',
      'name': 'Ahmet Yılmaz',
      'balance': 0.0,
      'balance_minor': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    await legacyDb.insert('products', {
      'id': 'prod-01',
      'name': 'Fındık Ezmesi 500g',
      'quantity': 100.0,
      'price': 150.0,
      'price_minor': 15000,
      'barcode': 'BAR-001',
      'created_at': DateTime.now().toIso8601String(),
    });

    // 2. Core Next Schema & Baseline Data
    coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
    await coreDb.db.insert('app_settings', {
      'key': 'tenant_id',
      'value': 'nutopia',
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    await coreDb.db.insert('app_settings', {
      'key': 'business_name',
      'value': 'Nutopia Fındık Değirmeni',
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    await coreDb.db.insert('app_settings', {
      'key': 'legacy_migration_completed',
      'value': 'true',
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    await coreDb.db.insert('customers', {
      'id': 'cust-01',
      'name': 'Ahmet Yılmaz',
      'balance_cents': 0,
      'is_active': 1,
      'is_deleted': 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    await coreDb.db.insert('products', {
      'id': 'prod-01',
      'name': 'Fındık Ezmesi 500g',
      'stock_quantity': 100.0,
      'price_cents': 15000,
      'cost_price_cents': 10000,
      'barcode': 'BAR-001',
      'is_active': 1,
      'is_deleted': 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> tearDownDatabases() async {
    await legacyDb.close();
    await coreDb.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }

  group('STAGE 10.12.78: Güvenli Geri Dönüş Koordinatörü Testleri', () {
    test('1. Yeni Satış/Tahsilat Sonrası Güvenli ve Atomik Geri Dönüş', () async {
      await setupDatabases();
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        PilotCutoverGate.prefKeyKillSwitch: false,
      });
      final prefs = await SharedPreferences.getInstance();

      // Core Next üzerinde yeni bir veresiye satış yapılıyor (1 adet Fındık Ezmesi = 150 TL)
      final saleId = 'core-sale-new-1';
      final saleTime = DateTime.now().millisecondsSinceEpoch;
      await coreDb.db.insert('sales', {
        'id': saleId,
        'customer_id': 'cust-01',
        'receipt_no': 'REC-9001',
        'subtotal_cents': 15000,
        'discount_cents': 0,
        'vat_total_cents': 2500,
        'total_cents': 15000,
        'paid_cents': 5000, // 50 TL peşin, 100 TL veresiye
        'debt_cents': 10000,
        'status': 'COMPLETED',
        'created_at': saleTime,
      });
      await coreDb.db.insert('sale_items', {
        'id': 'item-01',
        'sale_id': saleId,
        'product_id': 'prod-01',
        'barcode': 'BAR-001',
        'product_name': 'Fındık Ezmesi 500g',
        'quantity': 1.0,
        'unit_price_cents': 15000,
        'discount_cents': 0,
        'vat_rate': 20,
        'total_cents': 15000,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'pay-01',
        'sale_id': saleId,
        'payment_type': 'cash',
        'amount_cents': 5000,
        'created_at': saleTime,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'pay-02',
        'sale_id': saleId,
        'payment_type': 'onAccount',
        'amount_cents': 10000,
        'created_at': saleTime,
      });
      // Cari defter kaydı: 100 TL borç
      await coreDb.db.insert('ledger_entries', {
        'id': 'le-01',
        'customer_id': 'cust-01',
        'reference_sale_id': saleId,
        'entry_type': 'SALE',
        'amount_cents': 10000,
        'balance_after_cents': -10000,
        'description': 'Veresiye Satış',
        'created_at': saleTime,
      });
      // Müşteri bakiyesi ve stok güncellendi
      await coreDb.db.update('customers', {'balance_cents': -10000}, where: 'id = ?', whereArgs: ['cust-01']);
      await coreDb.db.update('products', {'stock_quantity': 99.0}, where: 'id = ?', whereArgs: ['prod-01']);

      // Geri dönüşü çalıştır
      final cutoffLock = CutoffMaintenanceLock(
        storage: SharedPreferencesMaintenanceStorage.withInstance(prefs),
      );
      final coordinator = SafeRollbackCoordinator(cutoffLock: cutoffLock);

      final result = await coordinator.executeSafeRollback(
        legacyDb: legacyDb,
        coreDb: coreDb,
        prefs: prefs,
        tenantId: 'nutopia',
      );

      print('ROLLBACK RESULT: isSuccess=${result.isSuccess}, status=${result.status}');
      expect(result.isSuccess, isTrue);
      expect(result.status, equals('completed'));

      // Doğrulama: Legacy DB satış ve kalemleri eksiksiz aldı mı?
      final legSales = await legacyDb.query('sales', where: 'id = ?', whereArgs: [saleId]);
      expect(legSales.length, equals(1));
      expect((legSales.first['total_amount'] as num).toDouble(), equals(150.0));
      expect(legSales.first['payment_method'], equals('mixed')); // Parçalı ödeme

      // Kalemler
      final legItems = await legacyDb.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
      expect(legItems.length, equals(1));

      // Parçalı ödeme tablosu
      final legPayments = await legacyDb.query('sale_payments', where: 'sale_id = ?', whereArgs: [saleId]);
      expect(legPayments.length, equals(2));

      // Cari bakiye güncellendi mi? (-100 TL)
      final legCust = await legacyDb.query('customers', where: 'id = ?', whereArgs: ['cust-01']);
      expect((legCust.first['balance_minor'] as num).toInt(), equals(-10000));

      // Stok güncellendi mi? (99 adet)
      final legProd = await legacyDb.query('products', where: 'id = ?', whereArgs: ['prod-01']);
      expect((legProd.first['quantity'] as num).toDouble(), equals(99.0));

      // SharedPreferences bayrakları
      expect(prefs.getString(SafeRollbackCoordinator.prefKeyRollbackState), equals('completed'));
      expect(prefs.getBool(PilotCutoverGate.prefKeyPilotEnabled), isFalse);
      expect(prefs.getBool(PilotCutoverGate.prefKeyKillSwitch), isTrue);

      await tearDownDatabases();
    });

    test('2. Aktarım Sırasında Hata ve Tekrar Deneme (Resilience & Retry)', () async {
      await setupDatabases();
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        PilotCutoverGate.prefKeyKillSwitch: false,
      });
      final prefs = await SharedPreferences.getInstance();

      final coordinator = SafeRollbackCoordinator();

      // 1. Simüle edilmiş mutabakat hatası ile çalıştırma
      final failResult = await coordinator.executeSafeRollback(
        legacyDb: legacyDb,
        coreDb: coreDb,
        prefs: prefs,
        tenantId: 'nutopia',
        simulateReconciliationFailure: true,
      );

      expect(failResult.isSuccess, isFalse);
      expect(failResult.status, equals('reconciliation_failed'));
      expect(prefs.getString(SafeRollbackCoordinator.prefKeyRollbackState), equals('failed_blocked'));

      // Pilot ve kill-switch bayrakları KESİNLİKLE güvenli olmayan duruma izin vermemeli
      expect(prefs.getBool(PilotCutoverGate.prefKeyKillSwitch), isFalse);

      // 2. Tekrar deneme (Retry) — normal çalışma
      final retryResult = await coordinator.executeSafeRollback(
        legacyDb: legacyDb,
        coreDb: coreDb,
        prefs: prefs,
        tenantId: 'nutopia',
        simulateReconciliationFailure: false,
      );

      expect(retryResult.isSuccess, isTrue);
      expect(retryResult.status, equals('completed'));
      expect(prefs.getString(SafeRollbackCoordinator.prefKeyRollbackState), equals('completed'));
      expect(prefs.getBool(PilotCutoverGate.prefKeyKillSwitch), isTrue);

      await tearDownDatabases();
    });

    test('3. Aynı Geri Dönüşün İki Kez Çağrılması (Idempotency Koruması)', () async {
      await setupDatabases();
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        PilotCutoverGate.prefKeyKillSwitch: false,
      });
      final prefs = await SharedPreferences.getInstance();

      final coordinator = SafeRollbackCoordinator();

      // 1. Çalıştırma
      final res1 = await coordinator.executeSafeRollback(
        legacyDb: legacyDb,
        coreDb: coreDb,
        prefs: prefs,
        tenantId: 'nutopia',
      );
      expect(res1.isSuccess, isTrue);

      final salesCount1 = Sqflite.firstIntValue(await legacyDb.rawQuery('SELECT COUNT(*) FROM sales;'));

      // 2. Çalıştırma
      final res2 = await coordinator.executeSafeRollback(
        legacyDb: legacyDb,
        coreDb: coreDb,
        prefs: prefs,
        tenantId: 'nutopia',
      );
      expect(res2.isSuccess, isTrue);

      final salesCount2 = Sqflite.firstIntValue(await legacyDb.rawQuery('SELECT COUNT(*) FROM sales;'));
      // Mükerrer satış oluşmadı!
      expect(salesCount2, equals(salesCount1));
      expect(res2.migrationReport?.salesExported, equals(0));

      await tearDownDatabases();
    });

    test('4. Finansal Toplam veya Kayıt Uyuşmazlığı Durumunda Durdurma', () async {
      await setupDatabases();
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        PilotCutoverGate.prefKeyKillSwitch: false,
      });
      final prefs = await SharedPreferences.getInstance();

      final coordinator = SafeRollbackCoordinator();

      final res = await coordinator.executeSafeRollback(
        legacyDb: legacyDb,
        coreDb: coreDb,
        prefs: prefs,
        tenantId: 'nutopia',
        simulateReconciliationFailure: true,
      );

      expect(res.isSuccess, isFalse);
      expect(res.status, equals('reconciliation_failed'));
      expect(res.reconciliationReport?.isReconciled, isFalse);

      await tearDownDatabases();
    });

    test('5. Aktarım Başarısızken Legacy Routing Kesinlikle Açılmaz (Fail-Closed)', () async {
      await setupDatabases();
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        PilotCutoverGate.prefKeyKillSwitch: false,
        SafeRollbackCoordinator.prefKeyRollbackState: 'failed_blocked',
      });
      final prefs = await SharedPreferences.getInstance();

      const gate = PilotCutoverGate();
      final eval = await gate.evaluate(
        prefs: prefs,
        legacyDbPath: legacyDbPath,
        targetDbPath: targetDbPath,
        requestedTenantId: 'comp-1785241628448-c7f5677d',
      );

      print('GATE EVAL WITH FAILED ROLLBACK: ${eval.status} | Reason: ${eval.reason}');
      expect(eval.status, equals(PilotGateStatus.blockedUnsafeRollback));
      expect(eval.isPilotActive, isFalse);

      // Guarded kill-switch engellemesi
      final switchTriggered = await PilotCutoverGate.triggerEmergencyKillSwitch(
        prefs,
        requireVerifiedRollback: true,
      );
      expect(switchTriggered, isFalse); // Rollback tamamlanmadığı için kill switch engellendi

      await tearDownDatabases();
    });

    test('6. İade, Senet/Taksit ve İptal Kayıtlarının Eksiksiz Korunması', () async {
      await setupDatabases();
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        PilotCutoverGate.prefKeyKillSwitch: false,
      });
      final prefs = await SharedPreferences.getInstance();

      final time = DateTime.now().millisecondsSinceEpoch;

      // 1. İade Kaydı (Negatif Satış)
      await coreDb.db.insert('sales', {
        'id': 'core-refund-1',
        'customer_id': 'cust-01',
        'receipt_no': 'REF-9001',
        'subtotal_cents': -5000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': -5000, // 50 TL İade
        'paid_cents': -5000,
        'debt_cents': 0,
        'status': 'REFUND',
        'created_at': time,
      });
      await coreDb.db.insert('sale_items', {
        'id': 'ref-item-1',
        'sale_id': 'core-refund-1',
        'product_id': 'prod-01',
        'barcode': 'BAR-001',
        'product_name': 'Fındık Ezmesi 500g',
        'quantity': -1.0,
        'unit_price_cents': 5000,
        'discount_cents': 0,
        'vat_rate': 20,
        'total_cents': -5000,
      });
      // İade ile stok 1 adet arttı (100 -> 101)
      await coreDb.db.update('products', {'stock_quantity': 101.0}, where: 'id = ?', whereArgs: ['prod-01']);

      // 2. Senet/Taksit Planı (customer_installment_plans & customer_installments)
      await coreDb.db.insert('customer_installment_plans', {
        'id': 'plan-core-1',
        'customer_id': 'cust-01',
        'total_amount_cents': 60000, // 600 TL
        'down_payment_cents': 10000, // 100 TL peşinat
        'installment_count': 2,
        'description': 'Yeni Çeyiz Senet Sözleşmesi',
        'status': 'active',
        'created_at': time,
        'updated_at': time,
      });
      await coreDb.db.insert('customer_installments', {
        'id': 'inst-c-1',
        'plan_id': 'plan-core-1',
        'customer_id': 'cust-01',
        'installment_no': 1,
        'amount_cents': 25000,
        'paid_amount_cents': 0,
        'due_date': time + 86400000 * 30,
        'status': 'pending',
        'created_at': time,
        'updated_at': time,
      });
      await coreDb.db.insert('customer_installments', {
        'id': 'inst-c-2',
        'plan_id': 'plan-core-1',
        'customer_id': 'cust-01',
        'installment_no': 2,
        'amount_cents': 25000,
        'paid_amount_cents': 0,
        'due_date': time + 86400000 * 60,
        'status': 'pending',
        'created_at': time,
        'updated_at': time,
      });

      final coordinator = SafeRollbackCoordinator();
      final res = await coordinator.executeSafeRollback(
        legacyDb: legacyDb,
        coreDb: coreDb,
        prefs: prefs,
        tenantId: 'nutopia',
      );

      print('TEST 6 RESULT: status=${res.status}, error=${res.errorMessage}');
      expect(res.isSuccess, isTrue, reason: res.errorMessage);

      // İade legacy refunds tablosuna yazıldı mı?
      final refunds = await legacyDb.query('refunds', where: 'id = ?', whereArgs: ['core-refund-1']);
      expect(refunds.length, equals(1));
      expect((refunds.first['amount'] as num).toDouble(), equals(50.0));

      // Senet planı aktarıldı mı?
      final legPlan = await legacyDb.query('customer_installment_plans', where: 'id = ?', whereArgs: ['plan-core-1']);
      expect(legPlan.length, equals(1));
      expect((legPlan.first['total_amount'] as num).toDouble(), equals(600.0));
      expect((legPlan.first['down_payment'] as num).toDouble(), equals(100.0));

      // Taksit kalemleri aktarıldı mı?
      final legInsts = await legacyDb.query('customer_installments', where: 'plan_id = ?', whereArgs: ['plan-core-1']);
      expect(legInsts.length, equals(2));

      await tearDownDatabases();
    });
  });
}
