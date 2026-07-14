import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/payment_fsm.dart';

void main() {
  group('PaymentFSM Tests', () {
    late PaymentFSM fsm;

    setUp(() {
      fsm = PaymentFSM();
    });

    test('initial state is idle', () {
      expect(fsm.state, equals(PaymentState.idle));
    });

    test(
        'valid transition flow: idle -> initiated -> terminalSent -> authorized -> completed',
        () {
      fsm.initiate('tx-1', 150.0, 'idemp-1');
      expect(fsm.state, equals(PaymentState.initiated));
      expect(fsm.activeTransactionId, equals('tx-1'));
      expect(fsm.activeAmount, equals(150.0));
      expect(fsm.activeIdempotencyKey, equals('idemp-1'));

      fsm.sendToTerminal();
      expect(fsm.state, equals(PaymentState.terminalSent));

      fsm.authorize();
      expect(fsm.state, equals(PaymentState.authorized));

      fsm.complete();
      expect(fsm.state, equals(PaymentState.completed));
    });

    test('handles timeout and recovery flow', () {
      fsm.initiate('tx-2', 200.0, 'idemp-2');
      fsm.sendToTerminal();
      fsm.triggerTimeout();
      expect(fsm.state, equals(PaymentState.timeout));

      // Can retry/send to terminal from timeout
      fsm.sendToTerminal();
      expect(fsm.state, equals(PaymentState.terminalSent));

      fsm.authorize();
      fsm.complete();
      expect(fsm.state, equals(PaymentState.completed));
    });

    test('handles unreconciled state flow', () {
      fsm.initiate('tx-3', 300.0, 'idemp-3');
      fsm.sendToTerminal();
      fsm.markUnreconciled();
      expect(fsm.state, equals(PaymentState.unreconciled));

      // Can reconcile and complete
      fsm.complete();
      expect(fsm.state, equals(PaymentState.completed));
    });

    test('throws StateError on invalid transitions', () {
      fsm.initiate('tx-4', 400.0, 'idemp-4');

      // Cannot transition to authorized directly from initiated
      expect(() => fsm.authorize(), throwsStateError);

      fsm.sendToTerminal();
      fsm.authorize();
      fsm.complete();

      // Cannot transition from completed without resetting
      expect(() => fsm.sendToTerminal(), throwsStateError);
      expect(() => fsm.initiate('tx-5', 10.0, 'idemp-5'), throwsStateError);

      fsm.reset();
      expect(fsm.state, equals(PaymentState.idle));
      expect(fsm.activeTransactionId, isNull);
    });
  });
}
