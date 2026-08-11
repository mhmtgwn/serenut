import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Shared, transaction-safe cleanup primitives used by both the reset UI and
/// Sync V4's server-issued reset barrier.
class DataResetService {
  const DataResetService._();

  static Future<void> clearOperationalTables(
    DatabaseExecutor db, {
    bool clearSyncState = true,
  }) async {
    await db.rawUpdate('UPDATE ledger_bypass_flag SET active = 1');
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
      await db.rawUpdate('UPDATE ledger_bypass_flag SET active = 0');
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
