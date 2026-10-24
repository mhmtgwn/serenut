// lib/infrastructure/bootstrap/app_bootstrap.dart
// Serenut OS — Uygulama Başlatma ve Ön Yükleme Pipeline'ı (AppBootstrap)
//
// main.dart dosyasındaki karmaşık ön yükleme, teşhis ve arka plan hazırlık
// mantığını modüler ve test edilebilir bir pipeline altında toplar.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/domain/services/device_manager.dart';
import 'package:serenutos/domain/services/error_boundary.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/domain/hardware/hardware_device.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/migration/cutoff_maintenance_lock.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/network/trusted_ca_http_overrides.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/infrastructure/services/dataset_loader_service.dart';
import 'package:serenutos/infrastructure/services/device_fingerprint_service.dart';
import 'package:serenutos/infrastructure/services/password_hash_service.dart';
import 'package:serenutos/infrastructure/services/integrity_check_service.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/presentation/observers/telemetry_provider_observer.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/hardware_devices_provider.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/sms_provider.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/core_next/infrastructure/database/dual_database_routing_coordinator.dart';

/// Pre-app başlatma sonucu
class BootstrapResult {
  final SharedPreferences prefs;
  final AuthService authService;
  final ApiClient apiClient;
  final DatasetLoaderService datasetLoader;
  final LicenseService licenseService;
  final List<Override> overrides;
  final List<ProviderObserver> observers;
  final PilotGateResult? pilotGateResult;

  const BootstrapResult({
    required this.prefs,
    required this.authService,
    required this.apiClient,
    required this.datasetLoader,
    required this.licenseService,
    required this.overrides,
    required this.observers,
    this.pilotGateResult,
  });
}

/// Teşhis ve başlatma sonuç raporu
class StartupDiagnosticsResult {
  final bool isSuccess;
  final String? errorMessage;
  final String? errorReference;
  final String? technicalDetails;

  const StartupDiagnosticsResult({
    required this.isSuccess,
    this.errorMessage,
    this.errorReference,
    this.technicalDetails,
  });
}

class AppBootstrap {
  AppBootstrap._();

  /// Uygulama ayağa kalkmadan önceki temel altyapıyı hazırlar.
  static Future<BootstrapResult> initPreApp({
    PilotCutoverGate? pilotGate,
    String? requestedTenantId,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Güvenilen CA Sertifikası
    if (!kIsWeb) {
      try {
        final trustedRoot =
            await rootBundle.load('assets/certificates/isrgrootx1.pem');
        HttpOverrides.global = TrustedCaHttpOverrides(
          trustedRoot.buffer.asUint8List(
            trustedRoot.offsetInBytes,
            trustedRoot.lengthInBytes,
          ),
        );
      } catch (error) {
        debugPrint('Trusted CA initialization failed: $error');
      }
    }

    // 2. Global Hata Yakalayıcı ve Yerelleştirme
    ErrorBoundary.install();
    await initializeDateFormatting('tr_TR', null);

    // 3. Masaüstü SQLite FFI
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    // 4. Kalıcı Depolama & Çekirdek Servisler
    final prefs = await SharedPreferences.getInstance();

    // 4.1. Merkezi Kesim Bakım Kilidi & Kalıcı Durum Yükleme
    try {
      final cutoffLock = CutoffMaintenanceLock(
        storage: SharedPreferencesMaintenanceStorage.withInstance(prefs),
      );
      await cutoffLock.initializeFromStorage();
      DatabaseManager.cutoffMaintenanceLock = cutoffLock;
    } catch (e) {
      debugPrint('[Bootstrap] Cutoff lock initialization fallback: $e');
      DatabaseManager.cutoffMaintenanceLock = CutoffMaintenanceLock(
        storage: SharedPreferencesMaintenanceStorage.withInstance(prefs),
      );
    }

    final dbManager = DatabaseManager.instance;
    final gateway = DbGatewayImpl(dbManager);
    final userRepository = SqliteUserRepository(gateway);
    final hashService = PasswordHashServiceImpl();
    final apiClient = ApiClient();

    // 5. Lisans & Cihaz Kimliği
    final licenseService = LicenseService(prefs);
    await licenseService.initialize();
    if (licenseService.getLicenseInfo() != null) {
      licenseService.startHeartbeat(apiClient);
    }

    final deviceManager = DeviceManager(prefs);
    final fingerprintService = DeviceFingerprintService(prefs, deviceManager);
    final settingsRepository = SqliteSettingsRepository(gateway);

    // 6. Sentry Kapsamı
    try {
      final deviceId = deviceManager.getDeviceId();
      final license = licenseService.getLicenseInfo();
      Sentry.configureScope((scope) {
        scope.setTag('device_id', deviceId);
        if (license != null) {
          scope.setTag('merchant_id', license.merchantId);
          scope.setTag('license_tier', license.tier.name);
          if (license.activationId != null) {
            scope.setTag('activation_id', license.activationId!);
          }
        }
      });
    } catch (_) {
      // Ignored: fallback or safe default applied
    }

    // 7. Kimlik Doğrulama Servisi
    final authService = AuthService(
      userRepository: userRepository,
      hashService: hashService,
      apiClient: apiClient,
      deviceManager: deviceManager,
      licenseService: licenseService,
      deviceFingerprintService: fingerprintService,
      cacheCompanyProfile: (company) async {
        final currentPrefs = await SharedPreferences.getInstance();
        if (currentPrefs.getBool('sync_v4_company_dirty') == true) {
          debugPrint(
              '[Auth] Local company changes are dirty; preserving local profile.');
          return;
        }
        final current = await settingsRepository.getSettings();
        final localIsCustomized = current.businessName.isNotEmpty &&
            current.businessName != 'Serenut OS';
        if (localIsCustomized) {
          debugPrint(
              '[Auth] Local business profile is customized ("${current.businessName}"); preserving against unversioned bootstrap.');
          return;
        }

        final rawName = company['name']?.toString().trim();
        final remoteName =
            (rawName != null && rawName.isNotEmpty) ? rawName : '';
        if (remoteName.isNotEmpty && remoteName != 'Serenut OS') {
          final phone = company['phone']?.toString().trim();
          final address = company['address']?.toString().trim();
          final taxNum = company['tax_number']?.toString().trim();
          final owner = company['owner_name']?.toString().trim();
          final email = company['email']?.toString().trim();
          final city = company['city']?.toString().trim();
          final district = company['district']?.toString().trim();
          await settingsRepository.updateSettings(current.copyWith(
            businessName: remoteName,
            businessPhone: (phone != null && phone.isNotEmpty)
                ? phone
                : current.businessPhone,
            businessAddress: (address != null && address.isNotEmpty)
                ? address
                : current.businessAddress,
            businessTaxId: (taxNum != null && taxNum.isNotEmpty)
                ? taxNum
                : current.businessTaxId,
            ownerName: (owner != null && owner.isNotEmpty)
                ? owner
                : current.ownerName,
            businessEmail: (email != null && email.isNotEmpty)
                ? email
                : current.businessEmail,
            businessCity: (city != null && city.isNotEmpty)
                ? city
                : current.businessCity,
            businessDistrict: (district != null && district.isNotEmpty)
                ? district
                : current.businessDistrict,
          ));
        }
      },
    );

    await authService.initialize();

    // 8. Oturum Bootstrap
    if (apiClient.jwtToken != null && apiClient.jwtToken!.isNotEmpty) {
      try {
        await authService.checkCurrentUserSessionOnline();
        await authService.refreshEntitlement();
      } catch (e) {
        debugPrint('Startup session bootstrap note: $e');
      }
    }

    // 9. Boş Kullanıcı / Onboarding Kontrolü
    try {
      final users = await authService.getUsers();
      if (users.isEmpty) {
        final db = await dbManager.getDatabase();
        await db.update('settings', {
          'admin_pin_code': null,
          'updated_at': DateTime.now().toIso8601String()
        });
      }
    } catch (e) {
      debugPrint('Failed to check or reset onboarding status: $e');
    }

    // 10. Demo Dataset Loader
    final datasetLoader = DatasetLoaderService(prefs);
    await datasetLoader.init();

    // 11. Core Next Pilot Cutover Kapısı (Fail-Closed Değerlendirme)
    PilotCutoverGate.defaultOverrideGenerator ??= ({
      required String requestedTenantId,
      required String legacyDbPath,
      required String targetDbPath,
      required bool enableSalesEngine,
      DatabaseFactory? dbFactory,
    }) async {
      final coordinator = const DualDatabaseRoutingCoordinator();
      final routing = await coordinator.resolveAndOpen(
        requestedTenantId: requestedTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: targetDbPath,
        migrationStateCompleted: true,
        dbFactory: dbFactory,
      );
      if (!routing.isSuccess || routing.targetDatabase == null) return null;
      return [
        ...DualDatabaseRoutingCoordinator.createRepositoryOverrides(
          coreDb: routing.targetDatabase!,
          enableSalesEngine: enableSalesEngine,
        ),
        coreNextSalesEngineEnabledProvider.overrideWith((ref) => enableSalesEngine),
      ];
    };

    final gate = pilotGate ?? const PilotCutoverGate();
    final effectiveTenantId =
        requestedTenantId ?? licenseService.getLicenseInfo()?.merchantId;
    final pilotResult = await gate.evaluate(
      prefs: prefs,
      requestedTenantId: effectiveTenantId,
    );

    if (pilotResult.isPilotActive) {
      debugPrint(
          '[AppBootstrap] 🚀 Core Next Pilot Yönlendirmesi AKTİF: ${pilotResult.reason}');
      try {
        await dbManager.close();
      } catch (e) {
        debugPrint('[AppBootstrap] Note on dbManager reset: $e');
      }
    } else {
      debugPrint(
          '[AppBootstrap] 🛡️ Core Next Pilot Kapalı (Legacy Aktif): ${pilotResult.reason}');
    }

    return BootstrapResult(
      prefs: prefs,
      authService: authService,
      apiClient: apiClient,
      datasetLoader: datasetLoader,
      licenseService: licenseService,
      pilotGateResult: pilotResult,
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        apiClientProvider.overrideWithValue(apiClient),
        sharedPreferencesProvider.overrideWithValue(prefs),
        datasetLoaderServiceProvider.overrideWithValue(datasetLoader),
        licenseServiceProvider.overrideWithValue(licenseService),
        ...pilotResult.overrides,
      ],
      observers: [
        TelemetryProviderObserver(),
      ],
    );
  }

  static String _generateErrorReference(String error) {
    final hash =
        (error.hashCode.abs() % 0xFFFFFF).toRadixString(16).toUpperCase();
    return 'ERR-${hash.padLeft(6, '0')}';
  }

  /// Uygulama açılışında veritabanı bütünlüğünü, donanımı ve yazıcı kuyruklarını denetler.
  static Future<StartupDiagnosticsResult> runStartupDiagnostics(
      dynamic ref) async {
    try {
      // 1. Veritabanı Bütünlüğü ve Onarım (Kritik Kontrol)
      final diag = ref.read(integrityCheckServiceProvider);
      final report = await diag.runDiagnostics().timeout(
            const Duration(seconds: 10),
            onTimeout: () => IntegrityReport(
              isDatabaseHealthy: false,
              isFileSystemHealthy: false,
              issues: const ['Veritabanı bütünlük kontrolü zaman aşımına uğradı (10s)'],
              logs: 'TIMEOUT',
            ),
          );
      if (!report.isAllPass) {
        final repaired = await diag.attemptDatabaseRepair();
        if (!repaired) {
          final rawIssues = report.issues.join(' | ');
          final refCode = _generateErrorReference(rawIssues);

          try {
            unawaited(TelemetryService().logError(
              Exception('Startup integrity failure: $rawIssues'),
              StackTrace.current,
              context: 'startup_integrity_diagnostics',
              correlationId: refCode,
            ));
            unawaited(Sentry.captureMessage(
              'Startup integrity failure ($refCode): $rawIssues',
              level: SentryLevel.fatal,
            ));
          } catch (_) {
            // Sentry/Telemetry reporting failure is non-blocking
          }

          return StartupDiagnosticsResult(
            isSuccess: false,
            errorMessage:
                'Veritabanı veya sistem bileşenleri hazırlanırken bir sorun oluştu.\n'
                'Hata detayları teknik ekibimize otomatik olarak iletildi.',
            errorReference: refCode,
            technicalDetails: rawIssues,
          );
        }
      }

      // 1.1 Core Next Geçiş Durumu Kontrolü ve Güvenli Koordinasyon
      try {
        final coordinator = ref.read(coreNextBootstrapCoordinatorProvider);
        final migrationState = await coordinator.getPersistentState();
        if (migrationState == CoreNextMigrationState.failedBlocked) {
          debugPrint('[AppBootstrap] ⚠️ Core Next migration kalıcı blokaj durumunda. Legacy akış korunuyor.');
        } else if (ref.read(coreNextMigrationRunnerProvider) != null &&
            migrationState != CoreNextMigrationState.completed) {
          debugPrint('[AppBootstrap] 🚀 Core Next migration runner aktif. Koordinasyon başlatılıyor...');
          final consentRequester = ref.read(coreNextConsentRequesterProvider);
          final result = await coordinator.coordinate(
            autonomousMode: true,
            consentRequester: consentRequester,
            onProgress: (progress) {
              ref.read(coreNextMigrationProgressProvider.notifier).state = progress;
            },
          );
          if (!result.isSuccess) {
            debugPrint('[AppBootstrap] ⚠️ Core Next koordinasyonu başarısız: ${result.errorMessage}. Legacy akış korunuyor.');
          }
        }
      } catch (e) {
        debugPrint('[AppBootstrap] Core Next coordinator check note: $e');
      }

      // 1.2 Bekleyen / Yarım Kalmış Rollback Kontrolü (Fail-Closed Güvenlik Kilidi)
      try {
        final prefs = ref.read(sharedPreferencesProvider);
        final rollbackState = prefs.getString('core_next_rollback_state');
        if (rollbackState == 'in_progress' || rollbackState == 'failed_blocked') {
          debugPrint('[AppBootstrap] ⚠️ Bekleyen/Yarım kalmış rollback tespit edildi ($rollbackState).');
          if (PilotCutoverGate.safeRollbackRunner != null) {
            final legacyDb = await DatabaseManager.instance.getDatabase();
            final targetDbPath = prefs.getString(CoreNextBootstrapCoordinator.prefKeyBackupPath) ?? 'core_next.db';
            final license = ref.read(licenseServiceProvider).getLicenseInfo();
            final tenantId = license?.merchantId ?? 'nutopia';

            final recoveryResult = await PilotCutoverGate.recoverPendingRollback(
              prefs: prefs,
              legacyDb: legacyDb,
              coreDb: targetDbPath,
              tenantId: tenantId,
            );
            if (!recoveryResult.isSuccess) {
              return StartupDiagnosticsResult(
                isSuccess: false,
                errorMessage: 'Kritik Durum: Önceki oturumda veritabanı geri dönüşü yarım kalmış ve otomatik kurtarılamamıştır.\n'
                    'Veri kaybını önlemek için sistem açılışı durduruldu.\nHata: ${recoveryResult.errorMessage}',
                errorReference: 'ERR-ROLLBACK-RECOVERY-FAILED',
                technicalDetails: recoveryResult.errorMessage,
              );
            }
          } else {
            return StartupDiagnosticsResult(
              isSuccess: false,
              errorMessage: 'Kritik Durum: Önceki oturumda veritabanı geri dönüşü yarım kaldı ($rollbackState).\n'
                  'Core Next verilerinin kaybolmasını önlemek için sistem güvenli olarak kilitlendi.\n'
                  'Lütfen teknik destek ile iletişime geçin.',
              errorReference: 'ERR-ROLLBACK-INCOMPLETE',
              technicalDetails: 'core_next_rollback_state: $rollbackState',
            );
          }
        }
      } catch (e) {
        debugPrint('[AppBootstrap] Rollback state check error: $e');
      }

      // 2. Çökme Kurtarma Taraması (Güvenli Zaman Aşımı)
      try {
        final recovery = ref.read(crashRecoveryManagerProvider);
        final crashed = await recovery.checkForCrashOnStartup().timeout(
              const Duration(seconds: 4),
              onTimeout: () => false,
            );
        if (crashed) {
          await recovery.recoverInterruptedSyncJobs().timeout(
                const Duration(seconds: 4),
                onTimeout: () => 0,
              );
        }
      } catch (e) {
        debugPrint('[AppBootstrap] Crash recovery note: $e');
      }

      // 3. Takılı Kalan SMS Kuyruğunu Süpürme (Non-blocking, Bounded Timeout)
      try {
        final smsLogRepo = ref.read(smsLogRepositoryProvider);
        await smsLogRepo.resetStuckJobs().timeout(
              const Duration(seconds: 3),
              onTimeout: () {
                debugPrint('[AppBootstrap] SMS stuck jobs reset timed out (3s); continuing boot safely.');
              },
            );
      } catch (e) {
        debugPrint('Failed to reset stuck SMS jobs at startup: $e');
      }

      // 4. Donanım Kayıtları ve Yazdırma Runtime Başlatma
      try {
        await ref.read(hardwareDevicesProvider.future).timeout(
              const Duration(seconds: 3),
              onTimeout: () => <HardwareDevice>[],
            );
      } catch (e) {
        debugPrint('Legacy hardware import failed: $e');
      }

      try {
        final printRecovery = await ref.read(printingRuntimeProvider).start().timeout(
              const Duration(seconds: 4),
              onTimeout: () => const PrintRecoverySummary(safelyRequeued: 0, awaitingUserCheck: 0),
            );
        final remoteConfig = ref.read(remoteConfigServiceProvider);
        await remoteConfig.fetchAndActivate().timeout(
              const Duration(seconds: 3),
              onTimeout: () {
                debugPrint('[AppBootstrap] RemoteConfig fetch timed out (3s); continuing with cached config.');
              },
            );
        final localHardware = await ref.read(hardwareDevicesProvider.future).timeout(
              const Duration(seconds: 3),
              onTimeout: () => <HardwareDevice>[],
            );
        if (remoteConfig.isSharedHardwareEnabled()) {
          try {
            await ref.read(sharedHardwareServiceProvider).publishPresence(
                  localHardware
                      .where((device) =>
                          device.connectionType != HardwareConnectionType.cloud)
                      .toList(growable: false),
                ).timeout(const Duration(seconds: 3));
          } catch (presenceErr) {
            debugPrint('Initial presence publish deferred: $presenceErr');
          }
          ref.read(sharedHardwareWorkerProvider).start();
          ref.read(sharedHardwarePresenceRuntimeProvider).start();
        }
        if (printRecovery.safelyRequeued > 0 ||
            printRecovery.awaitingUserCheck > 0) {
          debugPrint(
            'Print recovery: ${printRecovery.safelyRequeued} safely requeued, '
            '${printRecovery.awaitingUserCheck} awaiting user confirmation.',
          );
        }
      } catch (e) {
        debugPrint('Printing runtime startup failed: $e');
      }

      // 5. Yerel Depoları Ön Isıtma (Pre-warm) (İzole, Hata Güvenli ve Zaman Aşımı Korumalı)
      try {
        final settingsRepo = await ref.read(settingsRepositoryProvider.future).timeout(
              const Duration(seconds: 3),
            );
        await settingsRepo.getSettings().timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('Settings pre-warm warning at startup: $e');
      }

      try {
        final productRepo = await ref.read(productRepositoryProvider.future).timeout(
              const Duration(seconds: 3),
            );
        await productRepo.getInventorySummary().timeout(const Duration(seconds: 3));
        await productRepo.getCategories().timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('Product pre-warm warning at startup: $e');
      }

      try {
        final customerRepo = await ref.read(customerRepositoryProvider.future).timeout(
              const Duration(seconds: 3),
            );
        await customerRepo.count().timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('Customer pre-warm warning at startup: $e');
      }

      return const StartupDiagnosticsResult(isSuccess: true);
    } catch (e, st) {
      debugPrint('Integrity diagnostics run failure: $e');
      final rawError = e.toString();
      final refCode = _generateErrorReference(rawError);

      try {
        unawaited(TelemetryService().logError(
          e,
          st,
          context: 'startup_integrity_diagnostics_unhandled',
          correlationId: refCode,
        ));
        unawaited(Sentry.captureException(
          e,
          stackTrace: st,
          withScope: (scope) {
            scope.setTag('error_reference', refCode);
            scope.setTag('error_source', 'startup_diagnostics');
          },
        ));
      } catch (_) {
        // Sentry/Telemetry reporting failure is non-blocking
      }

      return StartupDiagnosticsResult(
        isSuccess: false,
        errorMessage: 'Sistem başlatılırken beklenmeyen bir hata oluştu.\n'
            'Durum teknik ekibimize otomatik olarak iletildi.',
        errorReference: refCode,
        technicalDetails: rawError,
      );
    }
  }
}
