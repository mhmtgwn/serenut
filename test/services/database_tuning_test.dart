// test/services/database_tuning_test.dart
// SQLite performance tuning, explain query plan, and write lock concurrency simulation tests.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:serenutos/infrastructure/database/database_provider.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('SQLite Tuning, Index usage & Concurrency Hardening Tests', () {
    late DatabaseManager dbManager;

    setUpAll(() async {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'serenut_tuning_test.db');
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }

      DatabaseManager.overrideDatabasePath = path;
      dbManager = DatabaseManager();
    });

    tearDownAll(() async {
      DatabaseManager.overrideDatabasePath = null;
      await dbManager.close();
    });

    test('SQLite Tuning — WAL and Synchronous pragma values', () async {
      final db = await dbManager.getDatabase();

      final journalModeResult = await db.rawQuery('PRAGMA journal_mode');
      final journalMode = journalModeResult.first.values.first as String;
      expect(journalMode.toLowerCase(), equals('wal'));

      final syncResult = await db.rawQuery('PRAGMA synchronous');
      final syncValue = syncResult.first.values.first;
      // synchronous NORMAL is represented by 1 (FULL is 2, OFF is 0)
      expect(syncValue, equals(1));
    });

    test('SQLite Explain Query Plan — Verify indexes are used', () async {
      final db = await dbManager.getDatabase();

      // 1. Verify idx_sales_synced on sales(is_synced)
      final explainSales = await db.rawQuery('EXPLAIN QUERY PLAN SELECT * FROM sales WHERE is_synced = 0');
      final salesPlan = explainSales.map((r) => r['detail'].toString()).join(' | ');
      expect(salesPlan, contains('idx_sales_synced'));

      // 2. Verify idx_sale_items_product on sale_items(product_id)
      final explainItems = await db.rawQuery('EXPLAIN QUERY PLAN SELECT * FROM sale_items WHERE product_id = "abc"');
      final itemsPlan = explainItems.map((r) => r['detail'].toString()).join(' | ');
      expect(itemsPlan, contains('idx_sale_items_product'));

      // 3. Verify idx_ft_reference on financial_transactions(reference_id)
      final explainFt = await db.rawQuery('EXPLAIN QUERY PLAN SELECT * FROM financial_transactions WHERE reference_id = "ft_abc"');
      final ftPlan = explainFt.map((r) => r['detail'].toString()).join(' | ');
      expect(ftPlan, contains('idx_ft_reference'));

      // 4. Verify idx_orders_customer on orders(customer_id)
      final explainOrders = await db.rawQuery('EXPLAIN QUERY PLAN SELECT * FROM orders WHERE customer_id = "cust_abc"');
      final ordersPlan = explainOrders.map((r) => r['detail'].toString()).join(' | ');
      expect(ordersPlan, contains('idx_orders_customer'));

      // 5. Verify idx_order_items_order on order_items(order_id)
      final explainOrderItems = await db.rawQuery('EXPLAIN QUERY PLAN SELECT * FROM order_items WHERE order_id = "ord_abc"');
      final orderItemsPlan = explainOrderItems.map((r) => r['detail'].toString()).join(' | ');
      expect(orderItemsPlan, contains('idx_order_items_order'));
    });

    test('SQLite Concurrency Simulation — Simultaneous imports and sales flow', () async {
      final db = await dbManager.getDatabase();

      await db.execute('DELETE FROM products');
      await db.execute('DELETE FROM sales');

      final operations = <Future>[];

      // 1. Background bulk insertion simulation
      operations.add(db.transaction((txn) async {
        final batch = txn.batch();
        for (int i = 0; i < 100; i++) {
          batch.insert('products', {
            'id': 'prod_$i',
            'name': 'Stress Product $i',
            'price': 10.0 + i,
            'quantity': 100,
            'category': 'Stress Test',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
        await batch.commit(noResult: true);
      }));

      // 2. Simultaneous Sales insertion simulation
      operations.add(db.transaction((txn) async {
        final batch = txn.batch();
        for (int i = 0; i < 50; i++) {
          batch.insert('sales', {
            'id': 'sale_stress_$i',
            'customer_id': '', // walk-in customer
            'total_amount': 150.0,
            'paid_amount': 150.0,
            'payment_method': 'cash',
            'status': 'completed',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
        await batch.commit(noResult: true);
      }));

      // Await concurrency tasks — should serialize sequentially on event loop with zero deadlock exceptions
      await expectLater(Future.wait(operations), completes);

      final productCount = (await db.rawQuery('SELECT COUNT(*) FROM products')).first.values.first as int;
      final saleCount = (await db.rawQuery('SELECT COUNT(*) FROM sales')).first.values.first as int;

      expect(productCount, equals(100));
      expect(saleCount, equals(50));
    });
  });
}
