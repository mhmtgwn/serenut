import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/audit_event.dart';
import 'package:serenutos/providers/audit_provider.dart';

final auditControllerProvider = Provider<AuditController>((ref) {
  return AuditController(ref);
});

class AuditController {
  final Ref _ref;

  AuditController(this._ref);

  Future<bool> verifyIntegrity() async {
    final repo = _ref.read(auditRepositoryProvider);
    return await repo.verifyIntegrity();
  }

  Future<List<AuditEvent>> getEvents({
    String? eventType,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final repo = _ref.read(auditRepositoryProvider);
    return await repo.getEvents(
      eventType: eventType,
      fromDate: fromDate,
      toDate: toDate,
    );
  }

  Future<List<AuditEvent>> search(String query) async {
    final repo = _ref.read(auditRepositoryProvider);
    return await repo.search(query);
  }

  Future<void> logSystemAction(
    String action,
    String details, {
    String? approvedByUserId,
    String? approvedByUserName,
  }) async {
    final service = await _ref.read(auditServiceProvider.future);
    await service.logSystemAction(
      action,
      details,
      approvedByUserId: approvedByUserId,
      approvedByUserName: approvedByUserName,
    );
  }

  Future<void> logEvent({
    required String eventType,
    required String entityType,
    required String entityId,
    String? oldValue,
    String? newValue,
    String? notes,
  }) async {
    final service = await _ref.read(auditServiceProvider.future);
    await service.logEvent(
      eventType: eventType,
      entityType: entityType,
      entityId: entityId,
      oldValue: oldValue,
      newValue: newValue,
      notes: notes,
    );
  }
}
