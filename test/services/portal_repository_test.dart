// test/services/portal_repository_test.dart
// Serenut Platform — PortalRepository Unit Tests (Sprint 10)
// Tests dashboard summarize, online status metrics and ticket dispatch replies.

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
  group('PortalDashboardSummary.fromJson', () {
    test('parses metrics summaries accurately', () {
      final json = {
        'stores': 3,
        'devices': 4,
        'activeLicenseCount': 2,
        'unpaidInvoices': 1,
        'monthlyRevenue': 4750.50
      };

      final data = PortalDashboardSummary.fromJson(json);
      expect(data.stores, 3);
      expect(data.devices, 4);
      expect(data.activeLicenseCount, 2);
      expect(data.unpaidInvoices, 1);
      expect(data.monthlyRevenue, 4750.50);
    });
  });

  group('PortalDevice.fromJson', () {
    test('parses device online metrics accurately', () {
      final json = {
        'id': 'dev-1',
        'device_name': 'Terminal A',
        'store_name': 'Kadikoy Store',
        'last_active_at': '2026-07-04T12:00:00Z',
        'is_online': true
      };

      final dev = PortalDevice.fromJson(json);
      expect(dev.id, 'dev-1');
      expect(dev.deviceName, 'Terminal A');
      expect(dev.storeName, 'Kadikoy Store');
      expect(dev.isOnline, true);
    });
  });

  group('PortalRepository Mock Tests', () {
    test('getDashboard returns successfully parsed data', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'summary': {
              'stores': 2,
              'devices': 3,
              'activeLicenseCount': 1,
              'unpaidInvoices': 0,
              'monthlyRevenue': 2500.00
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, config: testConfig);
      final repo = PortalRepository(apiClient: apiClient, config: testConfig);
      
      final summary = await repo.getDashboard();
      expect(summary.stores, 2);
      expect(summary.devices, 3);
      expect(summary.monthlyRevenue, 2500.00);
    });

    test('replyTicket dispatches reply successfully', () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body);
        expect(body['message'], 'Hello, troubleshooting completed');
        expect(request.url.path, endsWith('/tickets/tkt-123/reply'));
        
        return http.Response(
          jsonEncode({'success': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, config: testConfig);
      final repo = PortalRepository(apiClient: apiClient, config: testConfig);
      
      await repo.replyTicket('tkt-123', 'Hello, troubleshooting completed');
    });
  });
}
