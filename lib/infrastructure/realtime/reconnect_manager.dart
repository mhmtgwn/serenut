// lib/infrastructure/realtime/reconnect_manager.dart
// Production-grade exponential backoff reconnect strategy with jitter

import 'dart:math';

class ReconnectManager {
  final Duration minDelay;
  final Duration maxDelay;
  final double backoffFactor;
  final double jitter;

  int _attempts = 0;

  ReconnectManager({
    this.minDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 60),
    this.backoffFactor = 2.0,
    this.jitter = 0.2,
  });

  int get attempts => _attempts;

  void reset() {
    _attempts = 0;
  }

  void incrementAttempt() {
    _attempts++;
  }

  Duration getNextDelay() {
    if (_attempts == 0) return Duration.zero;

    final tempDelayMs = minDelay.inMilliseconds * pow(backoffFactor, _attempts - 1);
    var delayMs = min(tempDelayMs.toDouble(), maxDelay.inMilliseconds.toDouble());

    if (jitter > 0) {
      final random = Random();
      final jitterRange = delayMs * jitter;
      final offset = (random.nextDouble() * 2 - 1) * jitterRange;
      delayMs += offset;
    }

    delayMs = max(delayMs, minDelay.inMilliseconds.toDouble());
    return Duration(milliseconds: delayMs.round());
  }
}
