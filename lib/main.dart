import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:serenutos/config/app_platform.dart';
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/services/version_checker.dart';
import 'package:serenutos/infrastructure/bootstrap/app_bootstrap.dart';
import 'package:serenutos/infrastructure/services/release_manager_service.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/pages/force_update_page.dart';
import 'package:serenutos/presentation/widgets/app_notification_host.dart';
import 'package:serenutos/presentation/widgets/branded_splash_screen.dart';
import 'package:serenutos/presentation/widgets/update_dialog.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/event_providers.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/sms_provider.dart';
import 'package:serenutos/providers/sync_provider.dart';

void main() async {
  final envConfig = EnvironmentConfig.current;
  await SentryFlutter.init(
    (options) {
      options.dsn = envConfig.sentryDsn ?? '';
      // Optimize sampling in production: 10% trace sampling reduces overhead/quota usage,
      // while crash & exception reporting remains 100% active.
      options.tracesSampleRate = kReleaseMode ? 0.1 : 1.0;
      options.profilesSampleRate = kReleaseMode ? 0.05 : 1.0;
      options.environment = kReleaseMode ? 'production' : 'development';
      options.attachStacktrace = true;
      options.enableAutoSessionTracking = true;
    },
    appRunner: () async {
      try {
        final bootstrap = await AppBootstrap.initPreApp();
        runApp(
          ProviderScope(
            observers: bootstrap.observers,
            overrides: bootstrap.overrides,
            child: const MyApp(),
          ),
        );
      } catch (e, st) {
        final hash = (e.toString().hashCode.abs() % 0xFFFFFF)
            .toRadixString(16)
            .toUpperCase();
        final refCode = 'ERR-${hash.padLeft(6, '0')}';
        try {
          unawaited(Sentry.captureException(
            e,
            stackTrace: st,
            withScope: (scope) {
              scope.setTag('error_reference', refCode);
              scope.setTag('error_source', 'pre_app_bootstrap');
            },
          ));
        } catch (_) {
          // Sentry failure is non-blocking
        }
        runApp(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: BrandedSplashScreen(
              status: 'Sistem Başlatılamadı',
              error:
                  'Sistem bileşenleri başlatılırken bir aksaklık oluştu.\nDurum teknik ekibimize otomatik olarak iletildi.',
              errorReference: refCode,
              technicalDetails: e.toString(),
              onRetry: () => main(),
            ),
          ),
        );
      }
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
  String? _integrityRefCode;
  String? _integrityTechnicalDetails;
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
    // Warm up global background providers once on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(eventPublisherProvider);
      ref.read(syncProvider);
      ref.read(telemetryBridgeProvider);
      ref.read(smsNotificationHandlerProvider);
      ref.read(smsGatewayServiceProvider);
      unawaited(_checkAutoDebtReminders());
      // Pre-warm primary POS tab controllers in background so navigation to Satış, Ürünler, Müşteriler, Siparişler is instant (0ms delay)
      ref.read(salesProductsControllerProvider);
      ref.read(productsControllerProvider);
      ref.read(customersControllerProvider);
      ref.read(ordersControllerProvider);
      ref.read(productInventorySummaryProvider);
    });
  }

  Future<void> _checkAutoDebtReminders() async {
    try {
      final settings = ref.read(settingsNotifierProvider).value;
      if (settings == null || !settings.smsAutoDebtReminderEnabled) return;
      final reminderService =
          await ref.read(debtReminderServiceProvider.future);
      await reminderService.runAutoDebtReminderCheck(
        settings: settings,
        onSettingsUpdate: (updated) async {
          await ref
              .read(settingsNotifierProvider.notifier)
              .updateSettings(updated);
        },
      );
    } catch (e) {
      debugPrint('⚠️ Auto debt reminder check error: $e');
    }
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
    final result = await AppBootstrap.runStartupDiagnostics(ref);
    if (!result.isSuccess) {
      if (mounted) {
        setState(() {
          _integrityError = result.errorMessage;
          _integrityRefCode = result.errorReference;
          _integrityTechnicalDetails = result.technicalDetails;
          _checkingIntegrity = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _checkingIntegrity = false;
      });
    }
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
      _integrityRefCode = null;
      _integrityTechnicalDetails = null;
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
          errorReference: _integrityRefCode,
          technicalDetails: _integrityTechnicalDetails,
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

    // Keep background event publishers and listeners active without rebuilding
    // the root MaterialApp on periodic sync state transitions (idle -> syncing -> idle).
    ref.listen(eventPublisherProvider, (_, __) {});
    ref.listen(syncProvider, (_, __) {});
    ref.listen(telemetryBridgeProvider, (_, __) {});
    ref.listen(smsNotificationHandlerProvider, (_, __) {});
    ref.listen(smsGatewayServiceProvider, (_, __) {});

    return MaterialApp.router(
      title: 'Serenut OS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      routerConfig: router,
      builder: (context, child) => AppNotificationHost(
        key: AppNotificationHost.hostKey,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
