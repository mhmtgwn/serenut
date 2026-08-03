import 'dart:async';
import 'dart:io';
import 'package:serenutos/config/app_platform.dart';
import 'package:serenutos/config/environment.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/providers/event_providers.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/sync_provider.dart';
import 'package:serenutos/providers/sms_provider.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:serenutos/infrastructure/services/dataset_loader_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/infrastructure/services/password_hash_service.dart';
import 'package:serenutos/domain/services/version_checker.dart';
import 'package:serenutos/domain/services/error_boundary.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/network/trusted_ca_http_overrides.dart';
import 'package:serenutos/domain/services/device_manager.dart';
import 'package:serenutos/infrastructure/services/device_fingerprint_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:serenutos/presentation/pages/force_update_page.dart';
import 'package:serenutos/presentation/widgets/update_dialog.dart';
import 'package:serenutos/infrastructure/services/release_manager_service.dart';
import 'package:serenutos/presentation/widgets/branded_splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      // A packaging mistake must never prevent the application window from
      // opening. Network calls will surface their normal TLS error instead.
      debugPrint('Trusted CA initialization failed: $error');
    }
  }

  final envConfig = EnvironmentConfig.current;
  await SentryFlutter.init(
    (options) {
      options.dsn = envConfig.sentryDsn ?? '';
      options.tracesSampleRate = 0.1;
      options.environment = kReleaseMode ? 'production' : 'development';
    },
    appRunner: () async {
      ErrorBoundary.install();
      await initializeDateFormatting('tr_TR', null);

      if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      // Initialize SharedPreferences
      final prefs = await SharedPreferences.getInstance();

      // Initialize AuthService with required dependencies
      final IUserRepository userRepository;
      DatabaseManager? dbManager;
      dbManager = DatabaseManager();
      final gateway = DbGatewayImpl(dbManager);
      userRepository = SqliteUserRepository(gateway);
      final hashService = PasswordHashServiceImpl();
      final apiClient = ApiClient();

      final licenseService = LicenseService(prefs);
      await licenseService.initialize();
      if (licenseService.getLicenseInfo() != null) {
        licenseService.startHeartbeat(apiClient);
      }

      final deviceManager = DeviceManager(prefs);
      final fingerprintService = DeviceFingerprintService(prefs, deviceManager);
      final settingsRepository = SqliteSettingsRepository(gateway);

      final authService = AuthService(
        userRepository: userRepository,
        hashService: hashService,
        apiClient: apiClient,
        deviceManager: deviceManager,
        licenseService: licenseService,
        deviceFingerprintService: fingerprintService,
        cacheCompanyProfile: (company) async {
          final current = await settingsRepository.getSettings();
          await settingsRepository.updateSettings(current.copyWith(
            businessName: company['name']?.toString() ?? current.businessName,
            businessPhone:
                company['phone']?.toString() ?? current.businessPhone,
            businessAddress:
                company['address']?.toString() ?? current.businessAddress,
            businessTaxId:
                company['tax_number']?.toString() ?? current.businessTaxId,
            ownerName: company['owner_name']?.toString() ?? current.ownerName,
            businessEmail:
                company['email']?.toString() ?? current.businessEmail,
            businessCity: company['city']?.toString() ?? current.businessCity,
            businessDistrict:
                company['district']?.toString() ?? current.businessDistrict,
          ));
        },
      );
      // Global event publisher will be eagerly initialized in MyApp build

      // Initialize Auth service
      await authService.initialize();

      // Perform session bootstrap & online token validation if JWT token is saved
      if (apiClient.jwtToken != null && apiClient.jwtToken!.isNotEmpty) {
        try {
          await authService.checkCurrentUserSessionOnline();
          await authService.refreshEntitlement();
        } catch (e) {
          debugPrint('Startup session bootstrap note: $e');
        }
      }

      // If database contains no users, reset onboarding status to show the wizard
      try {
        final users = await authService.getUsers();
        if (users.isEmpty) {
          // Clear admin PIN from SQLite settings (single source of truth)
          final db = await dbManager.getDatabase();
          await db.update('settings', {
            'admin_pin_code': null,
            'updated_at': DateTime.now().toIso8601String()
          });
        }
      } catch (e) {
        debugPrint('Failed to check or reset onboarding status: $e');
      }

      // Initialize DatasetLoaderService
      final datasetLoader = DatasetLoaderService(prefs);
      await datasetLoader.init();

      runApp(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(authService),
            apiClientProvider.overrideWithValue(apiClient),
            sharedPreferencesProvider.overrideWithValue(prefs),
            datasetLoaderServiceProvider.overrideWithValue(datasetLoader),
            licenseServiceProvider.overrideWithValue(licenseService),
          ],
          child: const MyApp(),
        ),
      );
    },
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  bool _checkingIntegrity = true;
  String? _integrityError;
  bool _checkingVersion = true;
  bool _forceUpdateRequired = false;
  String _latestVersion = '';
  String _releaseNotes = '';
  String _downloadUrl = '';
  String? _sha256Hash;
  String? _signature;
  int? _fileSizeBytes;
  Timer? _updateCheckTimer;
  bool _updateCheckRunning = false;
  bool _updateDialogVisible = false;
  String? _lastPromptedVersion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runIntegrityDiagnostics();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateCheckTimer?.cancel();
    // Temiz kapanışı kaydet — lock dosyası silindi, sonraki başlatmada
    // yanlış crash tespiti yapılmaz.
    ref.read(crashRecoveryManagerProvider).markAppCleanShutdown();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkForLiveUpdate());
    }
    // Uygulama arka plandan tamamen kaldırılıyorsa temiz kapanışı işaretle
    if (state == AppLifecycleState.detached) {
      ref.read(crashRecoveryManagerProvider).markAppCleanShutdown();
    }
  }

  Future<void> _runIntegrityDiagnostics() async {
    try {
      final diag = ref.read(integrityCheckServiceProvider);
      final report = await diag.runDiagnostics();
      if (!report.isAllPass) {
        // Attempt automated recovery repair
        final repaired = await diag.attemptDatabaseRepair();
        if (!repaired) {
          setState(() {
            _integrityError = report.issues.join('\n');
            _checkingIntegrity = false;
          });
          return;
        }
      }

      // Run crash recovery scan on startup
      final recovery = ref.read(crashRecoveryManagerProvider);
      final crashed = await recovery.checkForCrashOnStartup();
      if (crashed) {
        await recovery.recoverInterruptedSyncJobs();
      }

      // Sweep stuck sending SMS logs to interrupted state
      try {
        final smsLogRepo = ref.read(smsLogRepositoryProvider);
        await smsLogRepo.resetStuckJobs();
      } catch (e) {
        debugPrint('Failed to reset stuck SMS jobs at startup: $e');
      }

      // Pre-warm local SQLite repositories so products & catalog are 100% ready instantly when splash ends
      try {
        final settingsRepo = await ref.read(settingsRepositoryProvider.future);
        await settingsRepo.getSettings();

        final productRepo = await ref.read(productRepositoryProvider.future);
        await productRepo.getProducts();
        await productRepo.getCategories();

        final customerRepo = await ref.read(customerRepositoryProvider.future);
        await customerRepo.getCustomers();
      } catch (e) {
        debugPrint('Pre-warm warning at startup: $e');
      }
    } catch (e) {
      debugPrint('Integrity diagnostics run failure: $e');
    }

    setState(() {
      _checkingIntegrity = false;
    });
    _checkVersion();
    _updateCheckTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(_checkForLiveUpdate()),
    );
    _triggerAutoBackup();
  }

  void _retryStartupChecks() {
    setState(() {
      _integrityError = null;
      _checkingIntegrity = true;
      _checkingVersion = true;
    });
    unawaited(_runIntegrityDiagnostics());
  }

  void _triggerAutoBackup() {
    ref.read(backupServiceProvider).autoBackupIfNeeded().catchError((e) {
      debugPrint('Otomatik yedekleme hatası: $e');
    });
  }

  Future<void> _checkVersion() async {
    VersionCheckResult? info;
    var required = false;
    try {
      await VersionChecker.getAppVersion();
      final checker = VersionChecker(apiClient: ref.read(apiClientProvider));
      required = await checker
          .checkForceUpdateRequired()
          .timeout(const Duration(seconds: 12));
      info =
          await checker.getVersionInfo().timeout(const Duration(seconds: 12));
      if (info != null && required) {
        _latestVersion = info.latestVersion;
        _releaseNotes = info.releaseNotes;
        _downloadUrl = info.downloadUrl;
        _sha256Hash = info.sha256Hash;
        _signature = info.signature;
        _fileSizeBytes = info.fileSizeBytes;
      }
    } catch (error) {
      // Güncelleme servisine ulaşılamaması çevrimdışı kullanımı engellemez.
      debugPrint('Startup version check skipped: $error');
    } finally {
      if (mounted) {
        setState(() {
          _forceUpdateRequired = required;
          _checkingVersion = false;
        });
      }
    }

    if (!required && info != null) {
      await _offerOptionalUpdate(info);
    }
  }

  Future<void> _checkForLiveUpdate() async {
    if (_updateCheckRunning || _checkingVersion || _forceUpdateRequired) return;
    _updateCheckRunning = true;
    try {
      final checker = VersionChecker(apiClient: ref.read(apiClientProvider));
      final info = await checker.getVersionInfo();
      if (info == null ||
          !VersionChecker.isVersionOlder(
              VersionChecker.currentVersion, info.latestVersion)) {
        return;
      }
      if (info.isForceUpdate) {
        if (!mounted) return;
        setState(() {
          _latestVersion = info.latestVersion;
          _releaseNotes = info.releaseNotes;
          _downloadUrl = info.downloadUrl;
          _sha256Hash = info.sha256Hash;
          _signature = info.signature;
          _fileSizeBytes = info.fileSizeBytes;
          _forceUpdateRequired = true;
        });
        return;
      }
      await _offerOptionalUpdate(info);
    } finally {
      _updateCheckRunning = false;
    }
  }

  Future<void> _offerOptionalUpdate(VersionCheckResult info) async {
    if (!VersionChecker.isVersionOlder(
            VersionChecker.currentVersion, info.latestVersion) ||
        _updateDialogVisible ||
        _lastPromptedVersion == info.latestVersion) {
      return;
    }
    _lastPromptedVersion = info.latestVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final context = rootNavigatorKey.currentContext;
      if (!mounted || context == null || _updateDialogVisible) return;
      _updateDialogVisible = true;
      try {
        await showUpdateDialog(
          context: context,
          updateInfo: UpdateInfo(
            hasUpdate: true,
            isForceUpdate: false,
            latestVersion: info.latestVersion,
            minRequiredVersion: info.minRequiredVersion,
            downloadUrl: info.downloadUrl,
            sha256Hash: info.sha256Hash,
            signature: info.signature,
            fileSizeBytes: info.fileSizeBytes,
            releaseNotes: info.releaseNotes,
            channel: 'stable',
          ),
          releaseManager: ref.read(releaseManagerServiceProvider),
          platform: AppPlatform.releaseKey,
          jwtToken: ref.read(authServiceProvider).getJwtToken(),
          deviceId:
              ref.read(licenseServiceProvider).getLicenseInfo()?.activationId,
        );
      } finally {
        _updateDialogVisible = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingIntegrity || _checkingVersion || _integrityError != null) {
      final String status;
      final String? detail;

      if (_integrityError != null) {
        status = 'Sistem kontrol ediliyor';
        detail = null;
      } else if (_checkingIntegrity) {
        status = 'Sistem kontrol ediliyor';
        detail = 'Verileriniz ve yarım kalan işlemler güvenle hazırlanıyor.';
      } else {
        status = 'Uygulama hazırlanıyor';
        detail = 'Sürüm ve güvenlik kontrolleri tamamlanıyor.';
      }

      return MaterialApp(
        title: 'Serenut OS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: BrandedSplashScreen(
          status: status,
          detail: detail,
          error: _integrityError,
          onRetry: _integrityError != null ? _retryStartupChecks : null,
        ),
      );
    }

    if (_forceUpdateRequired) {
      return MaterialApp(
        title: 'Serenut OS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: ForceUpdatePage(
          latestVersion: _latestVersion.isNotEmpty ? _latestVersion : '1.1.0',
          releaseNotes: _releaseNotes.isNotEmpty
              ? _releaseNotes
              : 'Kritik güvenlik ve performans güncellemeleri içerir.',
          downloadUrl: _downloadUrl.isNotEmpty
              ? _downloadUrl
              : 'https://serenut.com/api/v1/updates/download/${AppPlatform.releaseKey}/latest',
          sha256Hash: _sha256Hash,
          signature: _signature,
          fileSizeBytes: _fileSizeBytes,
        ),
      );
    }

    final router = ref.watch(routerProvider);

    // Eagerly initialize global event publisher
    ref.watch(eventPublisherProvider);

    // Eagerly initialize sync provider so AppLifecycle observer is registered
    // and auto-sync fires when app resumes from background.
    ref.watch(syncProvider);

    // Yerel hata/uyarı loglarını dayanıklı kuyruk üzerinden Admin telemetrisine bağla.
    ref.watch(telemetryBridgeProvider);

    // Eagerly initialize SMS notification handler to subscribe to domain events on startup
    ref.watch(smsNotificationHandlerProvider);
    ref.watch(smsGatewayServiceProvider);

    return MaterialApp.router(
      title: 'Serenut OS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
