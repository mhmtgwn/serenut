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
