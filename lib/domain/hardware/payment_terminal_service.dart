import 'package:serenutos/domain/services/payment_fsm.dart';

enum TerminalDecision { approved, declined, cancelled, unknown }

class TerminalPaymentResult {
  final TerminalDecision decision;
  final String transactionId;
  final String authorizationCode;
  final String? errorCode;
  final String? errorMessage;

  const TerminalPaymentResult({
    required this.decision,
    required this.transactionId,
    this.authorizationCode = '',
    this.errorCode,
    this.errorMessage,
  });
}

abstract class IPaymentTerminalAdapter {
  String get adapterId;

  Future<TerminalPaymentResult> sale(PaymentRequest request);
  Future<TerminalPaymentResult> query(String transactionId);
  Future<TerminalPaymentResult> voidPayment(String transactionId);
  Future<void> cancelActive();
}

class PaymentTerminalOrchestrator {
  final IPaymentTerminalAdapter terminal;
  final PaymentFSM fsm;

  PaymentTerminalOrchestrator({
    required this.terminal,
    PaymentFSM? fsm,
  }) : fsm = fsm ?? PaymentFSM();

  Future<TerminalPaymentResult> authorize(PaymentRequest request) async {
    fsm.initiate(request.transactionId, request.amount, request.idempotencyKey);
    fsm.sendToTerminal();
    try {
      final result = await terminal.sale(request);
      switch (result.decision) {
        case TerminalDecision.approved:
          fsm.authorize();
        case TerminalDecision.declined:
          fsm.decline();
        case TerminalDecision.cancelled:
          fsm.cancel();
        case TerminalDecision.unknown:
          fsm.markUnreconciled();
      }
      return result;
    } catch (_) {
      fsm.triggerTimeout();
      rethrow;
    }
  }

  void completeLocalSale() => fsm.complete();

  void reset() => fsm.reset();
}

class SimulatedPaymentTerminal implements IPaymentTerminalAdapter {
  SimulatedPaymentTerminal({this.nextDecision = TerminalDecision.approved});

  TerminalDecision nextDecision;

  @override
  String get adapterId => 'payment-simulator';

  @override
  Future<TerminalPaymentResult> sale(PaymentRequest request) async {
    return TerminalPaymentResult(
      decision: nextDecision,
      transactionId: request.transactionId,
      authorizationCode:
          nextDecision == TerminalDecision.approved ? 'SIM-OK' : '',
      errorCode:
          nextDecision == TerminalDecision.declined ? 'SIM-DECLINED' : null,
    );
  }

  @override
  Future<TerminalPaymentResult> query(String transactionId) async =>
      TerminalPaymentResult(
        decision: nextDecision,
        transactionId: transactionId,
        authorizationCode:
            nextDecision == TerminalDecision.approved ? 'SIM-OK' : '',
      );

  @override
  Future<TerminalPaymentResult> voidPayment(String transactionId) async =>
      TerminalPaymentResult(
        decision: TerminalDecision.approved,
        transactionId: transactionId,
        authorizationCode: 'SIM-VOID',
      );

  @override
  Future<void> cancelActive() async {}
}
