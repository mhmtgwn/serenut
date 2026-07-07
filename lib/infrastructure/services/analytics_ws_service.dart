// lib/infrastructure/services/analytics_ws_service.dart
// Serenut Platform — Real-time Analytics WebSocket Client (Sprint 7)
// Auto-reconnect, keepalive listener, and stream broadcaster.
// Created: 04 Jul 2026

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:serenutos/config/environment.dart';

class AnalyticsWsService {
  final EnvironmentConfig _config;
  WebSocket? _webSocket;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  bool _isConnecting = false;
  bool _shouldReconnect = true;
  int _reconnectDelaySeconds = 2;
  Timer? _reconnectTimer;

  AnalyticsWsService({EnvironmentConfig? config}) : _config = config ?? EnvironmentConfig.current;

  /// Stream of real-time sync events from server
  Stream<Map<String, dynamic>> get eventStream => _controller.stream;

  /// Initialize and connect to the WebSocket server
  Future<void> connect({required String jwtToken}) async {
    if (_isConnecting || _webSocket != null) return;
    _isConnecting = true;
    _shouldReconnect = true;

    // Convert HTTP to WS url scheme
    final apiBase = _config.apiBaseUrl;
    final wsBase = apiBase.startsWith('https')
        ? apiBase.replaceAll('https', 'wss')
        : apiBase.replaceAll('http', 'ws');

    final wsUrl = '$wsBase${_config.releaseEndpoint.replaceAll('releases', 'analytics')}/live?token=$jwtToken';

    try {
      debugPrint('[AnalyticsWS] Connecting to $wsUrl');
      _webSocket = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 10));
      _isConnecting = false;
      _reconnectDelaySeconds = 2; // Reset delay
      debugPrint('[AnalyticsWS] Connected successfully');

      _webSocket!.listen(
        (message) {
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            _controller.add(data);
          } catch (e) {
            debugPrint('[AnalyticsWS] Failed parsing message: $e');
          }
        },
        onDone: () {
          debugPrint('[AnalyticsWS] Connection closed by remote host');
          _handleDisconnect(jwtToken);
        },
        onError: (err) {
          debugPrint('[AnalyticsWS] WebSocket error: $err');
          _handleDisconnect(jwtToken);
        },
        cancelOnError: true,
      );
    } catch (e) {
      _isConnecting = false;
      debugPrint('[AnalyticsWS] Connection failed: $e');
      _handleDisconnect(jwtToken);
    }
  }

  void _handleDisconnect(String jwtToken) {
    _webSocket = null;
    if (!_shouldReconnect) return;

    _reconnectTimer?.cancel();
    debugPrint('[AnalyticsWS] Scheduling reconnect in $_reconnectDelaySeconds seconds...');
    
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelaySeconds), () {
      if (_reconnectDelaySeconds < 64) {
        _reconnectDelaySeconds *= 2; // Exponential backoff
      }
      connect(jwtToken: jwtToken);
    });
  }

  /// Close connection and stop auto-reconnection
  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _webSocket?.close();
    _webSocket = null;
    debugPrint('[AnalyticsWS] Disconnected manually');
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
