// lib/domain/models/sms_log_entry.dart
// Serenut OS — SMS Log Entry (Domain Model)
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
        id: (map['id'] ?? '').toString(),
        phone: (map['phone'] ?? '').toString(),
        eventType: (map['event_type'] ?? 'unknown').toString(),
        message: (map['message'] ?? '').toString(),
        status: SmsLogStatus.fromValue((map['status'] ?? 'pending').toString()),
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        sentAt: map['sent_at'] != null
            ? DateTime.tryParse(map['sent_at'].toString())
            : null,
        errorMessage: map['error_message']?.toString(),
        retryCount: (map['retry_count'] is num)
            ? (map['retry_count'] as num).toInt()
            : (int.tryParse((map['retry_count'] ?? '0').toString()) ?? 0),
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
