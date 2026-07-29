import 'dart:convert';

import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Durable, idempotent bridge for local SIM delivery results.
///
/// SMS sending and cloud reporting are separate operations. A sent SMS must
/// not disappear from cloud history merely because the device was offline
/// while reporting its result.
class SmsCloudOutbox {
  SmsCloudOutbox(this._api);

  static const _storageKey = 'sms_cloud_dispatch_outbox_v1';
  static Future<void> _serial = Future<void>.value();
  final ApiClient _api;

  Future<void> enqueue(Map<String, dynamic> payload) {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      final pending = _decode(prefs.getStringList(_storageKey) ?? const []);
      final messageId = payload['client_message_id']?.toString();
      pending.removeWhere(
          (item) => item['client_message_id']?.toString() == messageId);
      pending.add(payload);
      await _save(prefs, pending);
    });
  }

  Future<int> flush() {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      final pending = _decode(prefs.getStringList(_storageKey) ?? const []);
      var sent = 0;
      while (pending.isNotEmpty) {
        final payload = pending.first;
        try {
          await _api.send(
            'POST',
            '/api/v1/notifications/sync-local',
            body: payload,
            idempotencyKey:
                'sms-local-${payload['client_message_id']?.toString() ?? ''}',
          );
          pending.removeAt(0);
          sent++;
          await _save(prefs, pending);
        } catch (_) {
          // Preserve FIFO ordering. A later foreground/main-sync pass retries.
          break;
        }
      }
      return sent;
    });
  }

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _serial.then((_) => action());
    _serial = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  static List<Map<String, dynamic>> _decode(List<String> raw) => raw
      .map((item) {
        try {
          return Map<String, dynamic>.from(jsonDecode(item) as Map);
        } catch (_) {
          return <String, dynamic>{};
        }
      })
      .where((item) => item['client_message_id'] != null)
      .toList();

  static Future<void> _save(
    SharedPreferences prefs,
    List<Map<String, dynamic>> pending,
  ) {
    // Bound corrupted/offline installations without dropping recent results.
    final trimmed = pending.length > 1000
        ? pending.sublist(pending.length - 1000)
        : pending;
    return prefs.setStringList(
      _storageKey,
      trimmed.map(jsonEncode).toList(),
    );
  }
}
