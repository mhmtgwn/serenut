// test/core_next/stage10_12_45_automatic_cutover_integration_test.dart
// SERENUT OS — STAGE 10.12.45
// Otomatik Geçişin Entegrasyonu ve Canlı Veri Güvenliği Denetimi Test Paketi

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/infrastructure/bootstrap/app_bootstrap.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/database/legacy_database_retirement_policy.dart';
import '../../core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('SERENUT OS — STAGE 10.12.45 INTEGRATION & SAFETY AUDIT SUITE', () {
    late Directory tempDir;
    late String legacyDbPath;
    late String targetDbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('serenut_stage45_test_');
      legacyDbPath = '${tempDir.path}/legacy_pos.db';
      targetDbPath = '${tempDir.path}/serenut_core_v2.db';
      SharedPreferences.setMockInitialValues({});
      CoreNextBootstrapCoordinator.resetExecutionLock();
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    // ──────────────────────────────────────────────────────────────────────────
    // GRUP 1: Güvenlik Değişmezleri (Invariants)
    // ──────────────────────────────────────────────────────────────────────────
    test('1.1: coreNextSalesEngineEnabledProvider = false ve databaseRoutingHook = null değişmezdir', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse,
          reason: 'Canlı güvenlik kuralı: Satış motoru üretimde varsayılan olarak kapalıdır.');
      expect(DatabaseManager.databaseRoutingHook, isNull,
          reason: 'Canlı güvenlik kuralı: Routing hook varsayılan olarak null kalmalıdır.');
    });

    // ──────────────────────────────────────────────────────────────────────────
    // GRUP 2: Bootstrap ve Catch-Up Koordinatörünün Gerçek Entegrasyonu
    // ──────────────────────────────────────────────────────────────────────────
    test('2.1: AppBootstrap ve CoreNextBootstrapCoordinator, Catch-Up Runner ile otonom olarak uçtan uca çalışır', () async {
      final prefs = await SharedPreferences.getInstance();

      // Legacy DB oluştur
      final legDb = await databaseFactory.openDatabase(
        legacyDbPath,
        options: OpenDatabaseOptions(
          version: 60,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, barcode TEXT, name TEXT, price REAL, stock_quantity REAL, created_at TEXT, updated_at TEXT);');
            await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT, phone TEXT, balance REAL, created_at TEXT, updated_at TEXT);');
            await db.execute('CREATE TABLE sales (id TEXT PRIMARY KEY, receipt_number TEXT, customer_id TEXT, total_amount REAL, total_amount_minor INTEGER, payment_method TEXT, cashier_name TEXT, created_at TEXT, status TEXT);');
            await db.execute('CREATE TABLE sale_items (id TEXT PRIMARY KEY, sale_id TEXT, product_id TEXT, product_name TEXT, quantity REAL, unit_price REAL, subtotal REAL, created_at TEXT);');
            await db.execute('CREATE TABLE financial_transactions (id TEXT PRIMARY KEY, customer_id TEXT, type TEXT, amount REAL, reference_id TEXT, description TEXT, created_at TEXT);');

            await db.insert('products', {
              'id': 'p1',
              'barcode': '111',
              'name': 'Fındık 500g',
              'price': 150.0,
              'stock_quantity': 100.0,
              'created_at': '2026-10-20T08:00:00.000',
              'updated_at': '2026-10-20T08:00:00.000',
            });
            await db.insert('customers', {
              'id': 'c1',
              'name': 'Örnek Müşteri',
              'phone': '05551234567',
              'balance': 0.0,
              'created_at': '2026-10-20T08:00:00.000',
              'updated_at': '2026-10-20T08:00:00.000',
            });
          },
        ),
      );

      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);

      try {
        final coordinator = CoreNextBootstrapCoordinator(
          prefs: prefs,
          customLegacyDb: legDb,
          customTargetDb: coreDb.db,
          customLegacyFilePath: legacyDbPath,
          customBackupDirectory: tempDir.path,
          autonomousMode: true,
          migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = false}) async {
            // İlk aktarım: temel ürün ve cari kaydı
            await targetDb.execute('''
              INSERT OR IGNORE INTO products (id, barcode, name, price_cents, stock_quantity, updated_at)
              VALUES ('p1', '111', 'Fındık 500g', 15000, 100.0, 1000);
            ''');
            await targetDb.execute('''
              INSERT OR IGNORE INTO customers (id, name, balance_cents, updated_at)
              VALUES ('c1', 'Örnek Müşteri', 0, 1000);
            ''');
            return true;
          },
          catchUpRunner: ({required legacyDb, required targetDb, required legacyDbPath, cutoffTimestamp}) async {
            final catchUpCoordinator = const LiveSafeCatchUpReconciliationCoordinator();
            final coreAppDb = CoreAppDatabase(targetDb);
            final report = await catchUpCoordinator.performCatchUpAndReconcile(
              legacyDb: legacyDb,
              targetCoreDb: coreAppDb,
              legacyDbPath: legacyDbPath,
              lastMigrationCutoffTimestamp: cutoffTimestamp,
              persistCutoverStatus: true,
            );
            return report.decision == CutoverReconciliationDecision.cutoverApproved;
          },
        );

        // Canlı işletme devam ederken ara dönemde yeni bir satış ve stok düşümü gerçekleşir
        await legDb.insert('sales', {
          'id': 'sale_live_01',
          'receipt_number': 'REC-001',
          'customer_id': 'c1',
          'total_amount': 150.0,
          'total_amount_minor': 15000,
          'payment_method': 'cash',
          'cashier_name': 'Kasiyer 1',
          'created_at': DateTime.now().toIso8601String(),
          'status': 'COMPLETED',
        });
        await legDb.insert('sale_items', {
          'id': 'item_live_01',
          'sale_id': 'sale_live_01',
          'product_id': 'p1',
          'product_name': 'Fındık 500g',
          'quantity': 1.0,
          'unit_price': 150.0,
          'subtotal': 150.0,
          'created_at': DateTime.now().toIso8601String(),
        });
        await legDb.update('products', {
          'stock_quantity': 99.0,
          'updated_at': DateTime.now().toIso8601String(),
        }, where: 'id = ?', whereArgs: ['p1']);

        // Koordinatör çalıştırılır (Uygulama açılış simülasyonu)
        final result = await coordinator.coordinate();

        expect(result.isSuccess, isTrue, reason: 'Koordinasyon başarılı olmalıdır: ${result.errorMessage}');
        expect(result.state, CoreNextMigrationState.completed);

        // Core Next hedef veritabanında catch-up ile aktarılan canlı satışın ve stok güncellemesinin varlığı doğrulanır
        final coreSales = await coreDb.db.rawQuery("SELECT * FROM sales WHERE id = 'sale_live_01'");
        expect(coreSales.length, 1);
        expect(coreSales.first['total_cents'], 15000);

        final coreProds = await coreDb.db.rawQuery("SELECT stock_quantity FROM products WHERE id = 'p1'");
        expect((coreProds.first['stock_quantity'] as num).toDouble(), 99.0);

        // app_settings tablosunda cutover_reconciliation_status = approved olduğu doğrulanır
        final cutoverSetting = await coreDb.db.rawQuery("SELECT value FROM app_settings WHERE key = 'cutover_reconciliation_status'");
        expect(cutoverSetting.isNotEmpty, isTrue);
        expect(cutoverSetting.first['value'], 'approved');
      } finally {
        await legDb.close();
        await coreDb.close();
      }
    });

    // ──────────────────────────────────────────────────────────────────────────
    // GRUP 3: Çok Boyutlu Canlı Catch-Up Kapsamı (Tüm Tablolar ve Veri Türleri)
    // ──────────────────────────────────────────────────────────────────────────
    test('3.1: Fiyat güncellemesi, cari bakiye değişimi, vadeli defter ve ödeme parçaları eksiksiz aktarılır', () async {
      final legDb = await databaseFactory.openDatabase(
        legacyDbPath,
        options: OpenDatabaseOptions(
          version: 60,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, barcode TEXT, name TEXT, price REAL, price_minor INTEGER, purchase_price REAL, stock_quantity REAL, min_stock REAL, is_active INTEGER, is_deleted INTEGER, created_at TEXT, updated_at TEXT);');
            await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT, phone TEXT, email TEXT, balance REAL, balance_minor INTEGER, notes TEXT, is_active INTEGER, is_deleted INTEGER, created_at TEXT, updated_at TEXT);');
            await db.execute('CREATE TABLE sales (id TEXT PRIMARY KEY, receipt_number TEXT, customer_id TEXT, total_amount REAL, total_amount_minor INTEGER, payment_method TEXT, cashier_name TEXT, created_at TEXT, status TEXT);');
            await db.execute('CREATE TABLE sale_items (id TEXT PRIMARY KEY, sale_id TEXT, product_id TEXT, product_name TEXT, quantity REAL, unit_price REAL, subtotal REAL, created_at TEXT);');
            await db.execute('CREATE TABLE financial_transactions (id TEXT PRIMARY KEY, customer_id TEXT, type TEXT, amount REAL, reference_id TEXT, description TEXT, created_at TEXT);');
          },
        ),
      );

      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);

      try {
        final now = DateTime.now();
        final nowIso = now.toIso8601String();

        // 1. Ürün fiyatı ve stok güncellemesi
        await legDb.insert('products', {
          'id': 'p_nut',
          'barcode': 'NUT-01',
          'name': 'Giresun Fındığı',
          'price': 220.0,
          'price_minor': 22000,
          'purchase_price': 150.0,
          'stock_quantity': 45.5,
          'min_stock': 10.0,
          'is_active': 1,
          'is_deleted': 0,
          'created_at': nowIso,
          'updated_at': nowIso,
        });

        // 2. Müşteri oluşturma ve vadeli bakiye
        await legDb.insert('customers', {
          'id': 'c_erkul',
          'name': 'Erkul Müşterisi',
          'phone': '05329998877',
          'email': 'erkul@example.com',
          'balance': 350.0,
          'balance_minor': 35000,
          'notes': 'Güvenilir cari',
          'is_active': 1,
          'is_deleted': 0,
          'created_at': nowIso,
          'updated_at': nowIso,
        });

        // 3. Satış ve split ödeme parçası
        await legDb.insert('sales', {
          'id': 'sale_split_01',
          'receipt_number': 'REC-SPLIT-01',
          'customer_id': 'c_erkul',
          'total_amount': 350.0,
          'total_amount_minor': 35000,
          'payment_method': 'split_payment',
          'cashier_name': 'Kasiyer Fatma',
          'created_at': nowIso,
          'status': 'COMPLETED',
        });
        await legDb.insert('sale_items', {
          'id': 'item_split_01',
          'sale_id': 'sale_split_01',
          'product_id': 'p_nut',
          'product_name': 'Giresun Fındığı',
          'quantity': 1.5,
          'unit_price': 220.0,
          'subtotal': 330.0,
          'created_at': nowIso,
        });

        // 4. Tahsilat / defter kaydı
        await legDb.insert('financial_transactions', {
          'id': 'tx_col_01',
          'customer_id': 'c_erkul',
          'type': 'collection',
          'amount': 350.0,
          'reference_id': 'sale_split_01',
          'description': 'Kısmi nakit tahsilat',
          'created_at': nowIso,
        });

        final catchUpCoordinator = const LiveSafeCatchUpReconciliationCoordinator();
        final report = await catchUpCoordinator.performCatchUpAndReconcile(
          legacyDb: legDb,
          targetCoreDb: coreDb,
          legacyDbPath: legacyDbPath,
          lastMigrationCutoffTimestamp: 0,
          persistCutoverStatus: true,
        );

        expect(report.decision, CutoverReconciliationDecision.cutoverApproved);
        expect(report.statistics.productsUpdated, greaterThanOrEqualTo(1));
        expect(report.statistics.customersUpdated, greaterThanOrEqualTo(1));
        expect(report.statistics.salesMigrated, greaterThanOrEqualTo(1));
        expect(report.statistics.saleItemsMigrated, greaterThanOrEqualTo(1));
        expect(report.statistics.ledgerEntriesMigrated, greaterThanOrEqualTo(1));

        // Core veritabanında kuruş doğruluğu kontrolü
        final custInCore = await coreDb.db.rawQuery("SELECT balance_cents, phone FROM customers WHERE id = 'c_erkul'");
        expect(custInCore.first['balance_cents'], 35000);
        expect(custInCore.first['phone'], '05329998877');

        final ledgerInCore = await coreDb.db.rawQuery("SELECT amount_cents, entry_type FROM ledger_entries WHERE id = 'tx_col_01'");
        expect(ledgerInCore.first['amount_cents'], 35000);
        expect(ledgerInCore.first['entry_type'], 'collection');
      } finally {
        await legDb.close();
        await coreDb.close();
      }
    });

    // ──────────────────────────────────────────────────────────────────────────
    // GRUP 4: Kesinti, Tekrar Çalıştırma ve Idempotens (Mükerrer Kayıt Önleme)
    // ──────────────────────────────────────────────────────────────────────────
    test('4.1: Yarım kalan veya tekrarlanan catch-up işlemlerinde veri kaybı ve mükerrer kayıt oluşmaz', () async {
      final legDb = await databaseFactory.openDatabase(
        legacyDbPath,
        options: OpenDatabaseOptions(
          version: 60,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, barcode TEXT, name TEXT, price REAL, stock_quantity REAL, created_at TEXT, updated_at TEXT);');
            await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT, balance REAL, created_at TEXT, updated_at TEXT);');
            await db.execute('CREATE TABLE sales (id TEXT PRIMARY KEY, customer_id TEXT, total_amount REAL, created_at TEXT);');
            await db.insert('products', {'id': 'p1', 'barcode': '111', 'name': 'Çay', 'price': 20.0, 'stock_quantity': 50.0, 'created_at': '2026-10-20T10:00:00.000'});
            await db.insert('customers', {'id': 'c1', 'name': 'Veli', 'balance': 100.0, 'created_at': '2026-10-20T10:00:00.000'});
            await db.insert('sales', {'id': 's1', 'customer_id': 'c1', 'total_amount': 100.0, 'created_at': '2026-10-20T10:00:00.000'});
          },
        ),
      );

      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);

      try {
        final coordinator = const LiveSafeCatchUpReconciliationCoordinator();

        // 1. Çalıştırma
        final report1 = await coordinator.performCatchUpAndReconcile(
          legacyDb: legDb,
          targetCoreDb: coreDb,
          legacyDbPath: legacyDbPath,
          lastMigrationCutoffTimestamp: 0,
        );
        expect(report1.decision, CutoverReconciliationDecision.cutoverApproved);

        // 2. Çalıştırma (Aynı verilerle tekrar tetikleme — Tekrarlama/Crash Recovery simülasyonu)
        final report2 = await coordinator.performCatchUpAndReconcile(
          legacyDb: legDb,
          targetCoreDb: coreDb,
          legacyDbPath: legacyDbPath,
          lastMigrationCutoffTimestamp: 0,
        );
        expect(report2.decision, CutoverReconciliationDecision.cutoverApproved);

        // Hedef tablolarında kayıt sayılarının birebir korunduğu (mükerrer kayıt OLMADIĞI) doğrulanır
        final prodCount = await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM products');
        final custCount = await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM customers');
        final saleCount = await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM sales');

        expect(prodCount.first['c'], 1, reason: 'Ürün mükerrer eklenmemelidir');
        expect(custCount.first['c'], 1, reason: 'Müşteri mükerrer eklenmemelidir');
        expect(saleCount.first['c'], 1, reason: 'Satış mükerrer eklenmemelidir');
      } finally {
        await legDb.close();
        await coreDb.close();
      }
    });

    // ──────────────────────────────────────────────────────────────────────────
    // GRUP 5: Doğrulama Hatasında Cutover Blokajı ve DatabaseRoutingResolver Kararı
    // ──────────────────────────────────────────────────────────────────────────
    test('5.1: Mutabakat sapmasında cutover engellenir ve DatabaseRoutingResolver güvenle legacy fallback seçer', () async {
      final legDb = await databaseFactory.openDatabase(
        legacyDbPath,
        options: OpenDatabaseOptions(
          version: 60,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, barcode TEXT, name TEXT, price REAL, stock_quantity REAL, created_at TEXT);');
            await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT, balance REAL, created_at TEXT);');
            await db.execute('CREATE TABLE sales (id TEXT PRIMARY KEY, customer_id TEXT, total_amount REAL, created_at TEXT);');
            await db.insert('products', {'id': 'p1', 'barcode': '111', 'name': 'A', 'price': 10.0, 'stock_quantity': 10.0, 'created_at': '2026-10-20T10:00:00'});
            await db.insert('customers', {'id': 'c1', 'name': 'B', 'balance': 50.0, 'created_at': '2026-10-20T10:00:00'});
            // Kaynakta 100 TL'lik satış var
            await db.insert('sales', {'id': 's1', 'customer_id': 'c1', 'total_amount': 100.0, 'created_at': '2026-10-20T10:00:00'});
          },
        ),
      );

      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);

      try {
        // Hedefe bilinçli olarak farklı bir tutar veya eksik kayıt yazıyoruz (sapma simülasyonu)
        await coreDb.db.execute('''
          INSERT INTO products (id, barcode, name, price_cents, stock_quantity, updated_at)
          VALUES ('p1', '111', 'A', 1000, 10.0, 1);
        ''');
        await coreDb.db.execute('''
          INSERT INTO customers (id, name, balance_cents, updated_at)
          VALUES ('c1', 'B', 5000, 1);
        ''');
        await coreDb.db.execute('''
          INSERT INTO sales (id, receipt_no, customer_id, subtotal_cents, discount_cents, vat_total_cents, total_cents, paid_cents, debt_cents, status, idempotency_key, created_at)
          VALUES ('s1', 'REC-01', 'c1', 8000, 0, 0, 8000, 8000, 0, 'COMPLETED', 'idem_s1', 1);
        ''');

        // Canlı catch-up çalıştırılır; tutar uyuşmazlığı tespit edilir
        final catchUpCoordinator = const LiveSafeCatchUpReconciliationCoordinator();
        final report = await catchUpCoordinator.performCatchUpAndReconcile(
          legacyDb: legDb,
          targetCoreDb: coreDb,
          legacyDbPath: legacyDbPath,
          lastMigrationCutoffTimestamp: 9999999999999, // Filtreyi ileri atıyoruz ki satış yeniden aktarılmasın
          persistCutoverStatus: true,
        );

        expect(
          report.decision == CutoverReconciliationDecision.cutoverBlockedVarianceDetected ||
              report.decision == CutoverReconciliationDecision.cutoverBlockedConcurrentWrites ||
              report.decision == CutoverReconciliationDecision.cutoverBlockedIntegrityError,
          isTrue,
        );
        expect(report.isMatched, isFalse);

        // app_settings tablosunda cutover_reconciliation_status = blocked kaydedilmiş olmalıdır
        final blockedSetting = await coreDb.db.rawQuery("SELECT value FROM app_settings WHERE key = 'cutover_reconciliation_status'");
        expect(blockedSetting.first['value'], 'blocked');

        // DatabaseRoutingResolver değerlendirmesi
        final resolver = const DatabaseRoutingResolver();
        final decision = await resolver.resolve(
          requestedTenantId: 'tenant_test',
          legacyDbPath: legacyDbPath,
          targetDbPath: targetDbPath,
          migrationStateCompleted: true,
        );

        expect(decision.decision, RoutingDecision.legacyFallback,
            reason: 'Mutabakat başarısız olduğunda sistem kesinlikle legacyFallback hedefine dönmelidir.');
        expect(decision.reason, anyOf(contains('engellendi'), contains('blocked'), contains('blokaj')));
      } finally {
        await legDb.close();
        await coreDb.close();
      }
    });

    // ──────────────────────────────────────────────────────────────────────────
    // GRUP 6: Emeklilik Politikası ve Eski Dosya Korunumu
    // ──────────────────────────────────────────────────────────────────────────
    test('6.1: Emeklilik koşulları sağlanmadan dosya silinemez; tamamlandığında ise silinmeyip arşivlenir', () async {
      final prefs = await SharedPreferences.getInstance();
      final legacyFile = File(legacyDbPath);
      await legacyFile.writeAsString('MOCK_LEGACY_DATABASE_CONTENT');

      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);

      try {
        final policy = const LegacyDatabaseRetirementPolicy();

        // 1. Durum: Henüz 14 gün dolmamışken emeklilik değerlendirilir
        final earlyEval = await policy.evaluate(
          targetCoreDb: coreDb,
          legacyDbPath: legacyDbPath,
          prefs: prefs,
          routingResolver: const DatabaseRoutingResolver(),
          tenantId: 'tenant_test',
        );

        expect(earlyEval.isEligibleForRetirement, isFalse);
        expect(earlyEval.blockingReasons.any((r) => r.contains('Kriter 7')), isTrue);
        expect(legacyFile.existsSync(), isTrue, reason: 'Eski dosya kesinlikle silinmemelidir.');

        // 2. Durum: 14 günlük kusursuz süre geçtikten sonra ve tüm kriterler sağlandığında
        // Core Next geçiş tamamlanma ayarını yaz
        await coreDb.db.insert('app_settings', {
          'key': 'legacy_migration_completed',
          'value': 'true',
          'updated_at': 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        // Core Next aktivasyon tarihini 15 gün öncesine ayarla
        final fifteenDaysAgoMs = DateTime.now().subtract(const Duration(days: 15)).millisecondsSinceEpoch;
        await prefs.setInt(LegacyDatabaseRetirementPolicy.prefKeyCoreNextActivatedAt, fifteenDaysAgoMs);

        // Müşteri tablosuna örnek bir kayıt ekle ki yabancı anahtar ihlali olmasın
        await coreDb.db.insert('customers', {
          'id': 'c1',
          'name': 'Müşteri c1',
          'balance_cents': 0,
          'is_active': 1,
          'is_deleted': 0,
          'updated_at': fifteenDaysAgoMs,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);

        // Satış tablosuna örnek bir kayıt ekle ki Kriter 6 geçsin
        await coreDb.db.insert('sales', {
          'id': 'sale_retire_check',
          'receipt_no': 'REC-RET',
          'customer_id': 'c1',
          'subtotal_cents': 1000,
          'discount_cents': 0,
          'vat_total_cents': 0,
          'total_cents': 1000,
          'paid_cents': 1000,
          'debt_cents': 0,
          'status': 'COMPLETED',
          'idempotency_key': 'idem_ret',
          'created_at': fifteenDaysAgoMs,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);

        final matureEval = await policy.evaluate(
          targetCoreDb: coreDb,
          legacyDbPath: legacyDbPath,
          prefs: prefs,
          routingResolver: const DatabaseRoutingResolver(),
          tenantId: 'tenant_test',
        );

        expect(matureEval.isEligibleForRetirement, isTrue,
            reason: 'Tüm 7 kriter sağlandığında emeklilik uygun olmalıdır: ${matureEval.blockingReasons}');

        final archived = await policy.executeSafeRetirement(
          evaluation: matureEval,
          legacyDbPath: legacyDbPath,
          prefs: prefs,
        );

        expect(archived, isTrue);
        expect(legacyFile.existsSync(), isFalse, reason: 'Orijinal konumdaki dosya taşınmış olmalıdır.');

        final archivedFiles = tempDir.listSync().where((f) => f.path.contains('.archived_'));
        expect(archivedFiles.isNotEmpty, isTrue, reason: 'Silinmeyip .archived_ adıyla saklanmalıdır.');
      } finally {
        await coreDb.close();
      }
    });
  });
}
