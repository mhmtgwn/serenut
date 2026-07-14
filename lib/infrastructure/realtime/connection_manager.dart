// lib/infrastructure/realtime/connection_manager.dart
// Central coordinator of the real-time websocket client

import 'dart:async';
import 'package:serenutos/domain/realtime/realtime_status.dart';
import 'package:serenutos/domain/realtime/realtime_message.dart';
import 'package:serenutos/domain/realtime/event_parser.dart';
import 'package:serenutos/domain/realtime/event_dispatcher.dart';
import 'package:serenutos/infrastructure/realtime/websocket_manager.dart';
import 'package:serenutos/infrastructure/realtime/heartbeat_manager.dart';
import 'package:serenutos/infrastructure/realtime/reconnect_manager.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

class ConnectionManager {
  final WebSocketManager wsManager;
  final ReconnectManager reconnectManager;
  final EventDispatcher eventDispatcher;
  final AuthService authService;
  final String wsBaseUrl;
  final void Function(RealtimeStatus status) onStatusChanged;

  late final HeartbeatManager heartbeatManager;

  RealtimeStatus _status = RealtimeStatus.disconnected;
  RealtimeStatus get status => _status;

  final Set<String> _activeSubscriptions = {};
  StreamSubscription? _msgSubscription;
  StreamSubscription? _stateSubscription;
  Timer? _reconnectTimer;
  bool _explicitClose = false;

  ConnectionManager({
    required this.wsManager,
    required this.reconnectManager,
    required this.eventDispatcher,
    required this.authService,
    required this.wsBaseUrl,
    required this.onStatusChanged,
  }) {
    heartbeatManager = HeartbeatManager(
      onPing: () {
        wsManager.send(const RealtimeMessage(action: 'ping').toJson());
      },
      onTimeout: () {
        _handleDisconnect();
      },
    );

    _msgSubscription = wsManager.messages.listen(_onRawMessageReceived);
    _stateSubscription = wsManager.connectionState.listen((connected) {
      if (connected) {
        _handleConnect();
      } else {
        _handleDisconnect();
      }
    });
  }

  void _setStatus(RealtimeStatus status) {
    _status = status;
    onStatusChanged(status);
  }

  Future<void> connect() async {
    _explicitClose = false;
    if (_status == RealtimeStatus.connected ||
        _status == RealtimeStatus.connecting ||
        _status == RealtimeStatus.reconnecting) {
      return;
    }

    if (_reconnectTimer != null) {
      _reconnectTimer!.cancel();
      _reconnectTimer = null;
    }

    _setStatus(reconnectManager.attempts > 0
        ? RealtimeStatus.reconnecting
        : RealtimeStatus.connecting);

    try {
      final user = await authService.getCurrentUser();
      if (user == null) {
        _setStatus(RealtimeStatus.disconnected);
        return;
      }

      String? token = authService.getJwtToken();
      if (token == null) {
        final refreshed = await authService.refreshToken();
        if (refreshed) {
          token = authService.getJwtToken();
        }
      }

      if (token == null) {
        _setStatus(RealtimeStatus.disconnected);
        authService.triggerSessionExpired();
        return;
      }

      final uri = Uri.parse(wsBaseUrl);
      final wsUrlWithParams = uri.replace(queryParameters: {
        'token': token,
        'reconnectCount': reconnectManager.attempts.toString(),
      }).toString();

      wsManager.connect(wsUrlWithParams);
    } catch (e) {
      _setStatus(RealtimeStatus.disconnected);
      if (e is ApiException &&
          (e.statusCode == 400 || e.statusCode == 401 || e.statusCode == 403)) {
        authService.triggerSessionExpired();
      } else {
        _scheduleReconnect();
      }
    }
  }

  void subscribe(String topic) {
    _activeSubscriptions.add(topic);
    if (_status == RealtimeStatus.connected) {
      final msg = RealtimeMessage(
        action: 'subscribe',
        topic: topic,
        correlationId: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      wsManager.send(msg.toJson());
    }
  }

  void unsubscribe(String topic) {
    _activeSubscriptions.remove(topic);
    if (_status == RealtimeStatus.connected) {
      final msg = RealtimeMessage(
        action: 'unsubscribe',
        topic: topic,
        correlationId: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      wsManager.send(msg.toJson());
    }
  }

  void disconnect() {
    _explicitClose = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    heartbeatManager.stop();
    wsManager.disconnect();
    reconnectManager.reset();
    _setStatus(RealtimeStatus.disconnected);
  }

  void _handleConnect() {
    reconnectManager.reset();
    _setStatus(RealtimeStatus.connected);
    heartbeatManager.start();

    // Re-subscribe to all active topics
    for (final topic in _activeSubscriptions) {
      final msg = RealtimeMessage(
        action: 'subscribe',
        topic: topic,
        correlationId: 're-sub-${DateTime.now().millisecondsSinceEpoch}',
      );
      wsManager.send(msg.toJson());
    }
  }

  void _handleDisconnect() {
    heartbeatManager.stop();
    wsManager.disconnect();

    if (_explicitClose) {
      _setStatus(RealtimeStatus.disconnected);
      return;
    }

    _setStatus(RealtimeStatus.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    reconnectManager.incrementAttempt();
    final delay = reconnectManager.getNextDelay();

    _setStatus(RealtimeStatus.reconnecting);

    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      try {
        final refreshed = await authService.refreshToken();
        if (!refreshed) {
          // Permanent auth error (invalid/expired refresh token, session revoked, replay attack)
          // Set status and trigger immediate session expired redirect to login page.
          _setStatus(RealtimeStatus.disconnected);
          authService.triggerSessionExpired();
          return;
        }

        // Reset status to disconnected temporarily so connect() isn't filtered out
        if (_status == RealtimeStatus.reconnecting) {
          _status = RealtimeStatus.disconnected;
        }

        connect();
      } catch (e) {
        // Temporary network / connection error (timeout, SocketException, offline)
        // Keep attempting reconnection. We do not abort the reconnect loop.
        _setStatus(RealtimeStatus.disconnected);
        _scheduleReconnect();
      }
    });
  }

  void _onRawMessageReceived(String raw) {
    final msg = EventParser.parseRawMessage(raw);
    if (msg == null) return;

    if (msg.action == 'pong') {
      heartbeatManager.receivedPong();
    } else if (msg.event != null) {
      final event = EventParser.parseEvent(raw);
      if (event != null) {
        eventDispatcher.dispatch(event);
      }
    }
  }

  void dispose() {
    _msgSubscription?.cancel();
    _stateSubscription?.cancel();
    _reconnectTimer?.cancel();
    heartbeatManager.stop();
    wsManager.dispose();
  }
}
