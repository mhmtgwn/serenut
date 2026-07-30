import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/hardware/payment_terminal_service.dart';
import 'package:serenutos/domain/hardware/hardware_status.dart';
import 'package:serenutos/domain/services/payment_fsm.dart';
import 'package:serenutos/infrastructure/services/terminal_payment_journal.dart';
import 'package:serenutos/providers/hardware_config_provider.dart';

final paymentTerminalAdapterProvider = Provider<IPaymentTerminalAdapter>((ref) {
  final config = ref.watch(hardwareConfigProvider).valueOrNull;
  if (config == null || !config.hasPosBridge) {
    return UnconfiguredPaymentTerminal();
  }
  return TcpPaymentTerminalAdapter(
    host: config.posBridgeHost,
    port: config.posBridgePort,
    vendor: config.posVendor,
    protocol: config.posProtocol,
  );
});

/// The only UI-facing entry point for an in-store card charge.  A ledger write
/// must be made only after this service returns an approved terminal response.
class PhysicalCardPaymentService {
  PhysicalCardPaymentService(this._terminal, this._journal);

  final IPaymentTerminalAdapter _terminal;
  final TerminalPaymentJournal _journal;

  static Map<String, dynamic> manualLedgerMetadata({
    required String context,
  }) =>
      {
        'card_entry_mode': 'manual',
        'terminal_authorized': false,
        'entry_context': context,
      };

  Future<AuthorizedCardPayment> authorize({
    required double amount,
    required String idempotencyKey,
    String contextType = 'card_payment',
    String? contextId,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(
          amount, 'amount', 'Kart tutarı sıfırdan büyük olmalıdır.');
    }
    final capabilities = await _terminal.probe();
    if (!capabilities.paired || !capabilities.saleSupported) {
      throw const HardwareFailure(
        'POS_NOT_READY',
        'POS eşleştirilmemiş veya satışa hazır değil.',
      );
    }
    final transactionId = 'pos-${DateTime.now().microsecondsSinceEpoch}';
    final journalId = await _journal.recordPending(
      idempotencyKey: idempotencyKey,
      terminalTransactionId: transactionId,
      amount: amount,
      currency: 'TRY',
      contextType: contextType,
      contextId: contextId,
    );
    late final TerminalPaymentResult result;
    try {
      result = await PaymentTerminalOrchestrator(terminal: _terminal)
          .authorize(PaymentRequest(
        transactionId: transactionId,
        amount: amount,
        idempotencyKey: idempotencyKey,
        currency: 'TRY',
      ));
    } catch (error) {
      await _journal.markUnreconciled(journalId, error);
      rethrow;
    }
    if (result.decision != TerminalDecision.approved) {
      await _journal.markUnreconciled(
        journalId,
        result.errorMessage ??
            'POS işlemi onaylanmadı (${result.decision.name}).',
      );
      throw HardwareFailure(
        'POS_NOT_APPROVED',
        result.errorMessage ??
            'POS işlemi onaylanmadı (${result.decision.name}).',
      );
    }
    await _journal.markAuthorized(journalId, result.authorizationCode);
    return AuthorizedCardPayment(journalId: journalId, result: result);
  }

  Future<void> markLocalCommit(AuthorizedCardPayment payment,
          {String? contextId}) =>
      _journal.markCommitted(payment.journalId, contextId: contextId);

  Future<void> markUnreconciled(AuthorizedCardPayment payment, Object error) =>
      _journal.markUnreconciled(payment.journalId, error);
}

class AuthorizedCardPayment {
  const AuthorizedCardPayment({required this.journalId, required this.result});
  final String journalId;
  final TerminalPaymentResult result;

  Map<String, dynamic> get ledgerMetadata => {
        'terminal_journal_id': journalId,
        'terminal_transaction_id': result.transactionId,
        'terminal_authorization_code': result.authorizationCode,
      };
}

final physicalCardPaymentServiceProvider = Provider<PhysicalCardPaymentService>(
  (ref) => PhysicalCardPaymentService(
    ref.watch(paymentTerminalAdapterProvider),
    TerminalPaymentJournal(),
  ),
);
