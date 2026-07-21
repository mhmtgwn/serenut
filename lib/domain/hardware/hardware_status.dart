enum HardwareConnectionState {
  disconnected,
  connecting,
  connected,
  degraded,
  error,
}

class HardwareFailure implements Exception {
  final String code;
  final String message;
  final Object? cause;

  const HardwareFailure(this.code, this.message, {this.cause});

  @override
  String toString() => '$code: $message';
}
