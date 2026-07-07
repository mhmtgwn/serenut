// lib/domain/realtime/event_dispatcher.dart
// Decodes and routes events to correct stream listeners

import 'dart:async';
import 'package:serenutos/domain/realtime/realtime_event.dart';

class EventDispatcher {
  final _eventController = StreamController<RealtimeEvent>.broadcast();

  Stream<RealtimeEvent> get allEvents => _eventController.stream;

  void dispatch(RealtimeEvent event) {
    _eventController.add(event);
  }

  Stream<RealtimeEvent> onEvent(String eventType) {
    return _eventController.stream.where((e) => e.type == eventType);
  }

  Stream<RealtimeEvent> onTopic(String topicCategory) {
    return _eventController.stream.where((e) {
      final type = e.type.toLowerCase();
      if (topicCategory == 'orders' && (type.contains('order') || type.contains('sale'))) return true;
      if (topicCategory == 'inventory' && (type.contains('inventory') || type.contains('price'))) return true;
      if (topicCategory == 'payments' && type.contains('payment')) return true;
      if (topicCategory == 'customers' && type.contains('customer')) return true;
      if (topicCategory == 'notifications' && type.contains('notification')) return true;
      if (topicCategory == 'license' && type.contains('license')) return true;
      if (topicCategory == 'backup' && type.contains('backup')) return true;
      if (topicCategory == 'auth' && (type.contains('user') || type.contains('auth') || type.contains('log'))) return true;
      if (topicCategory == 'settings' && type.contains('setting')) return true;
      if (topicCategory == 'reports' && type.contains('report')) return true;
      return false;
    });
  }

  void dispose() {
    _eventController.close();
  }
}
