import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/sync_v4/sms_cloud_outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('offline SMS delivery report survives and retries idempotently',
      () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient();
    var online = false;
    var requestCount = 0;
    api.mockHandler = (request) {
      requestCount++;
      if (!online) throw const ApiException('offline');
      final body = (request as http.Request).body;
      expect(body, contains('"client_message_id":"sms-1"'));
      return const ApiResponse(
        statusCode: 201,
        headers: {},
        body: '{"success":true}',
      );
    };
    final outbox = SmsCloudOutbox(api);

    await outbox.enqueue({
      'recipient': '+905551112233',
      'body': 'Test',
      'status': 'sent',
      'channel': 'sms',
      'client_message_id': 'sms-1',
      'created_at': '2026-07-29T00:00:00.000Z',
    });
    expect(await outbox.flush(), 0);

    online = true;
    expect(await SmsCloudOutbox(api).flush(), 1);
    expect(await SmsCloudOutbox(api).flush(), 0);
    expect(requestCount, 2);
  });
}
