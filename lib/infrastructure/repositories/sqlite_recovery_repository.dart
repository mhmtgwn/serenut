// lib/infrastructure/repositories/sqlite_recovery_repository.dart
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/repositories/recovery_repository.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';

class SqliteRecoveryRepository implements IRecoveryRepository {
  final DatabaseManager _dbManager;

  SqliteRecoveryRepository(this._dbManager);

  @override
  Future<List<Map<String, dynamic>>> getDeletedItems(String type) async {
    final db = await _dbManager.getDatabase();
    String table;
    switch (type) {
      case 'product':
        table = 'products';
        break;
      case 'customer':
        table = 'customers';
        break;
      case 'sale':
        table = 'sales';
        break;
      case 'order':
        table = 'orders';
        break;
      default:
        throw Exception('Bilinmeyen varlık tipi: $type');
    }

    final results = await db.query(
      table,
      where: 'is_deleted = 1',
      orderBy: 'deleted_at DESC',
    );
    return results;
  }

  @override
  Future<void> restore(String type, String id) async {
    final db = await _dbManager.getDatabase();
    final now = DateTime.now().toIso8601String();

    switch (type) {
      case 'product':
        await db.update(
          'products',
          {
            'is_deleted': 0,
            'is_active': 1,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        break;
      case 'customer':
        await db.update(
          'customers',
          {
            'is_deleted': 0,
            'is_active': 1,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        break;
      case 'sale':
        await db.update(
          'sales',
          {
            'is_deleted': 0,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        // Also restore related financial transactions if soft-deleted
        await db.transaction((txn) async {
          await txn.rawUpdate('UPDATE ledger_bypass_flag SET active = 1');
          try {
            await txn.update(
              'financial_transactions',
              {
                'is_deleted': 0,
              },
              where: 'reference_id = ?',
              whereArgs: [id],
            );
          } finally {
            await txn.rawUpdate('UPDATE ledger_bypass_flag SET active = 0');
          }
        });
        break;
      case 'order':
        await db.update(
          'orders',
          {
            'is_deleted': 0,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        break;
    }
  }

  @override
  Future<void> purge(String type, String id) async {
    final db = await _dbManager.getDatabase();

    switch (type) {
      case 'product':
        await db.delete('products', where: 'id = ?', whereArgs: [id]);
        break;
      case 'customer':
        await db.delete('customers', where: 'id = ?', whereArgs: [id]);
        break;
      case 'sale':
        await db.transaction((txn) async {
          // Delete sale items
          await txn.delete('sale_items', where: 'sale_id = ?', whereArgs: [id]);
          
          // Delete related financial transactions (requires immutability bypass)
          await txn.rawUpdate('UPDATE ledger_bypass_flag SET active = 1');
          try {
            await txn.delete('financial_transactions', where: 'reference_id = ?', whereArgs: [id]);
          } finally {
            await txn.rawUpdate('UPDATE ledger_bypass_flag SET active = 0');
          }

          // Delete the sale itself
          await txn.delete('sales', where: 'id = ?', whereArgs: [id]);
        });
        break;
      case 'order':
        await db.transaction((txn) async {
          // Delete order items
          await txn.delete('order_items', where: 'order_id = ?', whereArgs: [id]);
          // Delete the order itself
          await txn.delete('orders', where: 'id = ?', whereArgs: [id]);
        });
        break;
    }
  }
}
