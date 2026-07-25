import 'dart:async';

abstract class SyncEngineEvent {
  final int timestamp;
  SyncEngineEvent() : timestamp = DateTime.now().millisecondsSinceEpoch;
}

class OutboxCreatedEvent extends SyncEngineEvent {
  final String clientMutationId;
  final int priority;
  OutboxCreatedEvent({required this.clientMutationId, required this.priority});
}

class RevisionInvalidatedEvent extends SyncEngineEvent {
  final String tenantId;
  final int headRevision;
  RevisionInvalidatedEvent({required this.tenantId, required this.headRevision});
}

class NetworkStatusChangedEvent extends SyncEngineEvent {
  final bool isConnected;
  NetworkStatusChangedEvent({required this.isConnected});
}

class AppLifecycleChangedEvent extends SyncEngineEvent {
  final bool isForeground;
  AppLifecycleChangedEvent({required this.isForeground});
}

class PeriodicTickEvent extends SyncEngineEvent {}

class SyncEventBus {
  final _controller = StreamController<SyncEngineEvent>.broadcast();

  Stream<SyncEngineEvent> get stream => _controller.stream;

  void publish(SyncEngineEvent event) {
    _controller.add(event);
  }

  Stream<T> on<T extends SyncEngineEvent>() {
    return _controller.stream.where((e) => e is T).cast<T>();
  }

  void dispose() {
    _controller.close();
  }
}
