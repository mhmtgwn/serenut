// test/services/standard_reset_test.dart
// KRITIK C DOGRULAMA: Native platformlarda Standart Sifirlama
// tum operasyonel tablolari tek bir transaction icinde temizledigini dogrular.
// Pesin musteri (id='default') korunmalidir.
//
// Sprint 1 kabul kriteri:
//   - Standart Sifirlama sonrasi sales, orders, financial_transactions,
//     products tablolari tamamen bos olmali.
//   - customers tablosunda sadece id='default' kaydi kalmali.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/services/data_reset_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Standart Sifirlama - Kritik C (Native DB Transaction)', () {
    late DatabaseManager dbManager;

    setUp(() async {
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      dbManager = DatabaseManager();
      await dbManager.close();
    });

    tearDown(() async {
      await dbManager.close();
      DatabaseManager.overrideDatabasePath = null;
    });

    Future<void> seedData(dynamic db) async {
      await db.delete(
          'customers'); // Clear auto-seeded customer so we only have what we expect in the test
      await db.insert('customers', {
        'id': 'default',
        'name': 'Pesin Musteri',
        'phone': '',
        'balance': 0.0,
        'credit_limit': 0.0,
        'is_synced': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      await db.insert('customers', {
        'id': 'cust-1',
        'name': 'Ahmet Yilmaz',
        'phone': '05551234567',
        'balance': 500.0,
        'credit_limit': 1000.0,
        'is_synced': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      await db.insert('products', {
        'id': 'prod-1',
        'name': 'Findik',
        'price': 150.0,
        'quantity': 10,
        'category': 'Kuruyemis',
        'vat': 8,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      await db.insert('sales', {
        'id': 'sale-1',
        'customer_id': 'cust-1',
        'total_amount': 300.0,
        'paid_amount': 300.0,
        'payment_method': 'cash',
        'status': 'completed',
        'is_synced': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      await db.insert('sale_items', {
        'id': 'si-1',
        'sale_id': 'sale-1',
        'product_id': 'prod-1',
        'quantity': 2.0,
        'unit_price': 150.0,
        'subtotal': 300.0,
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert('refunds', {
        'id': 'refund-1',
        'sale_id': 'sale-1',
        'amount': 150.0,
        'refund_method': 'cash',
        'reason': 'Test iadesi',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert('refund_items', {
        'id': 'refund-item-1',
        'refund_id': 'refund-1',
        'sale_item_id': 'si-1',
        'product_id': 'prod-1',
        'quantity': 1,
        'unit_refund_amount': 150.0,
        'subtotal': 150.0,
      });
      await db.insert('orders', {
        'id': 'ord-1',
        'order_number': 'TEST-ORD-1',
        'customer_id': 'cust-1',
        'status': 'created',
        'total_amount': 300.0,
        'order_date': DateTime.now().toIso8601String(),
        'is_synced': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      await db.insert('order_items', {
        'id': 'oi-1',
        'order_id': 'ord-1',
        'product_id': 'prod-1',
        'quantity': 2.0,
        'unit_price': 150.0,
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert('financial_transactions', {
        'id': 'ft-1',
        'type': 'payment',
        'customer_id': 'cust-1',
        'amount': 200.0,
        'paid_amount': 200.0,
        'debt_amount': 0.0,
        'is_synced': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert('sync_outbox_v4', {
        'mutation_id': 'mut-1',
        'entity_type': 'sale',
        'entity_id': 'sale-1',
        'operation': 'UPSERT',
        'payload': '{}',
        'state': 'PENDING',
        'attempts': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert('sync_cursor_v4', {
        'key': 'global',
        'cursor': 42,
      });
    }

    test(
        'standart sifirlama tum tablolari transaction icinde temizlemeli ve siparislerde FK hatasi vermemeli',
        () async {
      final db = await dbManager.getDatabase();
      await seedData(db);

      expect((await db.query('sales')).length, 1);
      expect((await db.query('refunds')).length, 1);
      expect((await db.query('refund_items')).length, 1);
      expect((await db.query('orders')).length, 1);
      expect((await db.query('order_items')).length, 1);
      expect((await db.query('products')).length, 1);
      expect((await db.query('financial_transactions')).length, 1);
      expect((await db.query('customers')).length, 2);
      expect((await db.query('sync_outbox_v4')).length, 1);
      expect((await db.query('sync_cursor_v4')).length, 1);

      // Uretim kodundaki ortak, transaction-safe sifirlama servisini kullan.
      await db.transaction((txn) async {
        await DataResetService.clearOperationalTables(txn);
      });

      final salesCount = (await db.query('sales')).length;
      final refundsCount = (await db.query('refunds')).length;
      final refundItemsCount = (await db.query('refund_items')).length;
      final ordersCount = (await db.query('orders')).length;
      final orderItemsCount = (await db.query('order_items')).length;
      final productsCount = (await db.query('products')).length;
      final txCount = (await db.query('financial_transactions')).length;
      final outboxCount = (await db.query('sync_outbox_v4')).length;
      final cursorCount = (await db.query('sync_cursor_v4')).length;
      final custRows = await db.query('customers');

      expect(salesCount, 0, reason: 'Tum satislar silinmeli');
      expect(refundsCount, 0, reason: 'Tum iadeler silinmeli');
      expect(refundItemsCount, 0, reason: 'Tum iade kalemleri silinmeli');
      expect(ordersCount, 0, reason: 'Tum siparisler silinmeli');
      expect(orderItemsCount, 0, reason: 'Tum siparis kalemleri silinmeli');
      expect(productsCount, 0, reason: 'Tum urunler silinmeli');
      expect(txCount, 0, reason: 'Tum finansal islemler silinmeli');
      expect(outboxCount, 0, reason: 'Outbox temizlenmeli');
      expect(cursorCount, 1,
          reason: 'Cursor sunucu reset revizyonu yazilana kadar korunmali');
      expect(custRows.length, 1, reason: 'Sadece pesin musteri kalmali');
      expect(custRows.first['id'], 'default',
          reason: 'Kalan musteri pesin musteri olmali');
    });

    test(
        'standard reset fails midway -> transaction rolls back and ledger_bypass_flag is restored/remains 0',
        () async {
      final db = await dbManager.getDatabase();
      await seedData(db);

      // Verify bypass flag is initially 0
      var flagRes =
          await db.rawQuery('SELECT active FROM ledger_bypass_flag LIMIT 1');
      expect(flagRes.first['active'], 0);

      // Try running transaction that throws exception midway
      try {
        await db.transaction((txn) async {
          await txn.rawUpdate('UPDATE ledger_bypass_flag SET active = 1');
          try {
            await txn.rawDelete('DELETE FROM sale_items');
            await txn.rawDelete('DELETE FROM sales');
            // Force failure
            throw Exception('Simulated middle failure');
          } finally {
            await txn.rawUpdate('UPDATE ledger_bypass_flag SET active = 0');
          }
        });
      } catch (_) {}

      // Verify that after transaction fails and rolls back, bypass flag remains/reverts to 0
      flagRes =
          await db.rawQuery('SELECT active FROM ledger_bypass_flag LIMIT 1');
      expect(flagRes.first['active'], 0,
          reason: 'Flag must be 0 after failed transaction rollback');

      // Verify that sales were not deleted due to rollback
      expect((await db.query('sales')).length, 1);
    });
  });
}
