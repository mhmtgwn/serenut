import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/sync_v4/whatsapp_notification_outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('WhatsApp event survives a network failure and is retried idempotently',
      () async {
    final api = ApiClient();
    var available = false;
    var calls = 0;
    api.mockHandler = (request) {
      calls++;
      if (!available) {
        return const ApiResponse(
          statusCode: 503,
          body: '{"error":"offline"}',
          headers: {},
        );
      }
      expect(request.url.path, '/api/v1/whatsapp/events');
      final payload = jsonDecode((request as dynamic).body) as Map<String, dynamic>;
      expect(payload['client_event_id'], 'event-1');
      expect(payload['event_key'], 'order_ready');
      return const ApiResponse(
        statusCode: 202,
        body: '{"queued":true}',
        headers: {},
      );
    };

    final outbox = WhatsappNotificationOutbox(api);
    await outbox.enqueue({
      'client_event_id': 'event-1',
      'event_key': 'order_ready',
      'recipient': '05551112233',
      'parameters': ['Ayşe', 'SP-1', 'Örnek İşletme'],
      'fallback_body': 'Siparişiniz hazırdır.',
    });

    expect(await outbox.flush(), 0);
    available = true;
    expect(await outbox.flush(), 1);
    expect(await outbox.flush(), 0);
    expect(calls, 2);
  });
}
