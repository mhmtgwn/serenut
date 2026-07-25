// lib/infrastructure/services/update_v2/update_event_bus.dart
// Serenut Platform — Event-Driven Update Event Bus dispatcher

import 'dart:async';
import 'package:serenutos/domain/models/update_v2/update_telemetry_event.dart';

class UpdateEventBus {
  final StreamController<UpdateTelemetryEvent> _controller =
      StreamController<UpdateTelemetryEvent>.broadcast();

  /// Stream of all update events triggered within the state machine.
  Stream<UpdateTelemetryEvent> get stream => _controller.stream;

  /// Publishes a telemetry event to the bus.
  void publish(UpdateTelemetryEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void dispose() {
    _controller.close();
  }
}
