import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/database/schema/db_schema.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_hazelnut_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DbGateway gateway;
  late SqliteHazelnutRepository repo;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // Create base tables needed for customer, financial_transactions, and hazelnut
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        balance REAL NOT NULL DEFAULT 0,
        balance_minor INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE financial_transactions (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        amount_minor INTEGER NOT NULL DEFAULT 0,
        paid_amount REAL NOT NULL DEFAULT 0,
        paid_amount_minor INTEGER NOT NULL DEFAULT 0,
        debt_amount REAL NOT NULL DEFAULT 0,
        debt_amount_minor INTEGER NOT NULL DEFAULT 0,
        reference_id TEXT,
        description TEXT,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        metadata TEXT,
        created_at TEXT NOT NULL,
        logical_clock INTEGER NOT NULL DEFAULT 1,
        device_id TEXT,
        is_synced INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE cash_expenses (
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        category TEXT NOT NULL DEFAULT 'genel',
        description TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Create hazelnut tables
    await DatabaseSchema.createHazelnutTables(db);

    // Insert dummy customer
    await db.insert('customers', {
      'id': 'cust-1',
      'name': 'Hasan Çiftçi',
      'balance': -5000.0, // 5000 TL borcu var
      'balance_minor': -500000,
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    gateway = DbGatewayImpl.raw(db);
    repo = SqliteHazelnutRepository(gateway);
  });

  tearDown(() async {
    await db.close();
  });

  group('SqliteHazelnutRepository Tests', () {
    test('Initial seeded warehouse exists', () async {
      final warehouses = await repo.getWarehouses();
      expect(warehouses.isNotEmpty, true);
      expect(warehouses.first.id, 'wh-main');
      expect(warehouses.first.currentStockKg, 0.0);
    });

    test('addEscrowBatch updates warehouse stock and weighted rendiment', () async {
      // Hasan brings 1000 kg gross, 10 sacks (1 kg each = 10 kg tare -> 990 kg net) at 52 randıman
      final escrow = await repo.addEscrowBatch(
        customerId: 'cust-1',
        warehouseId: 'wh-main',
        grossKg: 1000.0,
        sackCount: 10,
        tarePerSack: 1.0,
        rendiment: 52.0,
        notes: '2026 Mahsulü',
      );

      expect(escrow.netKg, 990.0);
      expect(escrow.remainingKg, 990.0);
      expect(escrow.rendiment, 52.0);

      final wh = await repo.getWarehouseById('wh-main');
      expect(wh!.currentStockKg, 990.0);
      expect(wh.averageRendiment, 52.0);

      final movements = await repo.getWarehouseMovements('wh-main');
      expect(movements.length, 1);
      expect(movements.first.movementType, 'ESCROW_IN');
      expect(movements.first.quantityKg, 990.0);
    });

    test('cutEscrowPrice with OFFSET_DEBT reduces escrow and logs financial transaction', () async {
      final escrow = await repo.addEscrowBatch(
        customerId: 'cust-1',
        warehouseId: 'wh-main',
        grossKg: 1010.0,
        sackCount: 10,
        tarePerSack: 1.0,
        rendiment: 50.0, // net 1000 kg
      );

      // Cut 500 kg at 130 TL base price (50 R -> 130 TL effective)
      // Total amount = 500 * 130 = 65,000 TL
      final cut = await repo.cutEscrowPrice(
        escrowId: escrow.id,
        cutKg: 500.0,
        basePrice50: 130.0,
        settlementType: 'OFFSET_DEBT',
        customerName: 'Hasan Çiftçi',
      );

      expect(cut.cutKg, 500.0);
      expect(cut.effectivePrice, 130.0);
      expect(cut.totalAmount, 65000.0);

      // Verify escrow remaining is now 500 kg and status is partially_cut
      final updatedEscrow = await repo.getEscrowById(escrow.id);
      expect(updatedEscrow!.remainingKg, 500.0);
      expect(updatedEscrow.status, 'partially_cut');

      // Verify financial transaction was inserted
      final txRows = await db.query('financial_transactions', where: 'reference_id = ?', whereArgs: [cut.id]);
      expect(txRows.length, 1);
      expect(txRows.first['amount'], 65000.0);
      expect(txRows.first['type'], 'payment');
    });

    test('dispatchFromWarehouse reduces warehouse stock', () async {
      await repo.addEscrowBatch(
        customerId: 'cust-1',
        warehouseId: 'wh-main',
        grossKg: 2000.0,
        sackCount: 0,
        manualTareKg: 0,
        rendiment: 51.0,
      );

      // Mal Çıkışı / Sevk: 1500 kg fabrika satışı
      final movement = await repo.dispatchFromWarehouse(
        warehouseId: 'wh-main',
        movementType: 'SALE_OUT',
        quantityKg: 1500.0,
        description: 'Ferrero Fabrika Sevk',
      );

      expect(movement.movementType, 'SALE_OUT');
      expect(movement.balanceKgAfter, 500.0);

      final wh = await repo.getWarehouseById('wh-main');
      expect(wh!.currentStockKg, 500.0);
      expect(wh.averageRendiment, 51.0); // Randıman değişmez
    });
  });
}
