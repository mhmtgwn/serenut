// lib/domain/services/payment_fsm.dart
// Phase 5 — Payment Architecture (Abstraction Only)
// Finite State Machine (FSM) and interfaces for payment terminals & providers

enum PaymentState {
  idle,
  initiated,
  terminalSent,
  timeout,
  authorized,
  completed,
  unreconciled,
}

class PaymentRequest {
  final String transactionId;
  final double amount;
  final String idempotencyKey;
  final String currency;

  PaymentRequest({
    required this.transactionId,
    required this.amount,
    required this.idempotencyKey,
    required this.currency,
  });
}

class PaymentResponse {
  final String transactionId;
  final bool isSuccess;
  final String authorizationCode;
  final String errorCode;
  final String errorMessage;

  PaymentResponse({
    required this.transactionId,
    required this.isSuccess,
    required this.authorizationCode,
    this.errorCode = '',
    this.errorMessage = '',
  });
}

abstract class IPaymentTerminalBridge {
  Future<PaymentResponse> sendTransaction(PaymentRequest request);
  Future<PaymentResponse> voidTransaction(String transactionId);
  Future<void> cancelActiveTransaction();
}

abstract class IOnlinePaymentProvider {
  Future<PaymentResponse> charge(PaymentRequest request);
  Future<PaymentResponse> refund(String transactionId, double amount);
}

class PaymentFSM {
  PaymentState _state = PaymentState.idle;
  PaymentState get state => _state;

  String? _activeTransactionId;
  double? _activeAmount;
  String? _activeIdempotencyKey;

  String? get activeTransactionId => _activeTransactionId;
  double? get activeAmount => _activeAmount;
  String? get activeIdempotencyKey => _activeIdempotencyKey;

  /// Initiate a new payment cycle.
  /// Prevents starting a transaction if the machine is not idle (Double charge guard).
  void initiate(String transactionId, double amount, String idempotencyKey) {
    if (_state != PaymentState.idle) {
      throw StateError('Cannot initiate transaction: Payment FSM is in $_state state. Reset or complete the current transaction first.');
    }
    _activeTransactionId = transactionId;
    _activeAmount = amount;
    _activeIdempotencyKey = idempotencyKey;
    _transitionTo(PaymentState.initiated);
  }

  /// Mark that request has been dispatched to the physical terminal.
  void sendToTerminal() {
    _verifyStateIn([PaymentState.initiated, PaymentState.timeout]);
    _transitionTo(PaymentState.terminalSent);
  }

  /// Flag connection or reader timeout.
  void triggerTimeout() {
    _verifyStateIn([PaymentState.terminalSent]);
    _transitionTo(PaymentState.timeout);
  }

  /// Transition to authorized state when terminal returns success.
  void authorize() {
    _verifyStateIn([PaymentState.terminalSent, PaymentState.timeout]);
    _transitionTo(PaymentState.authorized);
  }

  /// Successfully complete transaction and persist to database.
  void complete() {
    _verifyStateIn([PaymentState.authorized, PaymentState.initiated, PaymentState.unreconciled]);
    _transitionTo(PaymentState.completed);
  }

  /// Mark transaction as UNRECONCILED if payment completed but local database update failed.
  void markUnreconciled() {
    _verifyStateIn([PaymentState.authorized, PaymentState.terminalSent, PaymentState.timeout]);
    _transitionTo(PaymentState.unreconciled);
  }

  /// Reset state machine to idle for new transaction blocks.
  void reset() {
    _state = PaymentState.idle;
    _activeTransactionId = null;
    _activeAmount = null;
    _activeIdempotencyKey = null;
  }

  void _transitionTo(PaymentState newState) {
    // Define strict transition constraints
    if (_state == PaymentState.completed && newState != PaymentState.idle) {
      throw StateError('Cannot transition from completed state to $newState without resetting FSM.');
    }
    _state = newState;
  }

  void _verifyStateIn(List<PaymentState> allowedStates) {
    if (!allowedStates.contains(_state)) {
      throw StateError('Invalid FSM transition: Attempted state modification from $_state which is not in allowed sources: $allowedStates');
    }
  }
}
