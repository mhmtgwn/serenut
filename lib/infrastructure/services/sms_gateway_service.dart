import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:serenutos/domain/services/device_manager.dart';
import 'package:serenutos/domain/services/sms_service.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

/// Polls Serenut's company SMS queue only when this Android installation is
/// selected as the company's primary SIM gateway. Existing local SMS triggers
/// remain independent and continue to work when this service is unavailable.
class SmsGatewayService {
  final ApiClient _apiClient;
  final SmsService _smsService;
  final DeviceManager _deviceManager;
  Timer? _timer;
  bool _busy = false;

  SmsGatewayService(this._apiClient, this._smsService, this._deviceManager);

  void start() {
    if (kIsWeb || !Platform.isAndroid || _timer != null) return;
    unawaited(poll());
    _timer =
        Timer.periodic(const Duration(seconds: 20), (_) => unawaited(poll()));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> poll() async {
    if (_busy || _apiClient.jwtToken == null) return;
    _busy = true;
    try {
      final deviceHash = _deviceManager.getDeviceId();
      final gatewayResponse =
          await _apiClient.send('GET', '/api/v1/notifications/sms-gateway');
      final gateway = gatewayResponse.json;
      if (gateway is! Map<String, dynamic> ||
          gateway['device_hash'] != deviceHash) {
        return;
      }

      final response = await _apiClient.send(
        'POST',
        '/api/v1/notifications/sms-gateway/poll',
        body: {'device_id': deviceHash, 'limit': 20},
      );
      final payload = response.json;
      final messages =
          payload is Map<String, dynamic> && payload['messages'] is List
              ? payload['messages'] as List
              : const [];
      for (final raw in messages) {
        if (raw is! Map<String, dynamic>) continue;
        final id = raw['id']?.toString();
        final recipient = raw['recipient']?.toString();
        final body = raw['body']?.toString();
        if (id == null || recipient == null || body == null) continue;
        var sent = false;
        String? error;
        try {
          await _report(id, deviceHash, 'sending');
          sent = await _smsService.sendGatewaySms(recipient, body);
          if (!sent) error = 'SIM gönderimi başarısız oldu.';
        } catch (e) {
          error = e.toString();
        }
        await _report(id, deviceHash, sent ? 'sent' : 'failed', error: error);
      }
    } on ApiException catch (e) {
      // A non-selected device receives no work. Network/session handling stays
      // with ApiClient and must never interrupt POS operations.
      if (e.statusCode != 403 && e.statusCode != 404) {
        debugPrint('[SmsGateway] Poll failed: $e');
      }
    } catch (e) {
      debugPrint('[SmsGateway] Poll failed: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _report(String id, String deviceHash, String status,
      {String? error}) async {
    await _apiClient.send(
      'POST',
      '/api/v1/notifications/sms-gateway/messages/${Uri.encodeComponent(id)}/result',
      body: {'device_id': deviceHash, 'status': status, 'error_message': error},
    );
  }
}
