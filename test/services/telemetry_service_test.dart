// test/services/telemetry_service_test.dart
// Unit tests for TelemetryService logs execution and JSONL consistency checks.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late TelemetryService telemetryService;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('telemetry_test');
    
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );

    telemetryService = TelemetryService();
  });

  tearDownAll(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    await telemetryService.clearLogs();
  });

  group('TelemetryService Tests', () {
    test('Logs events to JSONL and reads them back correctly', () async {
      // 1. Log two different events
      await telemetryService.logEvent('test_event_1', {
        'metric_val': 42,
        'tag': 'debug',
      });
      await telemetryService.logEvent('test_event_2', {
        'metric_val': 100,
        'tag': 'production',
      });

      // 2. Retrieve log events
      final events = await telemetryService.getEvents();

      expect(events, hasLength(2));

      // 3. Assert first event
      final ev1 = events.first;
      expect(ev1.event, equals('test_event_1'));
      expect(ev1.metadata['metric_val'], equals(42));
      expect(ev1.metadata['tag'], equals('debug'));
      expect(ev1.metadata['rss_mb'], isNotNull); // RSS memory profiling verification

      // 4. Assert second event
      final ev2 = events.last;
      expect(ev2.event, equals('test_event_2'));
      expect(ev2.metadata['metric_val'], equals(100));
      expect(ev2.metadata['tag'], equals('production'));
    });

    test('clearLogs removes the underlying log file', () async {
      // 1. Log an event
      await telemetryService.logEvent('test_to_clear', {'val': 1});
      var events = await telemetryService.getEvents();
      expect(events, isNotEmpty);

      // 2. Clear
      await telemetryService.clearLogs();
      events = await telemetryService.getEvents();
      expect(events, isEmpty);
    });
  });
}
