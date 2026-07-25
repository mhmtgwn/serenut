// test/unit/update_v2/update_fsm_test.dart
// Serenut Platform — Client State Machine & Guard Transition Tests

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/update_v2/update_context.dart';
import 'package:serenutos/domain/models/update_v2/update_telemetry_event.dart';
import 'package:serenutos/domain/services/update_v2/update_state_machine.dart';
import 'package:serenutos/infrastructure/services/update_v2/update_event_bus.dart';
import 'package:serenutos/infrastructure/services/update_v2/update_trigger_manager.dart';

class MockLifecycleAction implements StateLifecycle {
  bool entryCalled = false;
  bool executeCalled = false;
  bool exitCalled = false;

  @override
  Future<void> entry(UpdateContext context) async {
    entryCalled = true;
  }

  @override
  Future<void> execute(UpdateContext context) async {
    executeCalled = true;
  }

  @override
  Future<void> exit(UpdateContext context) async {
    exitCalled = true;
  }
}

void main() {
  group('UpdateStateMachine Transition Tests', () {
    late UpdateEventBus eventBus;
    late UpdateStateMachine fsm;
    late UpdateContext context;
    final List<UpdateTelemetryEvent> publishedEvents = [];

    setUp(() {
      eventBus = UpdateEventBus();
      publishedEvents.clear();
      eventBus.stream.listen((event) {
        publishedEvents.add(event);
      });

      fsm = UpdateStateMachine(eventBus: eventBus, deviceId: 'dev-001');
      context = UpdateContext(
        correlationId: 'upd-100',
        triggerSource: TriggerSource.startup,
      );
    });

    tearDown(() {
      eventBus.dispose();
    });

    test('Valid FSM state sequence runs successfully', () async {
      final checkingAction = MockLifecycleAction();
      fsm.registerStateLifecycle(UpdateState.checking, checkingAction);

      // Transition: Idle -> Checking
      await fsm.transitionTo(context, UpdateState.checking);
      expect(context.currentState, equals(UpdateState.checking));
      expect(checkingAction.entryCalled, isTrue);
      expect(checkingAction.executeCalled, isTrue);

      // Verify event was dispatched
      expect(publishedEvents.length, equals(1));
      expect(publishedEvents.first.eventType, equals(UpdateEventType.checkStarted));

      // Transition: Checking -> Precheck
      await fsm.transitionTo(context, UpdateState.precheck);
      expect(checkingAction.exitCalled, isTrue);
      expect(context.currentState, equals(UpdateState.precheck));
    });

    test('Blocks invalid/illegal transitions with InvalidStateTransitionException', () async {
      expect(context.currentState, equals(UpdateState.idle));

      // Attempt illegal transition: Idle -> Handshake directly
      expect(
        () => fsm.transitionTo(context, UpdateState.handshake),
        throwsA(isA<InvalidStateTransitionException>()),
      );
    });
  });
}
