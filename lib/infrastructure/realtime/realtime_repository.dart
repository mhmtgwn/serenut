// lib/infrastructure/realtime/realtime_repository.dart
// High-level data access repository for realtime events

import 'dart:async';
import 'package:serenutos/domain/realtime/realtime_event.dart';
import 'package:serenutos/domain/realtime/event_dispatcher.dart';
import 'package:serenutos/infrastructure/realtime/connection_manager.dart';

class RealtimeRepository {
  final ConnectionManager _connectionManager;
  final EventDispatcher _eventDispatcher;

  const RealtimeRepository({
    required ConnectionManager connectionManager,
    required EventDispatcher eventDispatcher,
  })  : _connectionManager = connectionManager,
        _eventDispatcher = eventDispatcher;

  /// Subscribe to a topic category (e.g. orders, inventory, notifications)
  /// Automatically registers subscription on connection and returns a filtered event stream.
  Stream<RealtimeEvent> subscribeToTopic(String companyId, String category) {
    final topic = 'tenant/$companyId/$category';

    // Register subscription in connection manager
    _connectionManager.subscribe(topic);

    return _eventDispatcher.onTopic(category);
  }

  /// Unsubscribe from a topic category
  void unsubscribeFromTopic(String companyId, String category) {
    final topic = 'tenant/$companyId/$category';
    _connectionManager.unsubscribe(topic);
  }

  /// Expose a stream of all events
  Stream<RealtimeEvent> get allEvents => _eventDispatcher.allEvents;
}
