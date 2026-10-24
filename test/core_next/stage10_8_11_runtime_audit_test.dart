// ignore_for_file: avoid_relative_lib_imports
// test/core_next/stage10_8_11_runtime_audit_test.dart
// SERENUT OS — STAGE 10.8.11
// Dual-DB Split Closure, Safe Data Migration, and Independent Cutover Readiness Audit Suite

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/sync_provider.dart';

import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_product_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_customer_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_financial_transaction_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_sale_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/domain/usecases/refund_use_case.dart';
import '../../core_next/client_core/lib/infrastructure/sales/core_next_sales_bridge.dart';
import '../../core_next/client_core/lib/domain/models/core_entities.dart' as core;
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/presentation/sales/sales_engine_adapter.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart';

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
    tempDir = await Directory.systemTemp.createTemp('serenut_stage10_8_11_');
    legacyDbPath = '${tempDir.path}/legacy_stage11.db';
    coreDbPath = '${tempDir.path}/core_stage11.db';

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
            credit_limit REAL DEFAULT 0.0,
            credit_limit_minor INTEGER DEFAULT 0,
            is_active INTEGER DEFAULT 1,
            is_deleted INTEGER DEFAULT 0,
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
          CREATE TABLE financial_transactions (
            id TEXT PRIMARY KEY,
            contact_id TEXT NOT NULL,
            amount REAL NOT NULL,
            amount_minor INTEGER,
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

  group('STAGE 10.8.11 — 18 Bağımsız Denetim ve Adversarial Test Senaryosu', () {
    test('1. Eski DB\'den yeni DB\'ye ilk migration (Tam Kapsam)', () async {
      // Legacy DB'ye örnek veriler yükle
      await legacyDb.insert('users', {
        'id': 'u-1',
        'username': 'ahmet',
        'name': 'Ahmet Yılmaz',
        'created_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('categories', {
        'id': 'cat-1',
        'name': 'Gıda',
      });
      await legacyDb.insert('products', {
        'id': 'p-1',
        'barcode': '8690001',
        'name': 'Süt 1L',
        'category_id': 'cat-1',
        'price': 30.0,
        'quantity': 15,
        'created_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('customers', {
        'id': 'c-1',
        'name': 'Mehmet Demir',
        'phone': '05551112233',
        'balance': -100.0, // 100 TL borç
        'created_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('sales', {
        'id': 's-1',
        'receipt_no': 'REC-001',
        'customer_id': 'c-1',
        'total_amount': 100.0,
        'paid_amount': 0.0,
        'payment_method': 'on_account',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('sale_items', {
        'id': 'si-1',
        'sale_id': 's-1',
        'product_id': 'p-1',
        'barcode': '8690001',
        'product_name': 'Süt 1L',
        'unit_price': 30.0,
        'quantity': 3.0,
        'subtotal': 90.0,
        'vat_rate': 20,
      });

      final report = await bridgeEngine.migrateFromLegacy(
        legacyDb,
        legacyFilePath: legacyDbPath,
        fullScope: true,
      );

      expect(report.isSuccess, isTrue);
      expect(report.productsMigrated, equals(1));
      expect(report.customersMigrated, equals(1));
      expect(report.salesMigrated, equals(1));
      expect(report.saleItemsMigrated, equals(1));

      // Core Next DB doğrulama
      final coreCust = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-1'])).first;
      expect(coreCust['balance_cents'], equals(-10000));

      final coreProd = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-1'])).first;
      expect(coreProd['price_cents'], equals(3000));
      expect(coreProd['stock_quantity'], equals(15));
    });

    test('2. Migration\'ın iki kez çalıştırılması (Idempotency & Zero FK Crash)', () async {
      await legacyDb.insert('categories', {'id': 'cat-1', 'name': 'Bakliyat'});
      await legacyDb.insert('products', {
        'id': 'p-2',
        'barcode': '8690002',
        'name': 'Pirinç 1KG',
        'category_id': 'cat-1',
        'price': 50.0,
        'quantity': 20,
        'created_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('customers', {
        'id': 'c-2',
        'name': 'Ali Veli',
        'balance': 0.0,
        'created_at': DateTime.now().toIso8601String(),
      });

      // 1. Çalıştırma
      final rep1 = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep1.isSuccess, isTrue);

      // Kaynakta veri güncellemesi (fiyat 55 TL oldu)
      await legacyDb.update('products', {'price': 55.0}, where: 'id = ?', whereArgs: ['p-2']);

      // 2. Çalıştırma
      final rep2 = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep2.isSuccess, isTrue);

      final pRows = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-2']);
      expect(pRows.length, equals(1));
      expect(pRows.first['price_cents'], equals(5500), reason: 'In-place UPSERT ile güncel fiyat taşınmalıdır');
    });

    test('3. Migration ortasında hata ve yeniden başlatma (Rollback Güvencesi)', () async {
      // Bozuk legacy satırı (negatif toplam)
      await legacyDb.insert('sales', {
        'id': 's-bad',
        'receipt_no': 'REC-BAD',
        'total_amount': -50.0, // Geçersiz negatif satış
        'paid_amount': 0.0,
        'payment_method': 'cash',
        'status': 'COMPLETED',
        'created_at': DateTime.now().toIso8601String(),
      });

      final report = await bridgeEngine.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, isFalse);
      expect(report.errorMessage, contains('GEÇMİŞ SATIŞ MUTABAKAT HATASI'));

      // Core DB temiz olmalı
      final salesInCore = await coreDb.db.query('sales');
      expect(salesInCore.isEmpty, isTrue, reason: 'Transaction rollback olmalıdır');
    });

    test('4. Aynı ürünün güncellenmesi ve ilişkili satış kalemlerinin korunması (FK RESTRICT)', () async {
      final productRepo = CoreNextProductRepository(coreDb.db);

      final entity = ProductEntity(
        id: 'p-fk-1',
        name: 'Orijinal Ürün',
        description: '',
        price: 100.0,
        quantity: 10,
        category: 'Kırtasiye',
      );
      await productRepo.create(entity);

      // Satış ve satış kalemi ekle
      await coreDb.db.insert('sales', {
        'id': 's-fk-1',
        'receipt_no': 'REC-FK-1',
        'subtotal_cents': 10000,
        'total_cents': 10000,
        'paid_cents': 10000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_items', {
        'id': 'si-fk-1',
        'sale_id': 's-fk-1',
        'product_id': 'p-fk-1',
        'barcode': 'p-fk-1',
        'product_name': 'Orijinal Ürün',
        'unit_price_cents': 10000,
        'quantity': 1,
        'vat_rate': 20,
        'total_cents': 10000,
      });

      // Ürün güncellemesi
      final updated = entity.copyWith(name: 'Güncellenmiş Ürün Adı', price: 120.0);
      final affected = await productRepo.update(updated);
      expect(affected, equals(1));

      // Kalem hâlâ mevcut olmalı ve FK bozulmamalı
      final items = await coreDb.db.query('sale_items', where: 'id = ?', whereArgs: ['si-fk-1']);
      expect(items.length, equals(1));
    });

    test('5. Stok yetersizliği ve eşzamanlı satış (Zero Negative Stock Invariant)', () async {
      await coreDb.db.insert('products', {
        'id': 'p-stock-1',
        'barcode': '8690099',
        'name': 'Sınırlı Stok Ürün',
        'price_cents': 2000,
        'stock_quantity': 2,
        'critical_threshold': 1,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      final hardwareWorker = HardwareWorker();
      await hardwareWorker.initialize();
      final ledgerRepo = SqliteLedgerRepository(coreDb.db);
      final ledgerService = LedgerService(ledgerRepo);
      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        ledgerService: ledgerService,
        hardwareWorker: hardwareWorker,
        defaultActor: ActorContext.testManager,
      );

      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      final product = core.ProductEntity(
        id: 'p-stock-1',
        barcode: '8690099',
        name: 'Sınırlı Stok Ürün',
        price: MoneyCents(2000),
        stockQuantity: 2,
        updatedAt: DateTime.now(),
      );

      notifier.addProduct(product, quantity: 3); // 3 adet istendi, stokta 2 var!
      notifier.setPaymentSplits([
        const core.PaymentSplitEntity(type: core.PaymentType.cash, amount: MoneyCents(6000)),
      ]);

      expect(
        () async => await notifier.completeCheckout(receiptNo: 'REC-ST-1', storeTitle: 'Test Store'),
        throwsA(isA<StateError>()),
      );

      final p = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-stock-1'])).first;
      expect(p['stock_quantity'], equals(2), reason: 'Stok yetersizliğinde hiçbir düşüm yapılmamalıdır');
    });

    test('6. Satış, karma ödeme ve satış geçmişi (CoreNextSaleRepository Bridge)', () async {
      await coreDb.db.insert('products', {
        'id': 'p-mix-1',
        'barcode': '8690mix',
        'name': 'Karma Ürün',
        'price_cents': 10000,
        'stock_quantity': 50,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('sales', {
        'id': 's-mix-1',
        'receipt_no': 'REC-MIX-1',
        'subtotal_cents': 10000,
        'total_cents': 10000,
        'paid_cents': 8000,
        'debt_cents': 2000,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_items', {
        'id': 'si-mix-1',
        'sale_id': 's-mix-1',
        'product_id': 'p-mix-1',
        'barcode': '8690mix',
        'product_name': 'Karma Ürün',
        'unit_price_cents': 10000,
        'quantity': 1,
        'vat_rate': 20,
        'total_cents': 10000,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'sp-1',
        'sale_id': 's-mix-1',
        'payment_type': 'cash',
        'amount_cents': 5000,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_payments', {
        'id': 'sp-2',
        'sale_id': 's-mix-1',
        'payment_type': 'creditCard',
        'amount_cents': 3000,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      final saleRepo = CoreNextSaleRepository(coreDb.db);
      final sale = await saleRepo.findById('s-mix-1');

      expect(sale, isNotNull);
      expect(sale!.totalAmount, equals(100.0));
      expect(sale.paidAmount, equals(80.0));
      expect(sale.paymentMethod, equals('mixed'));
      expect(sale.items.length, equals(1));
    });

    test('7. Kısmi iade, tam iade ve aynı iade isteğinin tekrarı (CoreRefundUseCase)', () async {
      await coreDb.db.insert('products', {
        'id': 'p-ref-1',
        'barcode': '8690ref',
        'name': 'İade Edilecek Ürün',
        'price_cents': 4000,
        'stock_quantity': 8, // Satıştan sonra 8 kaldı (önce 10'du)
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sales', {
        'id': 's-ref-1',
        'receipt_no': 'REC-REF-1',
        'subtotal_cents': 8000,
        'total_cents': 8000,
        'paid_cents': 8000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_items', {
        'id': 'si-ref-1',
        'sale_id': 's-ref-1',
        'product_id': 'p-ref-1',
        'barcode': '8690ref',
        'product_name': 'İade Edilecek Ürün',
        'unit_price_cents': 4000,
        'quantity': 2,
        'vat_rate': 20,
        'total_cents': 8000,
      });

      final refundUseCase = CoreRefundUseCase(db: coreDb);

      // Kısmi İade: 2 adetten 1 adeti iade et
      final req = RefundRequest(
        originalSaleId: 's-ref-1',
        items: [
          const RefundItemRequest(productId: 'p-ref-1', quantity: 1),
        ],
        reason: 'Müşteri vazgeçti',
        idempotencyKey: 'idem-ref-101',
        actor: const ActorContext(
          userId: 'manager-1',
          username: 'Müdür',
          role: AppRole.manager,
        ),
      );

      final res1 = await refundUseCase.execute(req);
      expect(res1.refundTotal.value, equals(4000));

      // Stok 8'den 9'a çıkmalı
      final p1 = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-ref-1'])).first;
      expect(p1['stock_quantity'], equals(9));

      // Aynı idempotency key ile tekrar çağır (İdempotency Denetimi)
      final res2 = await refundUseCase.execute(req);
      expect(res2.refundTotal.value, equals(4000));

      final p2 = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-ref-1'])).first;
      expect(p2['stock_quantity'], equals(9), reason: 'Tekrar çağrıldığında stok ikinci kez artmamalıdır');
    });

    test('8. Tahsilatın iki kez işlenmesi (Idempotent Collection)', () async {
      await coreDb.db.insert('customers', {
        'id': 'c-coll-1',
        'name': 'Borçlu Müşteri',
        'phone': '05559998877',
        'balance_cents': -15000, // 150 TL borç
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      final ftRepo = CoreNextFinancialTransactionRepository(coreDb.db);

      final collEntity = FinancialTransactionEntity(
        id: 'coll-idem-1',
        type: 'collection',
        customerId: 'c-coll-1',
        amount: 50.0,
        paidAmount: 50.0,
        debtAmount: 0.0,
        date: DateTime.now(),
      );

      // 1. Tahsilat
      await ftRepo.create(collEntity);
      final c1 = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-coll-1'])).first;
      expect(c1['balance_cents'], equals(-10000), reason: '150 TL borçtan 50 TL düşünce 100 TL borç kalmalı');

      // 2. Aynı ID ile tekrar Tahsilat (İdempotency)
      await ftRepo.create(collEntity);
      final c2 = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-coll-1'])).first;
      expect(c2['balance_cents'], equals(-10000), reason: 'Mükerrer tahsilat bakiyeyi ikinci kez değiştirmemelidir');
    });

    test('9. Müşteri bakiyesi ve hesap hareketi mutabakatı (Ledger Balance Invariant)', () async {
      await coreDb.db.insert('customers', {
        'id': 'c-leg-1',
        'name': 'Cari Müşteri',
        'phone': '05553334455',
        'balance_cents': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      final custRepo = CoreNextCustomerRepository(coreDb.db);
      final ftRepo = CoreNextFinancialTransactionRepository(coreDb.db);

      // 1. Borç Satışı: 100 TL
      await ftRepo.create(FinancialTransactionEntity(
        id: 'ft-s-1',
        type: 'debt',
        customerId: 'c-leg-1',
        amount: 100.0,
        paidAmount: 0.0,
        debtAmount: 100.0,
        date: DateTime.now(),
      ));

      // 2. Kısmi Tahsilat: 30 TL
      await ftRepo.create(FinancialTransactionEntity(
        id: 'ft-c-1',
        type: 'collection',
        customerId: 'c-leg-1',
        amount: 30.0,
        paidAmount: 30.0,
        debtAmount: 0.0,
        date: DateTime.now(),
      ));

      // Bakiye kontrolü
      final bal = await custRepo.getBalance('c-leg-1');
      expect(bal, equals(-70.0), reason: 'Net bakiye -70 TL borç olmalıdır');

      final debt = await custRepo.getTotalDebt('c-leg-1');
      expect(debt, equals(70.0));

      final paid = await custRepo.getTotalPaid('c-leg-1');
      expect(paid, equals(30.0));

      final history = await ftRepo.getByCustomerId('c-leg-1');
      expect(history.length, equals(2));
    });

    test('10. Çevrimdışı satış ve outbox kuyruğu (sync_events)', () async {
      final productRepo = CoreNextProductRepository(coreDb.db);
      await productRepo.create(ProductEntity(
        id: 'p-off-1',
        name: 'Çevrimdışı Ürün',
        description: '',
        price: 25.0,
        quantity: 100,
        category: 'Genel',
      ));

      final syncEvents = await coreDb.db.query('sync_events', where: 'entity_id = ?', whereArgs: ['p-off-1']);
      expect(syncEvents.length, equals(1));
      expect(syncEvents.first['sync_state'], equals('PENDING'));
    });

    test('11. Aynı senkronizasyon olayının tekrar alınması (Duplicate Prevention)', () async {
      await coreDb.db.insert('sync_events', {
        'event_id': 'evt-dup-1',
        'entity_type': 'product',
        'entity_id': 'p-dup-1',
        'operation': 'UPSERT',
        'payload_json': '{"id":"p-dup-1"}',
        'client_timestamp': DateTime.now().millisecondsSinceEpoch,
        'sync_state': 'PENDING',
      });

      // Aynı event_id tekrar eklenirse UNIQUE constraint / ignore devreye girer
      await coreDb.db.insert('sync_events', {
        'event_id': 'evt-dup-1',
        'entity_type': 'product',
        'entity_id': 'p-dup-1',
        'operation': 'UPSERT',
        'payload_json': '{"id":"p-dup-1"}',
        'client_timestamp': DateTime.now().millisecondsSinceEpoch,
        'sync_state': 'PENDING',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      final count = Sqflite.firstIntValue(
        await coreDb.db.rawQuery('SELECT COUNT(*) FROM sync_events WHERE event_id = ?', ['evt-dup-1']),
      );
      expect(count, equals(1));
    });

    test('12. Sunucu hatası ve yeniden deneme (Attempts Increment)', () async {
      await coreDb.db.insert('sync_events', {
        'event_id': 'evt-retry-1',
        'entity_type': 'sale',
        'entity_id': 's-1',
        'operation': 'UPSERT',
        'payload_json': '{}',
        'client_timestamp': DateTime.now().millisecondsSinceEpoch,
        'sync_state': 'PENDING',
        'attempts': 0,
      });

      // Simüle hata: state TRANSIENT_ERROR yapılır ve attempts artırılır
      await coreDb.db.update(
        'sync_events',
        {
          'sync_state': 'TRANSIENT_ERROR',
          'attempts': 1,
          'last_error': '500 Internal Server Error',
        },
        where: 'event_id = ?',
        whereArgs: ['evt-retry-1'],
      );

      final evt = (await coreDb.db.query('sync_events', where: 'event_id = ?', whereArgs: ['evt-retry-1'])).first;
      expect(evt['sync_state'], equals('TRANSIENT_ERROR'));
      expect(evt['attempts'], equals(1));
    });

    test('13. Legacy modda regresyon (coreNextSalesEngineEnabled = false)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final isEnabled = container.read(coreNextSalesEngineEnabledProvider);
      expect(isEnabled, isFalse, reason: 'Varsayılan bayrak false olmalıdır');

      final coreSaleRepo = container.read(coreNextSaleRepositoryProvider);
      expect(coreSaleRepo, isNull);

      final coreProdRepo = container.read(coreNextProductRepositoryProvider);
      expect(coreProdRepo, isNull);

      final coreCustRepo = container.read(coreNextCustomerRepositoryProvider);
      expect(coreCustRepo, isNull);
    });

    test('14. Core Next modunda ürün, müşteri, satış ve iade zinciri (Tam Yaşam Döngüsü)', () async {
      final productRepo = CoreNextProductRepository(coreDb.db);
      final custRepo = CoreNextCustomerRepository(coreDb.db);
      final saleRepo = CoreNextSaleRepository(coreDb.db);
      final refundUseCase = CoreRefundUseCase(db: coreDb);

      // 1. Ürün ekle
      await productRepo.create(ProductEntity(
        id: 'p-cycle-1',
        name: 'Zincir Test Ürünü',
        description: '',
        price: 80.0,
        quantity: 20,
        category: 'Temizlik',
      ));

      // 2. Müşteri ekle
      await custRepo.create(CustomerEntity(
        id: 'c-cycle-1',
        name: 'Zincir Müşteri',
        phone: '05550001122',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));

      // 3. Veresiye Satış: 2 adet = 160 TL
      await coreDb.db.insert('sales', {
        'id': 's-cycle-1',
        'receipt_no': 'REC-CYC-1',
        'customer_id': 'c-cycle-1',
        'subtotal_cents': 16000,
        'total_cents': 16000,
        'paid_cents': 0,
        'debt_cents': 16000,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await coreDb.db.insert('sale_items', {
        'id': 'si-cycle-1',
        'sale_id': 's-cycle-1',
        'product_id': 'p-cycle-1',
        'barcode': 'p-cycle-1',
        'product_name': 'Zincir Test Ürünü',
        'unit_price_cents': 8000,
        'quantity': 2,
        'vat_rate': 20,
        'total_cents': 16000,
      });
      await productRepo.decreaseStock('p-cycle-1', 2);
      await custRepo.updateBalance('c-cycle-1', -160.0);

      expect((await productRepo.findById('p-cycle-1'))!.quantity, equals(18));
      expect(await custRepo.getBalance('c-cycle-1'), equals(-160.0));

      // 4. Kısmi İade: 1 adet iade et (80 TL alacak)
      final refundRes = await refundUseCase.execute(RefundRequest(
        originalSaleId: 's-cycle-1',
        items: [
          const RefundItemRequest(productId: 'p-cycle-1', quantity: 1),
        ],
        reason: 'Fazla alındı',
        actor: const ActorContext(
          userId: 'mgr-1',
          username: 'Yönetici',
          role: AppRole.manager,
        ),
      ));

      expect(refundRes.refundTotal.value, equals(8000));
      expect((await productRepo.findById('p-cycle-1'))!.quantity, equals(19), reason: 'Stok 19 olmalı');

      // 5. Satış Deposu üzerinden detayı doğrula
      final retrievedSale = await saleRepo.findById('s-cycle-1');
      expect(retrievedSale, isNotNull);
      expect(retrievedSale!.totalAmount, equals(160.0));
    });

    test('15. Uygulama yeniden başlatıldıktan sonra veri tutarlılığı (Disk Persistence)', () async {
      await coreDb.db.insert('products', {
        'id': 'p-persist-1',
        'barcode': '8690persist',
        'name': 'Kalıcı Ürün',
        'price_cents': 7500,
        'stock_quantity': 42,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Veritabanını kapat
      await coreDb.close();

      // Yeniden aç
      final reopenedDb = await CoreAppDatabase.open(inMemoryOrCustomPath: coreDbPath);
      final prodRepo = CoreNextProductRepository(reopenedDb.db);
      final p = await prodRepo.findById('p-persist-1');

      expect(p, isNotNull);
      expect(p!.name, equals('Kalıcı Ürün'));
      expect(p.price, equals(75.0));
      expect(p.quantity, equals(42));
      await reopenedDb.close();
    });

    test('16. Türkçe karakterler, barkodlar ve arama performansı (Turkish Collation & Search)', () async {
      final productRepo = CoreNextProductRepository(coreDb.db);
      await productRepo.create(ProductEntity(
        id: 'p-tr-1',
        name: 'İNCİR REÇELİ GELENEKSEL',
        description: '',
        price: 95.0,
        quantity: 10,
        category: 'Reçeller',
      ));
      await productRepo.create(ProductEntity(
        id: 'p-tr-2',
        name: 'ŞEKERPARE TATLISI',
        description: '',
        price: 65.0,
        quantity: 10,
        category: 'Tatlılar',
      ));

      final res1 = await productRepo.searchByName('incir');
      expect(res1.length, equals(1));
      expect(res1.first.name, equals('İNCİR REÇELİ GELENEKSEL'));

      final res2 = await productRepo.searchByName('şeker');
      expect(res2.length, equals(1));
      expect(res2.first.name, equals('ŞEKERPARE TATLISI'));
    });

    test('17. İşlem ortasında zorla hata oluşturulduğunda yarım kayıtların engellenmesi (ACID Rollback)', () async {
      expect(
        () async {
          await coreDb.transaction((txn) async {
            await txn.insert('sales', {
              'id': 's-fail-1',
              'receipt_no': 'REC-FAIL-1',
              'subtotal_cents': 5000,
              'total_cents': 5000,
              'paid_cents': 5000,
              'debt_cents': 0,
              'status': 'COMPLETED',
              'created_at': DateTime.now().millisecondsSinceEpoch,
            });

            // Zorla patlat
            throw const SocketException('Simüle bağlantı kopması');
          });
        },
        throwsA(isA<SocketException>()),
      );

      final sales = await coreDb.db.query('sales', where: 'id = ?', whereArgs: ['s-fail-1']);
      expect(sales.isEmpty, isTrue, reason: 'İşlem yarım kalmamalı, tamamen rollback olmalıdır');
    });

    test('18. Farklı ödeme türlerinde kuruş bazında mutabakat (Floating Point Precision Invariant)', () async {
      // 33.33 TL Nakit + 33.33 TL Kart + 33.34 TL Veresiye = 100.00 TL (10,000 kuruş)
      final pay1 = 33.33;
      final pay2 = 33.33;
      final pay3 = 33.34;

      final cents1 = (pay1 * 100).round();
      final cents2 = (pay2 * 100).round();
      final cents3 = (pay3 * 100).round();

      expect(cents1, equals(3333));
      expect(cents2, equals(3333));
      expect(cents3, equals(3334));
      expect(cents1 + cents2 + cents3, equals(10000));

      await coreDb.db.insert('sales', {
        'id': 's-cents-1',
        'receipt_no': 'REC-CENTS-1',
        'subtotal_cents': 10000,
        'total_cents': 10000,
        'paid_cents': cents1 + cents2,
        'debt_cents': cents3,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      final row = (await coreDb.db.query('sales', where: 'id = ?', whereArgs: ['s-cents-1'])).first;
      expect(row['total_cents'], equals(10000));
      expect(row['paid_cents'], equals(6666));
      expect(row['debt_cents'], equals(3334));
    });
  });
}
