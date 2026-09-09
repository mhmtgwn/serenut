// test/unit/admin_error_logs_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TelemetryService telemetry;

  setUp(() async {
    telemetry = TelemetryService();
    await telemetry.clearLogs();
  });

  tearDown(() async {
    await telemetry.clearLogs();
  });

  group('Admin Error Logs & Telemetry Pipeline Tests', () {
    test('logError records exception, context, stack trace, and exposes getters', () async {
      try {
        throw const FormatException('Geçersiz sipariş verisi');
      } catch (e, st) {
        await telemetry.logError(
          e,
          st,
          context: 'OrderValidationService',
          level: LogLevel.error,
        );
      }

      final events = await telemetry.getEvents();
      expect(events, isNotEmpty);

      final errorEvent = events.first;
      expect(errorEvent.event, equals('error:OrderValidationService'));
      expect(errorEvent.level, equals(LogLevel.error));
      expect(errorEvent.errorContext, equals('OrderValidationService'));
      expect(errorEvent.errorType, equals('FormatException'));
      expect(errorEvent.errorMessage, contains('Geçersiz sipariş verisi'));
      expect(errorEvent.stackTrace, isNotNull);
      expect(errorEvent.stackTrace!.isNotEmpty, isTrue);
    });

    test('eventStream emits telemetry events in real time', () async {
      final emittedEvents = <TelemetryEvent>[];
      final sub = telemetry.eventStream.listen((ev) {
        emittedEvents.add(ev);
      });

      await telemetry.logStructured(
        event: 'test_realtime_event',
        level: LogLevel.warning,
        metadata: {'test': true},
      );

      await Future.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(emittedEvents, hasLength(1));
      expect(emittedEvents.first.event, equals('test_realtime_event'));
      expect(emittedEvents.first.level, equals(LogLevel.warning));
    });

    test('getEvents returns events ordered newest-first', () async {
      await telemetry.logStructured(
        event: 'event_old',
        level: LogLevel.info,
      );

      // Brief delay to ensure different timestamps
      await Future.delayed(const Duration(milliseconds: 10));

      await telemetry.logStructured(
        event: 'event_new',
        level: LogLevel.error,
      );

      final events = await telemetry.getEvents();
      expect(events.length, greaterThanOrEqualTo(2));
      expect(events.first.event, equals('event_new'));
      expect(events[1].event, equals('event_old'));
    });

    test('getEventsByLevel filters by minimum severity', () async {
      await telemetry.logStructured(
        event: 'info_event',
        level: LogLevel.info,
      );
      await telemetry.logStructured(
        event: 'warning_event',
        level: LogLevel.warning,
      );
      await telemetry.logStructured(
        event: 'error_event',
        level: LogLevel.error,
      );

      final errorsOnly = await telemetry.getEventsByLevel(LogLevel.error);
      expect(errorsOnly.every((e) => e.level.index >= LogLevel.error.index), isTrue);
      expect(errorsOnly.any((e) => e.event == 'error_event'), isTrue);
      expect(errorsOnly.any((e) => e.event == 'info_event'), isFalse);
    });
  });
}
