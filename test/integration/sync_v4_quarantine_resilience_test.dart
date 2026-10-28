import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_v4_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Sync v4 Pull Quarantine Resilience Tests', () {
    test('toxic change in pull batch is quarantined, valid changes applied, and cursor advances', () async {
      SharedPreferences.setMockInitialValues({
        'sync_v4_legacy_snapshot_v1': true,
        'sync_v4_unsynced_product_recovery_v1': true,
      });
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      final manager = DatabaseManager();
      final db = await manager.getDatabase();

      // Set initial cursor to 10
      await db.insert('sync_cursor_v4', {'key': 'global', 'cursor': 10});

      final api = ApiClient();
      api.mockHandler = (request) {
        if (request.url.path.endsWith('/api/v4/sync/pull')) {
          return const ApiResponse(
            statusCode: 200,
            headers: {},
            body: '''{
              "next_cursor": "25",
              "changes": [
                {
                  "mutation_id": "mut-prod-ok",
                  "entity_type": "product",
                  "entity_id": "prod-quarantine-test-1",
                  "operation": "UPSERT",
                  "payload": {
                    "id": "prod-quarantine-test-1",
                    "name": "Karantina Test Ürünü",
                    "price": 100,
                    "quantity": 50,
                    "category": "Genel",
                    "sku": "SKU-Q-1",
                    "vat": 20,
                    "is_active": 1,
                    "is_deleted": 0,
                    "created_at": "2026-01-01T00:00:00.000Z",
                    "updated_at": "2026-01-01T00:00:00.000Z"
                  }
                },
                {
                  "mutation_id": "mut-refund-poison",
                  "entity_type": "refund",
                  "entity_id": "refund-poison-1",
                  "operation": "UPSERT",
                  "payload": {
                    "id": "refund-poison-1",
                    "sale_id": "non_existent_sale_xyz",
                    "items": [
                      {"sale_item_id": "missing_item_1", "quantity": 1}
                    ]
                  }
                },
                {
                  "mutation_id": "mut-cust-ok",
                  "entity_type": "customer",
                  "entity_id": "cust-quarantine-test-1",
                  "operation": "UPSERT",
                  "payload": {
                    "id": "cust-quarantine-test-1",
                    "name": "Karantina Test Müşterisi",
                    "balance": 0,
                    "status": "active",
                    "is_active": 1,
                    "is_deleted": 0,
                    "created_at": "2026-01-01T00:00:00.000Z",
                    "updated_at": "2026-01-01T00:00:00.000Z"
                  }
                }
              ]
            }''',
          );
        }
        return const ApiResponse(statusCode: 404, headers: {}, body: '{}');
      };

      final service = SyncV4Service(
        api,
        deviceActivationIdResolver: () async => 'dact-test',
        deviceIdResolver: () async => 'dev-test',
      );

      final result = await service.sync();

      // 1. Quarantined count is 1
      expect(result.quarantined, equals(1));
      expect(result.pulled, equals(3));

      // 2. Valid product was saved
      final prods = await db.query('products', where: 'id = ?', whereArgs: ['prod-quarantine-test-1']);
      expect(prods.length, equals(1));
      expect(prods.first['name'], equals('Karantina Test Ürünü'));

      // 3. Valid customer was saved
      final custs = await db.query('customers', where: 'id = ?', whereArgs: ['cust-quarantine-test-1']);
      expect(custs.length, equals(1));
      expect(custs.first['name'], equals('Karantina Test Müşterisi'));

      // 4. Toxic refund was recorded in sync_quarantine_v4 table
      final quarantinedRows = await db.query('sync_quarantine_v4');
      expect(quarantinedRows.length, equals(1));
      final q = quarantinedRows.first;
      expect(q['mutation_id'], equals('mut-refund-poison'));
      expect(q['entity_type'], equals('refund'));
      expect(q['entity_id'], equals('refund-poison-1'));
      expect(q['source'], equals('pull'));
      expect(q['error_message'].toString().contains('refund_sale_missing') || q['error_message'].toString().contains('StateError'), isTrue);

      // 5. Cursor advanced to 25 so the terminal is NOT locked!
      final cursorRows = await db.query('sync_cursor_v4', where: 'key = ?', whereArgs: ['global']);
      expect(cursorRows.first['cursor'], equals(25));
    });

    test('clean batch applies with zero quarantined rows', () async {
      SharedPreferences.setMockInitialValues({
        'sync_v4_legacy_snapshot_v1': true,
        'sync_v4_unsynced_product_recovery_v1': true,
      });
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      final manager = DatabaseManager();
      final db = await manager.getDatabase();

      await db.delete('sync_quarantine_v4');
      await db.insert('sync_cursor_v4', {'key': 'global', 'cursor': 50},
          conflictAlgorithm: ConflictAlgorithm.replace);

      final api = ApiClient();
      api.mockHandler = (request) {
        if (request.url.path.endsWith('/api/v4/sync/pull')) {
          return const ApiResponse(
            statusCode: 200,
            headers: {},
            body: '''{
              "next_cursor": "60",
              "changes": [
                {
                  "mutation_id": "mut-prod-clean",
                  "entity_type": "product",
                  "entity_id": "prod-clean-1",
                  "operation": "UPSERT",
                  "payload": {
                    "id": "prod-clean-1",
                    "name": "Temiz Ürün",
                    "price": 25,
                    "quantity": 10,
                    "category": "Genel",
                    "sku": "SKU-CLEAN",
                    "vat": 10,
                    "is_active": 1,
                    "is_deleted": 0,
                    "created_at": "2026-01-01T00:00:00.000Z",
                    "updated_at": "2026-01-01T00:00:00.000Z"
                  }
                }
              ]
            }''',
          );
        }
        return const ApiResponse(statusCode: 404, headers: {}, body: '{}');
      };

      final service = SyncV4Service(
        api,
        deviceActivationIdResolver: () async => 'dact-test',
        deviceIdResolver: () async => 'dev-test',
      );

      final result = await service.sync();

      expect(result.quarantined, equals(0));
      expect(result.pulled, equals(1));

      final prods = await db.query('products', where: 'id = ?', whereArgs: ['prod-clean-1']);
      expect(prods.length, equals(1));

      final quarantinedRows = await db.query('sync_quarantine_v4');
      expect(quarantinedRows.length, equals(0));

      final cursorRows = await db.query('sync_cursor_v4', where: 'key = ?', whereArgs: ['global']);
      expect(cursorRows.first['cursor'], equals(60));
    });
  });
}
