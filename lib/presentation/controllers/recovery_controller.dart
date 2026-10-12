// lib/presentation/controllers/recovery_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/providers/recovery_provider.dart';
import 'package:serenutos/providers/audit_provider.dart';

final recoveryControllerProvider = Provider<RecoveryController>((ref) {
  return RecoveryController(ref);
});

class RecoveryController {
  final Ref _ref;

  RecoveryController(this._ref);

  Future<List<Map<String, dynamic>>> getDeletedItems(String type) async {
    final repo = _ref.read(recoveryRepositoryProvider);
    return repo.getDeletedItems(type);
  }

  Future<void> restoreItem({
    required String type,
    required String id,
    required String name,
    String? approvedByUserId,
    String? approvedByUserName,
  }) async {
    final repo = _ref.read(recoveryRepositoryProvider);
    await repo.restore(type, id);

    try {
      final auditService = await _ref.read(auditServiceProvider.future);
      await auditService.logSystemAction(
        'entity_restored',
        'Tur: $type, ID: $id, Name: $name',
        approvedByUserId: approvedByUserId,
        approvedByUserName: approvedByUserName,
      );
    } catch (_) {
      // Ignored: audit trail failure shouldn't block operation
    }
  }

  Future<void> purgeItem({
    required String type,
    required String id,
    required String name,
    String? approvedByUserId,
    String? approvedByUserName,
  }) async {
    final repo = _ref.read(recoveryRepositoryProvider);
    await repo.purge(type, id);

    try {
      final auditService = await _ref.read(auditServiceProvider.future);
      await auditService.logSystemAction(
        'entity_purged',
        'Tur: $type, ID: $id, Name: $name',
        approvedByUserId: approvedByUserId,
        approvedByUserName: approvedByUserName,
      );
    } catch (_) {
      // Ignored: audit trail failure shouldn't block operation
    }
  }
}
