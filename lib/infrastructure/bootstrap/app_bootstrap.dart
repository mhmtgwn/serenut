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
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/network/trusted_ca_http_overrides.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/infrastructure/services/dataset_loader_service.dart';
import 'package:serenutos/infrastructure/services/device_fingerprint_service.dart';
import 'package:serenutos/infrastructure/services/password_hash_service.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/presentation/observers/telemetry_provider_observer.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/hardware_devices_provider.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/sms_provider.dart';

/// Pre-app başlatma sonucu
class BootstrapResult {
  final SharedPreferences prefs;
  final AuthService authService;
  final ApiClient apiClient;
  final DatasetLoaderService datasetLoader;
  final LicenseService licenseService;
  final List<Override> overrides;
  final List<ProviderObserver> observers;

  const BootstrapResult({
    required this.prefs,
    required this.authService,
    required this.apiClient,
    required this.datasetLoader,
    required this.licenseService,
    required this.overrides,
    required this.observers,
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
  static Future<BootstrapResult> initPreApp() async {
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

    return BootstrapResult(
      prefs: prefs,
      authService: authService,
      apiClient: apiClient,
      datasetLoader: datasetLoader,
      licenseService: licenseService,
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        apiClientProvider.overrideWithValue(apiClient),
        sharedPreferencesProvider.overrideWithValue(prefs),
        datasetLoaderServiceProvider.overrideWithValue(datasetLoader),
        licenseServiceProvider.overrideWithValue(licenseService),
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
      WidgetRef ref) async {
    try {
      // 1. Veritabanı Bütünlüğü ve Onarım
      final diag = ref.read(integrityCheckServiceProvider);
      final report = await diag.runDiagnostics();
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

      // 2. Çökme Kurtarma Taraması
      final recovery = ref.read(crashRecoveryManagerProvider);
      final crashed = await recovery.checkForCrashOnStartup();
      if (crashed) {
        await recovery.recoverInterruptedSyncJobs();
      }

      // 3. Takılı Kalan SMS Kuyruğunu Süpürme
      try {
        final smsLogRepo = ref.read(smsLogRepositoryProvider);
        await smsLogRepo.resetStuckJobs();
      } catch (e) {
        debugPrint('Failed to reset stuck SMS jobs at startup: $e');
      }

      // 4. Donanım Kayıtları ve Yazdırma Runtime Başlatma
      try {
        await ref.read(hardwareDevicesProvider.future);
      } catch (e) {
        debugPrint('Legacy hardware import failed: $e');
      }

      try {
        final printRecovery = await ref.read(printingRuntimeProvider).start();
        final remoteConfig = ref.read(remoteConfigServiceProvider);
        await remoteConfig.fetchAndActivate();
        final localHardware = await ref.read(hardwareDevicesProvider.future);
        if (remoteConfig.isSharedHardwareEnabled()) {
          try {
            await ref.read(sharedHardwareServiceProvider).publishPresence(
                  localHardware
                      .where((device) =>
                          device.connectionType != HardwareConnectionType.cloud)
                      .toList(growable: false),
                );
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

      // 5. Yerel Depoları Ön Isıtma (Pre-warm)
      try {
        final settingsRepo = await ref.read(settingsRepositoryProvider.future);
        await settingsRepo.getSettings();

        final productRepo = await ref.read(productRepositoryProvider.future);
        await productRepo.getInventorySummary();
        await productRepo.getCategories();

        final customerRepo = await ref.read(customerRepositoryProvider.future);
        await customerRepo.count();
      } catch (e) {
        debugPrint('Pre-warm warning at startup: $e');
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
