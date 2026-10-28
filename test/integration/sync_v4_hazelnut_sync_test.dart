import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_hazelnut_repository.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_v4_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Sync v4 Hazelnut & Warehouse Full Integration Tests', () {
    test('local hazelnut operations enqueue outbox and remote changes materialize correctly', () async {
      SharedPreferences.setMockInitialValues({
        'sync_v4_legacy_snapshot_v1': true,
        'sync_v4_unsynced_product_recovery_v1': true,
      });
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      final manager = DatabaseManager();
      final db = await manager.getDatabase();
      final gateway = DbGatewayImpl(manager);

      // Create a test customer
      await db.insert('customers', {
        'id': 'cust-hazel-1',
        'name': 'Fındık Üreticisi Ahmet',
        'phone': '05551112233',
        'balance': 0.0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      final repo = SqliteHazelnutRepository(gateway);
      final warehouses = await repo.getWarehouses();
      expect(warehouses.isNotEmpty, isTrue);
      final defaultWh = warehouses.first;

      // 1. Add Escrow Batch and verify outbox enqueue
      final escrow = await repo.addEscrowBatch(
        customerId: 'cust-hazel-1',
        warehouseId: defaultWh.id,
        grossKg: 1000.0,
        sackCount: 20,
        tarePerSack: 1.0,
        rendiment: 52.5,
        receiptNo: 'EM-TEST-001',
      );
      expect(escrow.netKg, 980.0);

      // Verify outbox entries
      final outboxItems = await db.query('sync_outbox_v4');
      final outboxTypes = outboxItems.map((r) => r['entity_type'] as String).toSet();
      expect(outboxTypes.contains('warehouse'), isTrue);
      expect(outboxTypes.contains('customer_hazelnut_escrow'), isTrue);
      expect(outboxTypes.contains('warehouse_hazelnut_movement'), isTrue);

      // 2. Cut Escrow Price and verify outbox enqueue
      final priceCut = await repo.cutEscrowPrice(
        escrowId: escrow.id,
        cutKg: 400.0,
        basePrice50: 120.0,
        settlementType: 'ACCOUNT_CREDIT',
      );
      expect(priceCut.cutKg, 400.0);

      final outboxItemsAfterCut = await db.query('sync_outbox_v4');
      final cutTypes = outboxItemsAfterCut.map((r) => r['entity_type'] as String).toSet();
      expect(cutTypes.contains('hazelnut_price_cut'), isTrue);
      expect(cutTypes.contains('financial_transaction'), isTrue);

      // 3. Test Pull and Materialization of remote hazelnut mutations
      final api = ApiClient();
      api.mockHandler = (request) {
        if (request.url.path.endsWith('/api/v4/sync/pull')) {
          return const ApiResponse(
            statusCode: 200,
            headers: {},
            body: '''{
              "next_cursor": "50",
              "changes": [
                {
                  "mutation_id": "mut-remote-wh-1",
                  "entity_type": "warehouse",
                  "entity_id": "wh-remote-sube2",
                  "operation": "UPSERT",
                  "payload": {
                    "id": "wh-remote-sube2",
                    "name": "Şube 2 Depo",
                    "location": "Çarşamba",
                    "capacity_kg": 75000,
                    "current_stock_kg": 15000,
                    "average_rendiment": 51.5,
                    "is_active": 1,
                    "is_deleted": 0,
                    "created_at": "2026-01-01T00:00:00.000Z",
                    "updated_at": "2026-01-01T00:00:00.000Z"
                  }
                },
                {
                  "mutation_id": "mut-remote-escrow-1",
                  "entity_type": "customer_hazelnut_escrow",
                  "entity_id": "escrow-remote-99",
                  "operation": "UPSERT",
                  "payload": {
                    "id": "escrow-remote-99",
                    "customer_id": "cust-hazel-1",
                    "warehouse_id": "wh-remote-sube2",
                    "receipt_no": "EM-REMOTE-99",
                    "gross_kg": 500,
                    "sack_count": 10,
                    "tare_kg": 10,
                    "net_kg": 490,
                    "rendiment": 50.0,
                    "remaining_kg": 490,
                    "status": "active",
                    "notes": "Bulut senkronizasyon testi",
                    "created_by": "cloud_user",
                    "created_at": "2026-01-01T00:00:00.000Z",
                    "updated_at": "2026-01-01T00:00:00.000Z"
                  }
                }
              ]
            }''',
          );
        }
        return const ApiResponse(
          statusCode: 200,
          headers: {},
          body: '{"success": true}',
        );
      };

      await db.insert('sync_cursor_v4', {'key': 'global', 'cursor': 10},
          conflictAlgorithm: ConflictAlgorithm.replace);

      final syncService = SyncV4Service(
        api,
        deviceActivationIdResolver: () async => 'dact-test',
        deviceIdResolver: () async => 'dev-test',
      );
      final pullResult = await syncService.sync();

      expect(pullResult.success, isTrue);
      expect(pullResult.pulled, greaterThanOrEqualTo(2));
      expect(pullResult.quarantined, 0);

      // Verify that the remote warehouse and escrow materialized cleanly in SQLite
      final remoteWh = await repo.getWarehouseById('wh-remote-sube2');
      expect(remoteWh, isNotNull);
      expect(remoteWh!.name, 'Şube 2 Depo');
      expect(remoteWh.currentStockKg, 15000);

      final remoteEscrow = await repo.getEscrowById('escrow-remote-99');
      expect(remoteEscrow, isNotNull);
      expect(remoteEscrow!.netKg, 490);
      expect(remoteEscrow.receiptNo, 'EM-REMOTE-99');
    });
  });
}
