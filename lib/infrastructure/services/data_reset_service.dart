import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/schema/db_triggers.dart';

/// Shared, transaction-safe cleanup primitives used by both the reset UI and
/// Sync V4's server-issued reset barrier.
class DataResetService {
  const DataResetService._();

  /// Safely wipes and recreates the local SQLite database.
  static Future<void> resetLocalDatabase() async {
    final dbManager = DatabaseManager.instance;
    await dbManager.resetDatabase();
  }

  static Future<void> clearOperationalTables(
    DatabaseExecutor db, {
    bool clearSyncState = true,
  }) async {
    // Drop immutable triggers temporarily to permit complete administrative wipe
    await db.execute('DROP TRIGGER IF EXISTS trg_ft_block_delete');
    await db.execute('DROP TRIGGER IF EXISTS trg_ft_block_update');
    await db.execute('DROP TRIGGER IF EXISTS trg_ft_delete');
    await db.execute('DROP TRIGGER IF EXISTS trg_ft_update');
    await db.execute('DROP TRIGGER IF EXISTS trg_ft_insert');
    try {
      // Refund and inventory rows reference sale/product aggregates and must
      // be removed before their parents.
      await _deleteIfPresent(db, 'refund_items');
      await _deleteIfPresent(db, 'refunds');
      await _deleteIfPresent(db, 'inventory_movements');
      await _deleteIfPresent(db, 'sale_items');
      await _deleteIfPresent(db, 'sales');
      await _deleteIfPresent(db, 'customer_order_items');
      await _deleteIfPresent(db, 'order_items');
      await _deleteIfPresent(db, 'orders');
      await _deleteIfPresent(db, 'financial_transactions');
      await _deleteIfPresent(db, 'products');
      await db.rawDelete(
        "DELETE FROM customers WHERE id != '' AND id != 'default'",
      );

      if (clearSyncState) {
        await _deleteIfPresent(db, 'sync_outbox_v4');
        await _deleteIfPresent(db, 'sync_conflicts_v4');
      }
    } finally {
      await DatabaseTriggers.createTriggers(db);
    }
  }

  static Future<void> clearProductImages({Directory? supportDirectory}) async {
    final supportDir =
        supportDirectory ?? await getApplicationSupportDirectory();
    final imagesDir = Directory(p.join(supportDir.path, 'product_images'));
    if (await imagesDir.exists()) {
      await imagesDir.delete(recursive: true);
    }
  }

  /// Hides the complete product catalogue while preserving product rows that
  /// are referenced by historical sales. Pending product mutations are
  /// discarded because the server-issued catalogue reset is the causal
  /// barrier for every device in the tenant.
  static Future<void> clearProductCatalog(
    DatabaseExecutor db, {
    bool clearProductOutbox = true,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawUpdate('''
      UPDATE products
      SET is_active = 0,
          is_deleted = 1,
          deleted_at = COALESCE(deleted_at, ?),
          updated_at = ?,
          is_synced = 1
    ''', [now, now]);
    if (clearProductOutbox) {
      await db.rawDelete(
        "DELETE FROM sync_outbox_v4 WHERE entity_type = 'product'",
      );
      await db.rawDelete(
        "DELETE FROM sync_conflicts_v4 WHERE entity_type = 'product'",
      );
    }
  }

  static Future<void> _deleteIfPresent(
    DatabaseExecutor db,
    String table,
  ) async {
    try {
      await db.rawDelete('DELETE FROM $table');
    } on DatabaseException catch (error) {
      if (!error.toString().toLowerCase().contains('no such table')) rethrow;
    }
  }
}
