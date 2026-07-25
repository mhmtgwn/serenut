import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/sync_v2/local/sync_v2_schema.dart';
import 'package:serenutos/infrastructure/sync_v2/local/outbox_dao.dart';
import 'package:serenutos/infrastructure/sync_v2/local/inbox_dao.dart';
import 'package:serenutos/infrastructure/sync_v2/local/sync_state_dao.dart';
import 'package:serenutos/infrastructure/sync_v2/engine/sync_event_bus.dart';
import 'package:serenutos/infrastructure/sync_v2/engine/sync_engine_state_machine.dart';
import 'package:serenutos/infrastructure/sync_v2/engine/retry_manager.dart';
import 'package:serenutos/infrastructure/sync_v2/engine/metrics_collector.dart';
import 'package:serenutos/infrastructure/sync_v2/engine/push_manager.dart';
import 'package:serenutos/infrastructure/sync_v2/engine/pull_manager.dart';
import 'package:serenutos/infrastructure/sync_v2/engine/priority_queue_scheduler.dart';
import 'package:serenutos/infrastructure/sync_v2/engine/sync_engine.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late OutboxDao outboxDao;
  late InboxDao inboxDao;
  late SyncStateDao syncStateDao;
  late SyncEventBus eventBus;
  late SyncEngineStateMachine stateMachine;
  late RetryManager retryManager;
  late SyncMetricsCollector metrics;
  late PushManager pushManager;
  late PullManager pullManager;
  late PriorityQueueScheduler scheduler;
  late SyncEngineV2 syncEngine;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await SyncV2Schema.createTables(db);

    outboxDao = OutboxDao(db);
    inboxDao = InboxDao(db);
    syncStateDao = SyncStateDao(db);

    eventBus = SyncEventBus();
    stateMachine = SyncEngineStateMachine();
    retryManager = RetryManager();
    metrics = SyncMetricsCollector();

    pushManager = PushManager(
      outboxDao: outboxDao,
      serverBaseUrl: 'http://localhost:4002',
      authToken: 'test_token',
      metrics: metrics,
    );

    pullManager = PullManager(
      db: db,
      syncStateDao: syncStateDao,
      inboxDao: inboxDao,
      serverBaseUrl: 'http://localhost:4002',
      authToken: 'test_token',
      metrics: metrics,
    );

    scheduler = PriorityQueueScheduler(
      eventBus: eventBus,
      stateMachine: stateMachine,
      pushManager: pushManager,
      pullManager: pullManager,
      retryManager: retryManager,
      metrics: metrics,
    );

    syncEngine = SyncEngineV2(
      eventBus: eventBus,
      stateMachine: stateMachine,
      pushManager: pushManager,
      pullManager: pullManager,
      retryManager: retryManager,
      metrics: metrics,
      scheduler: scheduler,
      tenantId: 'comp_test',
    );
  });

  tearDown(() {
    syncEngine.stop();
    db.close();
  });

  group('Faz 5 Sync Engine Subsystems Verification Test Suite', () {
    test('1. Runtime State Machine Transitions & Invalid Transition Guard', () {
      expect(stateMachine.currentState, equals(SyncState.idle));

      stateMachine.transitionTo(SyncState.pushing);
      expect(stateMachine.currentState, equals(SyncState.pushing));

      stateMachine.transitionTo(SyncState.offline);
      expect(stateMachine.currentState, equals(SyncState.offline));

      // Assert invalid transition (offline -> pushing directly) throws StateError
      expect(
        () => stateMachine.transitionTo(SyncState.pushing),
        throwsA(isA<StateError>()),
      );
    });

    test('2. Exponential Backoff & Full Jitter Calculation', () {
      final delay1 = retryManager.getNextBackoffDelayMs();
      expect(delay1, lessThanOrEqualTo(1000));
      expect(retryManager.attempts, equals(1));

      final delay2 = retryManager.getNextBackoffDelayMs();
      expect(delay2, lessThanOrEqualTo(2000));
      expect(retryManager.attempts, equals(2));

      retryManager.reset();
      expect(retryManager.attempts, equals(0));
    });

    test('3. EventBus Event Emission & Subscription', () async {
      final completer = Completer<OutboxCreatedEvent>();
      eventBus.on<OutboxCreatedEvent>().listen((event) {
        completer.complete(event);
      });

      syncEngine.notifyOutboxCreated('mut_evt_1', priority: 0);

      final receivedEvent = await completer.future;
      expect(receivedEvent.clientMutationId, equals('mut_evt_1'));
      expect(receivedEvent.priority, equals(0));
    });

    test('4. Telemetry Metrics Collector', () {
      metrics.recordPush();
      metrics.recordPull();
      metrics.recordRetry();
      metrics.updateQueueDepth(5);

      final json = metrics.toJson();
      expect(json['push_count'], equals(1));
      expect(json['pull_count'], equals(1));
      expect(json['retry_count'], equals(1));
      expect(json['queue_depth'], equals(5));
    });
  });
}
