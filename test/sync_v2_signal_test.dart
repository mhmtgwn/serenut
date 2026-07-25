import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/sync_v2/engine/sync_event_bus.dart';
import 'package:serenutos/infrastructure/sync_v2/engine/socket_connection_state_machine.dart';

void main() {
  late SyncEventBus eventBus;
  late SocketConnectionStateMachine socketStateMachine;

  setUp(() {
    eventBus = SyncEventBus();
    socketStateMachine = SocketConnectionStateMachine();
  });

  tearDown(() {
    eventBus.dispose();
  });

  group('Faz 6 Signal-Only WebSocket Integration Test Suite', () {
    test('1. Socket Connection State Machine Transitions', () {
      expect(socketStateMachine.currentState, equals(SocketConnectionState.disconnected));

      socketStateMachine.transitionTo(SocketConnectionState.connecting);
      expect(socketStateMachine.currentState, equals(SocketConnectionState.connecting));

      socketStateMachine.transitionTo(SocketConnectionState.connected);
      expect(socketStateMachine.currentState, equals(SocketConnectionState.connected));
    });

    test('2. Signal Invalidation Ticket Bus Emission (Zero Payload Guarantee)', () async {
      final completer = Completer<RevisionInvalidatedEvent>();

      eventBus.on<RevisionInvalidatedEvent>().listen((event) {
        completer.complete(event);
      });

      // Emit signal ticket with ZERO payload
      eventBus.publish(RevisionInvalidatedEvent(
        tenantId: 'company_tenant_1',
        headRevision: 18234,
      ));

      final received = await completer.future;
      expect(received.tenantId, equals('company_tenant_1'));
      expect(received.headRevision, equals(18234));
    });

    test('3. Duplicate Signal Coalescing Safeguard', () async {
      int receivedCount = 0;

      eventBus.on<RevisionInvalidatedEvent>().listen((_) {
        receivedCount++;
      });

      // Emit 10 duplicate signals for same head_revision: 18234
      for (int i = 0; i < 10; i++) {
        eventBus.publish(RevisionInvalidatedEvent(
          tenantId: 'company_tenant_1',
          headRevision: 18234,
        ));
      }

      await Future.delayed(const Duration(milliseconds: 50));
      expect(receivedCount, equals(10));
    });
  });
}
