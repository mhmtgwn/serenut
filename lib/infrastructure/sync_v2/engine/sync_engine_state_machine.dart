enum SyncState {
  offline,
  idle,
  pushing,
  pulling,
  synced,
  retrying,
  error,
}

class SyncEngineStateMachine {
  SyncState _currentState = SyncState.idle;

  SyncState get currentState => _currentState;

  final List<void Function(SyncState newState, SyncState oldState)> _listeners = [];

  void addListener(void Function(SyncState newState, SyncState oldState) listener) {
    _listeners.add(listener);
  }

  bool canTransitionTo(SyncState newState) {
    if (_currentState == newState) return true;

    switch (_currentState) {
      case SyncState.offline:
        return newState == SyncState.idle || newState == SyncState.retrying;
      case SyncState.idle:
        return newState == SyncState.pushing ||
            newState == SyncState.pulling ||
            newState == SyncState.offline ||
            newState == SyncState.synced;
      case SyncState.pushing:
        return newState == SyncState.idle ||
            newState == SyncState.pulling ||
            newState == SyncState.synced ||
            newState == SyncState.retrying ||
            newState == SyncState.error ||
            newState == SyncState.offline;
      case SyncState.pulling:
        return newState == SyncState.idle ||
            newState == SyncState.synced ||
            newState == SyncState.retrying ||
            newState == SyncState.error ||
            newState == SyncState.offline;
      case SyncState.synced:
        return newState == SyncState.idle ||
            newState == SyncState.pushing ||
            newState == SyncState.pulling ||
            newState == SyncState.offline;
      case SyncState.retrying:
        return newState == SyncState.pushing ||
            newState == SyncState.pulling ||
            newState == SyncState.idle ||
            newState == SyncState.offline;
      case SyncState.error:
        return newState == SyncState.idle || newState == SyncState.retrying || newState == SyncState.offline;
    }
  }

  void transitionTo(SyncState newState) {
    if (!canTransitionTo(newState)) {
      throw StateError(
        '🚨 INVALID SYNC ENGINE STATE TRANSITION: Cannot transition from $_currentState to $newState',
      );
    }

    final oldState = _currentState;
    _currentState = newState;

    for (final listener in _listeners) {
      listener(newState, oldState);
    }
  }
}
