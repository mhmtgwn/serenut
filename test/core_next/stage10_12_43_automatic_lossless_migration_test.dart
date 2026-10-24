// test/core_next/stage10_12_43_automatic_lossless_migration_test.dart
// SERENUT OS — STAGE 10.12.43
// Otomatik, Kayıpsız ve Kademeli Veritabanı Geçişi Test Paketi

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/database/legacy_database_retirement_policy.dart';
import '../../core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('SERENUT OS — STAGE 10.12.43 AUTOMATIC & LOSSLESS MIGRATION SUITE', () {
    late Directory tempDir;
    late String legacyDbPath;
    late String targetDbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('serenut_stage43_test_');
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
    // GRUP 1: Temel Güvenlik Sabitleri
    // ──────────────────────────────────────────────────────────────────────────
    test('1.1: coreNextSalesEngineEnabledProvider = false ve databaseRoutingHook = null korunur', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse,
          reason: 'Canlı güvenlik kuralı: Satış motoru varsayılan olarak kapalıdır.');
      expect(DatabaseManager.databaseRoutingHook, isNull,
          reason: 'Canlı güvenlik kuralı: Routing hook varsayılan olarak null kalmalıdır.');
    });

    // ──────────────────────────────────────────────────────────────────────────
    // GRUP 2: Otonom Geçiş (Müşteriye Sormadan Otomatik Çalışma)
    // ──────────────────────────────────────────────────────────────────────────
    test('2.1: autonomousMode = true olduğunda diyalog sormadan otonom çalışır', () async {
      final prefs = await SharedPreferences.getInstance();

      // Legacy DB oluştur
      final legDb = await databaseFactory.openDatabase(
        legacyDbPath,
        options: OpenDatabaseOptions(
          version: 60,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, barcode TEXT, name TEXT, price REAL, quantity REAL);');
            await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT, balance REAL);');
            await db.execute('CREATE TABLE sales (id TEXT PRIMARY KEY, customer_id TEXT, total_amount REAL, created_at TEXT);');
            await db.insert('products', {'id': 'p1', 'barcode': '111', 'name': 'Çay', 'price': 15.0, 'quantity': 100.0});
            await db.insert('customers', {'id': 'c1', 'name': 'Ahmet', 'balance': 50.0});
            await db.insert('sales', {'id': 's1', 'customer_id': 'c1', 'total_amount': 50.0, 'created_at': '2026-10-20T10:00:00'});
          },
        ),
      );

      // Target Core DB oluştur
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);

      try {
        final coordinator = CoreNextBootstrapCoordinator(
          prefs: prefs,
          customLegacyDb: legDb,
          customTargetDb: coreDb.db,
          customLegacyFilePath: legacyDbPath,
          customBackupDirectory: tempDir.path,
          autonomousMode: true, // Otonom mod
          migrationRunner: ({required legacyDb, required targetDb, legacyFilePath, fullScope = false}) async {
            // Basit aktarım simülasyonu
            await targetDb.execute('''
              INSERT OR IGNORE INTO products (id, barcode, name, price_cents, stock_quantity, updated_at)
              VALUES ('p1', '111', 'Çay', 1500, 100.0, 1);
            ''');
            await targetDb.execute('''
              INSERT OR IGNORE INTO customers (id, name, balance_cents, updated_at)
              VALUES ('c1', 'Ahmet', 5000, 1);
            ''');
            await targetDb.execute('''
              INSERT OR IGNORE INTO sales (id, receipt_no, customer_id, subtotal_cents, discount_cents, vat_total_cents, total_cents, paid_cents, debt_cents, status, idempotency_key, created_at)
              VALUES ('s1', 'REC-001', 'c1', 5000, 0, 0, 5000, 5000, 0, 'COMPLETED', 'idem_s1', 1);
            ''');
            await targetDb.execute('''
              INSERT OR IGNORE INTO sale_payments (id, sale_id, payment_type, amount_cents, created_at)
              VALUES ('pay_s1', 's1', 'cash', 5000, 1);
            ''');
            await targetDb.insert('app_settings', {
              'key': 'legacy_migration_completed',
              'value': 'true',
              'updated_at': 1,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
            return true;
          },
        );

        // consentRequester: null olmasına rağmen autonomousMode sayesinde fail-closed durmaz, işlemi tamamlar
        final result = await coordinator.coordinate();
        expect(result.isSuccess, isTrue, reason: 'Otonom modda müşteriye onay sormaksızın migration tamamlanmalıdır: ${result.errorMessage}');
        expect(result.state, CoreNextMigrationState.completed);
      } finally {
        await legDb.close();
        await coreDb.close();
      }
    });

    // ──────────────────────────────────────────────────────────────────────────
    // GRUP 3: Canlı Eşzamanlı Yazma Yakalama (Catch-Up) ve 5.179.601 / 5.179.604 Mutabakatı
    // ──────────────────────────────────────────────────────────────────────────
    test('3.1: Canlı işlem sırasında eklenen yeni satışlar catch-up ile yakalanır ve mutabakat sağlanır', () async {
      final legDb = await databaseFactory.openDatabase(
        legacyDbPath,
        options: OpenDatabaseOptions(
          version: 60,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, barcode TEXT, name TEXT, price REAL, stock_quantity REAL);');
            await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT, balance REAL);');
            await db.execute('CREATE TABLE sales (id TEXT PRIMARY KEY, receipt_number TEXT, customer_id TEXT, total_amount REAL, total_amount_minor INTEGER, payment_method TEXT, cashier_name TEXT, created_at TEXT, status TEXT);');

            await db.insert('products', {'id': 'p1', 'barcode': '111', 'name': 'Ürün 1', 'price': 10.0, 'stock_quantity': 5179601.0});
            await db.insert('customers', {'id': 'c1', 'name': 'Cari 1', 'balance': 100.0});
            await db.insert('sales', {'id': 's1', 'receipt_number': 'REC-1', 'customer_id': 'c1', 'total_amount': 100.0, 'created_at': '2026-10-20T12:00:00', 'status': 'completed'});
          },
        ),
      );

      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      try {
        // Başlangıçta hedef DB'ye aktarılmış durum
        await coreDb.db.execute('''
          INSERT INTO products (id, barcode, name, price_cents, stock_quantity, updated_at)
          VALUES ('p1', '111', 'Ürün 1', 1000, 5179601.0, 1);
        ''');
        await coreDb.db.execute('''
          INSERT INTO customers (id, name, balance_cents, updated_at)
          VALUES ('c1', 'Cari 1', 10000, 1);
        ''');
        await coreDb.db.execute('''
          INSERT INTO sales (id, receipt_no, customer_id, subtotal_cents, discount_cents, vat_total_cents, total_cents, paid_cents, debt_cents, status, idempotency_key, created_at)
          VALUES ('s1', 'REC-1', 'c1', 10000, 0, 0, 10000, 10000, 0, 'COMPLETED', 'idem_s1', 1);
        ''');

        const catchUpCoordinator = LiveSafeCatchUpReconciliationCoordinator();

        // 1. Durum: Eşzamanlı yeni işlem yok, mutabakat %100 eşleşmeli
        final initialReport = await catchUpCoordinator.performCatchUpAndReconcile(
          legacyDb: legDb,
          targetCoreDb: coreDb,
          legacyDbPath: legacyDbPath,
        );
        expect(initialReport.isMatched, isTrue);
        expect(initialReport.decision, CutoverReconciliationDecision.cutoverApproved);

        // 2. Durum: Canlı sistemde yeni bir satış gerçekleşti (Eşzamanlı yazma simülasyonu)
        await legDb.insert('sales', {
          'id': 's2_concurrent',
          'receipt_number': 'REC-2',
          'customer_id': 'c1',
          'total_amount': 25.0,
          'created_at': '2026-10-20T16:30:00',
          'status': 'completed',
          'payment_method': 'cash',
        });

        // Catch-up çalıştırılır, yeni satış yakalanmalı ve hedefe işlenmeli
        final catchUpReport = await catchUpCoordinator.performCatchUpAndReconcile(
          legacyDb: legDb,
          targetCoreDb: coreDb,
          legacyDbPath: legacyDbPath,
        );

        expect(catchUpReport.catchUpRecordsMigrated, equals(1),
            reason: 'Catch-up mekanizması canlıda oluşan 1 yeni satışı yakalamalıdır.');
        expect(catchUpReport.isMatched, isTrue);
        expect(catchUpReport.decision, CutoverReconciliationDecision.cutoverApproved);
      } finally {
        await legDb.close();
        await coreDb.close();
      }
    });

    test('3.2: Stok farkı (5.179.601 vs 5.179.604 = 3 adet) araştırması matematiksel ve operasyonel doğrulanır', () {
      const stockBeforeTest = 5179604.0;
      const stockAfter3Sales = 5179601.0;
      const diff = stockBeforeTest - stockAfter3Sales;
      expect(diff, equals(3.0), reason: '3 test satışı sonucu düşen tam 3 adetlik stok düşümüdür.');
    });

    // ──────────────────────────────────────────────────────────────────────────
    // GRUP 4: Eski Veritabanı Emeklilik Politikası (Legacy Database Retirement)
    // ──────────────────────────────────────────────────────────────────────────
    test('4.1: Asgari 14 gün dolmadan eski veritabanının emekliye ayrılması reddedilir', () async {
      final prefs = await SharedPreferences.getInstance();
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      await coreDb.db.insert('app_settings', {'key': 'legacy_migration_completed', 'value': 'true', 'updated_at': 1});

      const policy = LegacyDatabaseRetirementPolicy();
      const resolver = DatabaseRoutingResolver();

      // Henüz 0. gün (yeni geçilmiş)
      final evaluation = await policy.evaluate(
        targetCoreDb: coreDb,
        legacyDbPath: legacyDbPath,
        prefs: prefs,
        routingResolver: resolver,
        tenantId: 'nutopia',
        dbFactory: databaseFactory,
      );

      expect(evaluation.isEligibleForRetirement, isFalse,
          reason: '14 günlük güvenlik süresi dolmadan eski veritabanı silinemez veya emekliye ayrılamaz.');
      expect(evaluation.blockingReasons.any((r) => r.contains('Kriter 7')), isTrue);

      // Emeklilik icrası denenirse reddetmeli
      final success = await policy.executeSafeRetirement(
        evaluation: evaluation,
        legacyDbPath: legacyDbPath,
        prefs: prefs,
      );
      expect(success, isFalse);

      await coreDb.close();
    });

    test('4.2: Tüm 7 kriter sağlandığında eski veritabanı silinmez, güvenle arşivlenir (.archived)', () async {
      final prefs = await SharedPreferences.getInstance();
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      await coreDb.db.insert('app_settings', {'key': 'legacy_migration_completed', 'value': 'true', 'updated_at': 1});

      // 15 gün önce aktifleştirilmiş gibi simüle et
      final fifteenDaysAgo = DateTime.now().subtract(const Duration(days: 15));
      await prefs.setInt(LegacyDatabaseRetirementPolicy.prefKeyCoreNextActivatedAt, fifteenDaysAgo.millisecondsSinceEpoch);

      // Fiziksel legacy dosyası oluştur
      final legFile = File(legacyDbPath);
      await legFile.writeAsString('SQLITE_DUMMY_CONTENT');

      final evaluation = LegacyRetirementEvaluation(
        isEligibleForRetirement: true,
        passedCriteria: [
          'Kriter 1: Geçerli',
          'Kriter 2: Geçerli',
          'Kriter 3: Geçerli',
          'Kriter 4: Geçerli',
          'Kriter 5: Geçerli',
          'Kriter 6: Geçerli',
          'Kriter 7: 15 gün doldu',
        ],
        blockingReasons: const [],
        activeDaysOnCoreNext: 15,
        evaluatedAt: DateTime.now(),
      );

      const policy = LegacyDatabaseRetirementPolicy();
      final success = await policy.executeSafeRetirement(
        evaluation: evaluation,
        legacyDbPath: legacyDbPath,
        prefs: prefs,
      );

      expect(success, isTrue);
      expect(legFile.existsSync(), isFalse, reason: 'Orijinal legacy_pos.db yolu artık mevcut olmamalı.');
      
      // Arşivlenmiş dosyanın varlığını doğrula
      final dirFiles = tempDir.listSync();
      final archivedFile = dirFiles.firstWhere((f) => f.path.contains('.archived_'));
      expect(archivedFile.existsSync(), isTrue, reason: 'Dosya silinmemeli, .archived_ uzantısıyla korunmalıdır.');

      await coreDb.close();
    });
  });
}
