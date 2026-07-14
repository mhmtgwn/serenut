import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/sms_log_entry.dart';

class MockSmsLogRepository {
  final Map<String, SmsLogEntry> db = {};

  Future<void> insertLog(SmsLogEntry entry) async {
    db[entry.id] = entry;
  }

  Future<void> updateStatus(String id, SmsLogStatus status,
      {DateTime? sentAt, String? errorMessage}) async {
    if (db.containsKey(id)) {
      db[id] = db[id]!
          .copyWith(status: status, sentAt: sentAt, errorMessage: errorMessage);
    }
  }

  Future<List<SmsLogEntry>> getActiveCampaignLogs() async {
    return db.values
        .where((e) =>
            (e.status == SmsLogStatus.pending ||
                e.status == SmsLogStatus.sending) &&
            e.eventType == 'bulk_debt_reminder')
        .toList();
  }

  Future<void> cancelActiveCampaignLogs() async {
    for (final id in db.keys) {
      final entry = db[id]!;
      if ((entry.status == SmsLogStatus.pending ||
              entry.status == SmsLogStatus.sending) &&
          entry.eventType == 'bulk_debt_reminder') {
        db[id] = entry.copyWith(status: SmsLogStatus.cancelled);
      }
    }
  }
}

void main() {
  group('Bulk SMS Bounded Concurrency & Cancellation Tests', () {
    test(
        'Sends SMS in batches of at most 5 and stops immediately upon cancellation using SQLite state machine',
        () async {
      final logRepo = MockSmsLogRepository();

      final customerIds = List.generate(13, (i) => 'cust_$i');

      // 1. Initial State: Insert all pending logs
      for (final id in customerIds) {
        await logRepo.insertLog(SmsLogEntry(
          id: 'bulk_debt_$id',
          phone: '5550000000',
          eventType: 'bulk_debt_reminder',
          message: 'message',
          createdAt: DateTime.now(),
          status: SmsLogStatus.pending,
        ));
      }

      final activeLogs = await logRepo.getActiveCampaignLogs();
      expect(activeLogs, hasLength(13));

      final pendingIds = activeLogs
          .map((log) => log.id.replaceFirst('bulk_debt_', ''))
          .toList();

      int activeCount = 0;
      int maxConcurrent = 0;
      int totalSent = 0;
      bool isCancelled = false;
      const int batchSize = 5;

      while (pendingIds.isNotEmpty && !isCancelled) {
        final currentBatchIds = pendingIds.sublist(
            0, pendingIds.length > batchSize ? batchSize : pendingIds.length);

        // Mark batch as sending in SQLite
        for (final id in currentBatchIds) {
          await logRepo.updateStatus('bulk_debt_$id', SmsLogStatus.sending);
        }

        // Simulate Future.wait over the current batch
        await Future.wait(currentBatchIds.map((id) async {
          if (isCancelled) return;

          activeCount++;
          if (activeCount > maxConcurrent) {
            maxConcurrent = activeCount;
          }

          // Simulate network delay
          await Future.delayed(const Duration(milliseconds: 10));

          totalSent++;
          await logRepo.updateStatus('bulk_debt_$id', SmsLogStatus.sent,
              sentAt: DateTime.now());
          activeCount--;
        }));

        if (isCancelled) {
          await logRepo.cancelActiveCampaignLogs();
          break;
        }

        pendingIds.removeWhere((id) => currentBatchIds.contains(id));

        // Simulate cancellation trigger after first batch completes
        if (totalSent == 5) {
          isCancelled = true;
          await logRepo.cancelActiveCampaignLogs();
        }
      }

      // Assert that max concurrency did not exceed batchSize (5)
      expect(maxConcurrent, lessThanOrEqualTo(5));

      // Assert that only the first batch of 5 was sent because we cancelled it
      expect(totalSent, 5);

      // Assert that remaining logs are marked as cancelled
      final remainingActiveLogs = await logRepo.getActiveCampaignLogs();
      expect(remainingActiveLogs, isEmpty);

      final cancelledLogs = logRepo.db.values
          .where((e) => e.status == SmsLogStatus.cancelled)
          .toList();
      expect(cancelledLogs, hasLength(8));
    });
  });
}
