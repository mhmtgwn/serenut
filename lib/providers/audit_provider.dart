// lib/providers/audit_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/audit_repository.dart';
import 'package:serenutos/domain/services/audit_service.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_audit_repository.dart';
import 'package:serenutos/providers/database_provider.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';

final auditRepositoryProvider = Provider<IAuditRepository>((ref) {
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteAuditRepository(gateway);
});

final auditServiceProvider = FutureProvider<AuditService>((ref) async {
  final repository = ref.watch(auditRepositoryProvider);
  final authService = ref.watch(authServiceProvider);
  final licenseService = ref.watch(licenseServiceProvider);

  final user = await authService.getCurrentUser();
  final deviceId = licenseService.getDeviceUuid();
  final telemetryUpload = ref.watch(telemetryUploadServiceProvider);

  return AuditService(
    repository: repository,
    currentUserId: user?.id,
    currentUserName: user?.name,
    deviceId: deviceId,
    remoteBuffer: (event) => telemetryUpload.recordMetric(
      'audit_event',
      1,
      metadata: event.toMap(),
    ),
  );
});
