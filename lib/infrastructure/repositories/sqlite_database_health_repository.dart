import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:sqflite/sqflite.dart';

class SqliteDatabaseHealthRepository implements IDatabaseHealthRepository {
  final DbGateway _gateway;

  SqliteDatabaseHealthRepository(this._gateway);

  @override
  Future<DatabaseHealthReport> checkHealth() async {
    // 1. Orphaned Sale Items
    final orphanSaleItemsResult = await _gateway.rawQuery('''
      SELECT COUNT(*) as cnt 
      FROM sale_items 
      WHERE sale_id NOT IN (SELECT id FROM sales)
    ''');
    final orphanedSaleItems = Sqflite.firstIntValue(orphanSaleItemsResult) ?? 0;

    // 2. Orphaned Order Items
    final orphanOrderItemsResult = await _gateway.rawQuery('''
      SELECT COUNT(*) as cnt 
      FROM order_items 
      WHERE order_id NOT IN (SELECT id FROM orders)
    ''');
    final orphanedOrderItems = Sqflite.firstIntValue(orphanOrderItemsResult) ?? 0;

    // 3. Orphaned Order Payments
    final orphanOrderPaymentsResult = await _gateway.rawQuery('''
      SELECT COUNT(*) as cnt 
      FROM order_payments 
      WHERE order_id NOT IN (SELECT id FROM orders)
    ''');
    final orphanedOrderPayments = Sqflite.firstIntValue(orphanOrderPaymentsResult) ?? 0;

    // 4. Orphaned Transactions
    final orphanTransactionsResult = await _gateway.rawQuery('''
      SELECT COUNT(*) as cnt 
      FROM financial_transactions 
      WHERE customer_id NOT IN (SELECT id FROM customers)
    ''');
    final orphanedTransactions = Sqflite.firstIntValue(orphanTransactionsResult) ?? 0;

    // 5. Negative Stock Products
    final negativeStockResult = await _gateway.rawQuery('''
      SELECT COUNT(*) as cnt 
      FROM products 
      WHERE quantity < 0
    ''');
    final negativeStock = Sqflite.firstIntValue(negativeStockResult) ?? 0;

    // 6. Duplicate UUIDs (duplicate primary keys) - check each major table for non-unique IDs
    // Since SQL enforces primary key constraints, we check if there are duplicate IDs in synchronization records
    // or checks on duplicate keys in transaction tables.
    final duplicateUuidsResult = await _gateway.rawQuery('''
      SELECT COUNT(*) as cnt FROM (
        SELECT id FROM customers GROUP BY id HAVING COUNT(*) > 1
        UNION ALL
        SELECT id FROM products GROUP BY id HAVING COUNT(*) > 1
        UNION ALL
        SELECT id FROM sales GROUP BY id HAVING COUNT(*) > 1
        UNION ALL
        SELECT id FROM financial_transactions GROUP BY id HAVING COUNT(*) > 1
      )
    ''');
    final duplicateUuids = Sqflite.firstIntValue(duplicateUuidsResult) ?? 0;

    // 7. Customer Balance Drifts
    final driftsResult = await _gateway.rawQuery('''
      SELECT COUNT(*) as cnt FROM (
        SELECT c.id, c.balance,
               COALESCE(SUM(
                 CASE 
                   WHEN ft.type = 'sale' THEN -ft.debt_amount
                   WHEN ft.type = 'payment' THEN ft.paid_amount
                   WHEN ft.type = 'cancellation' THEN ft.debt_amount
                   WHEN ft.type = 'collection' THEN ft.paid_amount
                   WHEN ft.type = 'refund' AND ft.paid_amount = 0 THEN ft.amount
                   ELSE 0
                 END
               ), 0) as expected
        FROM customers c
        LEFT JOIN financial_transactions ft ON c.id = ft.customer_id
        GROUP BY c.id
        HAVING ABS(c.balance - expected) > 0.01
      )
    ''');
    final customerDrifts = Sqflite.firstIntValue(driftsResult) ?? 0;

    return DatabaseHealthReport(
      orphanedSaleItemsCount: orphanedSaleItems,
      orphanedOrderItemsCount: orphanedOrderItems,
      orphanedOrderPaymentsCount: orphanedOrderPayments,
      orphanedTransactionsCount: orphanedTransactions,
      negativeStockProductsCount: negativeStock,
      customerBalanceDriftsCount: customerDrifts,
      duplicateUuidsCount: duplicateUuids,
    );
  }

  @override
  Future<void> repairHealth() async {
    await _gateway.transaction(() async {
      // 1. Delete orphaned sale items
      await _gateway.execute('''
        DELETE FROM sale_items 
        WHERE sale_id NOT IN (SELECT id FROM sales)
      ''');

      // 2. Delete orphaned order items
      await _gateway.execute('''
        DELETE FROM order_items 
        WHERE order_id NOT IN (SELECT id FROM orders)
      ''');

      // 3. Delete orphaned order payments
      await _gateway.execute('''
        DELETE FROM order_payments 
        WHERE order_id NOT IN (SELECT id FROM orders)
      ''');



      // 5. Reset negative stock to 0
      await _gateway.execute('''
        UPDATE products 
        SET quantity = 0 
        WHERE quantity < 0
      ''');

      // 6. Recalculate and update customer balance drifts
      final driftsResult = await _gateway.rawQuery('''
        SELECT c.id,
               COALESCE(SUM(
                 CASE 
                   WHEN ft.type = 'sale' THEN -ft.debt_amount
                   WHEN ft.type = 'payment' THEN ft.paid_amount
                   WHEN ft.type = 'cancellation' THEN ft.debt_amount
                   WHEN ft.type = 'collection' THEN ft.paid_amount
                   WHEN ft.type = 'refund' AND ft.paid_amount = 0 THEN ft.amount
                   ELSE 0
                 END
               ), 0) as expected
        FROM customers c
        LEFT JOIN financial_transactions ft ON c.id = ft.customer_id
        GROUP BY c.id
        HAVING ABS(c.balance - expected) > 0.01
      ''');

      for (final drift in driftsResult) {
        final id = drift['id'] as String;
        final expected = (drift['expected'] as num?)?.toDouble() ?? 0.0;
        await _gateway.execute('''
          UPDATE customers 
          SET balance = ? 
          WHERE id = ?
        ''', [expected, id]);
      }
    });
  }
}
