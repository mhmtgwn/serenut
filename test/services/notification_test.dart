// test/services/notification_test.dart
// Serenut Platform — NotificationRepository Unit Tests (Sprint 9)
// Tests templates, credit parse, campaign queues and status reports mapping.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/infrastructure/repositories/notification_repository.dart';
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
  group('CompanyCredits.fromJson', () {
    test('parses credit limits correctly', () {
      final json = {
        'sms_credits': 85,
        'whatsapp_credits': 42,
        'email_credits': 950
      };
      final credits = CompanyCredits.fromJson(json);
      expect(credits.smsCredits, 85);
      expect(credits.whatsappCredits, 42);
      expect(credits.emailCredits, 950);
    });
  });

  group('QueueEntry.fromJson', () {
    test('parses queued message items correctly', () {
      final json = {
        'id': 'notif-1',
        'channel': 'sms',
        'recipient': '05301112233',
        'title': 'Test Title',
        'body': 'Message content',
        'status': 'sent',
        'retry_count': 1,
        'error_message': null,
        'delivered_at': '2026-07-04T12:00:00Z',
        'created_at': '2026-07-04T11:59:00Z'
      };

      final entry = QueueEntry.fromJson(json);
      expect(entry.id, 'notif-1');
      expect(entry.channel, 'sms');
      expect(entry.recipient, '05301112233');
      expect(entry.status, 'sent');
      expect(entry.retryCount, 1);
      expect(entry.errorMessage, isNull);
      expect(entry.deliveredAt, '2026-07-04T12:00:00Z');
      expect(entry.createdAt, '2026-07-04T11:59:00Z');
    });
  });

  group('NotificationRepository', () {
    test('getCredits returns correct balance', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'sms_credits': 120,
            'whatsapp_credits': 60,
            'email_credits': 500
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, config: testConfig);
      final repo =
          NotificationRepository(apiClient: apiClient, config: testConfig);
      final credits = await repo.getCredits();

      expect(credits.smsCredits, 120);
      expect(credits.whatsappCredits, 60);
    });

    test('sendCampaign returns correct queued count', () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body);
        expect(body['segment'], 'debtors');
        expect(body['channel'], 'sms');
        expect(body['template_name'], 'debt_reminder');

        return http.Response(
          jsonEncode({'success': true, 'queued_count': 14}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, config: testConfig);
      final repo =
          NotificationRepository(apiClient: apiClient, config: testConfig);
      final count = await repo.sendCampaign(
        segment: 'debtors',
        channel: 'sms',
        templateName: 'debt_reminder',
      );

      expect(count, 14);
    });
  });
}
