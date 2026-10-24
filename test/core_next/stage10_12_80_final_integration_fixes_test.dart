// test/core_next/stage10_12_80_final_integration_fixes_test.dart
// SERENUT OS — STAGE 10.12.80
// ÜÇ SOMUT ENGELİN HEDEFLİ DOĞRULAMA VE ENTEGRASYON TESTLERİ

import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/infrastructure/migration/cutoff_maintenance_lock.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';
import '../../core_next/client_core/lib/infrastructure/migration/safe_rollback_coordinator.dart' as core_rollback;
import '../../core_next/client_core/lib/presentation/sales/sales_engine_adapter.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('STAGE 10.12.80: Üç Somut Engel Düzeltmeleri ve Hedefli Testler', () {
    late Directory tempDir;
    late String legacyDbPath;
    late String targetDbPath;
    late Database legacyDb;
    late CoreAppDatabase coreAppDb;
    late SharedPreferences prefs;

    Map<String, dynamic> makeCoreProduct({
      required String id,
      required String name,
      required String barcode,
      required int priceCents,
      required double stockQuantity,
      int? updatedAt,
    }) {
      return {
        'id': id,
        'name': name,
        'barcode': barcode,
        'price_cents': priceCents,
        'stock_quantity': stockQuantity,
        'updated_at': updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      };
    }

    Map<String, dynamic> makeCoreSale({
      required String id,
      required String receiptNo,
      required int totalCents,
      required int paidCents,
      required String status,
      required int createdAt,
      int? subtotalCents,
    }) {
      return {
        'id': id,
        'receipt_no': receiptNo,
        'total_cents': totalCents,
        'subtotal_cents': subtotalCents ?? totalCents,
        'paid_cents': paidCents,
        'status': status,
        'created_at': createdAt,
      };
    }
    Map<String, dynamic> makeCoreSaleItem({
      required String id,
      required String saleId,
      required String productId,
      required String barcode,
      required String productName,
      required int unitPriceCents,
      required double quantity,
      int totalCents = 0,
      int discountCents = 0,
      int vatRate = 0,
    }) {
      return {
        'id': id,
        'sale_id': saleId,
        'product_id': productId,
        'barcode': barcode,
        'product_name': productName,
        'unit_price_cents': unitPriceCents,
        'quantity': quantity,
        'discount_cents': discountCents,
        'vat_rate': vatRate,
        'total_cents': totalCents == 0 ? (unitPriceCents * quantity).round() : totalCents,
      };
    }

    Map<String, dynamic> makeCoreSalePayment({
      required String id,
      required String saleId,
      required String paymentType,
      required int amountCents,
      int? createdAt,
      String? referenceNote,
    }) {
      return {
        'id': id,
        'sale_id': saleId,
        'payment_type': paymentType,
        'amount_cents': amountCents,
        'reference_note': referenceNote,
        'created_at': createdAt ?? DateTime.now().millisecondsSinceEpoch,
      };
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();

      // PilotCutoverGate çalışma zamanı geri dönüş koşucusunu SafeRollbackCoordinator'a bağla
      PilotCutoverGate.safeRollbackRunner = core_rollback.SafeRollbackCoordinator.runRollback;

      tempDir = Directory.systemTemp.createTempSync('stage80_fixes_');
      legacyDbPath = p.join(tempDir.path, 'legacy_mock.db');
      targetDbPath = p.join(tempDir.path, 'core_mock.db');

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
            CREATE TABLE app_settings (
              key TEXT PRIMARY KEY,
              value TEXT,
              updated_at INTEGER
            );
          ''');
        },
      );

      // Core Next veritabanını standart temiz şema ile aç
      coreAppDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      await coreAppDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': 'nutopia',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreAppDb.db.insert('app_settings', {
        'key': 'business_name',
        'value': 'Nutopia Fındık Değirmeni',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      await legacyDb.close();
      await coreAppDb.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    // ── 1. TEST: İptal Edilmiş Satışın Stok Hesabı ─────────────────────────────
    test('1. CANCELLED durumundaki satış ürün stoklarını ikinci kez eksiltmez', () async {
      // Başlangıç: Legacy'de 100 adet stok var
      await legacyDb.insert('products', {
        'id': 'prod_nut_1',
        'name': 'Fındık Ezmesi',
        'price': 150.0,
        'quantity': 100.0,
      });

      // Core Next'te: 100 adet stokla başladı
      // 1 tane COMPLETED satış yapıldı (5 adet satıldı -> stok 95 oldu)
      // 1 tane CANCELLED satış yapıldı (10 adetlik sepetti ama iptal edildi, stoğu etkilemedi -> stok 95 kaldı)
      await coreAppDb.db.insert(
        'products',
        makeCoreProduct(
          id: 'prod_nut_1',
          name: 'Fındık Ezmesi',
          barcode: 'BAR-NUT-1',
          priceCents: 15000,
          stockQuantity: 95.0,
        ),
      );

      final now = DateTime.now().millisecondsSinceEpoch;

      // Normal Satış (5 adet)
      await coreAppDb.db.insert(
        'sales',
        makeCoreSale(
          id: 'sale_completed_1',
          receiptNo: 'RCP-COMP-1',
          totalCents: 75000,
          paidCents: 75000,
          status: 'completed',
          createdAt: now,
        ),
      );
      await coreAppDb.db.insert(
        'sale_items',
        makeCoreSaleItem(
          id: 'item_comp_1',
          saleId: 'sale_completed_1',
          productId: 'prod_nut_1',
          barcode: 'BAR-NUT-1',
          productName: 'Fındık Ezmesi',
          unitPriceCents: 15000,
          quantity: 5.0,
          totalCents: 75000,
        ),
      );

      // İptal Satış (10 adet - CANCELLED)
      await coreAppDb.db.insert(
        'sales',
        makeCoreSale(
          id: 'sale_cancelled_1',
          receiptNo: 'RCP-CANC-1',
          totalCents: 150000,
          paidCents: 0,
          status: 'CANCELLED',
          createdAt: now + 10,
        ),
      );
      await coreAppDb.db.insert(
        'sale_items',
        makeCoreSaleItem(
          id: 'item_canc_1',
          saleId: 'sale_cancelled_1',
          productId: 'prod_nut_1',
          barcode: 'BAR-NUT-1',
          productName: 'Fındık Ezmesi',
          unitPriceCents: 15000,
          quantity: 10.0,
          totalCents: 150000,
        ),
      );

      // Tersine aktarımı işlet
      final report = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreAppDb,
      );

      expect(report.isSuccess, isTrue, reason: 'Rollback hatasız tamamlanmalı: ${report.errorMessage}');

      // Doğrulama: Legacy products quantity değeri tam olarak 95.0 olmalıdır!
      // (Eğer CANCELLED satışı da stoktan düşseydi 100 - 5 - 10 = 85 baseline çatışması verirdi)
      final prodRows = await legacyDb.query('products', where: 'id = ?', whereArgs: ['prod_nut_1']);
      expect(prodRows.first['quantity'], equals(95.0));

      // Satışlar tablosunda iptal kaydı 'CANCELLED' olarak görünmeli
      final cancRows = await legacyDb.query('sales', where: 'id = ?', whereArgs: ['sale_cancelled_1']);
      expect(cancRows.isNotEmpty, isTrue);
      expect(cancRows.first['status'], equals('CANCELLED'));
    });

    // ── 2. TEST: Kilitliyken Core Next Checkout Engeli ─────────────────────────
    test('2. CutoffMaintenanceLock locked veya draining durumundayken Core Next checkout engellenir', () async {
      final lock = CutoffMaintenanceLock();
      final adapter = SalesEngineAdapter(
        initialUseCoreNext: true,
        cutoffLock: lock,
      );

      // Kilit açıkken: normal kural (notifier yoksa failure döner, yani kilit engelini geçti)
      final openRes = await adapter.executeCheckout(
        receiptNo: 'RCP-001',
        storeTitle: 'Nutopia',
      );
      expect(openRes.isSuccess, isFalse);
      expect(openRes.errorMessage, contains('notifier'));

      // Kilidi al (locked yap)
      final locked = await lock.acquireLock(tenantId: 'nutopia');
      expect(locked, isTrue);
      expect(lock.state.isWritePermitted, isFalse);

      // Artık CutoffMaintenanceActiveException fırlatılmalıdır!
      expect(
        () => adapter.executeCheckout(
          receiptNo: 'RCP-002',
          storeTitle: 'Nutopia',
        ),
        throwsA(isA<CutoffMaintenanceActiveException>()),
      );
    });

    // ── 3. TEST: Devam Eden Checkout ile Rollback Yarışı (Drain) ────────────────
    test('3. Devam eden Core Next checkout işlemi bitmeden acquireLock drain tamamlanmaz', () async {
      final lock = CutoffMaintenanceLock();
      final adapter = SalesEngineAdapter(
        initialUseCoreNext: false, // Legacy executor kullanarak gecikmeli checkout simüle ediyoruz
        cutoffLock: lock,
      );

      final checkoutCompleter = Completer<void>();
      bool checkoutFinished = false;

      // Gecikmeli bir checkout başlatıyoruz
      final checkoutFuture = adapter.executeCheckout(
        receiptNo: 'RCP-ASYNC',
        storeTitle: 'Nutopia',
        legacyExecute: () async {
          await checkoutCompleter.future;
          checkoutFinished = true;
          return {'id': 'sale_async'};
        },
      );

      // Kilit henüz alınmadan önce in-flight count 1 olmalı
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(lock.drainer.inFlightCount, equals(1));

      // Kilit alma isteği başlatıyoruz (drain bekleyecek)
      final lockFuture = lock.acquireLock(
        tenantId: 'nutopia',
        timeout: const Duration(seconds: 2),
      );

      // Kilit henüz tamamlanmamış olmalı çünkü checkout hala sürüyor
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(lock.drainer.inFlightCount, equals(1));
      expect(checkoutFinished, isFalse);

      // Checkout'u tamamlatıyoruz
      checkoutCompleter.complete();
      await checkoutFuture;
      expect(checkoutFinished, isTrue);

      // Artık drain tamamlanmalı ve kilit güvenle alınmalı
      final lockAcquired = await lockFuture;
      expect(lockAcquired, isTrue);
      expect(lock.drainer.inFlightCount, equals(0));
      expect(lock.isSafeForSnapshot, isTrue);
    });

    // ── 4. TEST: PilotCutoverGate Üzerinden Güvenli Rollback & Kill Switch ──────
    test('4. PilotCutoverGate.triggerSafeRollbackAndKillSwitch başarılı rollback sonrası kill-switchi açar', () async {
      // Core Next'e yeni bir satış ekle
      final now = DateTime.now().millisecondsSinceEpoch;
      await coreAppDb.db.insert(
        'sales',
        makeCoreSale(
          id: 'sale_rt_1',
          receiptNo: 'RCP-RT-1',
          totalCents: 5000,
          paidCents: 5000,
          status: 'completed',
          createdAt: now,
        ),
      );
      await coreAppDb.db.insert(
        'sale_payments',
        makeCoreSalePayment(
          id: 'pay_rt_1',
          saleId: 'sale_rt_1',
          paymentType: 'cash',
          amountCents: 5000,
          createdAt: now,
        ),
      );

      final lock = CutoffMaintenanceLock();

      final result = await PilotCutoverGate.triggerSafeRollbackAndKillSwitch(
        prefs: prefs,
        legacyDb: legacyDb,
        coreDb: coreAppDb,
        tenantId: 'nutopia',
        cutoffLock: lock,
      );

      expect(result.isSuccess, isTrue, reason: 'Rollback başarılı olmalı: ${result.errorMessage}');
      expect(result.status, equals('completed'));
      expect(prefs.getBool(PilotCutoverGate.prefKeyKillSwitch), isTrue);
      expect(prefs.getString(core_rollback.SafeRollbackCoordinator.prefKeyRollbackState), equals('completed'));

      // Legacy DB'ye aktarıldı mı?
      final legSales = await legacyDb.query('sales', where: 'id = ?', whereArgs: ['sale_rt_1']);
      expect(legSales.length, equals(1));
    });

    // ── 5. TEST: Rollback Hatasında Legacy Routing Asla Açılmaz ─────────────────
    test('5. Rollback mutabakat hatasında kill-switch KESİNLİKLE açılmaz (Fail-Closed)', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await coreAppDb.db.insert(
        'sales',
        makeCoreSale(
          id: 'sale_fail_1',
          receiptNo: 'RCP-FAIL-1',
          totalCents: 10000,
          paidCents: 10000,
          status: 'completed',
          createdAt: now,
        ),
      );

      // Legacy DB'de aynı ID'li satış farklı bir tutarla var olsun (içerik çatışması üretmek için)
      await legacyDb.insert('sales', {
        'id': 'sale_fail_1',
        'customer_id': 'cust_default',
        'total_amount': 999.0, // 999 TL != 100 TL
        'payment_method': 'cash',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
      });

      final lock = CutoffMaintenanceLock();

      final result = await PilotCutoverGate.triggerSafeRollbackAndKillSwitch(
        prefs: prefs,
        legacyDb: legacyDb,
        coreDb: coreAppDb,
        tenantId: 'nutopia',
        cutoffLock: lock,
      );

      // Sonuç başarısız olmalı
      expect(result.isSuccess, isFalse);
      expect(result.status, equals('transfer_failed'));

      // KESİN GÜVENLİK SINIRI: Kill switch kesinlikle açılmamalıdır!
      expect(prefs.getBool(PilotCutoverGate.prefKeyKillSwitch), isNull);
      expect(prefs.getString(core_rollback.SafeRollbackCoordinator.prefKeyRollbackState), equals('failed_blocked'));

      // Gate evaluate fail-closed davranmalı
      final gateResult = await const PilotCutoverGate().evaluate(
        prefs: prefs,
        requestedTenantId: 'nutopia',
      );
      expect(gateResult.status, equals(PilotGateStatus.blockedUnsafeRollback));
      expect(gateResult.isPilotActive, isFalse);
    });

    // ── 6. TEST: in_progress Durumunda Güvenli Kurtarma ─────────────────────────
    test('6. in_progress çökme durumunda recoverPendingRollback idempotent olarak tamamlar ve kurtarır', () async {
      // Çökme durumunu simüle et: prefs'te 'in_progress' kalmış
      await prefs.setString(core_rollback.SafeRollbackCoordinator.prefKeyRollbackState, 'in_progress');

      // Gate başlangıçta fail-closed kilitli olmalı
      final initialEval = await const PilotCutoverGate().evaluate(
        prefs: prefs,
        requestedTenantId: 'nutopia',
      );
      expect(initialEval.status, equals(PilotGateStatus.blockedUnsafeRollback));

      // Core Next'e 1 satış ekle
      final now = DateTime.now().millisecondsSinceEpoch;
      await coreAppDb.db.insert(
        'sales',
        makeCoreSale(
          id: 'sale_recover_1',
          receiptNo: 'RCP-REC-1',
          totalCents: 2500,
          paidCents: 2500,
          status: 'completed',
          createdAt: now,
        ),
      );

      // Kurtarma akışını işlet
      final recoveryResult = await PilotCutoverGate.recoverPendingRollback(
        prefs: prefs,
        legacyDb: legacyDb,
        coreDb: coreAppDb,
        tenantId: 'nutopia',
      );

      expect(recoveryResult.isSuccess, isTrue, reason: 'Kurtarma başarılı olmalı: ${recoveryResult.errorMessage}');
      expect(recoveryResult.status, equals('completed'));
      expect(prefs.getString(core_rollback.SafeRollbackCoordinator.prefKeyRollbackState), equals('completed'));
      expect(prefs.getBool(PilotCutoverGate.prefKeyKillSwitch), isTrue);

      // Kurtarma sonrası satış legacy DB'ye geçmiş olmalı
      final legSales = await legacyDb.query('sales', where: 'id = ?', whereArgs: ['sale_recover_1']);
      expect(legSales.length, equals(1));
    });
  });
}
