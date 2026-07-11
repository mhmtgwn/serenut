import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/version_checker.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/config/environment.dart';

void main() {
  group('VersionChecker Tests', () {
    test('isVersionOlder compares versions correctly', () {
      expect(VersionChecker.isVersionOlder('1.0.0+1', '1.0.0+2'), isTrue);
      expect(VersionChecker.isVersionOlder('1.0.0+2', '1.0.0+1'), isFalse);
      expect(VersionChecker.isVersionOlder('1.0.0+1', '1.0.1+1'), isTrue);
      expect(VersionChecker.isVersionOlder('1.1.0+1', '1.0.0+1'), isFalse);
      expect(VersionChecker.isVersionOlder('2.0.0+1', '1.0.0+10'), isFalse);
    });

    test('checkForceUpdateRequired returns true when backend forces update', () async {
      final apiClient = ApiClient(config: EnvironmentConfig.fromEnv(AppEnvironment.test));
      apiClient.mockHandler = (request) {
        return const ApiResponse(
          statusCode: 200,
          body: '{"latestVersion": "1.1.0+10", "minRequiredVersion": "1.0.0+1", "isForceUpdate": true, "downloadUrl": ""}',
          headers: {},
        );
      };

      final checker = VersionChecker(apiClient: apiClient);
      final forceRequired = await checker.checkForceUpdateRequired();
      expect(forceRequired, isTrue);
    });

    test('checkForceUpdateRequired returns true when current version is older than minRequiredVersion', () async {
      final apiClient = ApiClient(config: EnvironmentConfig.fromEnv(AppEnvironment.test));
      apiClient.mockHandler = (request) {
        return const ApiResponse(
          statusCode: 200,
          body: '{"latestVersion": "1.1.0+10", "minRequiredVersion": "1.0.0+5", "isForceUpdate": false, "downloadUrl": ""}',
          headers: {},
        );
      };

      final checker = VersionChecker(apiClient: apiClient);
      final forceRequired = await checker.checkForceUpdateRequired();
      expect(forceRequired, isTrue);
    });

    test('checkForceUpdateRequired returns false when current version is up to date', () async {
      final apiClient = ApiClient(config: EnvironmentConfig.fromEnv(AppEnvironment.test));
      apiClient.mockHandler = (request) {
        return const ApiResponse(
          statusCode: 200,
          body: '{"latestVersion": "1.0.0+1", "minRequiredVersion": "1.0.0+1", "isForceUpdate": false, "downloadUrl": ""}',
          headers: {},
        );
      };

      final checker = VersionChecker(apiClient: apiClient);
      final forceRequired = await checker.checkForceUpdateRequired();
      expect(forceRequired, isFalse);
    });

    test('checkForceUpdateRequired fails open on network failure (resiliency)', () async {
      final apiClient = ApiClient(config: EnvironmentConfig.fromEnv(AppEnvironment.test));
      apiClient.mockHandler = (request) {
        throw Exception('Network error');
      };

      final checker = VersionChecker(apiClient: apiClient);
      final forceRequired = await checker.checkForceUpdateRequired();
      expect(forceRequired, isFalse);
    });
  });
}
