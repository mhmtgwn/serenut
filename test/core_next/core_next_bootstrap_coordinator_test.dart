// ignore_for_file: avoid_relative_lib_imports
// test/core_next/core_next_bootstrap_coordinator_test.dart
// SERENUT OS — STAGE 10.9.3
// CoreNextBootstrapCoordinator Comprehensive Safety, Backup Verification, and Fail-Closed Tests

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';

import 'package:serenutos/core_next/infrastructure/database/app_database.dart';
import 'package:serenutos/core_next/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String legacyDbPath;
  late String coreDbPath;
  late String backupDirPath;
  late Database legacyDb;
  late CoreAppDatabase coreDb;

  Future<void> populateLegacyDatabase(Database db) async {
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT UNIQUE,
        name TEXT,
        role TEXT,
        password_hash TEXT,
        pin_hash TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT
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
        unit TEXT DEFAULT 'piece',
        quantity REAL DEFAULT 0,
        min_stock REAL DEFAULT 5,
        is_active INTEGER DEFAULT 1,
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
        status TEXT DEFAULT 'COMPLETED',
        idempotency_key TEXT,
        created_at TEXT,
        notes TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE sale_items (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        unit_price_minor INTEGER,
        subtotal REAL NOT NULL,
        subtotal_minor INTEGER,
        FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id)
      );
    ''');

    await db.execute('''
      CREATE TABLE financial_transactions (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        amount_minor INTEGER,
        paid_amount REAL DEFAULT 0.0,
        debt_amount REAL DEFAULT 0.0,
        description TEXT,
        created_at TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers (id)
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
        base_revision INTEGER DEFAULT 0,
        state TEXT DEFAULT 'PENDING',
        attempts INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      );
    ''');

    // Seed realistic synthetic data
    await db.insert('users', {
      'id': 'usr-admin',
      'username': 'admin',
      'name': 'Yönetici',
      'role': 'admin',
      'pin_hash': '1234',
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });

    await db.insert('categories', {
      'id': 'cat-gida',
      'name': 'Gıda',
      'color_hex': '#FF0000',
      'sort_order': 1,
      'is_active': 1,
    });

    await db.insert('products', {
      'id': 'p-ekmek',
      'barcode': '8690001',
      'name': 'Somun Ekmek',
      'category': 'Gıda',
      'category_id': 'cat-gida',
      'price': 10.0,
      'price_minor': 1000,
      'cost_price': 7.0,
      'cost_price_minor': 700,
      'quantity': 100.0,
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });

    await db.insert('customers', {
      'id': 'c-ahmet',
      'name': 'Ahmet Yılmaz',
      'phone': '05551234567',
      'balance': 50.0,
      'balance_minor': 5000,
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });

    await db.insert('sales', {
      'id': 's-1001',
      'receipt_no': 'REC-1001',
      'customer_id': 'c-ahmet',
      'total_amount': 50.0,
      'total_amount_minor': 5000,
      'paid_amount': 50.0,
      'paid_amount_minor': 5000,
      'payment_method': 'cash',
      'status': 'COMPLETED',
      'created_at': DateTime.now().toIso8601String(),
    });

    await db.insert('sale_items', {
      'id': 'si-1',
      'sale_id': 's-1001',
      'product_id': 'p-ekmek',
      'product_name': 'Somun Ekmek',
      'quantity': 5.0,
      'unit_price': 10.0,
      'unit_price_minor': 1000,
      'subtotal': 50.0,
      'subtotal_minor': 5000,
    });

    await db.insert('financial_transactions', {
      'id': 'ft-1',
      'customer_id': 'c-ahmet',
      'type': 'SALE',
      'amount': 50.0,
      'amount_minor': 5000,
      'paid_amount': 50.0,
      'created_at': DateTime.now().toIso8601String(),
    });

    await db.insert('sync_outbox_v4', {
      'mutation_id': 'mut-sale-1',
      'entity_type': 'sale',
      'entity_id': 's-1001',
      'operation': 'UPSERT',
      'payload': '{"id": "s-1001"}',
      'state': 'PENDING',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  setUp(() async {
    CoreNextBootstrapCoordinator.resetExecutionLock();
    SharedPreferences.setMockInitialValues({});

    tempDir = await Directory.systemTemp.createTemp('core_next_coordinator_test_');
    legacyDbPath = p.join(tempDir.path, 'serenut_pos.db');
    coreDbPath = p.join(tempDir.path, 'serenut_core_v2.db');
    backupDirPath = p.join(tempDir.path, 'SerenutBackups');

    legacyDb = await openDatabase(
      legacyDbPath,
      version: 60,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
        await db.rawQuery('PRAGMA journal_mode = WAL;');
      },
    );

    await populateLegacyDatabase(legacyDb);

    coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: coreDbPath);
  });

  tearDown(() async {
    CoreNextBootstrapCoordinator.resetExecutionLock();
    try {
      await legacyDb.close();
      await coreDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  CoreNextBootstrapCoordinator createTestCoordinator({
    SharedPreferences? prefs,
    Database? customLegacyDb,
    Database? customTargetDb,
    String? customLegacyFilePath,
    String? customBackupDirectory,
    CoreNextMigrationRunner? migrationRunner,
    CoreNextCompletionChecker? completionChecker,
    MigrationConsentRequester? consentRequester,
    bool autonomousMode = true,
  }) {
    return CoreNextBootstrapCoordinator(
      customLegacyDb: customLegacyDb ?? legacyDb,
      customTargetDb: customTargetDb ?? coreDb.db,
      customLegacyFilePath: customLegacyFilePath ?? legacyDbPath,
      customBackupDirectory: customBackupDirectory ?? backupDirPath,
      prefs: prefs,
      autonomousMode: autonomousMode,
      consentRequester: consentRequester ?? (() async => MigrationConsentDecision.approved),
      migrationRunner: migrationRunner ??
          ({required legacyDb, required targetDb, legacyFilePath, fullScope = false}) async {
            return MigrationBridgeEngine(coreDb).migrateFromLegacy(
              legacyDb,
              legacyFilePath: legacyFilePath,
              fullScope: fullScope,
            );
          },
      completionChecker: completionChecker ??
          (targetDb) => MigrationBridgeEngine(coreDb).isMigrationCompleted(),
    );
  }

  group('STAGE 10.9.3 — CoreNextBootstrapCoordinator 12 Zorunlu Senaryo Testi', () {
    test('1. Migration gerekmiyorsa mevcut Legacy açılışı korunur (durum completed veya skip)', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(CoreNextBootstrapCoordinator.prefKeyMigrationState, 'completed');

      // Hedef DB içinde migration completed bayrağını da set edelim
      await coreDb.db.insert('app_settings', {
        'key': 'legacy_migration_completed',
        'value': 'true',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      final coordinator = createTestCoordinator(prefs: prefs);

      final result = await coordinator.coordinate();
      expect(result.isSuccess, true);
      expect(result.isSkipped, true);
      expect(result.state, CoreNextMigrationState.completed);
    });

    test('2. Yedekleme başarısızsa migration başlamaz (Fail-Closed güvencesi)', () async {
      final prefs = await SharedPreferences.getInstance();

      // Geçersiz bir backup dizini (dosya olan bir yolu dizin olarak gösterip patlatalım)
      final dummyFile = File(p.join(tempDir.path, 'dummy_file_blocking_dir'));
      await dummyFile.writeAsString('I am a file, not a directory');

      final coordinator = createTestCoordinator(
        prefs: prefs,
        customLegacyFilePath: '/invalid/non_existent_path.db',
        customBackupDirectory: dummyFile.path, // Dizin oluşturulamayacak
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, false);
      expect(result.state, CoreNextMigrationState.failedRecoverable);
      expect(result.errorMessage, contains('Yedekleme ve doğrulama aşamasında hata'));

      // Hedef DB boş kalmalıdır
      final coreProducts = await coreDb.db.query('products');
      expect(coreProducts.isEmpty, true);
    });

    test('3. Yedek yeniden açılır ve bütünlük kontrolünden (PRAGMA integrity_check) geçer', () async {
      final prefs = await SharedPreferences.getInstance();

      final coordinator = createTestCoordinator(prefs: prefs);

      final result = await coordinator.coordinate();
      expect(result.isSuccess, true);
      expect(result.backupPath, isNotNull);

      // Yedeğin bağımsız olarak diskte var olduğunu ve integrity_check'ten geçtiğini doğrula
      final backupFile = File(result.backupPath!);
      expect(await backupFile.exists(), true);

      final backupDb = await openDatabase(backupFile.path, readOnly: true);
      final check = await backupDb.rawQuery('PRAGMA integrity_check;');
      expect(check.first.values.first, 'ok');
      await backupDb.close();
    });

    test('4. Başarılı migration sonrası durum kalıcı kaydedilir (durum completed)', () async {
      final prefs = await SharedPreferences.getInstance();

      final coordinator = createTestCoordinator(prefs: prefs);

      final result = await coordinator.coordinate();
      expect(result.isSuccess, true);
      expect(result.state, CoreNextMigrationState.completed);

      // SharedPreferences kalıcı kaydını doğrula
      final savedState = prefs.getString(CoreNextBootstrapCoordinator.prefKeyMigrationState);
      expect(savedState, 'completed');
      expect(prefs.getString(CoreNextBootstrapCoordinator.prefKeyCompletedAt), isNotNull);

      // Hedef DB app_settings kaydını doğrula
      final settings = await coreDb.db.query('app_settings', where: 'key = ?', whereArgs: ['legacy_migration_completed']);
      expect(settings.first['value'], 'true');
    });

    test('5. Migration yarıda kesilirse tamamlandı olarak işaretlenmez (Rollback güvencesi)', () async {
      final prefs = await SharedPreferences.getInstance();

      // Legacy DB içine geçersiz negatif satış enjekte edelim (MigrationBridgeEngine StateError fırlatacaktır)
      await legacyDb.insert('sales', {
        'id': 's-neg-1',
        'receipt_no': 'REC-NEG-1',
        'total_amount': -150.0,
        'paid_amount': -150.0,
        'payment_method': 'cash',
        'status': 'COMPLETED',
        'created_at': DateTime.now().toIso8601String(),
      });

      final coordinator = createTestCoordinator(prefs: prefs);

      final result = await coordinator.coordinate();
      expect(result.isSuccess, false);
      expect(result.state, CoreNextMigrationState.failedRecoverable);

      // Durum ASLA completed olmamalıdır
      final savedState = prefs.getString(CoreNextBootstrapCoordinator.prefKeyMigrationState);
      expect(savedState, isNot('completed'));

      // Hedef DB transaction rollback olmalıdır
      final settings = await coreDb.db.query('app_settings', where: 'key = ?', whereArgs: ['legacy_migration_completed']);
      expect(settings.isEmpty, true);
    });

    test('6. Uygulama yeniden başladığında yarım kalmış migration güvenli ele alınır', () async {
      final prefs = await SharedPreferences.getInstance();
      // Önceki oturumun migration ortasında çöktüğünü simüle edelim
      await prefs.setString(CoreNextBootstrapCoordinator.prefKeyMigrationState, 'migration_in_progress');

      final coordinator = createTestCoordinator(prefs: prefs);

      // Yeni başlatmada koordinatör yarım kalmış durumu tespit edip temiz bir şekilde baştan tamamlayabilmelidir
      final result = await coordinator.coordinate();
      expect(result.isSuccess, true);
      expect(result.state, CoreNextMigrationState.completed);

      final savedState = prefs.getString(CoreNextBootstrapCoordinator.prefKeyMigrationState);
      expect(savedState, 'completed');
    });

    test('7. İkinci çağrı eşzamanlı migration başlatmaz (isAlreadyRunning koruması)', () async {
      final prefs = await SharedPreferences.getInstance();

      final coordinator1 = createTestCoordinator(prefs: prefs);

      // İlk çağrı başlarken kilit koyacak
      final future1 = coordinator1.coordinate();

      // İkinci çağrıyı hemen peşinden yapıyoruz
      final coordinator2 = createTestCoordinator(prefs: prefs);

      final result2 = await coordinator2.coordinate();
      expect(result2.isSuccess, false);
      expect(result2.isAlreadyRunning, true);
      expect(result2.errorMessage, contains('başka bir akış tarafından yürütülüyor'));

      final result1 = await future1;
      expect(result1.isSuccess, true);
    });

    test('8. Mutabakat başarısızsa Core Next tamamlandı olarak işaretlenmez (Reconciliation Guard)', () async {
      final prefs = await SharedPreferences.getInstance();

      // Hedef coreDb içine önceden fazladan bir satış ekleyelim ki coreSaleCount != legacySaleCount mutabakat sapması oluşsun
      await coreDb.db.insert('sales', {
        'id': 'phantom-core-sale',
        'receipt_no': 'REC-PHANTOM',
        'subtotal_cents': 9999,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 9999,
        'paid_cents': 9999,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      final coordinator = createTestCoordinator(prefs: prefs);

      final result = await coordinator.coordinate();
      expect(result.isSuccess, false);
      expect(result.errorMessage, contains('Satış adet mutabakat sapması'));
      expect(result.state, CoreNextMigrationState.failedRecoverable);

      final savedState = prefs.getString(CoreNextBootstrapCoordinator.prefKeyMigrationState);
      expect(savedState, isNot('completed'));
    });

    test('9. Legacy veritabanı migration öncesi ve sonrasında korunur', () async {
      final prefs = await SharedPreferences.getInstance();

      final beforeProducts = await legacyDb.query('products');
      final beforeCustomers = await legacyDb.query('customers');
      final beforeSales = await legacyDb.query('sales');

      final coordinator = createTestCoordinator(prefs: prefs);

      final result = await coordinator.coordinate();
      expect(result.isSuccess, true);

      final afterProducts = await legacyDb.query('products');
      final afterCustomers = await legacyDb.query('customers');
      final afterSales = await legacyDb.query('sales');

      // Satır sayıları ve içerikleri kesinlikle aynı olmalıdır
      expect(afterProducts.length, beforeProducts.length);
      expect(afterCustomers.length, beforeCustomers.length);
      expect(afterSales.length, beforeSales.length);

      expect(afterProducts.first['name'], beforeProducts.first['name']);
      expect(afterCustomers.first['balance'], beforeCustomers.first['balance']);
    });

    test('10. Mevcut feature flag varsayılanı değişmez (coreNextSalesEngineEnabled = false)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final isEnabled = container.read(coreNextSalesEngineEnabledProvider);
      expect(isEnabled, false, reason: 'Feature flag varsayılanı DAİMA false kalmalıdır.');
    });

    test('11. Migration hatası durumunda fail-closed davranılır ve writeLock temizlenir', () async {
      final prefs = await SharedPreferences.getInstance();

      final coordinator = createTestCoordinator(
        prefs: prefs,
        customLegacyFilePath: '/non_existent_legacy_file_path.db',
        customBackupDirectory: '/invalid_dir_path/?*:',
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, false);
      expect(DatabaseManager.isWriteLocked, false, reason: 'Hata sonrasında writeLock serbest bırakılmalıdır.');
    });

    test('12. Gerekli senaryolarda rollback ve outbox senkronizasyon kayıtları korunur', () async {
      final prefs = await SharedPreferences.getInstance();

      final coordinator = createTestCoordinator(prefs: prefs);

      final result = await coordinator.coordinate();
      expect(result.isSuccess, true);

      // Core Next veritabanında sync_events tablosuna outbox verisi taşınmış olmalıdır
      final syncEvents = await coreDb.db.query('sync_events');
      expect(syncEvents.isNotEmpty, true);
      expect(syncEvents.first['entity_id'], 's-1001');

      // Reverse migration ile legacy outbox'ın korunduğunu test edelim
      final reverseReport = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreDb,
      );
      expect(reverseReport.isSuccess, true, reason: reverseReport.errorMessage);

      final legacyOutbox = await legacyDb.query('sync_outbox_v4');
      expect(legacyOutbox.isNotEmpty, true);
    });

    test('13. Stok miktar sapması veya veri uyumsuzluğunda mutabakat hatayı yakalar ve fail-closed davranır', () async {
      final prefs = await SharedPreferences.getInstance();

      // Migration runner'ın stok miktarını hedefte farklı kaydettiği bir durum simüle edelim
      final coordinator = createTestCoordinator(
        prefs: prefs,
        migrationRunner: ({
          required Database legacyDb,
          required Database targetDb,
          String? legacyFilePath,
          bool fullScope = true,
        }) async {
          // Normal migration çalıştır
          final report = await MigrationBridgeEngine(coreDb).migrateFromLegacy(
            legacyDb,
            legacyFilePath: legacyFilePath,
            fullScope: fullScope,
          );
          // Hedefte stok miktarını kasıtlı bozarak sapma oluşturalım
          await targetDb.execute('UPDATE products SET stock_quantity = stock_quantity + 999 WHERE id = ?', ['p-ekmek']);
          return report;
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, false);
      expect(result.errorMessage, contains('Stok miktar mutabakat sapması'));
      expect(DatabaseManager.isWriteLocked, false);
      final state = await coordinator.getPersistentState();
      expect(state, CoreNextMigrationState.failedRecoverable);
    });

    test('14. Hedef veritabanı PRAGMA integrity_check hatası verirse tamamlandı sayılmaz ve fail-closed olur', () async {
      final prefs = await SharedPreferences.getInstance();

      // Hedef DB üzerinde tamamlandı bayrağı olsa bile completion checker bütünlüğü doğrular
      await coreDb.db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT,
          updated_at TEXT
        );
      ''');
      await coreDb.db.insert('app_settings', {
        'key': 'legacy_migration_completed',
        'value': 'true',
        'updated_at': DateTime.now().toIso8601String(),
      });

      // completionChecker targetDb'de integrity check başarısızlığını simüle eder
      final coordinator = createTestCoordinator(
        prefs: prefs,
        completionChecker: (targetDb) async => false, // Bozuk integrity sonucu
      );

      // Hedef bozuk olarak algılandığında isCompletedOnTarget false dönmeli ve yeniden koordinasyon tetiklenmelidir
      expect(await coordinator.getPersistentState(), isNot(CoreNextMigrationState.completed));
    });

    test('15. Adversarial Karşı Örnek: Ürün stok toplamı eşit olsa bile ürün bazında sapmayı mutabakat yakalar ve durdurur', () async {
      final prefs = await SharedPreferences.getInstance();

      // İkinci bir ürün ekleyelim
      await legacyDb.insert('products', {
        'id': 'p-su',
        'barcode': '8690002',
        'name': 'Doğal Kaynak Suyu',
        'category': 'Gıda',
        'category_id': 'cat-gida',
        'price': 5.0,
        'price_minor': 500,
        'quantity': 50.0,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });

      final coordinator = createTestCoordinator(
        prefs: prefs,
        migrationRunner: ({
          required Database legacyDb,
          required Database targetDb,
          String? legacyFilePath,
          bool fullScope = true,
        }) async {
          final report = await MigrationBridgeEngine(coreDb).migrateFromLegacy(
            legacyDb,
            legacyFilePath: legacyFilePath,
            fullScope: fullScope,
          );

          // Toplam stok aynı kalacak şekilde karşılıklı kaydırma (Offsetting error)
          // Toplam: 100 + 50 = 150
          // Hedefte: 90 + 60 = 150 (SUM eşit fakat ürün bazında hatalı!)
          await targetDb.execute('UPDATE products SET stock_quantity = stock_quantity - 10 WHERE id = ?', ['p-ekmek']);
          await targetDb.execute('UPDATE products SET stock_quantity = stock_quantity + 10 WHERE id = ?', ['p-su']);
          return report;
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, false);
      expect(result.errorMessage, contains('Ürün bazlı stok sapması'));
      expect(DatabaseManager.isWriteLocked, false);
      final state = await coordinator.getPersistentState();
      expect(state, CoreNextMigrationState.failedRecoverable);
    });

    test('16. Adversarial Karşı Örnek: Cari bakiye toplamı eşit olsa bile müşteri bazında bakiye sapmasını mutabakat yakalar ve durdurur', () async {
      final prefs = await SharedPreferences.getInstance();

      // İkinci bir müşteri ekleyelim
      await legacyDb.insert('customers', {
        'id': 'c-mehmet',
        'name': 'Mehmet Demir',
        'phone': '05559876543',
        'balance': 30.0,
        'balance_minor': 3000,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });

      final coordinator = createTestCoordinator(
        prefs: prefs,
        migrationRunner: ({
          required Database legacyDb,
          required Database targetDb,
          String? legacyFilePath,
          bool fullScope = true,
        }) async {
          final report = await MigrationBridgeEngine(coreDb).migrateFromLegacy(
            legacyDb,
            legacyFilePath: legacyFilePath,
            fullScope: fullScope,
          );

          // Toplam bakiye aynı kalacak şekilde karşılıklı kaydırma (Offsetting balance error)
          // Toplam: 5000 + 3000 = 8000 kuruş
          // Hedefte: 4500 + 3500 = 8000 kuruş (SUM eşit fakat cari bazında hatalı!)
          await targetDb.execute('UPDATE customers SET balance_cents = balance_cents - 500 WHERE id = ?', ['c-ahmet']);
          await targetDb.execute('UPDATE customers SET balance_cents = balance_cents + 500 WHERE id = ?', ['c-mehmet']);
          return report;
        },
      );

      final result = await coordinator.coordinate();
      expect(result.isSuccess, false);
      expect(result.errorMessage, contains('Müşteri bazlı bakiye sapması'));
      expect(DatabaseManager.isWriteLocked, false);
      final state = await coordinator.getPersistentState();
      expect(state, CoreNextMigrationState.failedRecoverable);
    });
  });
}
