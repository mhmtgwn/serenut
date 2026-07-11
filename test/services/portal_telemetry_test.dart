// test/services/portal_telemetry_test.dart
// Serenut Platform — Portal Telemetry & Auditing Unit Tests (Sprint 11)
// Tests system health checks, connection pools, and audit logs parse mapping.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/infrastructure/repositories/portal_repository.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

EnvironmentConfig get testConfig => const EnvironmentConfig(
      environment: AppEnvironment.test,
      apiBaseUrl: 'http://test-api.serenut.com/api/v1',
      authEndpoint: '/auth',
      syncEndpoint: '/sync',
      updateEndpoint: '/updates',
      releaseEndpoint: '/releases',
      releaseChannel: 'stable',
    );

void main() {
  group('PortalRepository Telemetry & Audit Tests', () {
    test('getTelemetryHealth returns mapped health values', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'system': {
              'cpuLoad': 0.85,
              'memoryUsage': '62.40%',
              'dbActivePool': 5
            },
            'queue': {'queued': 2, 'sent': 140},
            'gateways': {
              'sms': 'UP',
              'email': 'UP',
              'whatsapp': 'UP',
              'push': 'DOWN'
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, config: testConfig);
      final repo = PortalRepository(apiClient: apiClient, config: testConfig);
      
      final telemetry = await repo.getTelemetryHealth();
      
      expect(telemetry['system']['memoryUsage'], '62.40%');
      expect(telemetry['system']['dbActivePool'], 5);
      expect(telemetry['gateways']['push'], 'DOWN');
    });

    test('getAuditLogs parses list of events successfully', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'id': 'aud-1',
              'company_id': 'co-1',
              'user_id': 'usr-1',
              'user_name': 'Mehmet Manager',
              'action': 'DELETE_CUSTOMER',
              'entity_type': 'customers',
              'entity_id': 'cust-123',
              'ip_address': '192.168.1.45',
              'user_agent': 'Mozilla/5.0',
              'created_at': '2026-07-04T12:00:00Z'
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, config: testConfig);
      final repo = PortalRepository(apiClient: apiClient, config: testConfig);
      
      final logs = await repo.getAuditLogs();
      
      expect(logs.length, 1);
      expect(logs[0]['action'], 'DELETE_CUSTOMER');
      expect(logs[0]['ip_address'], '192.168.1.45');
    });
  });
}
