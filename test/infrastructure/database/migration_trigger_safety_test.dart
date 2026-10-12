import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/schema/db_migrations.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Migration from v58 to v60 with existing triggers must not fail with Ledger Immutability', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 58,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE financial_transactions (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            customer_id TEXT NOT NULL,
            amount REAL NOT NULL,
            paid_amount REAL NOT NULL DEFAULT 0,
            debt_amount REAL NOT NULL DEFAULT 0,
            reference_id TEXT,
            created_at TEXT NOT NULL,
            is_deleted INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            balance REAL NOT NULL DEFAULT 0,
            credit_limit REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            purchase_price REAL NOT NULL DEFAULT 0,
            quantity INTEGER NOT NULL,
            category TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sales (
            id TEXT PRIMARY KEY,
            customer_id TEXT NOT NULL,
            total_amount REAL NOT NULL,
            paid_amount REAL NOT NULL DEFAULT 0,
            refunded_amount REAL NOT NULL DEFAULT 0,
            discount_amount REAL NOT NULL DEFAULT 0.0
          )
        ''');
        await db.execute('''
          CREATE TABLE sale_items (
            id TEXT PRIMARY KEY,
            sale_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            unit_price REAL NOT NULL,
            subtotal REAL NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE trigger_audit_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            trigger_name TEXT,
            customer_id TEXT,
            transaction_id TEXT,
            before_balance REAL,
            after_balance REAL,
            timestamp TEXT
          )
        ''');

        // Create the blanket trigger as it existed before
        await db.execute('''
          CREATE TRIGGER trg_ft_block_update BEFORE UPDATE ON financial_transactions
          BEGIN
            SELECT RAISE(ABORT, 'Kritik Hata: Finansal defter kayıtları değiştirilemez (Ledger Immutability).');
          END;
        ''');

        // Seed some data
        await db.insert('customers', {'id': 'c1', 'name': 'Test', 'balance': 100});
        await db.insert('financial_transactions', {
          'id': 'tx1',
          'type': 'sale',
          'customer_id': 'c1',
          'amount': 100,
          'debt_amount': 100,
          'created_at': DateTime.now().toIso8601String(),
        });
      },
    );

    // Now upgrade from 58 to 60
    await DatabaseMigrations.onUpgrade(db, 58, 60);

    final res = await db.query('financial_transactions', where: 'id = ?', whereArgs: ['tx1']);
    expect(res.first['amount_minor'], 10000);
    await db.close();
  });
}
