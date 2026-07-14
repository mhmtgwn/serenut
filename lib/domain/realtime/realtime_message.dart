// lib/domain/realtime/realtime_message.dart
// Class representing raw socket frame wrappers

import 'dart:convert';

class RealtimeMessage {
  final String? action;
  final String? topic;
  final String? correlationId;
  final String? status;
  final String? message;
  final String? event;
  final Map<String, dynamic>? data;

  const RealtimeMessage({
    this.action,
    this.topic,
    this.correlationId,
    this.status,
    this.message,
    this.event,
    this.data,
  });

  Map<String, dynamic> toMap() => {
        if (action != null) 'action': action,
        if (topic != null) 'topic': topic,
        if (correlationId != null) 'correlationId': correlationId,
        if (status != null) 'status': status,
        if (message != null) 'message': message,
        if (event != null) 'event': event,
        if (data != null) 'data': data,
      };

  factory RealtimeMessage.fromMap(Map<String, dynamic> map) => RealtimeMessage(
        action: map['action'] as String?,
        topic: map['topic'] as String?,
        correlationId: map['correlationId'] as String?,
        status: map['status'] as String?,
        message: map['message'] as String?,
        event: map['event'] as String?,
        data: map['data'] != null
            ? Map<String, dynamic>.from(map['data'] as Map)
            : null,
      );

  String toJson() => jsonEncode(toMap());

  factory RealtimeMessage.fromJson(String source) =>
      RealtimeMessage.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
