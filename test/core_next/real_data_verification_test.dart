// test/core_next/real_data_verification_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_product_repository.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory sandboxDir;
  late String sandboxLegacyDbPath;
  late String sandboxCoreDbPath;

  setUpAll(() async {
    // İzole, geçici sandbox dizini oluştur (Asla canlı %APPDATA% yoluna erişilmez)
    sandboxDir = await Directory.systemTemp.createTemp('serenut_isolated_test_');
    sandboxLegacyDbPath = p.join(sandboxDir.path, 'legacy_fixture.db');
    sandboxCoreDbPath = p.join(sandboxDir.path, 'core_v2.db');

    // Eski SQLite şemasını ve deterministik test verisini fixture factory ile oluştur
    final legacyDb = await openDatabase(
      sandboxLegacyDbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            barcode TEXT,
            sku TEXT,
            name TEXT,
            price REAL,
            cost_price REAL,
            purchase_price REAL,
            vat_rate INTEGER,
            quantity REAL,
            min_stock REAL,
            sale_type TEXT,
            unit TEXT,
            image_url TEXT,
            is_active INTEGER DEFAULT 1,
            is_deleted INTEGER DEFAULT 0
          );
        ''');

        await db.execute('''
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            name TEXT,
            phone TEXT,
            email TEXT,
            balance REAL,
            balance_minor INTEGER,
            credit_limit REAL,
            credit_limit_minor INTEGER,
            is_active INTEGER DEFAULT 1,
            is_deleted INTEGER DEFAULT 0
          );
        ''');

        await db.execute('''
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

        // 1. Ürün Fixture Verileri (Normal, Tartılı ve Pasif Ürünler)
        await db.insert('products', {
          'id': 'prod-kavur-1',
          'barcode': '74296569-af8b-4638-8d2f-cbccff8a0f8d',
          'name': 'Kır Kavur 1Kg Pk.',
          'price': 70.0, // 70,00 TL
          'cost_price': 50.0,
          'vat_rate': 20,
          'quantity': 12879.0,
          'is_active': 1,
          'is_deleted': 0,
        });

        await db.insert('products', {
          'id': 'prod-ezine-2',
          'barcode': '86900010002',
          'name': 'Ezine Peyniri',
          'price': 180.0,
          'cost_price': 130.0,
          'vat_rate': 10,
          'quantity': 50.0,
          'sale_type': 'weighed',
          'unit': 'kg',
          'is_active': 1,
          'is_deleted': 0,
        });

        await db.insert('products', {
          'id': 'prod-pasif-3',
          'barcode': '86900010003',
          'name': 'Eski Pasif Ürün',
          'price': 10.0,
          'vat_rate': 20,
          'quantity': 0.0,
          'is_active': 0,
          'is_deleted': 0,
        });

        // 2. Müşteri Fixture Verileri (Peşin, Kararlı Cari ve 2 Adet Migration 60 Tetikleyici Hatalı Cari)
        await db.insert('customers', {
          'id': '',
          'name': 'Peşin Müşteri',
          'balance': 0.0,
          'balance_minor': 0,
          'credit_limit': 0.0,
          'credit_limit_minor': 0,
          'is_active': 1,
        });

        await db.insert('customers', {
          'id': 'cust-mehmet-1',
          'name': 'MEHMET DEMİR',
          'phone': '05551112233',
          'balance': 115.0, // +115,00 TL Alacak
          'balance_minor': 11500, // Uyumlu
          'credit_limit': 1000.0,
          'credit_limit_minor': 100000,
          'is_active': 1,
        });

        // Hatalı Cari 1: ŞEN*** (-2.266,68 TL Yetkili bakiye, ama trigger bayat olarak +933,32 TL bırakmış)
        await db.insert('customers', {
          'id': 'cust-senol-stale-1',
          'name': 'ŞENOL YILDIRIM',
          'balance': -2266.68,
          'balance_minor': 93332,
          'credit_limit': 5000.0,
          'credit_limit_minor': 500000,
          'is_active': 1,
        });

        // Hatalı Cari 2: TUĞ*** (-120,00 TL Yetkili bakiye, ama trigger bayat olarak 0 bırakmış)
        await db.insert('customers', {
          'id': 'cust-tugba-stale-2',
          'name': 'TUĞBA KAYA',
          'balance': -120.0,
          'balance_minor': 0,
          'credit_limit': 1000.0,
          'credit_limit_minor': 100000,
          'is_active': 1,
        });

        // 3. Satış Fixture Verileri
        await db.insert('sales', {
          'id': 'sale-af9b6fc4-8f06-4888-bf1f-b06cb5e575dd',
          'receipt_no': 'REC-LEGACY-001',
          'customer_id': 'cust-mehmet-1',
          'total_amount': 500.0,
          'paid_amount': 0.0,
          'payment_method': 'debt',
          'status': 'completed',
          'idempotency_key': '388c4de3-f234-4ca9-880f-20e8a928f7ba',
          'created_at': DateTime.now().toIso8601String(),
        });

        await db.insert('sales', {
          'id': 'sale-legacy-cash-2',
          'receipt_no': 'REC-LEGACY-002',
          'customer_id': null,
          'total_amount': 140.0,
          'paid_amount': 140.0,
          'payment_method': 'cash',
          'status': 'completed',
          'idempotency_key': '499d5ef4-g345-5db0-991g-31f9b039g8cb',
          'created_at': DateTime.now().toIso8601String(),
        });
      },
    );
    await legacyDb.close();
  });

  tearDownAll(() async {
    try {
      if (await sandboxDir.exists()) {
        await sandboxDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('İzole Fixture Veritabanı ile Doğrulama ve Mutabakat Testleri', () {
    test('Aşama 1: İzole Veritabanı Taraması ve İstatistik Tespiti', () async {
      final legacyDb = await openDatabase(sandboxLegacyDbPath, readOnly: true);

      // Tabloları listele
      final tables = await legacyDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
      );
      final tableNames = tables.map((t) => t['name'] as String).toList();
      print('\n[FİXTURE ANALİZİ] Mevcut Tablo Sayısı: ${tableNames.length}');

      final productCount = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM products')).first['c'] as int? ?? 0;
      final customerCount = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM customers')).first['c'] as int? ?? 0;
      final salesCount = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int? ?? 0;

      final balanceSumRow = await legacyDb.rawQuery(
        'SELECT SUM(balance) as total_balance FROM customers',
      );
      final double totalCustomerBalance =
          (balanceSumRow.first['total_balance'] as num? ?? 0.0).toDouble();

      print('[FİXTURE ANALİZİ] Ürün Sayısı: $productCount');
      print('[FİXTURE ANALİZİ] Müşteri Sayısı: $customerCount');
      print('[FİXTURE ANALİZİ] Satış Sayısı: $salesCount');
      print(
          '[FİXTURE ANALİZİ] Toplam Müşteri Bakiyesi (Eski Double): ${totalCustomerBalance.toStringAsFixed(2)} TL');

      expect(productCount, 3, reason: 'Fixture ürün sayısı tam eşleşmelidir');
      expect(customerCount, 4, reason: 'Fixture müşteri sayısı tam eşleşmelidir');
      expect(salesCount, 2, reason: 'Fixture satış sayısı tam eşleşmelidir');

      await legacyDb.close();
    });

    test('Aşama 2: İzole Veri Tabanının Yeni Kuruş Şemasına Migrasyonu ve Mutabakat', () async {
      // 1. Yeni veritabanını aç
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: sandboxCoreDbPath);
      final legacyDb = await openDatabase(sandboxLegacyDbPath, readOnly: true);

      // 2. Migrasyonu çalıştır
      final bridge = MigrationBridgeEngine(coreDb);
      final report = await bridge.migrateFromLegacy(legacyDb);

      print('\n[MİGRASYON RAPORU]');
      print('Aktarılan Ürün Sayısı: ${report.productsMigrated}');
      print('Aktarılan Müşteri Sayısı: ${report.customersMigrated}');
      print('Aktarılan Satış Sayısı: ${report.salesMigrated}');
      print('Tamamlanma Süresi: ${report.durationMs} ms');

      expect(report.isSuccess, true, reason: report.errorMessage);
      expect(report.productsMigrated, 3);
      expect(report.customersMigrated, 4);
      expect(report.salesMigrated, 2);

      // 3. Mutabakat: Müşteri bakiyelerinin kuruş bazında tam eşitliği
      final legacyBalRow = await legacyDb.rawQuery(
        'SELECT SUM(balance) as total_balance, SUM(balance_minor) as total_minor FROM customers',
      );
      final double legacyTotalBal =
          (legacyBalRow.first['total_balance'] as num? ?? 0.0).toDouble();
      final int legacyTotalMinor =
          (legacyBalRow.first['total_minor'] as num? ?? 0).toInt();

      final coreBalRow = await coreDb.db.rawQuery(
        'SELECT SUM(balance_cents) as total_cents FROM customers',
      );
      final int coreTotalCents =
          (coreBalRow.first['total_cents'] as num? ?? 0).toInt();

      final expectedFromDouble = (legacyTotalBal * 100).round();
      print('\n[FİNANSAL MUTABAKAT DETAYI]');
      print('Eski DB SUM(balance) (Double): ${legacyTotalBal.toStringAsFixed(2)} TL ($expectedFromDouble kuruş)');
      print('Eski DB SUM(balance_minor): $legacyTotalMinor kuruş');
      print('Yeni Core DB SUM(balance_cents): $coreTotalCents kuruş (${MoneyCents(coreTotalCents).formatTL()})');

      print('Tespit Edilen ve Yetkili Deftere Düzeltilen Müşteri Sayısı: ${report.customerDiscrepancies.length}');
      for (final d in report.customerDiscrepancies) {
        final masked = d.customerName.length >= 3 ? '${d.customerName.substring(0, 3)}***' : '***';
        print('  - $masked (ID: ${d.customerId}): Yetkili=${d.authoritativeBalanceCents} kuruş, BayatMinor=${d.staleMinorCents} kuruş, Fark=${d.discrepancyCents} kuruş');
      }

      // KESİN ADLİ MUTABAKAT DOĞRULAMASI:
      // Yeni kuruş şeması yetkili defter (balance) ile kuruşu kuruşuna eşit olmalıdır.
      expect(coreTotalCents, expectedFromDouble,
          reason: 'Yeni Core DB kuruş toplamı yetkili defterle tam denk olmalıdır!');
      expect(report.customerDiscrepancies.length, 2,
          reason: 'Yalnızca Migration 60 stale trigger hatası olan 2 müşteride fark olmalıdır!');

      final totalResolvedDiscrepancy = report.customerDiscrepancies.fold<int>(
        0, (sum, d) => sum + d.discrepancyCents,
      );
      expect(totalResolvedDiscrepancy, 332000,
          reason: 'Düzeltilen toplam fark tam 332.000 kuruş (3.320,00 TL) olmalıdır!');

      await legacyDb.close();
      await coreDb.close();
    });

    test('Aşama 3: Migre Edilen İzole Veritabanı Üzerinde Canlı Kasa Satış Simülasyonu', () async {
      // 1. Migre edilen izole veritabanını aç
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: sandboxCoreDbPath);
      final productRepo = SqliteProductRepository(coreDb.db);
      final ledgerRepo = SqliteLedgerRepository(coreDb.db);
      final hardwareWorker = HardwareWorker();
      await hardwareWorker.initialize();

      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        hardwareWorker: hardwareWorker,
        defaultActor: ActorContext.testManager,
      );
      final salesNotifier = CoreSalesFlowNotifier(checkoutUseCase);

      // 2. Aktif ürünü barkodla bul
      const targetBarcode = '74296569-af8b-4638-8d2f-cbccff8a0f8d';
      final product = await productRepo.getByBarcode(targetBarcode);
      expect(product, isNotNull, reason: 'Ürün bulunmalıdır');
      print('\n[KASA SİMÜLASYONU]');
      print('Test Edilen Ürün: ${product!.name} (Barkod: ${product.barcode}, Fiyat: ${product.price.formatTL()})');

      // 3. Aktif müşteriyi bul
      final customers = await coreDb.db.query(
        'customers',
        where: 'id = ?',
        whereArgs: ['cust-mehmet-1'],
      );
      expect(customers.isNotEmpty, true, reason: 'Müşteri bulunmalıdır');
      final targetCustomer = CustomerEntity.fromMap(customers.first);
      print('Test Edilen Müşteri: ${targetCustomer.name} (Mevcut Bakiye: ${targetCustomer.balance.formatTL()})');

      // 4. Sepete ekle ve veresiye satış yap (2 adet x 70 TL = 140 TL)
      salesNotifier.selectCustomer(targetCustomer);
      salesNotifier.addProduct(product, quantity: 2);

      final total = salesNotifier.state.total;
      print('Sepet Toplamı: ${total.formatTL()}');
      expect(total.value, 14000); // 140,00 TL

      // Tamamı veresiye
      salesNotifier.setPaymentSplits([
        PaymentSplitEntity(type: PaymentType.onAccount, amount: total),
      ]);

      final initialBalance = targetCustomer.balance;
      final initialStock = product.stockQuantity;

      final completedSale = await salesNotifier.completeCheckout(
        receiptNo: 'GERCEK-TEST-0001',
        storeTitle: 'Serenut Test Kasa',
      );

      expect(completedSale.receiptNo, 'GERCEK-TEST-0001');

      // 5. Stok ve bakiye doğrulama
      final updatedProduct = await productRepo.getByBarcode(targetBarcode);
      expect(updatedProduct!.stockQuantity, initialStock - 2);

      final updatedCustomer = await ledgerRepo.getCustomer(targetCustomer.id);
      expect(updatedCustomer!.balance, initialBalance - total);

      print('Satış Sonrası Güncel Bakiye: ${updatedCustomer.balance.formatTL()}');
      print('Satış Sonrası Güncel Stok: ${updatedProduct.stockQuantity}');
      print('Fiş ve Hareket Başarıyla Kaydedildi!');

      await hardwareWorker.dispose();
      await coreDb.close();
    });
  });
}
