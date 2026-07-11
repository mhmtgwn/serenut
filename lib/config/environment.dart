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
  final String releaseChannel; // 'stable' | 'beta' | 'alpha' | 'nightly' | 'internal'

  const EnvironmentConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.authEndpoint,
    required this.syncEndpoint,
    required this.updateEndpoint,
    required this.releaseEndpoint,
    required this.releaseChannel,
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
          apiBaseUrl: 'https://serenut.com/api/v1',
          authEndpoint: '/auth',
          syncEndpoint: '/sync',
          updateEndpoint: '/updates',
          releaseEndpoint: '/releases',
          releaseChannel: 'stable',
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
        );
      case AppEnvironment.prod:
        return const EnvironmentConfig(
          environment: AppEnvironment.prod,
          apiBaseUrl: 'https://serenut.com/api/v1',
          authEndpoint: '/auth',
          syncEndpoint: '/sync',
          updateEndpoint: '/updates',
          releaseEndpoint: '/releases',
          releaseChannel: 'stable',
        );
    }
  }

  /// Resolves the runtime environment configuration.
  /// Reads variables passed via '--dart-define=ENVIRONMENT=prod/test/dev'.
  /// Defaults to dev if not specified.
  static EnvironmentConfig get current {
    const envString = String.fromEnvironment('ENVIRONMENT', defaultValue: 'prod');
    switch (envString.toLowerCase()) {
      case 'prod':
      case 'production':
        return EnvironmentConfig.fromEnv(AppEnvironment.prod);
      case 'test':
      case 'staging':
        return EnvironmentConfig.fromEnv(AppEnvironment.test);
      case 'dev':
      case 'development':
      default:
        return EnvironmentConfig.fromEnv(AppEnvironment.dev);
    }
  }
}
