import 'dart:async';
import 'sync_event_bus.dart';
import 'sync_engine_state_machine.dart';
import 'push_manager.dart';
import 'pull_manager.dart';
import 'retry_manager.dart';
import 'metrics_collector.dart';

class PriorityQueueScheduler {
  final SyncEventBus eventBus;
  final SyncEngineStateMachine stateMachine;
  final PushManager pushManager;
  final PullManager pullManager;
  final RetryManager retryManager;
  final SyncMetricsCollector metrics;

  bool _isNetworkOnline = true;
  bool _isForeground = true;
  bool _isPushRunning = false;
  bool _isPullRunning = false;

  StreamSubscription? _eventSubscription;

  PriorityQueueScheduler({
    required this.eventBus,
    required this.stateMachine,
    required this.pushManager,
    required this.pullManager,
    required this.retryManager,
    required this.metrics,
  });

  void startListening(String tenantId) {
    _eventSubscription = eventBus.stream.listen((event) {
      _handleEvent(event, tenantId);
    });
  }

  void _handleEvent(SyncEngineEvent event, String tenantId) {
    if (event is NetworkStatusChangedEvent) {
      _isNetworkOnline = event.isConnected;
      if (!_isNetworkOnline) {
        stateMachine.transitionTo(SyncState.offline);
        return;
      } else if (stateMachine.currentState == SyncState.offline) {
        stateMachine.transitionTo(SyncState.idle);
      }
    }

    if (event is AppLifecycleChangedEvent) {
      _isForeground = event.isForeground;
    }

    if (!_isNetworkOnline) return;

    if (event is OutboxCreatedEvent) {
      // If P0 Critical item enqueued, trigger push immediately
      if (event.priority == 0) {
        schedulePushTask();
      } else {
        schedulePushTask();
      }
    } else if (event is RevisionInvalidatedEvent) {
      schedulePullTask(tenantId);
    } else if (event is PeriodicTickEvent && _isForeground) {
      schedulePushTask();
      schedulePullTask(tenantId);
    }
  }

  Future<void> schedulePushTask() async {
    if (_isPushRunning || !_isNetworkOnline) return;
    _isPushRunning = true;

    try {
      if (stateMachine.canTransitionTo(SyncState.pushing)) {
        stateMachine.transitionTo(SyncState.pushing);
      }

      final success = await pushManager.executePushBatch();
      if (success) {
        retryManager.reset();
        if (stateMachine.canTransitionTo(SyncState.synced)) {
          stateMachine.transitionTo(SyncState.synced);
        }
      } else {
        metrics.recordRetry();
        if (stateMachine.canTransitionTo(SyncState.retrying)) {
          stateMachine.transitionTo(SyncState.retrying);
        }
      }
    } catch (e) {
      if (stateMachine.canTransitionTo(SyncState.error)) {
        stateMachine.transitionTo(SyncState.error);
      }
    } finally {
      _isPushRunning = false;
      if (stateMachine.canTransitionTo(SyncState.idle)) {
        stateMachine.transitionTo(SyncState.idle);
      }
    }
  }

  Future<void> schedulePullTask(String tenantId) async {
    if (_isPullRunning || !_isNetworkOnline) return;
    _isPullRunning = true;

    try {
      if (stateMachine.canTransitionTo(SyncState.pulling)) {
        stateMachine.transitionTo(SyncState.pulling);
      }

      final success = await pullManager.executeDeltaPull(tenantId);
      if (success) {
        retryManager.reset();
        if (stateMachine.canTransitionTo(SyncState.synced)) {
          stateMachine.transitionTo(SyncState.synced);
        }
      }
    } catch (e) {
      if (stateMachine.canTransitionTo(SyncState.error)) {
        stateMachine.transitionTo(SyncState.error);
      }
    } finally {
      _isPullRunning = false;
      if (stateMachine.canTransitionTo(SyncState.idle)) {
        stateMachine.transitionTo(SyncState.idle);
      }
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
  }
}
