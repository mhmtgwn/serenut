import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'sync_event_bus.dart';
import 'socket_connection_state_machine.dart';

class RealtimeSignalClient {
  final String serverWsUrl;
  final String tenantId;
  final SyncEventBus eventBus;
  final SocketConnectionStateMachine stateMachine;

  WebSocket? _socket;
  Timer? _heartbeatTimer;
  bool _isDisposed = false;

  RealtimeSignalClient({
    required this.serverWsUrl,
    required this.tenantId,
    required this.eventBus,
    required this.stateMachine,
  });

  Future<void> connect() async {
    if (_isDisposed) return;
    stateMachine.transitionTo(SocketConnectionState.connecting);

    try {
      final base = serverWsUrl.replaceFirst(RegExp(r'/api(/v\d+)?/?$'), '');
      final uri = Uri.parse('$base/api/v2/sync/live?tenant_id=$tenantId');
      _socket = await WebSocket.connect(uri.toString());
      stateMachine.transitionTo(SocketConnectionState.connected);

      _startHeartbeat();

      _socket!.listen(
        (data) {
          _handleMessage(data);
        },
        onDone: () {
          _onDisconnected();
        },
        onError: (err) {
          _onDisconnected();
        },
      );
    } catch (e) {
      _onDisconnected();
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final json = jsonDecode(data.toString());
      if (json['type'] == 'REVISION_INVALIDATED') {
        final headRevision = (json['head_revision'] as num).toInt();

        // NO DATA PAYLOAD INSIDE SIGNAL! Publish event strictly to SyncEventBus
        eventBus.publish(RevisionInvalidatedEvent(
          tenantId: tenantId,
          headRevision: headRevision,
        ));
      }
    } catch (e) {
      // Ignore malformed signals
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_socket != null && _socket!.readyState == WebSocket.open) {
        _socket!.add(jsonEncode({'type': 'PING'}));
      }
    });
  }

  void _onDisconnected() {
    if (_isDisposed) return;
    _heartbeatTimer?.cancel();
    stateMachine.transitionTo(SocketConnectionState.disconnected);

    // Schedule reconnect after 5s
    Timer(const Duration(seconds: 5), () {
      if (!_isDisposed && stateMachine.currentState == SocketConnectionState.disconnected) {
        connect();
      }
    });
  }

  void dispose() {
    _isDisposed = true;
    _heartbeatTimer?.cancel();
    _socket?.close();
    stateMachine.transitionTo(SocketConnectionState.disconnected);
  }
}
