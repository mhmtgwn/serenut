import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/domain/usecases/refund_use_case.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/schema_definitions.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late CoreAppDatabase coreDb;
  late HardwareWorker hardwareWorker;
  late SqliteLedgerRepository ledgerRepo;
  late LedgerService ledgerService;
  late CoreCheckoutUseCase checkoutUseCase;
  late CoreSalesFlowNotifier salesNotifier;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('serenut_branch_test_');
    coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: inMemoryDatabasePath);

    hardwareWorker = HardwareWorker();
    await hardwareWorker.initialize();

    ledgerRepo = SqliteLedgerRepository(coreDb.db);
    ledgerService = LedgerService(ledgerRepo);

    checkoutUseCase = CoreCheckoutUseCase(
      db: coreDb,
      ledgerService: ledgerService,
      hardwareWorker: hardwareWorker,
      defaultActor: ActorContext.testManager,
    );

    salesNotifier = CoreSalesFlowNotifier(checkoutUseCase);
  });

  tearDown(() async {
    await coreDb.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FAZ 6: İstemcide Çoklu Şube (branch_id) Mimarisi', () {
    test('6.1 Veritabanı Şeması v6, branches Tablosu ve branch_id Kolonları Doğrulanmalıdır', () async {
      expect(CoreSchemaDefinitions.schemaVersion, equals(7));

      final vRes = await coreDb.db.rawQuery('PRAGMA user_version;');
      expect((vRes.first.values.first as num).toInt(), equals(7));

      // 1. Tablo varlığı
      final tables = (await coreDb.db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'].toString())
          .toSet();
      expect(tables.contains('branches'), isTrue, reason: 'branches tablosu oluşturulmalıdır.');

      // 2. Kolon varlıkları
      final salesColumns = (await coreDb.db.rawQuery('PRAGMA table_info(sales);'))
          .map((r) => r['name'].toString())
          .toSet();
      expect(salesColumns.contains('branch_id'), isTrue);

      final ordersColumns = (await coreDb.db.rawQuery('PRAGMA table_info(orders);'))
          .map((r) => r['name'].toString())
          .toSet();
      expect(ordersColumns.contains('branch_id'), isTrue);

      final stockMovementsColumns = (await coreDb.db.rawQuery('PRAGMA table_info(stock_movements);'))
          .map((r) => r['name'].toString())
          .toSet();
      expect(stockMovementsColumns.contains('branch_id'), isTrue);

      final cashColumns = (await coreDb.db.rawQuery('PRAGMA table_info(cash_transactions);'))
          .map((r) => r['name'].toString())
          .toSet();
      expect(cashColumns.contains('branch_id'), isTrue);

      // 3. İndeksler
      final indexes = (await coreDb.db.rawQuery("SELECT name FROM sqlite_master WHERE type='index'"))
          .map((r) => r['name'].toString())
          .toSet();
      expect(indexes.contains('idx_branches_active'), isTrue);
      expect(indexes.contains('idx_sales_branch'), isTrue);
      expect(indexes.contains('idx_orders_branch'), isTrue);
      expect(indexes.contains('idx_stock_movements_branch'), isTrue);
    });

    test('6.2 v5 Veritabanından v6 Sürümüne Güvenli Otomatik Migrasyon Doğrulanmalıdır', () async {
      final migrationDbPath = p.join(tempDir.path, 'migrate_v5_to_v6.db');
      final legacyDb = await openDatabase(
        migrationDbPath,
        version: 5,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE sales (
              id TEXT PRIMARY KEY NOT NULL,
              receipt_no TEXT UNIQUE NOT NULL,
              customer_id TEXT,
              subtotal_cents INTEGER NOT NULL,
              discount_cents INTEGER NOT NULL DEFAULT 0,
              vat_total_cents INTEGER NOT NULL DEFAULT 0,
              total_cents INTEGER NOT NULL,
              paid_cents INTEGER NOT NULL,
              debt_cents INTEGER NOT NULL DEFAULT 0,
              status TEXT NOT NULL DEFAULT 'COMPLETED',
              idempotency_key TEXT UNIQUE,
              created_at INTEGER NOT NULL
            );
          ''');
          await db.execute('''
            CREATE TABLE orders (
              id TEXT PRIMARY KEY NOT NULL,
              order_number TEXT UNIQUE NOT NULL,
              customer_id TEXT,
              status TEXT NOT NULL DEFAULT 'pending',
              total_amount_cents INTEGER NOT NULL,
              discount_amount_cents INTEGER NOT NULL DEFAULT 0,
              order_date INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
          ''');
          await db.execute('''
            CREATE TABLE stock_movements (
              id TEXT PRIMARY KEY NOT NULL,
              product_id TEXT NOT NULL,
              reference_id TEXT,
              reference_type TEXT NOT NULL,
              quantity_delta REAL NOT NULL,
              previous_stock REAL NOT NULL,
              new_stock REAL NOT NULL,
              reason TEXT,
              created_by TEXT,
              created_at INTEGER NOT NULL
            );
          ''');
          await db.execute('''
            CREATE TABLE cash_transactions (
              id TEXT PRIMARY KEY NOT NULL,
              type TEXT NOT NULL,
              amount_cents INTEGER NOT NULL,
              category TEXT NOT NULL,
              description TEXT,
              created_at INTEGER NOT NULL
            );
          ''');

          // Seed sample sale in v5
          await db.insert('sales', {
            'id': 'sale-legacy-1',
            'receipt_no': 'REC-001',
            'subtotal_cents': 1000,
            'total_cents': 1000,
            'paid_cents': 1000,
            'created_at': 1700000000,
          });
        },
      );

      // Migrasyonu çalıştır (5 -> 6)
      await CoreSchemaDefinitions.migrate(legacyDb, 5, 6);
      await legacyDb.setVersion(6);

      // Migrasyon sonrası kolonları ve veriyi doğrula
      final salesColumns = (await legacyDb.rawQuery('PRAGMA table_info(sales);'))
          .map((r) => r['name'].toString())
          .toSet();
      expect(salesColumns.contains('branch_id'), isTrue);

      final preservedSale = await legacyDb.query('sales', where: 'id = ?', whereArgs: ['sale-legacy-1']);
      expect(preservedSale.isNotEmpty, isTrue);
      expect(preservedSale.first['total_cents'], equals(1000));
      expect(preservedSale.first['branch_id'], isNull);

      await legacyDb.close();
    });

    test('6.3 Satış Yapıldığında branch_id Satış ve Stok Defteri Kayıtlarına İşlenmelidir', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Şube ekle
      await coreDb.db.insert('branches', {
        'id': 'branch-kadikoy-1',
        'name': 'Kadıköy Şubesi',
        'address': 'Moda Cad. No: 12 Kadıköy / İstanbul',
        'phone': '02161234567',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      // 2. Ürün ekle
      await coreDb.db.insert('products', {
        'id': 'prod-kahve-1',
        'barcode': '869000000101',
        'name': 'Filtre Kahve 250g',
        'price_cents': 15000,
        'cost_price_cents': 9000,
        'vat_rate': 10,
        'unit': 'ADET',
        'stock_quantity': 40.0,
        'is_active': 1,
        'updated_at': now,
      });

      final pKahve = ProductEntity(
        id: 'prod-kahve-1',
        barcode: '869000000101',
        name: 'Filtre Kahve 250g',
        price: const MoneyCents(15000),
        stockQuantity: 40,
        updatedAt: DateTime.now(),
      );

      // 2 adet ekle (2 * 150.00 TL = 300.00 TL)
      salesNotifier.addProduct(pKahve, quantity: 2);
      salesNotifier.setPaymentSplits([
        const PaymentSplitEntity(type: PaymentType.cash, amount: MoneyCents(30000)),
      ]);

      final saleResult = await salesNotifier.completeCheckout(
        receiptNo: 'REC-BR-101',
        storeTitle: 'Serenut Coffee',
        branchId: 'branch-kadikoy-1',
      );
      expect(saleResult.receiptNo, equals('REC-BR-101'));

      // Satış kaydını doğrula
      final saleRows = await coreDb.db.query('sales', where: 'id = ?', whereArgs: [saleResult.id]);
      expect(saleRows.isNotEmpty, isTrue);
      expect(saleRows.first['branch_id'], equals('branch-kadikoy-1'));

      // Stok hareketini doğrula
      final movementRows = await coreDb.db.query(
        'stock_movements',
        where: 'reference_id = ?',
        whereArgs: [saleResult.id],
      );
      expect(movementRows.isNotEmpty, isTrue);
      expect(movementRows.first['branch_id'], equals('branch-kadikoy-1'));
      expect(movementRows.first['quantity_delta'], equals(-2.0));

      // İade yapıldığında branch_id'nin miras alındığını doğrula
      final refundUseCase = CoreRefundUseCase(db: coreDb);
      final refundResult = await refundUseCase.execute(RefundRequest(
        originalSaleId: saleResult.id,
        items: const [], // Tam iade
        reason: 'Müşteri vazgeçti',
        actor: ActorContext.testManager,
      ));

      final refundSaleRows = await coreDb.db.query(
        'sales',
        where: 'id = ?',
        whereArgs: [refundResult.refundId],
      );
      expect(refundSaleRows.first['branch_id'], equals('branch-kadikoy-1'));

      final refundMovementRows = await coreDb.db.query(
        'stock_movements',
        where: 'reference_id = ?',
        whereArgs: [refundResult.refundId],
      );
      expect(refundMovementRows.first['branch_id'], equals('branch-kadikoy-1'));
      expect(refundMovementRows.first['quantity_delta'], equals(2.0));
    });
  });
}
