// lib/providers/service_providers.dart
// Serenut POS — Central Service Locator Providers

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/domain/services/i_backup_service.dart';
import 'package:serenutos/domain/services/i_hash_service.dart';
import 'package:serenutos/domain/services/i_printer_service.dart';
import 'package:serenutos/domain/services/i_scanner_service.dart';
import 'package:serenutos/infrastructure/services/backup_service.dart';
import 'package:serenutos/infrastructure/services/password_hash_service.dart';
import 'package:serenutos/infrastructure/services/printer_service.dart';
import 'package:serenutos/infrastructure/services/unified_scanner_service.dart';
import 'package:serenutos/infrastructure/services/persistent_print_queue.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/services/device_manager.dart';
import 'package:serenutos/infrastructure/services/device_fingerprint_service.dart';
import 'package:serenutos/infrastructure/services/bootstrap_sync_service.dart';
import 'package:serenutos/infrastructure/services/integrity_check_service.dart';
import 'package:serenutos/infrastructure/services/central_background_scheduler.dart';
import 'package:serenutos/infrastructure/services/rollback_manager.dart';
import 'package:serenutos/infrastructure/services/remote_config_service.dart';
import 'package:serenutos/infrastructure/services/telemetry_upload_service.dart';
import 'package:serenutos/infrastructure/services/log_collection_service.dart';
import 'package:serenutos/infrastructure/services/client_health_service.dart';
import 'package:serenutos/infrastructure/services/crash_recovery_manager.dart';
import 'package:serenutos/infrastructure/services/release_channel_service.dart';
import 'package:serenutos/domain/services/trial_manager.dart';
import 'package:serenutos/domain/services/license_manager.dart';
import 'package:serenutos/domain/services/access_manager.dart';

import 'package:serenutos/domain/services/security_gate.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/domain/services/audit_log_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';

/// Persistent print queue — singleton shared across providers.
final persistentPrintQueueProvider = Provider<PersistentPrintQueue>((ref) {
  return PersistentPrintQueue();
});

/// Provides IPrinterService instance with persistent queue injected.
final printerServiceProvider = Provider<IPrinterService>((ref) {
  final queue = ref.watch(persistentPrintQueueProvider);
  return PrinterService(null, queue);
});

/// Provides IBackupService instance.
final backupServiceProvider = Provider<IBackupService>((ref) {
  return BackupService();
});

/// Provides IHashService instance.
final hashServiceProvider = Provider<IHashService>((ref) {
  return PasswordHashServiceImpl();
});

/// Provides IScannerService instance.
final scannerServiceProvider = Provider<IScannerService>((ref) {
  return UnifiedScannerService();
});

/// Provides LicenseService instance.
final licenseServiceProvider = Provider<LicenseService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return LicenseService(prefs);
});

/// Provides DeviceManager instance.
final deviceManagerProvider = Provider<DeviceManager>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return DeviceManager(prefs);
});

/// Provides DeviceFingerprintService instance.
final deviceFingerprintServiceProvider =
    Provider<DeviceFingerprintService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final deviceManager = ref.watch(deviceManagerProvider);
  return DeviceFingerprintService(prefs, deviceManager);
});

/// Provides TrialManager instance.
final trialManagerProvider = Provider<TrialManager>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return TrialManager(prefs);
});

/// Provides LicenseManager instance.
final licenseManagerProvider = Provider<LicenseManager>((ref) {
  final licenseService = ref.watch(licenseServiceProvider);
  return LicenseManager(licenseService);
});

/// Provides AccessManager instance.
final accessManagerProvider = Provider<AccessManager>((ref) {
  final trialManager = ref.watch(trialManagerProvider);
  final licenseManager = ref.watch(licenseManagerProvider);
  final deviceManager = ref.watch(deviceManagerProvider);
  return AccessManager(
    trialManager: trialManager,
    licenseManager: licenseManager,
    deviceManager: deviceManager,
  );
});

/// Provides ApiClient instance.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(() => client.dispose());
  return client;
});

/// Provides BootstrapSyncService instance.
final bootstrapSyncServiceProvider = Provider<BootstrapSyncService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final apiClient = ref.watch(apiClientProvider);
  return BootstrapSyncService(prefs, apiClient);
});

/// Provides IntegrityCheckService instance.
final integrityCheckServiceProvider = Provider<IntegrityCheckService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return IntegrityCheckService(prefs);
});

/// Provides CentralBackgroundScheduler instance.
final centralBackgroundSchedulerProvider =
    Provider<CentralBackgroundScheduler>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return CentralBackgroundScheduler(prefs);
});

/// Provides RollbackManager instance.
final rollbackManagerProvider = Provider<RollbackManager>((ref) {
  return RollbackManager();
});

/// Provides RemoteConfigService instance.
final remoteConfigServiceProvider = Provider<RemoteConfigService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final apiClient = ref.watch(apiClientProvider);
  return RemoteConfigService(prefs, apiClient);
});

/// Provides TelemetryUploadService instance (SQLite buffering + API batch upload).
final telemetryUploadServiceProvider = Provider<TelemetryUploadService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return TelemetryUploadService(apiClient);
});

/// Provides LogCollectionService instance.
final logCollectionServiceProvider = Provider<LogCollectionService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return LogCollectionService(apiClient);
});

/// Provides ClientHealthService instance.
final clientHealthServiceProvider = Provider<ClientHealthService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final licenseService = ref.watch(licenseServiceProvider);
  return ClientHealthService(apiClient, licenseService);
});

/// Provides CrashRecoveryManager instance.
final crashRecoveryManagerProvider = Provider<CrashRecoveryManager>((ref) {
  return CrashRecoveryManager();
});

/// Provides ReleaseChannelService instance.
final releaseChannelServiceProvider = Provider<ReleaseChannelService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ReleaseChannelService(prefs);
});

/// Provides AuditLogService instance.
final auditLogServiceProvider = Provider<AuditLogService>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuditLogService(
    dbManager: DatabaseManager(),
    authService: authService,
  );
});

/// Provides SecurityGate instance.
final securityGateProvider = Provider<SecurityGate>((ref) {
  final licenseService = ref.watch(licenseServiceProvider);
  final trialManager = ref.watch(trialManagerProvider);
  return SecurityGate(licenseService, trialManager);
});
