import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/hardware/payment_terminal_service.dart';
import 'package:serenutos/domain/services/payment_fsm.dart';

void main() {
  PaymentRequest request() => PaymentRequest(
        transactionId: 'tx-1',
        amount: 125.50,
        idempotencyKey: 'sale-1-card',
        currency: 'TRY',
      );

  test('approved terminal payment waits for local sale completion', () async {
    final orchestrator = PaymentTerminalOrchestrator(
      terminal: SimulatedPaymentTerminal(),
    );
    final result = await orchestrator.authorize(request());
    expect(result.decision, TerminalDecision.approved);
    expect(orchestrator.fsm.state, PaymentState.authorized);

    orchestrator.completeLocalSale();
    expect(orchestrator.fsm.state, PaymentState.completed);
  });

  test('declined payment cannot complete a local sale', () async {
    final orchestrator = PaymentTerminalOrchestrator(
      terminal:
          SimulatedPaymentTerminal(nextDecision: TerminalDecision.declined),
    );
    await orchestrator.authorize(request());
    expect(orchestrator.fsm.state, PaymentState.declined);
    expect(orchestrator.completeLocalSale, throwsStateError);
  });

  test('unknown result enters reconciliation state', () async {
    final orchestrator = PaymentTerminalOrchestrator(
      terminal:
          SimulatedPaymentTerminal(nextDecision: TerminalDecision.unknown),
    );
    await orchestrator.authorize(request());
    expect(orchestrator.fsm.state, PaymentState.unreconciled);
  });
}
