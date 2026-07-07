// lib/infrastructure/realtime/heartbeat_manager.dart
// Schedules heartbeats and detects network dropouts

import 'dart:async';

class HeartbeatManager {
  final Duration interval;
  final Duration timeout;
  final void Function() onPing;
  final void Function() onTimeout;

  Timer? _pingTimer;
  Timer? _timeoutTimer;
  bool _pongReceived = true;

  HeartbeatManager({
    this.interval = const Duration(seconds: 30),
    this.timeout = const Duration(seconds: 10),
    required this.onPing,
    required this.onTimeout,
  });

  void start() {
    stop();
    _pongReceived = true;
    _pingTimer = Timer.periodic(interval, (_) => _sendPing());
  }

  void stop() {
    _pingTimer?.cancel();
    _timeoutTimer?.cancel();
    _pingTimer = null;
    _timeoutTimer = null;
  }

  void receivedPong() {
    _pongReceived = true;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  void _sendPing() {
    if (!_pongReceived) {
      onTimeout();
      return;
    }

    _pongReceived = false;
    onPing();

    _timeoutTimer = Timer(timeout, () {
      if (!_pongReceived) {
        onTimeout();
      }
    });
  }
}
