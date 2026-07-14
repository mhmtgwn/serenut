// lib/domain/models/sms_log_entry.dart
// Serenut POS — SMS Log Entry (Domain Model)
// Maps to sms_logs SQLite table
// Created: 01 Jul 2026

class SmsLogEntry {
  final String id;
  final String phone;
  final String
      eventType; // 'sale_created' | 'debt_created' | 'collection_recorded' | 'order_created'
  final String message;
  final SmsLogStatus status;
  final DateTime createdAt;
  final DateTime? sentAt;
  final String? errorMessage;
  final int retryCount;

  const SmsLogEntry({
    required this.id,
    required this.phone,
    required this.eventType,
    required this.message,
    this.status = SmsLogStatus.pending,
    required this.createdAt,
    this.sentAt,
    this.errorMessage,
    this.retryCount = 0,
  });

  SmsLogEntry copyWith({
    String? id,
    String? phone,
    String? eventType,
    String? message,
    SmsLogStatus? status,
    DateTime? createdAt,
    DateTime? sentAt,
    String? errorMessage,
    int? retryCount,
  }) {
    return SmsLogEntry(
      id: id ?? this.id,
      phone: phone ?? this.phone,
      eventType: eventType ?? this.eventType,
      message: message ?? this.message,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      sentAt: sentAt ?? this.sentAt,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'phone': phone,
        'event_type': eventType,
        'message': message,
        'status': status.value,
        'created_at': createdAt.toIso8601String(),
        'sent_at': sentAt?.toIso8601String(),
        'error_message': errorMessage,
        'retry_count': retryCount,
      };

  factory SmsLogEntry.fromMap(Map<String, dynamic> map) => SmsLogEntry(
        id: map['id'] as String,
        phone: map['phone'] as String,
        eventType: map['event_type'] as String,
        message: map['message'] as String,
        status: SmsLogStatus.fromValue(map['status'] as String? ?? 'pending'),
        createdAt: DateTime.parse(map['created_at'] as String),
        sentAt: map['sent_at'] != null
            ? DateTime.parse(map['sent_at'] as String)
            : null,
        errorMessage: map['error_message'] as String?,
        retryCount: (map['retry_count'] as int?) ?? 0,
      );

  @override
  String toString() => 'SmsLogEntry($id, $eventType, $status)';
}

enum SmsLogStatus {
  pending('pending'),
  sending('sending'),
  sent('sent'),
  failed('failed'),
  cancelled('cancelled'),
  interrupted('interrupted'),
  unknown('unknown');

  final String value;
  const SmsLogStatus(this.value);

  static SmsLogStatus fromValue(String value) {
    return SmsLogStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => SmsLogStatus.pending,
    );
  }
}
