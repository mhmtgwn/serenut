// lib/domain/realtime/event_parser.dart
// Parse helper for WS communication

import 'dart:convert';
import 'package:serenutos/domain/realtime/realtime_event.dart';
import 'package:serenutos/domain/realtime/realtime_message.dart';

class EventParser {
  static RealtimeMessage? parseRawMessage(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        return RealtimeMessage.fromMap(decoded);
      }
    } catch (_) {}
    return null;
  }

  static RealtimeEvent? parseEvent(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        // Check if this map aligns with the RealtimeEvent format
        if (decoded.containsKey('type') &&
            decoded.containsKey('tenantId') &&
            decoded.containsKey('payload')) {
          return RealtimeEvent.fromMap(decoded);
        }
      }
    } catch (_) {}
    return null;
  }
}
