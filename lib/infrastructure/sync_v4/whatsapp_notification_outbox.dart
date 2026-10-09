import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Durable bridge from local domain events to the server's WhatsApp API queue.
/// The server decides whether the company connection and template are ready.
class WhatsappNotificationOutbox {
  WhatsappNotificationOutbox(this._api);

  static const _storageKey = 'whatsapp_notification_outbox_v1';
  static Future<void> _serial = Future<void>.value();
  final ApiClient _api;
  Timer? _periodicTimer;
  DateTime? _lastFailureLogAt;

  /// Starts a background timer that automatically flushes any queued messages.
  /// This ensures offline or failed messages are not stuck waiting for new events.
  void startPeriodicFlush({Duration interval = const Duration(seconds: 15)}) {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) => flush());
  }

  void stopPeriodicFlush() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  Future<void> enqueue(Map<String, dynamic> payload) => _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        final pending = _decode(prefs.getStringList(_storageKey) ?? const []);
        final eventId = payload['client_event_id']?.toString();
        pending.removeWhere(
            (item) => item['client_event_id']?.toString() == eventId);
        pending.add(payload);
        await _save(prefs, pending);
      });

  Future<int> flush() => _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        final pending = _decode(prefs.getStringList(_storageKey) ?? const []);
        var sent = 0;
        while (pending.isNotEmpty) {
          final payload = pending.first;
          try {
            final response = await _api.send(
              'POST',
              '/api/v1/whatsapp/events',
              body: payload,
              idempotencyKey:
                  'wa-event-${payload['client_event_id']?.toString() ?? ''}',
            );
            final result = response.json;
            if (result is! Map ||
                (result['queued'] != true && result['duplicate'] != true)) {
              final reason = result is Map
                  ? result['reason']?.toString() ?? result['error']?.toString()
                  : null;
              throw ApiException(
                'WhatsApp bildirimi kuyruğa alınmadı${reason == null ? '' : ': $reason'}',
                statusCode: response.statusCode,
                responseBody: response.body,
              );
            }
            pending.removeAt(0);
            sent++;
            await _save(prefs, pending);
          } catch (error) {
            final now = DateTime.now();
            if (_lastFailureLogAt == null ||
                now.difference(_lastFailureLogAt!) >=
                    const Duration(minutes: 1)) {
              debugPrint(
                  'WhatsApp bildirimi gönderilemedi; kuyrukta tutuluyor: $error');
              _lastFailureLogAt = now;
            }
            break;
          }
        }
        return sent;
      });

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
      .where((item) => item['client_event_id'] != null)
      .toList();

  static Future<void> _save(
    SharedPreferences prefs,
    List<Map<String, dynamic>> pending,
  ) {
    final trimmed =
        pending.length > 500 ? pending.sublist(pending.length - 500) : pending;
    return prefs.setStringList(
      _storageKey,
      trimmed.map(jsonEncode).toList(),
    );
  }
}
