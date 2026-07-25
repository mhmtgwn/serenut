enum SocketConnectionState {
  disconnected,
  connecting,
  connected,
  degraded,
  retrying,
}

class SocketConnectionStateMachine {
  SocketConnectionState _currentState = SocketConnectionState.disconnected;

  SocketConnectionState get currentState => _currentState;

  final List<void Function(SocketConnectionState newState)> _listeners = [];

  void addListener(void Function(SocketConnectionState newState) listener) {
    _listeners.add(listener);
  }

  void transitionTo(SocketConnectionState newState) {
    if (_currentState == newState) return;
    _currentState = newState;
    for (final listener in _listeners) {
      listener(newState);
    }
  }
}
