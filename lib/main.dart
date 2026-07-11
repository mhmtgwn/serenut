import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/domain/services/auth_service.dart';
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
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';
import 'package:serenutos/infrastructure/services/password_hash_service.dart';
import 'package:serenutos/domain/services/version_checker.dart';
import 'package:serenutos/domain/services/error_boundary.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:serenutos/presentation/pages/force_update_page.dart';

void main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://637bf7c98099e289bf650ccb646c05ef@o4507542289657856.ingest.us.sentry.io/4507542295621632';
      options.tracesSampleRate = 0.1;
      options.environment = kReleaseMode ? 'production' : 'development';
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();
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
      if (kIsWeb) {
        userRepository = InMemoryUserRepository();
      } else {
        final dbManager = DatabaseManager();
        final gateway = DbGatewayImpl(dbManager);
        userRepository = SqliteUserRepository(gateway);
      }
      final hashService = PasswordHashServiceImpl();
      final apiClient = ApiClient();

      final licenseService = LicenseService(prefs);
      if (licenseService.getLicenseInfo() != null) {
        licenseService.startHeartbeat(apiClient);
      }

      final authService = AuthService(
        userRepository: userRepository,
        hashService: hashService,
        apiClient: apiClient,
      );
      await authService.initialize();
      
      // If database contains no users, reset onboarding status to show the wizard
      if (!kIsWeb) {
        try {
          final users = await authService.getUsers();
          if (users.isEmpty) {
            await prefs.remove('admin_pin_code');
          }
        } catch (_) {}
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

class _MyAppState extends ConsumerState<MyApp> {
  bool _checkingIntegrity = true;
  String? _integrityError;
  bool _checkingVersion = true;
  bool _forceUpdateRequired = false;
  String _latestVersion = '';
  String _releaseNotes = '';
  String _downloadUrl = '';

  @override
  void initState() {
    super.initState();
    _runIntegrityDiagnostics();
  }

  Future<void> _runIntegrityDiagnostics() async {
    if (kIsWeb) {
      setState(() {
        _checkingIntegrity = false;
      });
      _checkVersion();
      _triggerAutoBackup();
      return;
    }

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
    } catch (e) {
      debugPrint('Integrity diagnostics run failure: $e');
    }

    setState(() {
      _checkingIntegrity = false;
    });
    _checkVersion();
    _triggerAutoBackup();
  }

  void _triggerAutoBackup() {
    if (!kIsWeb) {
      ref.read(backupServiceProvider).autoBackupIfNeeded().catchError((e) {
        debugPrint('Otomatik yedekleme hatası: $e');
      });
    }
  }

  Future<void> _checkVersion() async {
    final checker = VersionChecker(apiClient: ref.read(apiClientProvider));
    final required = await checker.checkForceUpdateRequired();
    if (required) {
      final info = await checker.getVersionInfo();
      if (info != null) {
        _latestVersion = info.latestVersion;
        _releaseNotes = info.releaseNotes;
        _downloadUrl = info.downloadUrl;
      }
    }
    if (mounted) {
      setState(() {
        _forceUpdateRequired = required;
        _checkingVersion = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingIntegrity) {
      return MaterialApp(
        title: 'Serenut POS',
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
        title: 'Serenut POS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 80, color: Colors.redAccent),
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
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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
        title: 'Serenut POS',
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
        title: 'Serenut POS',
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
        ),
      );
    }

    final router = ref.watch(routerProvider);
    
    // Eagerly initialize sync provider so AppLifecycle observer is registered
    // and auto-sync fires when app resumes from background.
    ref.watch(syncProvider);
    
    // Eagerly initialize SMS notification handler to subscribe to domain events on startup
    ref.watch(smsNotificationHandlerProvider);
    
    return MaterialApp.router(
      title: 'Serenut POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
