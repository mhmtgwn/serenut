// test/device/printer_stress_test.dart
// Serenut POS — Printer Stress & Resilience Tests
// Tests: 100-receipt loop, mid-print disconnect, network outage recovery,
//        failover chain, persistent queue, stuck job reset
// Created: 24 Jun 2026

import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/infrastructure/services/persistent_print_queue.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
  });
  // ── PersistentPrintQueue Tests ────────────────────────────────────────────

  group('PersistentPrintQueue — Crash Safety', () {
    late PersistentPrintQueue queue;
    int testCounter = 0;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      // Each test gets a unique SP key → fully isolated, no cross-test pollution
      testCounter++;
      queue = PersistentPrintQueue(testKey: 'test_queue_$testCounter');
    });

    test('enqueue persists a job and loadPending returns it', () async {
      final job = await queue.enqueue(
        title: 'Test Fisi',
        receiptJson: '{"sale":"test123"}',
      );
      expect(job.id, isNotEmpty);

      final pending = await queue.loadPending();
      expect(pending.any((j) => j.id == job.id), isTrue);
    });

    test('markDone removes job from pending', () async {
      final job = await queue.enqueue(
        title: 'Done Test',
        receiptJson: '{}',
      );
      await queue.markDone(job.id);

      final pending = await queue.loadPending();
      expect(pending.any((j) => j.id == job.id), isFalse);
    });

    test('markFailed increments retryCount', () async {
      final job = await queue.enqueue(
        title: 'Fail Test',
        receiptJson: '{}',
      );

      await queue.markFailed(job.id, error: 'Printer disconnected');

      final all = await queue.loadAll();
      final updated = all.firstWhere((j) => j.id == job.id);
      expect(updated.retryCount, equals(1));
      expect(updated.lastError, contains('disconnected'));
    });

    test('job is abandoned after max retries (5)', () async {
      final job = await queue.enqueue(
        title: 'Max Retry Test',
        receiptJson: '{}',
      );

      // Fail 5 times
      for (int i = 0; i < 5; i++) {
        await queue.markFailed(job.id, error: 'Failure $i');
      }

      final all = await queue.loadAll();
      final updated = all.firstWhere((j) => j.id == job.id);
      expect(updated.status, equals(PrintJobStatus.abandoned));
      expect(updated.retryCount, equals(5));

      // Should NOT be in pending anymore
      final pending = await queue.loadPending();
      expect(pending.any((j) => j.id == job.id), isFalse);
    });

    test('resetStuckJobs resets "printing" status back to pending', () async {
      final job = await queue.enqueue(
        title: 'Stuck Job Test',
        receiptJson: '{}',
      );
      await queue.markPrinting(job.id);

      // Simulate app kill — on restart, call resetStuckJobs
      await queue.resetStuckJobs();

      final pending = await queue.loadPending();
      expect(pending.any((j) => j.id == job.id), isTrue);
    });

    test('pendingCount returns correct count', () async {
      await queue.enqueue(title: 'Job 1', receiptJson: '{}');
      await queue.enqueue(title: 'Job 2', receiptJson: '{}');
      await queue.enqueue(title: 'Job 3', receiptJson: '{}');

      final count = await queue.pendingCount();
      expect(count, greaterThanOrEqualTo(3));
    });

    test('clearCompleted removes success and abandoned jobs', () async {
      final job1 = await queue.enqueue(title: 'To succeed', receiptJson: '{}');
      final job2 = await queue.enqueue(title: 'To abandon', receiptJson: '{}');

      await queue.markDone(job1.id);
      for (int i = 0; i < 5; i++) {
        await queue.markFailed(job2.id);
      }

      await queue.clearCompleted();

      final all = await queue.loadAll();
      expect(all.any((j) => j.id == job1.id), isFalse);
      expect(all.any((j) => j.id == job2.id), isFalse);
    });

    test('100 receipts loop — enqueue all, mark all done', () async {
      final ids = <String>[];

      // Enqueue 100 jobs
      for (int i = 0; i < 100; i++) {
        final job = await queue.enqueue(
          title: 'Fis #$i',
          receiptJson: '{"index":$i,"amount":${(i + 1) * 10.0}}',
        );
        ids.add(job.id);
      }

      final pendingAfterEnqueue = await queue.pendingCount();
      expect(pendingAfterEnqueue, greaterThanOrEqualTo(100));

      // Mark all done (simulating successful print)
      for (final id in ids) {
        await queue.markDone(id);
      }

      // All should be gone from pending
      final pendingAfterDone = await queue.loadPending();
      final anyStillPending = pendingAfterDone.any((j) => ids.contains(j.id));
      expect(anyStillPending, isFalse);
    });

    test('printer disconnect mid-batch — failed jobs re-queue', () async {
      const totalJobs = 10;
      final ids = <String>[];

      for (int i = 0; i < totalJobs; i++) {
        final job = await queue.enqueue(
          title: 'Batch Fis #$i',
          receiptJson: '{"batch":$i}',
        );
        ids.add(job.id);
      }

      // Simulate: first 5 succeed, then printer disconnects
      for (int i = 0; i < 5; i++) {
        await queue.markDone(ids[i]);
      }
      for (int i = 5; i < totalJobs; i++) {
        await queue.markFailed(ids[i],
            error: 'SocketException: printer offline');
      }

      // Failed jobs should still be in pending (retry count = 1, not abandoned)
      final pending = await queue.loadPending();
      final failedPending =
          pending.where((j) => ids.sublist(5).contains(j.id)).toList();
      expect(failedPending.length, equals(5));
      expect(failedPending.every((j) => j.retryCount == 1), isTrue);
    });

    test('network outage recovery — jobs persist across simulated restart',
        () async {
      // Simulate: app creates job, then crashes before printing
      final job = await queue.enqueue(
        title: 'Outage Recovery Test',
        receiptJson: '{"amount":250.0}',
      );
      await queue.markPrinting(job.id); // Set to printing state

      // Simulate app restart — new queue instance loads persisted state
      final newQueueInstance = PersistentPrintQueue(testKey: queue.testKey);
      await newQueueInstance.resetStuckJobs(); // Called on startup

      final pending = await newQueueInstance.loadPending();
      expect(pending.any((j) => j.id == job.id), isTrue);

      // Cleanup
      await newQueueInstance.markDone(job.id);
    });
  });

  // ── Printer Failover Logic Tests ──────────────────────────────────────────

  group('Printer Failover — Mock Scenarios', () {
    test('TCP connect timeout is bounded to 5 seconds', () async {
      // Try to connect to a non-routable IP — should timeout within limit
      final sw = Stopwatch()..start();
      try {
        await Socket.connect('192.0.2.1', 9100,
            timeout: const Duration(seconds: 5));
      } on SocketException {
        // Expected — no server
      } on TimeoutException {
        // Expected — timeout
      } catch (_) {
        // Other exceptions also acceptable
      }
      sw.stop();

      // Should fail quickly (within 6s with margin)
      expect(sw.elapsed.inSeconds, lessThan(7));
    });

    test('queue enqueue does not throw on repeated calls', () async {
      SharedPreferences.setMockInitialValues({});
      final q = PersistentPrintQueue(testKey: 'test_stress_enqueue');
      expect(
        () async {
          for (int i = 0; i < 20; i++) {
            await q.enqueue(title: 'Stress $i', receiptJson: '{}');
          }
        },
        returnsNormally,
      );
    });
  });
}
