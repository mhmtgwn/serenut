// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/services/persistent_print_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Sprint C atomic queue, crash recovery and dead-letter acceptance',
      () async {
    DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
    final manager = DatabaseManager();
    addTearDown(() async {
      await manager.close();
      DatabaseManager.overrideDatabasePath = null;
    });
    final queue = PersistentPrintQueue(testKey: 'sprint_c');
    final job = await queue.enqueue(title: 'Fiş', receiptJson: '{"id":1}');
    await queue.markPrinting(job.id);

    final restartedQueue = PersistentPrintQueue(testKey: 'sprint_c');
    await restartedQueue.resetStuckJobs();
    expect((await restartedQueue.loadPending()).single.id, job.id);

    for (var attempt = 0; attempt < 5; attempt++) {
      await restartedQueue.markFailed(job.id, error: 'printer_offline');
    }
    final abandoned = (await restartedQueue.loadAll()).single;
    expect(abandoned.status, PrintJobStatus.abandoned);
    expect(abandoned.retryCount, 5);
    expect(await restartedQueue.loadPending(), isEmpty);

    final db = await manager.getDatabase();
    try {
      await db.transaction((txn) async {
        await txn.insert('print_queue_sprint_c', {
          'id': 'partial-write',
          'title': 'Yarım iş',
          'receipt_json': '{}',
          'created_at': DateTime.now().toIso8601String(),
          'retry_count': 0,
          'status': 'pending',
          'purpose': 'receipt',
          'device_id': 'test-printer',
        });
        throw StateError('simulated power loss');
      });
    } on StateError {
      // Expected: SQLite must roll the partial write back atomically.
    }
    expect(
      await db.query(
        'print_queue_sprint_c',
        where: 'id = ?',
        whereArgs: ['partial-write'],
      ),
      isEmpty,
    );
  });
}
