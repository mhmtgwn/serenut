import 'dart:math';

class RetryManager {
  final int baseDelayMs;
  final int maxDelayMs;
  final int maxAttempts;

  int _attempts = 0;
  final Random _random = Random();

  RetryManager({
    this.baseDelayMs = 1000,
    this.maxDelayMs = 30000,
    this.maxAttempts = 10,
  });

  int get attempts => _attempts;

  /// Calculates next sleep duration using Full Jitter Exponential Backoff.
  int getNextBackoffDelayMs() {
    if (_attempts >= maxAttempts) {
      return maxDelayMs;
    }

    final exponentialDelay = baseDelayMs * pow(2, _attempts).toInt();
    final cappedDelay = min(maxDelayMs, exponentialDelay);
    
    // Full Jitter Formula: random(0, cappedDelay)
    final jitteredDelay = _random.nextInt(cappedDelay + 1);
    _attempts++;
    return jitteredDelay;
  }

  void reset() {
    _attempts = 0;
  }

  bool get shouldStop => _attempts >= maxAttempts;
}
