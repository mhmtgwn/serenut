import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketConnectionEvent {
  final String type;
  final Object? error;
  final int? closeCode;
  final String? closeReason;

  const WebSocketConnectionEvent(
    this.type, {
    this.error,
    this.closeCode,
    this.closeReason,
  });
}

/// Owns only one socket connection. Reconnect policy belongs exclusively to
/// ConnectionManager so one failure can never create competing retry loops.
class WebSocketManager {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _connected = false;
  bool _failureReported = false;

  final _messageController = StreamController<String>.broadcast();
  final _stateController = StreamController<bool>.broadcast();
  final _eventController =
      StreamController<WebSocketConnectionEvent>.broadcast();
  final List<String> _offlineQueue = [];

  Stream<String> get messages => _messageController.stream;
  Stream<bool> get connectionState => _stateController.stream;
  Stream<WebSocketConnectionEvent> get connectionEvents =>
      _eventController.stream;
  bool get isConnected => _connected;

  void connect(String url) {
    disconnect();
    _failureReported = false;
    _eventController.add(const WebSocketConnectionEvent('handshake_started'));

    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      channel.ready.then((_) {
        if (!identical(_channel, channel)) return;
        _connected = true;
        _eventController
            .add(const WebSocketConnectionEvent('handshake_succeeded'));
        _stateController.add(true);
        _flushOfflineQueue();
      }).catchError((Object error, StackTrace stackTrace) {
        if (identical(_channel, channel)) _reportFailure(channel, error);
      });

      _subscription = channel.stream.listen(
        (data) => _messageController.add(data.toString()),
        onError: (Object error, StackTrace stackTrace) =>
            _reportFailure(channel, error),
        onDone: () => _reportFailure(channel, null),
        cancelOnError: true,
      );
    } catch (error) {
      _reportFailure(null, error);
    }
  }

  void _reportFailure(WebSocketChannel? channel, Object? error) {
    if (_failureReported) return;
    _failureReported = true;
    final wasConnected = _connected;
    _connected = false;
    _eventController.add(WebSocketConnectionEvent(
      wasConnected ? 'connection_closed' : 'handshake_failed',
      error: error,
      closeCode: channel?.closeCode,
      closeReason: channel?.closeReason,
    ));
    _stateController.add(false);
  }

  void send(String data) {
    if (_connected && _channel != null) {
      try {
        _channel!.sink.add(data);
        return;
      } catch (_) {}
    }
    _offlineQueue.add(data);
  }

  void _flushOfflineQueue() {
    final queued = List<String>.from(_offlineQueue);
    _offlineQueue.clear();
    for (final message in queued) {
      send(message);
    }
  }

  void disconnect() {
    _connected = false;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _stateController.close();
    _eventController.close();
  }
}
