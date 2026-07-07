// lib/domain/realtime/realtime_event.dart
// Production-grade Event Model representing real-time updates

import 'dart:convert';

class RealtimeEvent {
  final String id;
  final String type;
  final String tenantId;
  final DateTime timestamp;
  final Map<String, dynamic> payload;
  final int version;
  final String correlationId;

  const RealtimeEvent({
    required this.id,
    required this.type,
    required this.tenantId,
    required this.timestamp,
    required this.payload,
    required this.version,
    required this.correlationId,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'tenantId': tenantId,
        'timestamp': timestamp.toIso8601String(),
        'payload': payload,
        'version': version,
        'correlationId': correlationId,
      };

  factory RealtimeEvent.fromMap(Map<String, dynamic> map) => RealtimeEvent(
        id: map['id'] as String? ?? '',
        type: map['type'] as String? ?? '',
        tenantId: map['tenantId'] as String? ?? '',
        timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
        payload: Map<String, dynamic>.from(map['payload'] as Map? ?? {}),
        version: map['version'] as int? ?? 1,
        correlationId: map['correlationId'] as String? ?? '',
      );

  String toJson() => jsonEncode(toMap());

  factory RealtimeEvent.fromJson(String source) =>
      RealtimeEvent.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'RealtimeEvent(id: $id, type: $type, tenantId: $tenantId, correlationId: $correlationId)';
  }
}
