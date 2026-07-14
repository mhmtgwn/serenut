// test/services/persistent_print_queue_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/services/persistent_print_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
  });

  group('PersistentPrintQueue SQLite Tests', () {
    late PersistentPrintQueue queue;
    const String testKey = 'test_queue';

    setUp(() async {
      queue = PersistentPrintQueue(testKey: testKey);
      await queue.clearAll();
    });

    test('enqueue adds print job and loads pending successfully', () async {
      final job = await queue.enqueue(title: 'Sale Receipt', receiptJson: '{"amount": 100}');
      expect(job.title, 'Sale Receipt');
      expect(job.status, PrintJobStatus.pending);

      final pending = await queue.loadPending();
      expect(pending.length, 1);
      expect(pending.first.id, job.id);
      expect(pending.first.receiptJson, '{"amount": 100}');
    });

    test('markPrinting and markDone updates job status correctly', () async {
      final job = await queue.enqueue(title: 'Fis', receiptJson: '{}');
      
      await queue.markPrinting(job.id);
      var pending = await queue.loadPending();
      expect(pending.length, 0); // No longer pending

      var all = await queue.loadAll();
      expect(all.first.status, PrintJobStatus.printing);

      await queue.markDone(job.id);
      all = await queue.loadAll();
      expect(all.first.status, PrintJobStatus.success);
    });

    test('markFailed increments retry count and marks abandoned if exceeds limit', () async {
      final job = await queue.enqueue(title: 'Fis', receiptJson: '{}');

      // Retry up to 5 times
      for (int i = 0; i < 4; i++) {
        await queue.markFailed(job.id, error: 'Connection lost');
        final pending = await queue.loadPending();
        expect(pending.length, 1); // Still pending
        expect(pending.first.retryCount, i + 1);
        expect(pending.first.status, PrintJobStatus.pending);
      }

      // 5th retry -> abandoned
      await queue.markFailed(job.id, error: 'Connection lost');
      final pending = await queue.loadPending();
      expect(pending.length, 0); // No longer pending

      final all = await queue.loadAll();
      expect(all.first.status, PrintJobStatus.abandoned);
      expect(all.first.lastError, 'Connection lost');
    });

    test('resetStuckJobs resets printing jobs to pending', () async {
      final job = await queue.enqueue(title: 'Fis', receiptJson: '{}');
      await queue.markPrinting(job.id);

      await queue.resetStuckJobs();

      final pending = await queue.loadPending();
      expect(pending.length, 1);
      expect(pending.first.status, PrintJobStatus.pending);
    });

    test('high concurrency enqueues do not produce race conditions', () async {
      // Run 20 concurrent enqueue operations in parallel
      await Future.wait(List.generate(20, (i) {
        return queue.enqueue(title: 'Concurrent Fis $i', receiptJson: '{"id": $i}');
      }));

      final all = await queue.loadAll();
      expect(all.length, 20);

      final titles = all.map((j) => j.title).toList();
      for (int i = 0; i < 20; i++) {
        expect(titles.contains('Concurrent Fis $i'), isTrue);
      }
    });
  });
}
