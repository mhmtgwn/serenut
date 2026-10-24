import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sentry & Telemetry Hardening Tests', () {
    late TelemetryService telemetry;

    setUp(() async {
      telemetry = TelemetryService();
      await telemetry.clearLogs();
    });

    tearDown(() async {
      await telemetry.clearLogs();
    });

    test('TelemetryService.logError filters operational session/network noise gracefully', () async {
      // 1. Log a 401 Session expired error
      await telemetry.logError(
        const ApiException('Session expired', statusCode: 401),
        StackTrace.current,
        context: 'SyncNotifier.triggerSync',
      );

      // 2. Log a network socket offline error
      await telemetry.logError(
        const SocketException('Failed host lookup: api.serenut.com'),
        StackTrace.current,
        context: 'SyncNotifier.triggerSync',
      );

      // 3. Log a genuine application error
      await telemetry.logError(
        StateError('Unexpected fatal state'),
        StackTrace.current,
        context: 'OrderPlacementService',
      );

      final events = await telemetry.getEvents();
      expect(events.length, equals(3));
      expect(events[0].event, contains('SyncNotifier.triggerSync'));
      expect(events[1].event, contains('SyncNotifier.triggerSync'));
      expect(events[2].event, contains('OrderPlacementService'));
    });

    test('TelemetryService.logError attaches correlationId and sets correct error level', () async {
      const testCorrelation = 'ERR-TEST1234';
      await telemetry.logError(
        Exception('Crash simulation'),
        StackTrace.current,
        context: 'FlutterError',
        correlationId: testCorrelation,
        level: LogLevel.critical,
      );

      final events = await telemetry.getEvents();
      expect(events.length, equals(1));
      expect(events.first.correlationId, equals(testCorrelation));
      expect(events.first.level, equals(LogLevel.critical));
    });
  });
}
