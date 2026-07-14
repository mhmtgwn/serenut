import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketManager {
  String? _url;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  int _reconnectDelaySec = 1;
  int _reconnectAttempts = 0;
  bool _isManuallyClosed = false;

  final _messageController = StreamController<String>.broadcast();
  final _stateController = StreamController<bool>.broadcast();

  // Offline message queue
  final List<String> _offlineQueue = [];

  Stream<String> get messages => _messageController.stream;
  Stream<bool> get connectionState => _stateController.stream;

  bool get isConnected => _channel != null;
  int get reconnectAttempts => _reconnectAttempts;

  void connect(String url) {
    _url = url;
    _isManuallyClosed = false;
    _reconnectTimer?.cancel();
    disconnect();

    // Append current reconnect attempts to the URL for server metrics upgrade
    final finalUrl = url.contains('?')
        ? '$url&reconnectCount=$_reconnectAttempts'
        : '$url?reconnectCount=$_reconnectAttempts';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(finalUrl));

      // Catch connection handshake errors on the ready future to prevent unhandled exceptions
      _channel!.ready.then((_) {
        _stateController.add(true);
        _reconnectDelaySec = 1; // Reset delay on successful handshake
      }).catchError((err) {
        _stateController.add(false);
        _handleConnectionFailure();
      });

      _subscription = _channel!.stream.listen(
        (data) {
          _messageController.add(data.toString());
        },
        onError: (err) {
          _handleConnectionFailure();
        },
        onDone: () {
          _handleConnectionFailure();
        },
        cancelOnError: true,
      );

      // Start ping/pong heartbeat interval (30 seconds)
      _startHeartbeat();
      _flushOfflineQueue();
    } catch (_) {
      _handleConnectionFailure();
    }
  }

  void _handleConnectionFailure() {
    _stateController.add(false);
    disconnect();

    if (_isManuallyClosed) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelaySec), () {
      _reconnectAttempts++;
      // Exponential backoff up to 60s
      _reconnectDelaySec = (_reconnectDelaySec * 2).clamp(1, 60);
      if (_url != null) {
        connect(_url!);
      }
    });
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (isConnected) {
        send('{"action":"ping"}');
      } else {
        timer.cancel();
      }
    });
  }

  void _flushOfflineQueue() {
    if (_offlineQueue.isEmpty) return;
    final messagesToSend = List<String>.from(_offlineQueue);
    _offlineQueue.clear();
    for (final msg in messagesToSend) {
      send(msg);
    }
  }

  void send(String data) {
    if (_channel != null) {
      try {
        _channel!.sink.add(data);
      } catch (_) {
        _offlineQueue.add(data);
      }
    } else {
      _offlineQueue.add(data);
    }
  }

  void disconnect() {
    _pingTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  void close() {
    _isManuallyClosed = true;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    disconnect();
  }

  void dispose() {
    close();
    _messageController.close();
    _stateController.close();
  }
}
