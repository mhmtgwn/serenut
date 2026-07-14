// test/services/api_client_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

void main() {
  group('ApiClient Tests', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient = ApiClient(
        config: EnvironmentConfig.fromEnv(AppEnvironment.test),
      );
    });

    test('Attaches Content-Type and Accept headers', () async {
      apiClient.mockHandler = (request) {
        expect(request.headers['Content-Type'], 'application/json');
        expect(request.headers['Accept'], 'application/json');
        return const ApiResponse(
          statusCode: 200,
          body: '{"status": "ok"}',
          headers: {},
        );
      };

      final response = await apiClient.get('/test');
      expect(response.isSuccess, true);
      expect(response.json['status'], 'ok');
    });

    test('Attaches JWT Bearer token when authenticated', () async {
      apiClient.setJwtToken('my_secure_token');
      apiClient.mockHandler = (request) {
        expect(request.headers['Authorization'], 'Bearer my_secure_token');
        return const ApiResponse(
          statusCode: 200,
          body: '{"auth": true}',
          headers: {},
        );
      };

      final response = await apiClient.get('/auth-check');
      expect(response.json['auth'], true);
    });

    test('Generates Idempotency-Key for modifying requests by default',
        () async {
      apiClient.mockHandler = (request) {
        expect(request.headers.containsKey('Idempotency-Key'), true);
        expect(request.headers['Idempotency-Key']!.length, 36); // UUID length
        return const ApiResponse(
          statusCode: 201,
          body: '{"created": true}',
          headers: {},
        );
      };

      final response = await apiClient.post('/create', {'name': 'New Product'});
      expect(response.statusCode, 201);
    });

    test('Throws ApiException on HTTP error statuses', () async {
      apiClient.mockHandler = (request) {
        return const ApiResponse(
          statusCode: 400,
          body: '{"error": "Bad Request"}',
          headers: {},
        );
      };

      expect(
        apiClient.get('/bad-route'),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });
  });
}
