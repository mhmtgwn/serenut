// test/services/environment_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/config/environment.dart';

void main() {
  group('EnvironmentConfig Tests', () {
    test('Resolves correct settings for dev environment', () {
      final config = EnvironmentConfig.fromEnv(AppEnvironment.dev);
      expect(config.environment, AppEnvironment.dev);
      expect(config.apiBaseUrl, 'http://localhost:3000/api/v1');
      expect(config.authEndpoint, '/auth');
      expect(config.syncEndpoint, '/sync');
      expect(config.updateEndpoint, '/updates');
    });

    test('Resolves correct settings for test environment', () {
      final config = EnvironmentConfig.fromEnv(AppEnvironment.test);
      expect(config.environment, AppEnvironment.test);
      expect(config.apiBaseUrl, 'https://test-api.serenut.com/api/v1');
    });

    test('Resolves correct settings for prod environment', () {
      final config = EnvironmentConfig.fromEnv(AppEnvironment.prod);
      expect(config.environment, AppEnvironment.prod);
      expect(config.apiBaseUrl, 'https://api.serenut.com/api/v1');
    });

    test('Loads default current config', () {
      final current = EnvironmentConfig.current;
      const expectedEnvStr =
          String.fromEnvironment('ENVIRONMENT', defaultValue: '');
      final expectedEnv = AppEnvironment.values.firstWhere(
          (e) => e.name == (expectedEnvStr.isEmpty ? 'dev' : expectedEnvStr),
          orElse: () => AppEnvironment.dev);
      expect(current.environment, expectedEnv);
    });
  });
}
