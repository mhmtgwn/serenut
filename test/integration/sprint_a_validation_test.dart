import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/pagination_service.dart';
import 'package:serenutos/domain/services/sync_state_machine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Sprint A sync pagination and crash-resume acceptance', () async {
    final source = List<int>.generate(8, (index) => index);
    final pagination = PaginationService<int>(
      pageSize: 3,
      dataLoader: (offset, limit, _) async =>
          source.skip(offset).take(limit).toList(growable: false),
    );

    await pagination.loadFirstPage();
    await pagination.loadNextPage();
    expect(pagination.items, [0, 1, 2, 3, 4, 5]);
    expect(pagination.currentPage, 1);
    expect(pagination.hasMoreData, isTrue);

    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE sync_state_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        from_state TEXT NOT NULL,
        to_state TEXT NOT NULL,
        trigger_event TEXT NOT NULL,
        sale_id TEXT,
        device_id TEXT,
        metadata TEXT,
        occurred_at TEXT NOT NULL
      )
    ''');

    const sessionId = 'sprint-a-resume';
    final interrupted = SyncStateMachine(db: db, sessionId: sessionId);
    await interrupted.transition(SyncTrigger.startSync);
    await interrupted.transition(
      SyncTrigger.pushConflict,
      metadata: {'cursor': 6},
    );

    final resumed = SyncStateMachine(db: db, sessionId: sessionId);
    await resumed.restoreFromCrash();
    expect(resumed.currentState, SyncState.conflictDetected);
    await resumed.transition(SyncTrigger.startSync);
    await resumed.transition(SyncTrigger.mergeComplete);
    expect(resumed.currentState, SyncState.syncing);

    await pagination.loadNextPage();
    expect(pagination.items, source);
    expect(pagination.hasMoreData, isFalse);
  });
}
