import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/sync_v2/local/sync_v2_schema.dart';
import 'package:serenutos/infrastructure/sync_v2/local/outbox_dao.dart';
import 'package:serenutos/infrastructure/sync_v2/local/inbox_dao.dart';
import 'package:serenutos/infrastructure/sync_v2/local/sync_state_dao.dart';
import 'package:serenutos/infrastructure/sync_v2/local/sync_local_transaction_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late OutboxDao outboxDao;
  late InboxDao inboxDao;
  late SyncStateDao syncStateDao;
  late SyncLocalTransactionService txService;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await SyncV2Schema.createTables(db);

    // Create a dummy sales_orders entity table for local offline repository testing
    await db.execute('''
      CREATE TABLE sales_orders (
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        title TEXT NOT NULL
      );
    ''');

    outboxDao = OutboxDao(db);
    inboxDao = InboxDao(db);
    syncStateDao = SyncStateDao(db);
    txService = SyncLocalTransactionService(db: db, outboxDao: outboxDao);
  });

  tearDown(() async {
    await db.close();
  });

  group('Faz 4 Offline Storage & Outbox Test Suite', () {
    test('1. Schema Creation & Priority Queue Indexing', () async {
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final names = tables.map((t) => t['name'] as String).toList();
      expect(names, containsAll(['sync_outbox', 'sync_inbox', 'sync_state', 'sync_metadata']));
    });

    test('2. Atomic Local Transaction (Entity + Outbox Commit)', () async {
      await txService.executeLocalTransaction(
        tenantId: 'company_offline_1',
        deviceId: 'dev_01',
        domain: 'sales',
        entityType: 'sales_orders',
        entityId: 'ord_1001',
        opType: 'INSERT',
        payload: {'id': 'ord_1001', 'amount': 150.0, 'title': 'Offline Order 1'},
        clientMutationId: 'mut_off_1',
        baseRevision: 0,
        priority: 1,
        entityOperation: (txn) async {
          await txn.insert('sales_orders', {'id': 'ord_1001', 'amount': 150.0, 'title': 'Offline Order 1'});
        },
      );

      // Verify entity inserted into sales_orders
      final orders = await db.query('sales_orders');
      expect(orders.length, equals(1));
      expect(orders.first['id'], equals('ord_1001'));

      // Verify mutation enqueued into sync_outbox
      final pendingMutations = await outboxDao.getPendingBatch(10);
      expect(pendingMutations.length, equals(1));
      expect(pendingMutations.first.clientMutationId, equals('mut_off_1'));
      expect(pendingMutations.first.priority, equals(1));
    });

    test('3. Priority Queue Dispatch Ordering (P0 > P1 > P2)', () async {
      // Insert P2, P1, P0 in reverse order
      await txService.executeLocalTransaction(
        tenantId: 'comp_1',
        deviceId: 'dev_01',
        domain: 'sales',
        entityType: 'sales_orders',
        entityId: 'ord_p2',
        opType: 'INSERT',
        payload: {'id': 'ord_p2'},
        clientMutationId: 'mut_p2',
        baseRevision: 0,
        priority: 2, // P2 Low
        entityOperation: (txn) async {},
      );

      await txService.executeLocalTransaction(
        tenantId: 'comp_1',
        deviceId: 'dev_01',
        domain: 'sales',
        entityType: 'sales_orders',
        entityId: 'ord_p1',
        opType: 'INSERT',
        payload: {'id': 'ord_p1'},
        clientMutationId: 'mut_p1',
        baseRevision: 0,
        priority: 1, // P1 Normal
        entityOperation: (txn) async {},
      );

      await txService.executeLocalTransaction(
        tenantId: 'comp_1',
        deviceId: 'dev_01',
        domain: 'sales',
        entityType: 'sales_orders',
        entityId: 'ord_p0',
        opType: 'DELETE',
        payload: {'id': 'ord_p0'},
        clientMutationId: 'mut_p0',
        baseRevision: 0,
        priority: 0, // P0 Critical (Delete)
        entityOperation: (txn) async {},
      );

      final batch = await outboxDao.getPendingBatch(10);
      expect(batch.length, equals(3));
      // First in batch MUST be P0, then P1, then P2
      expect(batch[0].clientMutationId, equals('mut_p0'));
      expect(batch[1].clientMutationId, equals('mut_p1'));
      expect(batch[2].clientMutationId, equals('mut_p2'));
    });

    test('4. Idempotent Inbox Tracking', () async {
      expect(await inboxDao.isProcessed('mut_test_1'), isFalse);
      await inboxDao.markProcessed('mut_test_1');
      expect(await inboxDao.isProcessed('mut_test_1'), isTrue);
    });

    test('5. Sync State Vector Tracking', () async {
      await syncStateDao.setVector('sales', 145);
      await syncStateDao.setVector('stock', 890);

      expect(await syncStateDao.getVector('sales'), equals(145));
      expect(await syncStateDao.getVector('stock'), equals(890));

      final allVectors = await syncStateDao.getAllVectors();
      expect(allVectors['sales'], equals(145));
      expect(allVectors['stock'], equals(890));
    });
  });
}
