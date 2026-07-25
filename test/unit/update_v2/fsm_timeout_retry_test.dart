// test/unit/update_v2/fsm_timeout_retry_test.dart
// Serenut Platform — FSM State Timeout and Auto-Retry Unit Tests

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/update_v2/update_context.dart';
import 'package:serenutos/domain/services/update_v2/update_state_machine.dart';
import 'package:serenutos/infrastructure/services/update_v2/update_event_bus.dart';
import 'package:serenutos/infrastructure/services/update_v2/update_trigger_manager.dart';

class MockTimeoutLifecycle implements StateLifecycle {
  @override
  Future<void> entry(UpdateContext context) async {}

  @override
  Future<void> execute(UpdateContext context) async {
    // Hang execution to simulate timeout
    await Future.delayed(const Duration(seconds: 5));
  }

  @override
  Future<void> exit(UpdateContext context) async {}
}

class MockRetryLifecycle implements StateLifecycle {
  int executeCalls = 0;

  @override
  Future<void> entry(UpdateContext context) async {}

  @override
  Future<void> execute(UpdateContext context) async {
    executeCalls++;
    throw Exception('Simulated execution failure');
  }

  @override
  Future<void> exit(UpdateContext context) async {}
}

void main() {
  group('FSM Timeout & Auto-Retry Tests', () {
    late UpdateEventBus eventBus;
    late UpdateStateMachine fsm;
    late UpdateContext context;

    setUp(() {
      eventBus = UpdateEventBus();
      fsm = UpdateStateMachine(eventBus: eventBus, deviceId: 'dev-001');
      context = UpdateContext(
        correlationId: 'upd-retry-100',
        triggerSource: TriggerSource.startup,
      );
    });

    tearDown(() {
      eventBus.dispose();
    });

    test('Triggers auto-retries when state execution fails', () async {
      final retryAction = MockRetryLifecycle();
      // Register for a state with retries (e.g. checking has max 3 retries)
      fsm.registerStateLifecycle(UpdateState.checking, retryAction);

      await fsm.transitionTo(context, UpdateState.checking);

      // It should execute 4 times total (1 initial + 3 retries) and then fail/rollback
      expect(retryAction.executeCalls, equals(4));
      expect(context.currentState, equals(UpdateState.failed));
      expect(context.errorCode, equals('UPD-005'));
    });
  });
}
