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

  test('fresh device hydrates tenant snapshot before cursor pull', () async {
    SharedPreferences.setMockInitialValues({
      'sync_v4_legacy_snapshot_v1': true,
      'sync_v4_unsynced_product_recovery_v1': true,
    });
    DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
    final manager = DatabaseManager();
    final db = await manager.getDatabase();
    await db.insert('customers', {
      'id': 'cust-1',
      'name': 'Yerel Ayşe',
      'balance': -1748,
      'status': 'active',
      'is_active': 1,
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });
    final api = ApiClient();
    api.mockHandler = (request) {
      if (request.url.path.endsWith('/api/v4/sync/bootstrap')) {
        return const ApiResponse(
          statusCode: 200,
          headers: {},
          body: '''{
            "next_cursor": "7",
            "changes": [
              {"entity_type":"product","entity_id":"prod-1","operation":"UPSERT","payload":{"id":"prod-1","name":"Çay","description":"","price":15,"quantity":20,"category":"İçecek","sku":"prod-1","vat":10,"is_active":1,"is_deleted":0,"created_at":"2026-01-01T00:00:00.000Z","updated_at":"2026-01-01T00:00:00.000Z","image_url":""}},
              {"entity_type":"customer","entity_id":"cust-1","operation":"UPSERT","payload":{"id":"cust-1","name":"Ayşe","email":"","phone":"","balance":-1748,"credit_limit":0,"status":"active","is_active":1,"is_deleted":0,"created_at":"2026-01-01T00:00:00.000Z","updated_at":"2026-01-01T00:00:00.000Z"}},
              {"entity_type":"sale","entity_id":"sale-1","operation":"UPSERT","payload":{"id":"sale-1","customer_id":"cust-1","total_amount":"874.00","paid_amount":"0.00","payment_method":"debt","status":"completed","is_deleted":0,"created_at":"2026-01-01T00:00:00.000Z","future_server_field":"ignored","items":[{"id":"sale-item-1","product_id":"prod-1","product_name":"Çay (Satış Anı)","quantity":"2.000","unit_price":"437.00","subtotal":"874.00","created_at":"2026-01-01T00:00:00.000Z"}]}},
              {"entity_type":"financial_transaction","entity_id":"tx-1","operation":"UPSERT","payload":{"id":"tx-1","type":"sale","customer_id":"cust-1","amount":874,"paid_amount":0,"debt_amount":874,"created_at":"2026-01-01T00:00:00.000Z","updated_at":"2026-01-01T00:00:00.000Z"}}
            ]
          }''',
        );
      }
      if (request.url.path.endsWith('/api/v4/sync/pull')) {
        return const ApiResponse(
          statusCode: 200,
          headers: {},
          body: '{"changes":[],"next_cursor":"7"}',
        );
      }
      if (request.url.path.endsWith('/api/v4/sync/push')) {
        return const ApiResponse(
          statusCode: 200,
          headers: {},
          body: '{"results":[]}',
        );
      }
      throw StateError('Unexpected request: ${request.url}');
    };

    final result = await SyncV4Service(
      api,
      deviceActivationIdResolver: () async => 'dact-test',
      deviceIdResolver: () async => 'installation-test',
    ).sync();

    expect(result.success, isTrue);
    expect(result.reconciled, 1);
    expect(result.pulled, 4);
    expect(
        (await db.query('products', where: 'id = ?', whereArgs: ['prod-1']))
            .single['name'],
        'Çay');
    expect(
        (await db.query('customers', where: 'id = ?', whereArgs: ['cust-1']))
            .single['name'],
        'Ayşe');
    expect(
        (await db.query('customers', where: 'id = ?', whereArgs: ['cust-1']))
            .single['balance'],
        -874.0);
    expect(
        (await db.query('sales', where: 'id = ?', whereArgs: ['sale-1']))
            .single['total_amount'],
        874.0);
    expect(
        (await db.query('sales', where: 'id = ?', whereArgs: ['sale-1']))
            .single['updated_at'],
        '2026-01-01T00:00:00.000Z');
    expect(
        (await db.query('sale_items',
                where: 'sale_id = ?', whereArgs: ['sale-1']))
            .single['product_id'],
        'prod-1');
    expect(
        (await db.query('sale_items',
                where: 'sale_id = ?', whereArgs: ['sale-1']))
            .single['product_name'],
        'Çay (Satış Anı)');
    expect(
        (await db.query('sale_items',
                where: 'sale_id = ?', whereArgs: ['sale-1']))
            .single['quantity'],
        2.0);
    expect(
        (await db.query('sale_items',
                where: 'sale_id = ?', whereArgs: ['sale-1']))
            .single['unit_price'],
        437.0);
    expect(
        (await db.query('financial_transactions',
                where: 'id = ?', whereArgs: ['tx-1']))
            .single['amount'],
        874.0);
    expect(
        (await db.query('sync_cursor_v4',
                where: 'key = ?', whereArgs: ['global']))
            .single['cursor'],
        7);

    await manager.close();
    DatabaseManager.overrideDatabasePath = null;
  });
}
