// lib/domain/repositories/audit_repository.dart
import 'package:serenutos/domain/models/audit_event.dart';

abstract class IAuditRepository {
  Future<void> logEvent(AuditEvent event);
  Future<List<AuditEvent>> getEvents({
    String? eventType,
    String? entityType,
    String? userId,
    DateTime? fromDate,
    DateTime? toDate,
    int? limit,
    int? offset,
  });
  Future<List<AuditEvent>> search(String query);
}
