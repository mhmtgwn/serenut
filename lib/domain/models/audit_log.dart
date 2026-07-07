// lib/domain/models/audit_log.dart
class AuditLog {
  final String id;
  final String userId;
  final String userName;
  final String action; // price_changed, product_deleted, stock_adjusted, sale_cancelled, user_created
  final String details; // JSON description of state change
  final DateTime createdAt;

  AuditLog({
    required this.id,
    required this.userId,
    required this.userName,
    required this.action,
    required this.details,
    required this.createdAt,
  });

  factory AuditLog.fromMap(Map<String, dynamic> map) {
    return AuditLog(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      userName: map['user_name'] as String,
      action: map['action'] as String,
      details: map['details'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'user_name': userName,
        'action': action,
        'details': details,
        'created_at': createdAt.toIso8601String(),
      };
}
