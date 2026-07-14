// test/services/cloud_analytics_test.dart
// Serenut Platform — CloudAnalyticsRepository Unit Tests (Sprint 7)
// Tests dashboard, trend, stock, branches, and staff analytics parse methods.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/domain/models/analytics_models.dart';
import 'package:serenutos/infrastructure/repositories/cloud_analytics_repository.dart';
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
  group('DashboardMetrics.fromJson', () {
    test('parses payload correctly', () {
      final json = {
        'today': {'revenue': 150.00, 'orders': 2, 'avgBasket': 75},
        'week': {'revenue': 1050.00, 'growth_pct': 5.4},
        'month': {'revenue': 4500.00, 'growth_pct': 12.8},
        'topProduct': {'name': 'Espresso', 'qty': 10},
        'busiestHour': 14,
        'paymentBreakdown': {'cash': 40, 'card': 50, 'credit': 10}
      };

      final metrics = DashboardMetrics.fromJson(json);
      expect(metrics.todayRevenue, 150.00);
      expect(metrics.todayOrders, 2);
      expect(metrics.avgBasket, 75);
      expect(metrics.weeklyRevenue, 1050.00);
      expect(metrics.weeklyGrowth, 5.4);
      expect(metrics.topProduct?.name, 'Espresso');
      expect(metrics.topProduct?.quantity, 10.0);
      expect(metrics.busiestHour, 14);
      expect(metrics.paymentBreakdown.cash, 40);
      expect(metrics.paymentBreakdown.card, 50);
      expect(metrics.paymentBreakdown.credit, 10);
    });
  });

  group('CloudAnalyticsRepository', () {
    test('getDashboard returns metrics on HTTP 200', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'today': {'revenue': 53000.0, 'orders': 120, 'avgBasket': 441},
            'week': {'revenue': 310000.0, 'growth_pct': 8.0},
            'month': {'revenue': 1200000.0, 'growth_pct': 11.5},
            'topProduct': {'name': 'Filter Coffee', 'qty': 180},
            'busiestHour': 15,
            'paymentBreakdown': {'cash': 30, 'card': 65, 'credit': 5}
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, config: testConfig);
      final repo =
          CloudAnalyticsRepository(apiClient: apiClient, config: testConfig);
      final metrics = await repo.getDashboard();

      expect(metrics.todayRevenue, 53000.0);
      expect(metrics.todayOrders, 120);
      expect(metrics.topProduct?.name, 'Filter Coffee');
    });

    test('getSalesTrend returns list on HTTP 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.queryParameters['period'], 'weekly');
        return http.Response(
          jsonEncode([
            {'time': '2026-06-28T00:00:00Z', 'revenue': 42000.0, 'count': 80},
            {'time': '2026-07-04T00:00:00Z', 'revenue': 53000.0, 'count': 100}
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, config: testConfig);
      final repo =
          CloudAnalyticsRepository(apiClient: apiClient, config: testConfig);
      final trend = await repo.getSalesTrend(period: 'weekly');

      expect(trend.length, 2);
      expect(trend.first.revenue, 42000.0);
      expect(trend.last.count, 100);
    });

    test('getStockStats returns critical items correctly', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'criticalItems': [
              {
                'id': 'p1',
                'name': 'Milk 1L',
                'category': 'Dairy',
                'quantity': 2
              }
            ],
            'criticalCount': 1
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, config: testConfig);
      final repo =
          CloudAnalyticsRepository(apiClient: apiClient, config: testConfig);
      final stock = await repo.getStockStats();

      expect(stock.criticalCount, 1);
      expect(stock.criticalItems.first.name, 'Milk 1L');
      expect(stock.criticalItems.first.quantity, 2);
    });
  });
}
