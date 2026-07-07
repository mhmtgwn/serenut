// lib/domain/models/audit_event.dart
class AuditEvent {
  final String id;
  final String eventType; // e.g., 'product_created', 'price_changed', etc.
  final String entityType; // e.g., 'product', 'customer', 'sale', etc.
  final String? entityId;
  final String? userId;
  final String? userName;
  final String? oldValue;
  final String? newValue;
  final DateTime timestamp;
  final String? deviceId;
  final String? notes;

  AuditEvent({
    required this.id,
    required this.eventType,
    required this.entityType,
    this.entityId,
    this.userId,
    this.userName,
    this.oldValue,
    this.newValue,
    required this.timestamp,
    this.deviceId,
    this.notes,
  });

  factory AuditEvent.fromMap(Map<String, dynamic> map) {
    return AuditEvent(
      id: map['id'] as String,
      eventType: map['event_type'] as String,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String?,
      userId: map['user_id'] as String?,
      userName: map['user_name'] as String?,
      oldValue: map['old_value'] as String?,
      newValue: map['new_value'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      deviceId: map['device_id'] as String?,
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'event_type': eventType,
        'entity_type': entityType,
        'entity_id': entityId,
        'user_id': userId,
        'user_name': userName,
        'old_value': oldValue,
        'new_value': newValue,
        'timestamp': timestamp.toIso8601String(),
        'device_id': deviceId,
        'notes': notes,
      };
}
