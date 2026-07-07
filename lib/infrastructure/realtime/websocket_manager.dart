// lib/infrastructure/realtime/websocket_manager.dart
// Low-level socket manager wrapping web_socket_channel

import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketManager {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final _messageController = StreamController<String>.broadcast();
  final _stateController = StreamController<bool>.broadcast();

  Stream<String> get messages => _messageController.stream;
  Stream<bool> get connectionState => _stateController.stream;

  bool get isConnected => _channel != null;

  void connect(String url) {
    disconnect();
    
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      
      _subscription = _channel!.stream.listen(
        (data) {
          _stateController.add(true);
          _messageController.add(data.toString());
        },
        onError: (err) {
          _stateController.add(false);
          disconnect();
        },
        onDone: () {
          _stateController.add(false);
          disconnect();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _stateController.add(false);
      disconnect();
    }
  }

  void send(String data) {
    if (_channel != null) {
      _channel!.sink.add(data);
    }
  }

  void disconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _stateController.close();
  }
}
