// lib/providers/realtime/realtime_provider.dart
// Riverpod DI and Stream Providers for Realtime event channels

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/realtime/realtime_event.dart';
import 'package:serenutos/domain/realtime/realtime_status.dart';
import 'package:serenutos/domain/realtime/event_dispatcher.dart';
import 'package:serenutos/infrastructure/realtime/websocket_manager.dart';
import 'package:serenutos/infrastructure/realtime/reconnect_manager.dart';
import 'package:serenutos/infrastructure/realtime/connection_manager.dart';
import 'package:serenutos/infrastructure/realtime/realtime_repository.dart';
import 'package:serenutos/providers/realtime/connection_state_notifier.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/config/environment.dart';

final eventDispatcherProvider = Provider<EventDispatcher>((ref) {
  final dispatcher = EventDispatcher();
  ref.onDispose(() => dispatcher.dispose());
  return dispatcher;
});

final websocketManagerProvider = Provider<WebSocketManager>((ref) {
  final ws = WebSocketManager();
  ref.onDispose(() => ws.dispose());
  return ws;
});

final reconnectManagerProvider =
    Provider<ReconnectManager>((ref) => ReconnectManager());

final connectionStateProvider =
    StateNotifierProvider<ConnectionStateNotifier, RealtimeStatus>((ref) {
  return ConnectionStateNotifier();
});

final connectionManagerProvider = Provider<ConnectionManager>((ref) {
  final wsManager = ref.watch(websocketManagerProvider);
  final reconnectManager = ref.watch(reconnectManagerProvider);
  final eventDispatcher = ref.watch(eventDispatcherProvider);
  final authService = ref.watch(authServiceProvider);
  final notifier = ref.read(connectionStateProvider.notifier);

  final conn = ConnectionManager(
    wsManager: wsManager,
    reconnectManager: reconnectManager,
    eventDispatcher: eventDispatcher,
    authService: authService,
    wsBaseUrl: EnvironmentConfig.current.wsBaseUrl,
    onStatusChanged: (status) {
      notifier.updateStatus(status);
    },
  );

  ref.onDispose(() => conn.dispose());
  return conn;
});

final realtimeRepositoryProvider = Provider<RealtimeRepository>((ref) {
  final connectionManager = ref.watch(connectionManagerProvider);
  final eventDispatcher = ref.watch(eventDispatcherProvider);
  return RealtimeRepository(
    connectionManager: connectionManager,
    eventDispatcher: eventDispatcher,
  );
});

// Stream Provider for Order Events
final realtimeOrdersStreamProvider = StreamProvider<RealtimeEvent>((ref) {
  final repo = ref.watch(realtimeRepositoryProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) return const Stream.empty();

  // Trigger connect on subscription
  ref.read(connectionManagerProvider).connect();

  return repo.subscribeToTopic(user.companyId, 'orders');
});

// Stream Provider for Inventory/Stock/Price Events
final realtimeInventoryStreamProvider = StreamProvider<RealtimeEvent>((ref) {
  final repo = ref.watch(realtimeRepositoryProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) return const Stream.empty();

  ref.read(connectionManagerProvider).connect();

  return repo.subscribeToTopic(user.companyId, 'inventory');
});

// Stream Provider for Notification Events
final realtimeNotificationsStreamProvider =
    StreamProvider<RealtimeEvent>((ref) {
  final repo = ref.watch(realtimeRepositoryProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) return const Stream.empty();

  ref.read(connectionManagerProvider).connect();

  return repo.subscribeToTopic(user.companyId, 'notifications');
});
