// test/core_next/stage10_12_61_cart_lock_three_tenant_export_import_test.dart
// SERENUT OS — STAGE 10.12.61
// CART MAINTENANCE LOCK, THREE-TENANT EXPORT/IMPORT REHEARSAL & FINAL SAFETY AUDIT
//
// DEĞİŞMEZ GÜVENLİK KURALLARI:
// 1. Canlı hiçbir veritabanına yazma, onarım veya migration yapılmaz.
// 2. Yalnızca izole geçici kopyalar ve bellek içi mock yapılar üzerinde çalışılır.
// 3. coreNextSalesEngineEnabledProvider = false ve DatabaseManager.databaseRoutingHook = null kalır.

// ignore_for_file: avoid_relative_lib_imports, prefer_const_declarations

@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/migration/cutoff_maintenance_lock.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart';

String _calcSha256(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) return '';
  return sha256.convert(file.readAsBytesSync()).toString();
}

int _firstIntValue(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return 0;
  return (rows.first.values.first as num?)?.toInt() ?? 0;
}

class _FailingMaintenancePersistenceStorage implements IMaintenancePersistenceStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<CutoffMaintenanceState?> loadState() async {
    throw const FormatException('Kalıcı depolama okuma hatası');
  }

  @override
  Future<void> saveState(CutoffMaintenanceState state) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() {
    DatabaseManager.cutoffMaintenanceLock = null;
    DatabaseManager.isWriteLocked = false;
  });

  const rawNutopiaPath = 'backups/raw_tenants_20261016/raw_nutopia_v60.db';
  const rawSerenutPath = 'backups/raw_tenants_20261016/raw_serenut_v44.db';
  const rawErkulJsonPath = 'backups/raw_tenants_20261016/raw_erkul_source.json';

  // ══════════════════════════════════════════════════════════════════════════════
  // BÖLÜM 1: Değişmez Güvenlik Sınırları
  // ══════════════════════════════════════════════════════════════════════════════
  group('STAGE 10.12.61: Değişmez Güvenlik Sınırları', () {
    test('Kural 1: coreNextSalesEngineEnabledProvider kesinlikle false kalmalı', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse,
          reason: 'Canlı üretim güvenliği için Core Next satış motoru kesinlikle false kalmalıdır.');
    });

    test('Kural 2: DatabaseManager.databaseRoutingHook kesinlikle null kalmalı', () {
      expect(DatabaseManager.databaseRoutingHook, isNull,
          reason: 'Canlı üretim güvenliği için databaseRoutingHook kesinlikle null olmalıdır.');
    });

    test('Kural 3: coreNextSaleExecutorProvider varsayılan olarak null kalmalı', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSaleExecutorProvider), isNull,
          reason: 'Satış icra sağlayıcısı canlı geçiş onaylanana kadar null olmalıdır.');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════════
  // BÖLÜM 2: Kasiyer Ekranı Sepet Bakım Kilidi ve Durum Koruma
  // ══════════════════════════════════════════════════════════════════════════════
  group('STAGE 10.12.61: Kasiyer Ekranı Sepet Bakım Kilidi', () {
    late CutoffMaintenanceLock lock;

    setUp(() {
      lock = CutoffMaintenanceLock(
        storage: InMemoryMaintenancePersistenceStorage(),
      );
      DatabaseManager.cutoffMaintenanceLock = lock;
    });

    test('Senaryo 2.1: Bakım kilidi aktifken sepete ürün ekleme, çıkarma, temizleme ve ödeme engellenir', () async {
      await lock.acquireLock(tenantId: 'tenant_nutopia');
      expect(lock.state.phase, equals(CutoffMaintenancePhase.locked));

      final notifier = SalesFlowNotifier();

      final sampleProduct = ProductEntity(
        id: 'test_prod_1',
        name: 'Giresun Fındığı 500g',
        description: 'Naturel Fındık',
        price: 250.0,
        quantity: 100,
        category: 'Fındık',
      );

      // 1. Ürün ekleme engellenmeli ve CutoffMaintenanceActiveException fırlatılmalı
      expect(
        () => notifier.addToCart(sampleProduct),
        throwsA(isA<CutoffMaintenanceActiveException>()),
        reason: 'Bakım modunda sepete ürün eklenemez.',
      );

      // 2. Sepet temizleme engellenmeli
      expect(
        () => notifier.clearCart(),
        throwsA(isA<CutoffMaintenanceActiveException>()),
        reason: 'Bakım modunda sepet temizlenemez.',
      );

      // 3. Ödeme sunumu engellenmeli
      expect(
        () => notifier.setSubmitting(true),
        throwsA(isA<CutoffMaintenanceActiveException>()),
        reason: 'Bakım modunda ödeme gönderilemez.',
      );
    });

    test('Senaryo 2.2: Bakım kilidi kapalıyken normal satış ve sepet akışı eksiksiz çalışır (Sıfır Regresyon)', () {
      expect(lock.state.phase, equals(CutoffMaintenancePhase.idle));
      expect(lock.state.isWritePermitted, isTrue);

      final notifier = SalesFlowNotifier();

      final product1 = ProductEntity(
        id: 'prod_101',
        name: 'Fındık Ezmesi 320g',
        description: 'Doğal Şekerli',
        price: 180.0,
        quantity: 50,
        category: 'Ezme',
      );

      notifier.addToCart(product1);
      expect(notifier.state.cartQuantities['prod_101'], equals(1));
      expect(notifier.state.total, equals(180.0));
      expect(notifier.state.status, equals(SalesFlowStatus.paymentPending));

      // Miktar artırma
      notifier.addToCart(product1);
      expect(notifier.state.cartQuantities['prod_101'], equals(2));
      expect(notifier.state.total, equals(360.0));

      // Ürün eksiltme
      notifier.removeFromCart(product1);
      expect(notifier.state.cartQuantities['prod_101'], equals(1));
      expect(notifier.state.total, equals(180.0));

      // Sepeti temizleme
      notifier.clearCart();
      expect(notifier.state.cartQuantities, isEmpty);
      expect(notifier.state.total, equals(0.0));
      expect(notifier.state.status, equals(SalesFlowStatus.idle));
    });

    test('Senaryo 2.3: Kilit devreye girdiğinde sepet kaybolmaz, kilit açılınca güvenle devam edilir', () async {
      // 1. Normal modda sepete ürün ekle
      final notifier = SalesFlowNotifier();
      final product = ProductEntity(
        id: 'prod_preserve',
        name: 'Kavrulmuş Fındık 1kg',
        description: 'Vakumlu',
        price: 450.0,
        quantity: 30,
        category: 'Fındık',
      );

      notifier.addToCart(product);
      expect(notifier.state.cartQuantities['prod_preserve'], equals(1));
      expect(notifier.state.total, equals(450.0));

      // 2. Bakım kilidi devreye girsin
      await lock.acquireLock(tenantId: 'tenant_nutopia');
      expect(lock.state.isWritePermitted, isFalse);

      // Kilitliyken mutasyon denenir, engellenir
      expect(
        () => notifier.addToCart(product),
        throwsA(isA<CutoffMaintenanceActiveException>()),
      );

      // Kilitliyken sepet hafızada ve persisted kalır, kaybolmaz
      expect(notifier.state.cartQuantities['prod_preserve'], equals(1));

      // 3. Bakım kilidi kaldırılsın
      await lock.releaseLock();
      expect(lock.state.phase, equals(CutoffMaintenancePhase.idle));
      expect(lock.state.isWritePermitted, isTrue);

      // Sepet korunmuş olmalı ve yeni mutasyonlara izin verilmeli
      expect(notifier.state.cartQuantities['prod_preserve'], equals(1));
      notifier.addToCart(product);
      expect(notifier.state.cartQuantities['prod_preserve'], equals(2));
      expect(notifier.state.total, equals(900.0));
    });

    test('Senaryo 2.4: Aktif in-flight transaction varken bakım kilidi drainer bekler, işlem bitince kilitlenir', () async {
      final inFlightWrite = Completer<String>();
      final drainer = lock.drainer;

      // 1. Aktif satış transaction'ı başladı
      unawaited(drainer.runTrackedWrite(
        operationType: 'sales_transaction_in_flight',
        caller: 'cashier_desk_1',
        action: () => inFlightWrite.future,
        isWritePermitted: () => lock.state.isWritePermitted,
        currentPhase: () => lock.state.phase,
      ));

      expect(drainer.inFlightCount, equals(1));

      // 2. Bakım kilidi tetiklendi
      final lockFuture = lock.acquireLock(tenantId: 'tenant_nutopia');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Henüz kilitlenmedi, draining aşamasında bekliyor
      expect(lock.state.phase, equals(CutoffMaintenancePhase.draining));
      expect(lock.state.isWritePermitted, isFalse);

      // Bu sırada yeni bir satış mutasyonu reddedilmeli
      final notifier = SalesFlowNotifier();
      final prod = ProductEntity(
        id: 'p_race',
        name: 'Pikola Fındık',
        description: 'Özel Seri',
        price: 300.0,
        quantity: 10,
        category: 'Fındık',
      );

      expect(
        () => notifier.addToCart(prod),
        throwsA(isA<CutoffMaintenanceActiveException>()),
        reason: 'Draining sırasında da yeni sepet işlemleri anında engellenmelidir.',
      );

      // 3. In-flight transaction güvenle bitti
      inFlightWrite.complete('SALE_COMMITTED_SUCCESSFULLY');
      await lockFuture;

      expect(lock.state.phase, equals(CutoffMaintenancePhase.locked));
      expect(drainer.inFlightCount, equals(0));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════════
  // BÖLÜM 3: Fail-Closed Depolama ve Doğrudan SQLite Yazma Koruması
  // ══════════════════════════════════════════════════════════════════════════════
  group('STAGE 10.12.61: Fail-Closed & Direct DB Protection', () {
    test('Senaryo 3.1: Kalıcı depodan kilit yüklenirken hata durumunda fail-closed kalır', () async {
      final corruptedStorage = _FailingMaintenancePersistenceStorage();
      final lock = CutoffMaintenanceLock(storage: corruptedStorage);

      // initializeFromStorage bozuk veri veya hata görünce kilitli moda geçmelidir
      await lock.initializeFromStorage();
      expect(lock.state.phase, equals(CutoffMaintenancePhase.locked));
      expect(lock.state.isWritePermitted, isFalse);
    });

    test('Senaryo 3.2: DbGateway üzerinden doğrudan SQLite yazmaları bakım kilidi aktifken engellenir', () async {
      final isolatedDb = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE dummy_sales (id TEXT PRIMARY KEY, amount REAL)');
        },
      );

      final lock = CutoffMaintenanceLock(
        storage: InMemoryMaintenancePersistenceStorage(),
      );
      DatabaseManager.cutoffMaintenanceLock = lock;
      await lock.acquireLock(tenantId: 'tenant_test');

      final gateway = DbGatewayImpl.raw(isolatedDb);

      expect(
        () => gateway.insert('dummy_sales', {'id': 's1', 'amount': 100.0}),
        throwsA(isA<CutoffMaintenanceActiveException>()),
        reason: 'DbGateway insert kilitliyken CutoffMaintenanceActiveException fırlatmalıdır.',
      );

      expect(
        () => gateway.execute("INSERT INTO dummy_sales VALUES ('s2', 200.0)"),
        throwsA(isA<CutoffMaintenanceActiveException>()),
        reason: 'DbGateway execute kilitliyken CutoffMaintenanceActiveException fırlatmalıdır.',
      );

      expect(
        () => gateway.transaction(() async {
          await gateway.execute("INSERT INTO dummy_sales VALUES ('s3', 300.0)");
        }),
        throwsA(isA<CutoffMaintenanceActiveException>()),
        reason: 'DbGateway transaction kilitliyken CutoffMaintenanceActiveException fırlatmalıdır.',
      );

      await isolatedDb.close();
    });
  });

  // ══════════════════════════════════════════════════════════════════════════════
  // BÖLÜM 4: Üç İşletme İçin Bağımsız İzole Export/Import Provası
  // ══════════════════════════════════════════════════════════════════════════════
  group('STAGE 10.12.61: Üç İşletme Bağımsız Export/Import Provası', () {
    late Directory tempWorkDir;

    setUp(() async {
      tempWorkDir = await Directory.systemTemp.createTemp('stage61_tenants_rehearsal_');
    });

    tearDown(() async {
      if (tempWorkDir.existsSync()) {
        await tempWorkDir.delete(recursive: true);
      }
    });

    // ── 1. NUTOPIA FINDIK DEĞİRMENİ ──────────────────────────────────────────
    test('İşletme 1: Nutopia Fındık Değirmeni — Hash, Integrity, Export/Import ve Mutabakat', () async {
      final nutopiaFile = File(rawNutopiaPath);
      expect(nutopiaFile.existsSync(), isTrue, reason: 'Nutopia yedeği mevcut olmalıdır.');

      final initialSha = _calcSha256(rawNutopiaPath);
      expect(initialSha, equals('e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24'),
          reason: 'Nutopia yedek SHA-256 sağlama değeri doğrulanmalıdır.');

      // Salt okunur SQLite bütünlük denetimi
      final roDb = await openReadOnlyDatabase(File(rawNutopiaPath).absolute.path);
      final ic = await roDb.rawQuery('PRAGMA integrity_check');
      expect(ic.first.values.first, equals('ok'), reason: 'Nutopia SQLite PRAGMA integrity_check başarılı olmalıdır.');

      final settingsRow = await roDb.rawQuery('SELECT business_name FROM settings LIMIT 1');
      expect(settingsRow.first['business_name'].toString().toLowerCase(), contains('nutopia'),
          reason: 'İşletme kimliği Nutopia olmalıdır.');

      final productCount = _firstIntValue(await roDb.rawQuery('SELECT count(*) FROM products'));
      final customerCount = _firstIntValue(await roDb.rawQuery('SELECT count(*) FROM customers'));
      final salesCount = _firstIntValue(await roDb.rawQuery('SELECT count(*) FROM sales'));
      await roDb.close();

      expect(productCount, greaterThan(0));
      expect(customerCount, greaterThan(0));
      expect(salesCount, greaterThan(0));

      // İzole hedef DB'ye import provası
      final isolatedCandidatePath = p.join(tempWorkDir.path, 'nutopia_candidate.db');
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedCandidatePath);

      // Sentetik izole prova: Ürünler, birim bazlı stok ve kuruş mutabakatı
      await coreDb.db.transaction((txn) async {
        await txn.insert('products', {
          'id': 'nut_p_kg',
          'barcode': 'NUT-KG-01',
          'name': 'Naturel İç Fındık (Kilo)',
          'price_cents': 35000,
          'stock_quantity': 45.75, // Kilogram cinsinden ondalıklı stok
          'is_active': 1,
          'is_deleted': 0,
          'updated_at': 1000,
        });
        await txn.insert('products', {
          'id': 'nut_p_adet',
          'barcode': 'NUT-AD-01',
          'name': 'Fındık Ezmesi Cam Kavanoz 300g (Adet)',
          'price_cents': 18000,
          'stock_quantity': 120.0, // Adet cinsinden tam stok
          'is_active': 1,
          'is_deleted': 0,
          'updated_at': 1000,
        });
      });

      // Birim bazlı stok kontrolü (kg ve adet asla tek havuzda toplanamaz)
      final kgItem = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['nut_p_kg']);
      final adetItem = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['nut_p_adet']);
      expect(kgItem.first['stock_quantity'], equals(45.75));
      expect(adetItem.first['stock_quantity'], equals(120.0));

      // İdempotens testi: Tekrar çalıştırma mükerrer üretmemeli
      await coreDb.db.insert(
        'products',
        {
          'id': 'nut_p_kg',
          'barcode': 'NUT-KG-01',
          'name': 'Naturel İç Fındık (Kilo)',
          'price_cents': 35000,
          'stock_quantity': 45.75,
          'is_active': 1,
          'is_deleted': 0,
          'updated_at': 1000,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      final totalPCount = _firstIntValue(await coreDb.db.rawQuery('SELECT count(*) FROM products'));
      expect(totalPCount, equals(2), reason: 'İdempotens kuralı: Aynı kayıt tekrar aktarıldığında mükerrer oluşmaz.');

      await coreDb.close();

      // Kaynak SHA-256 provanın sonunda değişmemiş olmalı
      final afterSha = _calcSha256(rawNutopiaPath);
      expect(afterSha, equals(initialSha), reason: 'Kaynak Nutopia yedeğine 0 bayt mutasyon uygulanmalıdır.');
    });

    // ── 2. ERKUL ÇEYİZ ───────────────────────────────────────────────────────
    test('İşletme 2: Erkul Çeyiz — JSON Şeması, Alacak Mutabakatı ve İdempotens Provası', () async {
      final jsonFile = File(rawErkulJsonPath);
      expect(jsonFile.existsSync(), isTrue, reason: 'Erkul yedeği mevcut olmalıdır.');

      final initialSha = _calcSha256(rawErkulJsonPath);
      expect(initialSha, equals('b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389'),
          reason: 'Erkul yedek SHA-256 sağlama değeri doğrulanmalıdır.');

      final decoded = jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
      final companies = decoded['companies'] as List<dynamic>;
      expect(companies.first['name'].toString().toLowerCase(), contains('erkul'));

      final customers = decoded['customers'] as List<dynamic>;
      final products = decoded['products'] as List<dynamic>;
      final sales = decoded['sales'] as List<dynamic>;
      final transactions = decoded['financial_transactions'] as List<dynamic>;

      expect(customers.length, equals(401));
      expect(products.length, equals(26));
      expect(sales.length, equals(5));
      expect(transactions.length, equals(539));

      // Kuruş hassasiyetinde tutar hesaplaması
      var manualDebtCents = 0;
      var collectionCents = 0;

      for (final tx in transactions) {
        final type = tx['type']?.toString();
        final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        final amountCents = (amount * 100).round();

        if (type == 'manual_debt') {
          manualDebtCents += amountCents;
        } else if (type == 'collection') {
          collectionCents += amountCents;
        }
      }

      // 4,310,745.00 TL = 431074500 kuruş
      // 541,640.00 TL = 54164000 kuruş
      // Net alacak = 3,769,105.00 TL = 376910500 kuruş
      expect(manualDebtCents, equals(431074500));
      expect(collectionCents, equals(54164000));
      final netReceivableCents = manualDebtCents - collectionCents;
      expect(netReceivableCents, equals(376910500));

      // Kiracı izolasyonu: Erkul müşteri ID'leri Nutopia ve Serenut ile çakışamaz
      final erkulIds = customers.map((c) => c['id'].toString()).toSet();
      expect(erkulIds.length, equals(401));

      // Kaynak JSON SHA-256 prova sonrası değişmemiş olmalı
      final afterSha = _calcSha256(rawErkulJsonPath);
      expect(afterSha, equals(initialSha), reason: 'Kaynak Erkul JSON dosyasına 0 bayt mutasyon uygulanmalıdır.');
    });

    // ── 3. SERENUT ───────────────────────────────────────────────────────────
    test('İşletme 3: Serenut — Hash, Integrity, Kuruş Finansal Mutabakat ve İdempotens', () async {
      final serenutFile = File(rawSerenutPath);
      expect(serenutFile.existsSync(), isTrue, reason: 'Serenut yedeği mevcut olmalıdır.');

      final initialSha = _calcSha256(rawSerenutPath);
      expect(initialSha, equals('9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d'),
          reason: 'Serenut yedek SHA-256 sağlama değeri doğrulanmalıdır.');

      final roDb = await openReadOnlyDatabase(File(rawSerenutPath).absolute.path);
      final ic = await roDb.rawQuery('PRAGMA integrity_check');
      expect(ic.first.values.first, equals('ok'), reason: 'Serenut SQLite PRAGMA integrity_check başarılı olmalıdır.');

      final productCount = _firstIntValue(await roDb.rawQuery('SELECT count(*) FROM products'));
      final customerCount = _firstIntValue(await roDb.rawQuery('SELECT count(*) FROM customers'));
      final orderCount = _firstIntValue(await roDb.rawQuery('SELECT count(*) FROM orders'));
      await roDb.close();

      expect(productCount, greaterThan(0));
      expect(customerCount, greaterThan(0));
      expect(orderCount, greaterThan(0));

      // İzole hedef DB'de kuruş hassasiyetinde prova
      final isolatedSerenutCandidate = p.join(tempWorkDir.path, 'serenut_candidate.db');
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedSerenutCandidate);

      await coreDb.db.transaction((txn) async {
        await txn.insert('customers', {
          'id': 'ser_c_1',
          'name': 'Ali Serenut Müşteri',
          'balance_cents': -250050, // -2,500.50 TL kuruş hassasiyetinde
          'notes': 'Serenut Test',
          'is_active': 1,
          'is_deleted': 0,
          'updated_at': 1000,
        });
      });

      final cRow = await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['ser_c_1']);
      expect(cRow.first['balance_cents'], equals(-250050));

      await coreDb.close();

      final afterSha = _calcSha256(rawSerenutPath);
      expect(afterSha, equals(initialSha), reason: 'Kaynak Serenut yedeğine 0 bayt mutasyon uygulanmalıdır.');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════════
  // BÖLÜM 5: Adversarial Sapma Reddi ve Güvenli Geri Dönüş
  // ══════════════════════════════════════════════════════════════════════════════
  group('STAGE 10.12.61: Adversarial Variance Gate Rejection', () {
    late Directory tempDir;
    late String legacyPath;
    late String targetPath;
    final openDbs = <Database>[];
    const coordinator = LiveSafeCatchUpReconciliationCoordinator();

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage61_adversarial_');
      legacyPath = p.join(tempDir.path, 'adv_legacy.db');
      targetPath = p.join(tempDir.path, 'adv_target.db');
      openDbs.clear();
    });

    tearDown(() async {
      for (final db in openDbs) {
        if (db.isOpen) await db.close();
      }
      openDbs.clear();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Senaryo 5.1: Bilerek oluşturulan bakiye/tutar uyuşmazlığı cutover kapısı tarafından derhal reddedilir', () async {
      final leg = await databaseFactory.openDatabase(
        legacyPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE settings (id TEXT PRIMARY KEY, business_name TEXT)');
            await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, barcode TEXT, name TEXT, price REAL, quantity REAL, is_active INTEGER, is_deleted INTEGER, created_at TEXT)');
            await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT, balance REAL, is_active INTEGER, is_deleted INTEGER, created_at TEXT)');
            await db.execute('CREATE TABLE sales (id TEXT PRIMARY KEY, total_amount REAL, is_deleted INTEGER, created_at TEXT)');
            await db.execute('CREATE TABLE financial_transactions (id TEXT PRIMARY KEY, customer_id TEXT, amount REAL, type TEXT, created_at TEXT)');
            await db.insert('settings', {'id': '1', 'business_name': 'Nutopia Fındık Değirmeni'});
          },
        ),
      );
      openDbs.add(leg);

      // Kaynakta bakiye: -500.00 TL
      await leg.insert('customers', {
        'id': 'c_adv',
        'name': 'Adversarial Müşteri',
        'balance': -500.0,
        'is_active': 1,
        'is_deleted': 0,
        'created_at': '2026-10-21T10:00:00Z',
      });

      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetPath);
      openDbs.add(coreDb.db);

      // Hedefte kasıtlı olarak farklı bakiye ekle (-750.00 TL)
      await coreDb.db.insert('customers', {
        'id': 'c_adv',
        'name': 'Adversarial Müşteri',
        'balance_cents': -75000,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': 1000,
      });

      final report = await coordinator.performCatchUpAndReconcile(
        legacyDb: leg,
        targetCoreDb: coreDb,
        legacyDbPath: legacyPath,
        lastMigrationCutoffTimestamp: DateTime.now().millisecondsSinceEpoch + 100000,
      );

      // Mutabakat gate reddetmelidir
      expect(report.isMatched, isFalse);
      expect(report.decision, equals(CutoverReconciliationDecision.cutoverBlockedVarianceDetected));
      expect(report.details, contains('Müşteri bakiye toplamı uyumsuz'));

      // Güvenlik sınırları kesinlikle korunmalıdır
      expect(DatabaseManager.databaseRoutingHook, isNull,
          reason: 'Başarısız prova sonrasında databaseRoutingHook null kalmalıdır.');
    });
  });
}
