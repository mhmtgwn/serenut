// test/services/sms_crash_recovery_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/sms_log_entry.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/repositories/sms_log_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
  });

  group('SMS Crash Recovery SQLite Tests', () {
    late DatabaseManager dbManager;
    late SmsLogRepository repo;

    setUp(() async {
      dbManager = DatabaseManager();
      dbManager.reset();
      repo = SmsLogRepository(dbManager);

      // Clean start: clear sms_logs table
      final db = await dbManager.getDatabase();
      await db.delete('sms_logs');
    });

    test(
        'Transitions stuck "sending" SMS to "interrupted" state and does not auto-retry',
        () async {
      const logId = 'test_crashed_sms_123';

      // 1. Simulate the crash: insert an SMS log in "sending" status
      final entry = SmsLogEntry(
        id: logId,
        phone: '+905551112233',
        eventType: 'sale_created',
        message: 'Teşekkürler!',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        status: SmsLogStatus.sending, // App crashed during sending
      );
      await repo.insertLog(entry);

      // Verify it was correctly stored as sending
      var logs = await repo.getRecentLogs(limit: 10);
      expect(logs.length, 1);
      expect(logs.first.id, logId);
      expect(logs.first.status, SmsLogStatus.sending);

      // 2. Simulate Service Restart / startup recovery trigger
      await repo.resetStuckJobs();

      // Verify the log status is now "interrupted" (and NOT pending or sent)
      logs = await repo.getRecentLogs(limit: 10);
      expect(logs.length, 1);
      expect(logs.first.id, logId);
      expect(logs.first.status, SmsLogStatus.interrupted);

      // 3. Verify it is NOT considered pending for auto-retry
      // getPendingLogs should NOT return it
      final pendingLogs = await repo.getPendingLogs();
      expect(pendingLogs.any((l) => l.id == logId), isFalse);

      // Verify it is visible via getUnknownLogs() for user intervention
      final unknownLogs = await repo.getUnknownLogs();
      expect(unknownLogs.length, 1);
      expect(unknownLogs.first.id, logId);
      expect(unknownLogs.first.status, SmsLogStatus.interrupted);
    });

    test('Allows explicit manual status update of interrupted SMS logs',
        () async {
      const logId = 'test_manual_sms_456';

      final entry = SmsLogEntry(
        id: logId,
        phone: '+905551112233',
        eventType: 'collection_recorded',
        message: 'Ödeme alındı.',
        createdAt: DateTime.now(),
        status: SmsLogStatus.interrupted,
      );
      await repo.insertLog(entry);

      // Verify manual update works (simulating user selecting "Tekrar Gönder")
      await repo.updateStatus(logId, SmsLogStatus.sending);
      var logs = await repo.getRecentLogs(limit: 10);
      expect(logs.first.status, SmsLogStatus.sending);

      // Simulate successful dispatch
      await repo.updateStatus(logId, SmsLogStatus.sent, sentAt: DateTime.now());
      logs = await repo.getRecentLogs(limit: 10);
      expect(logs.first.status, SmsLogStatus.sent);
      expect(logs.first.sentAt, isNotNull);
    });
  });
}
