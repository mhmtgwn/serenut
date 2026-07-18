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
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/infrastructure/services/telemetry_upload_service.dart';

class ConnectionManager {
  final WebSocketManager wsManager;
  final ReconnectManager reconnectManager;
  final EventDispatcher eventDispatcher;
  final AuthService authService;
  final String wsBaseUrl;
  final void Function(RealtimeStatus status) onStatusChanged;
  final TelemetryUploadService? telemetryUpload;

  late final HeartbeatManager heartbeatManager;

  RealtimeStatus _status = RealtimeStatus.disconnected;
  RealtimeStatus get status => _status;

  final Set<String> _activeSubscriptions = {};
  StreamSubscription? _msgSubscription;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _eventSubscription;
  Timer? _reconnectTimer;
  bool _explicitClose = false;
  final String _connectionSessionId =
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  ConnectionManager({
    required this.wsManager,
    required this.reconnectManager,
    required this.eventDispatcher,
    required this.authService,
    required this.wsBaseUrl,
    required this.onStatusChanged,
    this.telemetryUpload,
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
    _eventSubscription = wsManager.connectionEvents.listen(_onConnectionEvent);
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
    _record('ws_connect_started', value: reconnectManager.attempts.toDouble());

    try {
      final user = await authService.getCurrentUser();
      if (user == null) {
        _record('ws_connect_skipped_no_user', level: LogLevel.warning);
        _setStatus(RealtimeStatus.disconnected);
        return;
      }

      String? token = authService.getJwtToken();
      if (token == null) {
        _record('ws_auth_token_unavailable', level: LogLevel.error);
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
      _record('ws_connect_exception', level: LogLevel.error, error: e);
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
    _record('ws_connected');
    final uploader = telemetryUpload;
    if (uploader != null) unawaited(uploader.uploadMetricsBatch());

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
    _record('ws_disconnected', level: LogLevel.warning);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    reconnectManager.incrementAttempt();
    final delay = reconnectManager.getNextDelay();
    _record(
      'ws_reconnect_scheduled',
      value: reconnectManager.attempts.toDouble(),
      extra: {'delay_ms': delay.inMilliseconds},
    );

    _setStatus(RealtimeStatus.reconnecting);

    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      try {
        final refreshed = await authService.refreshToken();
        if (!refreshed) {
          _record('ws_refresh_rejected', level: LogLevel.error);
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
        _record('ws_refresh_exception', level: LogLevel.warning, error: e);
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

  void _onConnectionEvent(WebSocketConnectionEvent event) {
    _record(
      'ws_${event.type}',
      level: event.type.contains('failed') ? LogLevel.warning : LogLevel.info,
      error: event.error,
      extra: {
        if (event.closeCode != null) 'close_code': event.closeCode,
        if (event.closeReason != null) 'close_reason': event.closeReason,
      },
    );
  }

  void _record(
    String event, {
    LogLevel level = LogLevel.info,
    double value = 1,
    Object? error,
    Map<String, dynamic>? extra,
  }) {
    final safeError = error == null ? null : _redactSecrets(error.toString());
    final metadata = <String, dynamic>{
      'attempt': reconnectManager.attempts,
      'status': _status.name,
      'connection_session_id': _connectionSessionId,
      if (error != null) 'error_type': error.runtimeType.toString(),
      if (safeError != null) 'error_message': safeError,
      ...?extra,
    };
    unawaited(TelemetryService()
        .logStructured(event: event, level: level, metadata: metadata));
    final uploader = telemetryUpload;
    if (uploader != null) {
      unawaited(uploader.recordMetric(event, value, metadata: metadata));
    }
  }

  String _redactSecrets(String value) {
    return value
        .replaceAllMapped(RegExp(r'([?&]token=)[^&\s]+', caseSensitive: false),
            (match) => '${match.group(1)}[REDACTED]')
        .replaceAll(RegExp(r'Bearer\s+[^\s]+', caseSensitive: false),
            'Bearer [REDACTED]')
        .replaceAll(
            RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
            '[JWT_REDACTED]');
  }

  void dispose() {
    _msgSubscription?.cancel();
    _stateSubscription?.cancel();
    _eventSubscription?.cancel();
    _reconnectTimer?.cancel();
    heartbeatManager.stop();
    wsManager.dispose();
  }
}
