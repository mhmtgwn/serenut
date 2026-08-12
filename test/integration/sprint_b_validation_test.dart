import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/sync_state_machine.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_customer_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_payment_repository.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_v4_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
      'Sprint B tombstone, clock-skew conflict and immutable ledger acceptance',
      () async {
    SharedPreferences.setMockInitialValues({
      'sync_v4_legacy_snapshot_v1': true,
      'sync_v4_unsynced_product_recovery_v1': true,
    });
    DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
    final manager = DatabaseManager();
    addTearDown(() async {
      await manager.close();
      DatabaseManager.overrideDatabasePath = null;
    });
    final db = await manager.getDatabase();
    final gateway = DbGatewayImpl.raw(db);

    await db.insert('products', {
      'id': 'deleted-product',
      'name': 'Silinecek ürün',
      'price': 10,
      'quantity': 1,
      'category': 'Test',
      'is_active': 1,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    });
    await db.insert('sync_cursor_v4', {'key': 'global', 'cursor': 4});

    final api = ApiClient();
    api.mockHandler = (request) {
      expect(request.url.path, endsWith('/api/v4/sync/pull'));
      return const ApiResponse(
        statusCode: 200,
        headers: {},
        body: '''{"next_cursor":5,"changes":[
          {"entity_type":"product","entity_id":"deleted-product","operation":"DELETE","payload":{"updated_at":"2026-01-02T00:00:00Z"}}
        ]}''',
      );
    };
    final result = await SyncV4Service(
      api,
      deviceActivationIdResolver: () async => 'activation-b',
      deviceIdResolver: () async => 'installation-b',
    ).sync();
    expect(result.success, isTrue);
    final product = (await db.query(
      'products',
      where: 'id = ?',
      whereArgs: ['deleted-product'],
    ))
        .single;
    expect(product['is_active'], 0);
    expect(product['is_deleted'], 1);

    final customerRepo = SqliteCustomerRepository(gateway);
    final transactionRepo = SqliteFinancialTransactionRepository(gateway);
    await customerRepo.create(CustomerEntity(
      id: 'customer-b',
      name: 'Test müşteri',
      email: '',
      phone: '',
      balance: 0,
      createdAt: DateTime.now(),
    ));
    final transaction = FinancialTransactionEntity(
      id: 'tx-b',
      type: 'sale',
      customerId: 'customer-b',
      amount: 100,
      paidAmount: 0,
      debtAmount: 100,
      date: DateTime.now(),
    );
    await transactionRepo.create(transaction);
    expect(() => transactionRepo.update(transaction), throwsUnsupportedError);
    expect(
      () => db.rawUpdate(
        'UPDATE financial_transactions SET amount = 200 WHERE id = ?',
        ['tx-b'],
      ),
      throwsA(isA<DatabaseException>()),
    );

    final machine = SyncStateMachine(db: db, sessionId: 'clock-skew-b');
    await machine.transition(SyncTrigger.startSync);
    await machine.transition(
      SyncTrigger.pushConflict,
      metadata: {'reason': 'clock_skew', 'clock_skew_ms': 120000},
    );
    expect(machine.currentState, SyncState.conflictDetected);
    final transitions = await machine.getSessionTransitions();
    expect(transitions.last['metadata'], contains('clock_skew_ms'));
  });
}
