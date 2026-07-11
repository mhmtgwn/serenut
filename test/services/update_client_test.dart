// test/services/update_client_test.dart
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/domain/services/update_client.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

void main() {
  group('UpdateClient Tests', () {
    late ApiClient apiClient;
    late UpdateClient updateClient;

    setUp(() {
      apiClient = ApiClient(config: EnvironmentConfig.fromEnv(AppEnvironment.test));
      updateClient = UpdateClient(apiClient);
    });

    test('Fetches and parses UpdateManifest correctly', () async {
      apiClient.mockHandler = (request) {
        return const ApiResponse(
          statusCode: 200,
          body: '{"latestVersion": "1.1.0+10", "minRequiredVersion": "1.0.0+1", "isForceUpdate": true, "downloadUrl": "http://pkg.apk", "sha256": "abc", "releaseNotes": "fixed bugs"}',
          headers: {},
        );
      };

      final manifest = await updateClient.checkForUpdates();
      expect(manifest, isNotNull);
      expect(manifest!.latestVersion, '1.1.0+10');
      expect(manifest.isForceUpdate, true);
      expect(manifest.downloadUrl, 'http://pkg.apk');
      expect(manifest.sha256, 'abc');
    });

    test('Verifies SHA256 checksum of downloaded update payload', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final tempFile = '${tempDir.path}/update.apk';

      // Mock download writes the mock payload: 'SERENUT_UPDATE_BINARY_PAYLOAD_MOCK_2026'
      final downloadedFile = await updateClient.downloadUpdate('http://pkg.apk', tempFile);
      expect(await downloadedFile.exists(), true);

      // Compute expected sha256
      final bytes = await downloadedFile.readAsBytes();
      final expectedSha = sha256.convert(bytes).toString();

      final verifySuccess = await updateClient.verifyChecksum(tempFile, expectedSha);
      expect(verifySuccess, true);

      final verifyFailed = await updateClient.verifyChecksum(tempFile, 'wrong_sha_key');
      expect(verifyFailed, false);

      // Cleanup
      tempDir.deleteSync(recursive: true);
    });
  });
}
