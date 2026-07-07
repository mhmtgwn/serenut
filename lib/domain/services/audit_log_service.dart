// lib/domain/services/audit_log_service.dart
import 'package:uuid/uuid.dart';
import 'package:serenutos/domain/models/audit_log.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';

class AuditLogService {
  final DatabaseManager _dbManager;
  final AuthService _authService;

  AuditLogService({
    required DatabaseManager dbManager,
    required AuthService authService,
  })  : _dbManager = dbManager,
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
      
      final db = await _dbManager.getDatabase();
      final record = AuditLog(
        id: const Uuid().v4(),
        userId: userId,
        userName: userName,
        action: action,
        details: details,
        createdAt: DateTime.now(),
      );

      await db.insert('audit_logs', record.toMap());
    } catch (_) {
      // Non-fatal fallback: do not crash active transaction if logging fails
    }
  }

  /// Get list of recent logs
  Future<List<AuditLog>> getRecentLogs({int limit = 100}) async {
    try {
      final db = await _dbManager.getDatabase();
      final rows = await db.query(
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
