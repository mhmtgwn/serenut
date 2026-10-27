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

  AnalyticsWsService({EnvironmentConfig? config})
      : _config = config ?? EnvironmentConfig.current;

  /// Stream of real-time sync events from server
  Stream<Map<String, dynamic>> get eventStream => _controller.stream;

  /// Initialize and connect to the WebSocket server (Deprecated - Realtime sync is handled by RealtimeWebSocket)
  Future<void> connect({required String jwtToken}) async {
    // Deprecated: Dead analytics socket decommissioned in favor of RealtimeWebSocket
    _isConnecting = false;
    _shouldReconnect = false;
  }

  void _handleDisconnect(String jwtToken) {
    _webSocket = null;
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
  }

  /// Close connection and stop auto-reconnection
  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _webSocket?.close();
    _webSocket = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
