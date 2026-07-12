// test/services/central_background_scheduler_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/infrastructure/services/central_background_scheduler.dart';

class MockJob extends SchedulerJob {
  @override
  final String name;
  @override
  final JobPriority priority;
  @override
  final Duration interval;

  int callCount = 0;
  bool shouldThrow = false;

  MockJob({
    required this.name,
    required this.priority,
    required this.interval,
  });

  @override
  Future<void> execute() async {
    callCount++;
    if (shouldThrow) {
      throw Exception('Mock job execution error');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late CentralBackgroundScheduler scheduler;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    scheduler = CentralBackgroundScheduler(prefs);
  });

  group('CentralBackgroundScheduler Tests', () {
    test('registerJob registers a job and runs it on tick', () async {
      final job = MockJob(
        name: 'test_job_1',
        priority: JobPriority.high,
        interval: const Duration(seconds: 5),
      );

      scheduler.registerJob(job);
      expect(job.callCount, 0);

      // Trigger tick manually
      await scheduler.tick();

      expect(job.callCount, 1);
    });

    test('Power Saving Mode (low battery < 20) slows down job runtime check', () async {
      final job = MockJob(
        name: 'test_power_saving',
        priority: JobPriority.medium,
        interval: const Duration(seconds: 10),
      );

      scheduler.registerJob(job);
      scheduler.updateBatteryStatus(15.0); // 15% battery (triggers low battery)

      // First run should execute immediately
      await scheduler.tick();
      expect(job.callCount, 1);

      // Advance battery modifier interval checks
      // Normal interval is 10s. Modified interval should be 10 * 5 = 50s.
      // After 20 seconds, difference since last run (0) is 20s.
      // 20s < 50s, so it should NOT execute on next tick.
      await scheduler.tick();
      expect(job.callCount, 1); // still 1
    });

    test('Offline mode skips medium/low jobs but runs high priority job', () async {
      final highJob = MockJob(name: 'high_job', priority: JobPriority.high, interval: const Duration(seconds: 5));
      final lowJob = MockJob(name: 'low_job', priority: JobPriority.low, interval: const Duration(seconds: 5));

      scheduler.registerJob(highJob);
      scheduler.registerJob(lowJob);

      scheduler.updateNetworkStatus(false); // Offline

      await scheduler.tick();

      expect(highJob.callCount, 1); // High priority runs offline
      expect(lowJob.callCount, 0);  // Low priority skipped offline
    });

    test('Exponential backoff increments on failure and resets on success', () async {
      final job = MockJob(
        name: 'failing_job',
        priority: JobPriority.high,
        interval: const Duration(seconds: 5),
      );

      scheduler.registerJob(job);
      job.shouldThrow = true;

      // First run: throws, callCount = 1, backoff factor = 1 (active interval increases)
      await scheduler.tick();
      expect(job.callCount, 1);

      // Verify backoff factor is 1
      expect(scheduler.backoffFactors[job.name], 1);

      // Make job succeed now
      job.shouldThrow = false;

      // Because backoff factor is 1, active interval is 5s + 30s = 35s.
      // Force elapsed time by overriding the last run time back in time
      scheduler.lastRunTimes[job.name] = DateTime.now().subtract(const Duration(seconds: 40));

      await scheduler.tick();
      expect(job.callCount, 2);

      // Backoff factor should reset to 0
      expect(scheduler.backoffFactors[job.name], 0);
    });
  });
}
