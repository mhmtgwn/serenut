import 'dart:async';
import 'sync_event_bus.dart';
import 'sync_engine_state_machine.dart';
import 'push_manager.dart';
import 'pull_manager.dart';
import 'retry_manager.dart';
import 'metrics_collector.dart';
import 'priority_queue_scheduler.dart';

class SyncEngineV2 {
  final SyncEventBus eventBus;
  final SyncEngineStateMachine stateMachine;
  final PushManager pushManager;
  final PullManager pullManager;
  final RetryManager retryManager;
  final SyncMetricsCollector metrics;
  final PriorityQueueScheduler scheduler;
  final String tenantId;

  Timer? _periodicTimer;

  SyncEngineV2({
    required this.eventBus,
    required this.stateMachine,
    required this.pushManager,
    required this.pullManager,
    required this.retryManager,
    required this.metrics,
    required this.scheduler,
    required this.tenantId,
  });

  /// Starts the Sync Engine orchestrator.
  void start({int periodicIntervalSeconds = 30}) {
    scheduler.startListening(tenantId);

    // Start 30s periodic tick timer emitting event to Bus
    _periodicTimer = Timer.periodic(
      Duration(seconds: periodicIntervalSeconds),
      (_) {
        eventBus.publish(PeriodicTickEvent());
      },
    );
  }

  void notifyOutboxCreated(String clientMutationId, {int priority = 1}) {
    eventBus.publish(OutboxCreatedEvent(clientMutationId: clientMutationId, priority: priority));
  }

  void notifyRevisionInvalidated(String tenantId, int headRevision) {
    eventBus.publish(RevisionInvalidatedEvent(tenantId: tenantId, headRevision: headRevision));
  }

  void notifyNetworkStatusChanged(bool isConnected) {
    eventBus.publish(NetworkStatusChangedEvent(isConnected: isConnected));
  }

  void notifyAppLifecycleChanged(bool isForeground) {
    eventBus.publish(AppLifecycleChangedEvent(isForeground: isForeground));
  }

  void stop() {
    _periodicTimer?.cancel();
    scheduler.dispose();
    eventBus.dispose();
  }
}
