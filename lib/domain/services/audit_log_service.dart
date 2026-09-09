// lib/domain/services/audit_log_service.dart
import 'package:uuid/uuid.dart';
import 'package:serenutos/domain/models/audit_log.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';

class AuditLogService {
  final DbGateway _gateway;
  final AuthService _authService;

  AuditLogService({
    DbGateway? gateway,
    DatabaseManager? dbManager,
    required AuthService authService,
  })  : _gateway = gateway ?? DbGatewayImpl(dbManager ?? DatabaseManager()),
        _authService = authService;

  /// Log an audit event securely to the database
  Future<void> log({
    required String action,
    required String details,
  }) async {
    try {
      final user = await _authService.getCurrentUser();
      final userId = user?.id ?? 'system';
      final userName = user?.name ?? 'System';

      final record = AuditLog(
        id: const Uuid().v4(),
        userId: userId,
        userName: userName,
        action: action,
        details: details,
        createdAt: DateTime.now(),
      );

      await _gateway.insert('audit_logs', record.toMap());
    } catch (_) {
      // Non-fatal fallback: do not crash active transaction if logging fails
    }
  }

  /// Get list of recent logs
  Future<List<AuditLog>> getRecentLogs({int limit = 100}) async {
    try {
      final rows = await _gateway.query(
        'audit_logs',
        orderBy: 'created_at DESC',
        limit: limit,
      );
      return rows.map((row) => AuditLog.fromMap(row)).toList();
    } catch (_) {
      return [];
    }
  }
}

