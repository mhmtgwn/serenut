// lib/infrastructure/services/update_v2/journal_event_listener.dart
// Serenut Platform — Decoupled event listener mapping event bus to journal writer

import 'dart:async';
import 'package:serenutos/domain/models/update_v2/update_telemetry_event.dart';
import 'package:serenutos/infrastructure/services/update_v2/update_event_bus.dart';
import 'package:serenutos/infrastructure/services/update_v2/journal_writer.dart';

class JournalEventListener {
  final UpdateEventBus _eventBus;
  final JournalWriter _journalWriter;
  StreamSubscription<UpdateTelemetryEvent>? _subscription;

  JournalEventListener({
    required UpdateEventBus eventBus,
    required JournalWriter journalWriter,
  })  : _eventBus = eventBus,
        _journalWriter = journalWriter;

  /// Starts listening to FSM events from the event bus and logging them to disk.
  void startListening() {
    _subscription = _eventBus.stream.listen((event) async {
      final stateStr = _mapEventTypeToState(event.eventType);
      await _journalWriter.append(
        correlationId: event.correlationId,
        eventType: event.eventType.toSchemaString(),
        state: stateStr,
        payload: {
          'fromVersion': event.fromVersion,
          'toVersion': event.toVersion,
          'errorCode': event.errorCode,
          'errorMessage': event.errorMessage,
        },
      );
    });
  }

  void stopListening() {
    _subscription?.cancel();
  }

  String _mapEventTypeToState(UpdateEventType type) {
    switch (type) {
      case UpdateEventType.checkStarted:
        return 'CHECKING';
      case UpdateEventType.manifestVerified:
        return 'VERIFYING';
      case UpdateEventType.precheckPassed:
        return 'PRECHECK';
      case UpdateEventType.downloadStarted:
        return 'DOWNLOADING';
      case UpdateEventType.drainStarted:
        return 'DRAINING';
      case UpdateEventType.bootstrapperLaunched:
        return 'HANDSHAKE';
      case UpdateEventType.postInstallStarted:
        return 'POST_INSTALL';
      case UpdateEventType.healthCheckPassed:
        return 'HEALTH_CHECK';
      case UpdateEventType.installSuccess:
        return 'COMPLETED';
      case UpdateEventType.installFailed:
        return 'FAILED';
      case UpdateEventType.rollbackExecuted:
        return 'ROLLBACK';
      default:
        return 'UNKNOWN';
    }
  }
}
