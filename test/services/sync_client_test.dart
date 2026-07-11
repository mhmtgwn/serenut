// test/services/sync_client_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/domain/services/sync_client.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

void main() {
  group('RealSyncClient Tests', () {
    late ApiClient apiClient;
    late RealSyncClient syncClient;

    setUp(() {
      apiClient = ApiClient(config: EnvironmentConfig.fromEnv(AppEnvironment.test));
      syncClient = RealSyncClient(apiClient);
    });

    test('checkHealth returns true on healthy status response', () async {
      apiClient.mockHandler = (request) {
        return const ApiResponse(
          statusCode: 200,
          body: '{"status": "healthy"}',
          headers: {},
        );
      };

      final healthy = await syncClient.checkHealth();
      expect(healthy, true);
    });

    test('push sends queue items and returns server status map', () async {
      apiClient.mockHandler = (request) {
        return const ApiResponse(
          statusCode: 200,
          body: '{"synced_count": 5, "errors": []}',
          headers: {},
        );
      };

      final result = await syncClient.push([
        {'id': 'item_1', 'type': 'sale'}
      ]);
      expect(result['synced_count'], 5);
      expect(result['errors'], isEmpty);
    });

    test('pull fetches update packets by logical clock timestamp', () async {
      apiClient.mockHandler = (request) {
        return const ApiResponse(
          statusCode: 200,
          body: '{"transactions": [{"id": "t1"}], "last_timestamp": 12345}',
          headers: {},
        );
      };

      final result = await syncClient.pull(1000);
      expect(result['transactions'].length, 1);
      expect(result['last_timestamp'], 12345);
    });
  });
}
