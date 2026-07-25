import 'package:flutter/foundation.dart';

// lib/config/environment.dart
// Serenut Platform — Environment Configuration Management
// Resolves settings for dev, test, and prod builds from launch arguments.
// Created: 04 Jul 2026

enum AppEnvironment { dev, test, prod }

class EnvironmentConfig {
  final AppEnvironment environment;
  final String apiBaseUrl;
  final String authEndpoint;
  final String syncEndpoint;
  final String updateEndpoint;
  final String releaseEndpoint;
  final String
      releaseChannel; // 'stable' | 'beta' | 'alpha' | 'nightly' | 'internal'
  final String? sentryDsn;

  const EnvironmentConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.authEndpoint,
    required this.syncEndpoint,
    required this.updateEndpoint,
    required this.releaseEndpoint,
    required this.releaseChannel,
    this.sentryDsn,
  });

  String get wsBaseUrl {
    final wsScheme = apiBaseUrl.startsWith('https') ? 'wss' : 'ws';
    final rawHostPath = apiBaseUrl.substring(apiBaseUrl.indexOf('://') + 3);
    return '$wsScheme://$rawHostPath/realtime/live';
  }

  /// Factory configuration mapping based on active environment parameter.
  factory EnvironmentConfig.fromEnv(AppEnvironment env) {
    switch (env) {
      case AppEnvironment.dev:
        return const EnvironmentConfig(
          environment: AppEnvironment.dev,
          apiBaseUrl: 'http://localhost:3000/api/v1',
          authEndpoint: '/auth',
          syncEndpoint: '/sync',
          updateEndpoint: '/updates',
          releaseEndpoint: '/releases',
          releaseChannel: 'stable',
          sentryDsn: null,
        );
      case AppEnvironment.test:
        return const EnvironmentConfig(
          environment: AppEnvironment.test,
          apiBaseUrl: 'https://test-api.serenut.com/api/v1',
          authEndpoint: '/auth',
          syncEndpoint: '/sync',
          updateEndpoint: '/updates',
          releaseEndpoint: '/releases',
          releaseChannel: 'beta',
          sentryDsn: String.fromEnvironment('SENTRY_DSN'),
        );
      case AppEnvironment.prod:
        return const EnvironmentConfig(
          environment: AppEnvironment.prod,
          apiBaseUrl: 'https://api.serenut.com/api/v1',
          authEndpoint: '/auth',
          syncEndpoint: '/sync',
          updateEndpoint: '/updates',
          releaseEndpoint: '/releases',
          releaseChannel: 'stable',
          sentryDsn: String.fromEnvironment('SENTRY_DSN'),
        );
    }
  }

  static String? _customApiBaseUrl;

  static void setCustomApiBaseUrl(String? url) {
    if (url != null && url.trim().isNotEmpty) {
      var clean = url.trim();
      if (clean.endsWith('/')) {
        clean = clean.substring(0, clean.length - 1);
      }
      if (!clean.endsWith('/api/v1')) {
        clean = '$clean/api/v1';
      }
      _customApiBaseUrl = clean;
    } else {
      _customApiBaseUrl = null;
    }
  }

  static String? get customApiBaseUrl => _customApiBaseUrl;

  /// Resolves the runtime environment configuration.
  /// Reads variables passed via '--dart-define=ENVIRONMENT=prod/test/dev'.
  /// Defaults to dev if not specified.
  static EnvironmentConfig get current {
    const envString = String.fromEnvironment('ENVIRONMENT', defaultValue: '');
    EnvironmentConfig baseConfig;
    if (envString.isEmpty) {
      baseConfig = EnvironmentConfig.fromEnv(
          kDebugMode ? AppEnvironment.dev : AppEnvironment.prod);
    } else {
      switch (envString.toLowerCase()) {
        case 'prod':
        case 'production':
          baseConfig = EnvironmentConfig.fromEnv(AppEnvironment.prod);
          break;
        case 'test':
        case 'staging':
          baseConfig = EnvironmentConfig.fromEnv(AppEnvironment.test);
          break;
        case 'dev':
        case 'development':
        default:
          baseConfig = EnvironmentConfig.fromEnv(AppEnvironment.dev);
          break;
      }
    }

    if (_customApiBaseUrl != null && _customApiBaseUrl!.isNotEmpty) {
      return EnvironmentConfig(
        environment: baseConfig.environment,
        apiBaseUrl: _customApiBaseUrl!,
        authEndpoint: baseConfig.authEndpoint,
        syncEndpoint: baseConfig.syncEndpoint,
        updateEndpoint: baseConfig.updateEndpoint,
        releaseEndpoint: baseConfig.releaseEndpoint,
        releaseChannel: baseConfig.releaseChannel,
        sentryDsn: baseConfig.sentryDsn,
      );
    }
    return baseConfig;
  }

  /// Feature flag controlling migration to Enterprise Release Management Platform v2.
  /// Defaults to false in production builds, true in dev/test/internal builds unless overridden.
  bool get useV2UpdatePlatform {
    const flagDefined = bool.hasEnvironment('USE_V2_UPDATE_PLATFORM');
    if (flagDefined) {
      return const bool.fromEnvironment('USE_V2_UPDATE_PLATFORM');
    }
    return environment != AppEnvironment.prod;
  }
}

