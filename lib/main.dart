import 'dart:async';
import 'dart:io';
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
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:serenutos/presentation/pages/force_update_page.dart';
import 'package:serenutos/presentation/widgets/update_dialog.dart';
import 'package:serenutos/infrastructure/services/release_manager_service.dart';

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

      final authService = AuthService(
        userRepository: userRepository,
        hashService: hashService,
        apiClient: apiClient,
        deviceManager: deviceManager,
        licenseService: licenseService,
      );
      // Global event publisher will be eagerly initialized in MyApp build

      // Initialize Auth service
      await authService.initialize();

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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkForLiveUpdate());
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

  void _triggerAutoBackup() {
    ref.read(backupServiceProvider).autoBackupIfNeeded().catchError((e) {
      debugPrint('Otomatik yedekleme hatası: $e');
    });
  }

  Future<void> _checkVersion() async {
    final checker = VersionChecker(apiClient: ref.read(apiClientProvider));
    final required = await checker.checkForceUpdateRequired();
    final info = await checker.getVersionInfo();
    if (info != null) {
      if (required) {
        _latestVersion = info.latestVersion;
        _releaseNotes = info.releaseNotes;
        _downloadUrl = info.downloadUrl;
        _sha256Hash = info.sha256Hash;
        _signature = info.signature;
        _fileSizeBytes = info.fileSizeBytes;
      }
    }
    if (mounted) {
      setState(() {
        _forceUpdateRequired = required;
        _checkingVersion = false;
      });
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
          platform: Platform.isAndroid ? 'android' : 'windows',
          jwtToken: ref.read(authServiceProvider).getJwtToken(),
          deviceId: null,
        );
      } finally {
        _updateDialogVisible = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingIntegrity) {
      return MaterialApp(
        title: 'Serenut OS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Sistem bütünlüğü kontrol ediliyor...'),
              ],
            ),
          ),
        ),
      );
    }

    if (_integrityError != null) {
      return MaterialApp(
        title: 'Serenut OS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 80, color: Colors.redAccent),
                  const SizedBox(height: 24),
                  const Text(
                    'Veritabanı Bütünlük Hatası!',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Sistem otomatik kurtarmayı denedi ancak başarılı olamadı. Lütfen teknik destek ekibiyle iletişime geçin.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withAlpha(60)),
                    ),
                    child: Text(
                      _integrityError!,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_checkingVersion) {
      return MaterialApp(
        title: 'Serenut OS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
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
              : 'https://serenut.com/api/v1/updates/download/android/latest',
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
