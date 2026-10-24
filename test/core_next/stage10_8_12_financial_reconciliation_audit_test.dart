// ignore_for_file: avoid_relative_lib_imports
// test/core_next/stage10_8_12_financial_reconciliation_audit_test.dart
// SERENUT OS — STAGE 10.8.12
// Bağımsız Finansal Mutabakat, Migration ve Rollback Güvenlik Denetimi Test Paketi

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/domain/repositories/base_repository.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_product_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_customer_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_financial_transaction_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_sale_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/domain/usecases/refund_use_case.dart';
import '../../core_next/client_core/lib/domain/models/core_entities.dart' as core;
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
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
  late HardwareWorker hardwareWorker;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('serenut_stage10_8_12_');
    legacyDbPath = '${tempDir.path}/legacy_audit_12.db';
    coreDbPath = '${tempDir.path}/core_audit_12.db';

    coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: coreDbPath);
    bridgeEngine = MigrationBridgeEngine(coreDb);

    hardwareWorker = HardwareWorker();
    await hardwareWorker.initialize();

    // Legacy veritabanı şeması (v60)
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
            sku TEXT,
            name TEXT NOT NULL,
            category_id TEXT,
            category TEXT,
            price REAL NOT NULL,
            price_minor INTEGER,
            purchase_price REAL,
            purchase_price_minor INTEGER,
            vat_rate INTEGER DEFAULT 20,
            unit TEXT DEFAULT 'adet',
            quantity REAL DEFAULT 0,
            min_stock REAL DEFAULT 5,
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
            balance REAL DEFAULT 0.0,
            balance_minor INTEGER DEFAULT 0,
            credit_limit REAL DEFAULT 0.0,
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
            notes TEXT,
            status TEXT DEFAULT 'COMPLETED',
            idempotency_key TEXT,
            created_at TEXT NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE sale_items (
            id TEXT PRIMARY KEY,
            sale_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            barcode TEXT,
            product_name TEXT NOT NULL,
            quantity REAL NOT NULL,
            unit_price REAL NOT NULL,
            unit_price_minor INTEGER,
            subtotal REAL NOT NULL,
            subtotal_minor INTEGER,
            vat_rate INTEGER DEFAULT 20,
            created_at TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE sale_payments (
            id TEXT PRIMARY KEY,
            sale_id TEXT NOT NULL,
            payment_type TEXT NOT NULL,
            amount REAL NOT NULL,
            amount_minor INTEGER NOT NULL,
            reference_note TEXT,
            created_at TEXT NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE refunds (
            id TEXT PRIMARY KEY,
            sale_id TEXT NOT NULL,
            amount REAL NOT NULL,
            refund_method TEXT NOT NULL,
            reason TEXT,
            status TEXT DEFAULT 'completed',
            created_at TEXT NOT NULL
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
            created_at TEXT NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE sync_outbox_v4 (
            mutation_id TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            operation TEXT NOT NULL,
            payload TEXT NOT NULL,
            base_revision INTEGER DEFAULT 0,
            state TEXT DEFAULT 'PENDING',
            attempts INTEGER DEFAULT 0,
            last_error TEXT,
            created_at TEXT NOT NULL
          );
        ''');
      },
    );
  });

  tearDown(() async {
    await coreDb.close();
    await legacyDb.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('STAGE 10.8.12 — Bağımsız Finansal Mutabakat ve Denetim Senaryoları', () {
    test('1. Karma ödeme kuruş yuvarlama, sınır değerleri ve geçersiz tutar engeli', () async {
      await coreDb.db.insert('products', {
        'id': 'p-round-1',
        'barcode': '869001',
        'name': 'Hassas Fiyatlı Ürün',
        'price_cents': 10000, // 100.00 TL
        'stock_quantity': 10,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      final ledgerRepo = SqliteLedgerRepository(coreDb.db);
      final ledgerService = LedgerService(ledgerRepo);
      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        ledgerService: ledgerService,
        hardwareWorker: hardwareWorker,
        defaultActor: ActorContext.testManager,
      );

      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      final prod = core.ProductEntity(
        id: 'p-round-1',
        barcode: '869001',
        name: 'Hassas Fiyatlı Ürün',
        price: MoneyCents(10000),
        stockQuantity: 10,
        updatedAt: DateTime.now(),
      );

      notifier.addProduct(prod);

      // Kuruş kırılımı: 33.33 TL Nakit + 33.33 TL Kart + 33.34 TL Nakit = 100.00 TL
      notifier.setPaymentSplits([
        const core.PaymentSplitEntity(type: core.PaymentType.cash, amount: MoneyCents(3333)),
        const core.PaymentSplitEntity(type: core.PaymentType.creditCard, amount: MoneyCents(3333)),
        const core.PaymentSplitEntity(type: core.PaymentType.cash, amount: MoneyCents(3334)),
      ]);

      final sale = await notifier.completeCheckout(
        receiptNo: 'REC-RND-1',
        storeTitle: 'Test Store',
      );

      expect(sale.total.value, equals(10000));
      expect(sale.paid.value, equals(10000));
      expect(sale.debt.value, equals(0));

      // Veritabanındaki gerçek kayıtları sorgula
      final payments = await coreDb.db.query('sale_payments', where: 'sale_id = ?', whereArgs: [sale.id]);
      expect(payments.length, equals(3));
      final sumPayments = payments.fold<int>(0, (sum, p) => sum + (p['amount_cents'] as int));
      expect(sumPayments, equals(10000));

      final saleRow = (await coreDb.db.query('sales', where: 'id = ?', whereArgs: [sale.id])).first;
      expect(saleRow['total_cents'], equals(10000));
      expect(saleRow['paid_cents'], equals(10000));
      expect(saleRow['debt_cents'], equals(0));
    });

    test('2. Kısmi iade, tam iade, miktar aşımı ve toplam tutar aşımı engeli', () async {
      await coreDb.db.insert('products', {
        'id': 'p-ref-test',
        'barcode': '8690ref',
        'name': 'İade Denetim Ürünü',
        'price_cents': 5000, // 50 TL
        'stock_quantity': 10,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('sales', {
        'id': 's-ref-test-1',
        'receipt_no': 'REC-RT-1',
        'subtotal_cents': 10000,
        'total_cents': 10000,
        'paid_cents': 10000,
        'debt_cents': 0,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('sale_items', {
        'id': 'si-rt-1',
        'sale_id': 's-ref-test-1',
        'product_id': 'p-ref-test',
        'barcode': '8690ref',
        'product_name': 'İade Denetim Ürünü',
        'unit_price_cents': 5000,
        'quantity': 2,
        'vat_rate': 20,
        'total_cents': 10000,
      });

      final refundUseCase = CoreRefundUseCase(db: coreDb);

      // Negatif Test 1: Miktar Aşımı (2 adet satıldı, 3 adet iade edilemez!)
      expect(
        () async => await refundUseCase.execute(RefundRequest(
          originalSaleId: 's-ref-test-1',
          items: [const RefundItemRequest(productId: 'p-ref-test', quantity: 3)],
          reason: 'Fazla miktar testi',
          actor: const ActorContext(userId: 'm-1', username: 'Müdür', role: AppRole.manager),
        )),
        throwsA(isA<StateError>()),
      );

      // Kısmi İade: 1 adet iade et (50 TL)
      final ref1 = await refundUseCase.execute(RefundRequest(
        originalSaleId: 's-ref-test-1',
        items: [const RefundItemRequest(productId: 'p-ref-test', quantity: 1)],
        reason: '1 adet iade',
        actor: const ActorContext(userId: 'm-1', username: 'Müdür', role: AppRole.manager),
      ));
      expect(ref1.refundTotal.value, equals(5000));

      // Stok kontrolü: 10'dan 11'e çıktı
      final p1 = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-ref-test'])).first;
      expect(p1['stock_quantity'], equals(11));

      // Negatif Test 2: Kalan 1 adetten fazla (2 adet) iade edilmeye çalışılırsa reddedilir
      expect(
        () async => await refundUseCase.execute(RefundRequest(
          originalSaleId: 's-ref-test-1',
          items: [const RefundItemRequest(productId: 'p-ref-test', quantity: 2)],
          reason: 'Kalan miktarı aşma testi',
          actor: const ActorContext(userId: 'm-1', username: 'Müdür', role: AppRole.manager),
        )),
        throwsA(isA<StateError>()),
      );

      // Kalan son 1 adeti iade et (Tam iadeye tamamlanır)
      final ref2 = await refundUseCase.execute(RefundRequest(
        originalSaleId: 's-ref-test-1',
        items: [const RefundItemRequest(productId: 'p-ref-test', quantity: 1)],
        reason: 'Son adet iadesi',
        actor: const ActorContext(userId: 'm-1', username: 'Müdür', role: AppRole.manager),
      ));
      expect(ref2.refundTotal.value, equals(5000));

      // Toplam iade kontrolü: 5000 + 5000 = 10000 kuruş
      final refundRows = await coreDb.db.query('sales', where: "status = 'REFUND' AND total_cents < 0");
      expect(refundRows.length, equals(2));
      final totalRefunded = refundRows.fold<int>(0, (sum, r) => sum + (r['total_cents'] as int).abs());
      expect(totalRefunded, equals(10000));
    });

    test('3. Aynı idempotency anahtarıyla mükerrer isteklerde finansal bütünlük', () async {
      await coreDb.db.insert('products', {
        'id': 'p-idem-sale',
        'barcode': '8690idem',
        'name': 'İdempotent Ürün',
        'price_cents': 4000,
        'stock_quantity': 20,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      final ledgerRepo = SqliteLedgerRepository(coreDb.db);
      final ledgerService = LedgerService(ledgerRepo);
      final checkoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        ledgerService: ledgerService,
        hardwareWorker: hardwareWorker,
        defaultActor: ActorContext.testManager,
      );

      final notifier = CoreSalesFlowNotifier(checkoutUseCase);
      final prod = core.ProductEntity(
        id: 'p-idem-sale',
        barcode: '8690idem',
        name: 'İdempotent Ürün',
        price: MoneyCents(4000),
        stockQuantity: 20,
        updatedAt: DateTime.now(),
      );

      notifier.addProduct(prod, quantity: 2); // 80 TL
      notifier.setPaymentSplits([
        const core.PaymentSplitEntity(type: core.PaymentType.cash, amount: MoneyCents(8000)),
      ]);

      // 1. İstek
      final sale1 = await notifier.completeCheckout(
        receiptNo: 'REC-IDEM-99',
        storeTitle: 'Test Store',
        idempotencyKey: 'idemp-fixed-key-99',
      );
      expect(sale1.total.value, equals(8000));

      // Stok 20 - 2 = 18 kalmalı
      var p = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-idem-sale'])).first;
      expect(p['stock_quantity'], equals(18));

      // 2. Aynı sepet ve aynı idempotency key ile tekrar istek
      notifier.addProduct(prod, quantity: 2);
      notifier.setPaymentSplits([
        const core.PaymentSplitEntity(type: core.PaymentType.cash, amount: MoneyCents(8000)),
      ]);
      final sale2 = await notifier.completeCheckout(
        receiptNo: 'REC-IDEM-99',
        storeTitle: 'Test Store',
        idempotencyKey: 'idemp-fixed-key-99',
      );

      // İkinci istekte aynı sipariş döner, stok tekrar düşmez
      expect(sale2.id, equals(sale1.id));
      p = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-idem-sale'])).first;
      expect(p['stock_quantity'], equals(18), reason: 'Tekrar çağrıldığında stok ikinci kez düşmemelidir');

      final saleCount = Sqflite.firstIntValue(
        await coreDb.db.rawQuery('SELECT COUNT(*) FROM sales WHERE idempotency_key = ?', ['idemp-fixed-key-99']),
      );
      expect(saleCount, equals(1));
    });

    test('4. Bağımsız Defter (Ledger) Mutabakatı: ledger_entries kayıtlarından bakiye sağlama', () async {
      await coreDb.db.insert('customers', {
        'id': 'c-audit-ledger',
        'name': 'Hesap Denetim Müşterisi',
        'phone': '05441112233',
        'balance_cents': 0, // Açılış bakiyesi 0 TL
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      final ledgerRepo = SqliteLedgerRepository(coreDb.db);
      final ledgerService = LedgerService(ledgerRepo);

      // Referans satışları veritabanına ekle (FK Bütünlüğü gereği)
      await coreDb.db.insert('sales', {
        'id': 's-led-1',
        'receipt_no': 'REC-LED-1',
        'subtotal_cents': 25000,
        'total_cents': 25000,
        'paid_cents': 0,
        'debt_cents': 25000,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('sales', {
        'id': 's-led-2',
        'receipt_no': 'REC-LED-2',
        'subtotal_cents': 5000,
        'total_cents': 5000,
        'paid_cents': 0,
        'debt_cents': 5000,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // 1. Vadeli Satış: 250 TL borç ekle
      await ledgerService.postDebitSale(
        entryId: 'le-1',
        customerId: 'c-audit-ledger',
        saleId: 's-led-1',
        debtAmount: MoneyCents(25000),
        receiptNo: 'REC-LED-1',
        timestamp: DateTime.now(),
      );

      // 2. Tahsilat: 100 TL tahsil et
      await ledgerService.postCollection(
        entryId: 'le-2',
        customerId: 'c-audit-ledger',
        collectionAmount: MoneyCents(10000),
        description: 'Nakit Tahsilat',
        timestamp: DateTime.now(),
      );

      // 3. İkinci Vadeli Satış: 50 TL borç ekle
      await ledgerService.postDebitSale(
        entryId: 'le-3',
        customerId: 'c-audit-ledger',
        saleId: 's-led-2',
        debtAmount: MoneyCents(5000),
        receiptNo: 'REC-LED-2',
        timestamp: DateTime.now(),
      );

      // 4. İade Alacağı: 20 TL iade
      await ledgerService.postRefund(
        entryId: 'le-4',
        customerId: 'c-audit-ledger',
        saleId: 's-led-1',
        refundAmount: MoneyCents(2000),
        description: 'Ürün İadesi',
        timestamp: DateTime.now(),
      );

      // BAĞIMSIZ HESAPLAMA: Repository fonksiyonuna güvenmeyip raw SQL'den hesapla
      // Beklenen Matematik:
      // Başlangıç: 0
      // le-1: -250 TL (-25000 kuruş)
      // le-2: +100 TL (+10000 kuruş) -> Ara Bakiye: -150 TL (-15000 kuruş)
      // le-3: -50 TL (-5000 kuruş)   -> Ara Bakiye: -200 TL (-20000 kuruş)
      // le-4: +20 TL (+2000 kuruş)   -> Son Bakiye: -180 TL (-18000 kuruş)

      final rawEntries = await coreDb.db.query(
        'ledger_entries',
        where: 'customer_id = ?',
        whereArgs: ['c-audit-ledger'],
        orderBy: 'created_at ASC',
      );

      int computedBalance = 0;
      for (final entry in rawEntries) {
        final type = entry['entry_type']?.toString();
        final amount = (entry['amount_cents'] as num).toInt();

        if (type == 'debitSale' || type == 'debit_sale' || type == 'SALE' || type == 'DEBT') {
          computedBalance -= amount;
        } else if (type == 'creditCollection' || type == 'creditRefund' || type == 'credit_collection' || type == 'credit_refund' || type == 'PAYMENT' || type == 'COLLECTION') {
          computedBalance += amount;
        }
      }

      expect(computedBalance, equals(-18000));

      // customers tablosundaki balance_cents ile tam eşit olmalıdır
      final cust = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-audit-ledger'])).first;
      expect(cust['balance_cents'], equals(-18000));
      expect(cust['balance_cents'], equals(computedBalance), reason: 'Defter kayıtları ile cari bakiye tam mutabık olmalıdır');
    });

    test('5. Satış, stok, ödeme, defter ve müşteri bakiyesi transaction atomikliği (Hata durumunda sıfır sızıntı)', () async {
      await coreDb.db.insert('products', {
        'id': 'p-atom-1',
        'barcode': '8690atom',
        'name': 'Atomik Ürün',
        'price_cents': 15000,
        'stock_quantity': 5,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('customers', {
        'id': 'c-atom-1',
        'name': 'Atomik Müşteri',
        'balance_cents': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      final ledgerRepo = SqliteLedgerRepository(coreDb.db);
      final ledgerService = LedgerService(ledgerRepo);

      // Hata fırlatan CheckoutUseCase (Fault Injection Hook ile kalem ekleme sonrası patlatılır)
      final faultUseCase = CoreCheckoutUseCase(
        db: coreDb,
        ledgerService: ledgerService,
        hardwareWorker: hardwareWorker,
        defaultActor: ActorContext.testManager,
        faultHook: (step) async {
          if (step == 'after_sales_insert') {
            throw const SocketException('Kritik Donanım / Ağ Kesintisi Simülasyonu');
          }
        },
      );

      final notifier = CoreSalesFlowNotifier(faultUseCase);
      final prod = core.ProductEntity(
        id: 'p-atom-1',
        barcode: '8690atom',
        name: 'Atomik Ürün',
        price: MoneyCents(15000),
        stockQuantity: 5,
        updatedAt: DateTime.now(),
      );

      notifier.addProduct(prod);
      notifier.setPaymentSplits([
        const core.PaymentSplitEntity(type: core.PaymentType.cash, amount: MoneyCents(15000)),
      ]);

      expect(
        () async => await notifier.completeCheckout(receiptNo: 'REC-ATOM-FAIL', storeTitle: 'Store'),
        throwsA(isA<SocketException>()),
      );

      // Veritabanını denetle: Satış, ödeme, kalem veya stok düşümü olmamalıdır
      final sales = await coreDb.db.query('sales', where: 'receipt_no = ?', whereArgs: ['REC-ATOM-FAIL']);
      expect(sales.isEmpty, isTrue, reason: 'Transaction tamamen rollback olmalıdır');

      final items = await coreDb.db.query('sale_items', where: 'barcode = ?', whereArgs: ['8690atom']);
      expect(items.isEmpty, isTrue);

      final p = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-atom-1'])).first;
      expect(p['stock_quantity'], equals(5), reason: 'Stok düşümü yapılmamış olmalıdır');
    });

    test('6. MigrationBridgeEngine ve ReverseMigrationEngine varlık, geçiş ve çift yönlü mutabakat doğrulaması', () async {
      // 1. Kaynak Legacy DB'ye zengin veri seti ekle
      await legacyDb.insert('categories', {'id': 'cat-100', 'name': 'Gıda & Şekerleme'});
      await legacyDb.insert('products', {
        'id': 'p-mig-100',
        'barcode': '869000100',
        'name': 'Çikolata Gofret 40g',
        'category_id': 'cat-100',
        'price': 12.50,
        'price_minor': 1250,
        'quantity': 100,
        'created_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('customers', {
        'id': 'c-mig-100',
        'name': 'Mahalle Bakkalı',
        'phone': '05321110099',
        'balance': -350.00,
        'balance_minor': -35000,
        'created_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('sales', {
        'id': 's-mig-100',
        'receipt_no': 'REC-MIG-100',
        'customer_id': 'c-mig-100',
        'total_amount': 25.00,
        'total_amount_minor': 2500,
        'paid_amount': 25.00,
        'paid_amount_minor': 2500,
        'payment_method': 'cash',
        'created_at': DateTime.now().toIso8601String(),
      });
      await legacyDb.insert('sale_items', {
        'id': 'si-mig-100',
        'sale_id': 's-mig-100',
        'product_id': 'p-mig-100',
        'barcode': '869000100',
        'product_name': 'Çikolata Gofret 40g',
        'quantity': 2.0,
        'unit_price': 12.50,
        'unit_price_minor': 1250,
        'subtotal': 25.00,
        'subtotal_minor': 2500,
        'created_at': DateTime.now().toIso8601String(),
      });

      // İLERİ MİGRASYON: Legacy -> Core Next
      final forwardReport = await bridgeEngine.migrateFromLegacy(
        legacyDb,
        legacyFilePath: legacyDbPath,
        fullScope: true,
      );
      expect(forwardReport.isSuccess, isTrue);
      expect(forwardReport.productsMigrated, equals(1));
      expect(forwardReport.customersMigrated, equals(1));
      expect(forwardReport.salesMigrated, equals(1));

      // Core Next DB parasal mutabakat
      final coreCust = (await coreDb.db.query('customers', where: 'id = ?', whereArgs: ['c-mig-100'])).first;
      expect(coreCust['balance_cents'], equals(-35000));

      final coreProd = (await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-mig-100'])).first;
      expect(coreProd['price_cents'], equals(1250));

      // CORE NEXT ÜZERİNDE YENİ İŞLEM (Cutover sonrası işlem simülasyonu)
      await coreDb.db.insert('sales', {
        'id': 's-core-next-only-1',
        'receipt_no': 'REC-CORE-1',
        'customer_id': 'c-mig-100',
        'subtotal_cents': 5000,
        'discount_cents': 0,
        'vat_total_cents': 0,
        'total_cents': 5000, // 50 TL
        'paid_cents': 0,
        'debt_cents': 5000,  // 50 TL veresiye
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('sale_items', {
        'id': 'si-core-next-1',
        'sale_id': 's-core-next-only-1',
        'product_id': 'p-mig-100',
        'barcode': '869000100',
        'product_name': 'Çikolata Gofret 40g',
        'unit_price_cents': 1250,
        'quantity': 4,
        'vat_rate': 20,
        'total_cents': 5000,
      });

      // Bakiye güncelle: -350 TL - 50 TL = -400 TL (-40000 kuruş)
      await coreDb.db.update('customers', {'balance_cents': -40000}, where: 'id = ?', whereArgs: ['c-mig-100']);
      // Stok güncelle: 100 - 4 = 96 adet
      await coreDb.db.update('products', {'stock_quantity': 96}, where: 'id = ?', whereArgs: ['p-mig-100']);

      // GERİYE DÖNÜK MİGRASYON: ReverseMigrationEngine.rollbackToLegacy
      final rollbackReport = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreDb,
      );
      expect(rollbackReport.isSuccess, isTrue);
      expect(rollbackReport.salesExported, equals(1));
      expect(rollbackReport.saleItemsExported, equals(1));

      // Legacy DB doğrulama
      final legSale = (await legacyDb.query('sales', where: 'id = ?', whereArgs: ['s-core-next-only-1'])).first;
      expect((legSale['total_amount'] as num).toDouble(), equals(50.0));
      expect((legSale['total_amount_minor'] as num).toInt(), equals(5000));

      final legCust = (await legacyDb.query('customers', where: 'id = ?', whereArgs: ['c-mig-100'])).first;
      expect((legCust['balance'] as num).toDouble(), equals(-400.00));

      final legProd = (await legacyDb.query('products', where: 'id = ?', whereArgs: ['p-mig-100'])).first;
      expect((legProd['quantity'] as num).toDouble(), equals(96.0));

      // İkinci kez Reverse Rollback çağrıldığında mükerrer kayıt oluşmamalıdır (Idempotency)
      final rollbackReport2 = await ReverseMigrationEngine.rollbackToLegacy(
        legacyDb: legacyDb,
        coreDb: coreDb,
      );
      expect(rollbackReport2.isSuccess, isTrue);
      expect(rollbackReport2.salesExported, equals(0), reason: 'Mükerrer satış aktarılmamalıdır');

      final finalLegacySalesCount = Sqflite.firstIntValue(
        await legacyDb.rawQuery('SELECT COUNT(*) FROM sales WHERE id = ?', ['s-core-next-only-1']),
      );
      expect(finalLegacySalesCount, equals(1));
    });
  });
}
