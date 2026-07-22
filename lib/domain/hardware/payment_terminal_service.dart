import 'dart:convert';
import 'dart:io';

import 'package:serenutos/domain/services/payment_fsm.dart';
import 'package:serenutos/domain/hardware/hardware_status.dart';

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

class TerminalCapabilities {
  final String vendor;
  final String model;
  final String protocol;
  final bool paired;
  final bool saleSupported;

  const TerminalCapabilities({
    required this.vendor,
    required this.model,
    required this.protocol,
    required this.paired,
    required this.saleSupported,
  });
}

abstract class IPaymentTerminalAdapter {
  String get adapterId;
  Future<TerminalCapabilities> probe();

  Future<TerminalPaymentResult> sale(PaymentRequest request);
  Future<TerminalPaymentResult> query(String transactionId);
  Future<TerminalPaymentResult> voidPayment(String transactionId);
  Future<void> cancelActive();
}

/// Talks to a local Windows hardware bridge over newline-delimited JSON.
/// The bridge is responsible for the bank/vendor SDK. A sale is never treated
/// as approved unless the bridge explicitly returns decision=approved and an
/// authorizationCode.
class TcpPaymentTerminalAdapter implements IPaymentTerminalAdapter {
  TcpPaymentTerminalAdapter({
    required this.host,
    required this.port,
    this.vendor = 'generic',
    this.protocol = 'vendor_sdk',
  });

  final String host;
  final int port;
  final String vendor;
  final String protocol;

  @override
  String get adapterId => 'tcp-pos-$host:$port';

  Future<TerminalPaymentResult> _send(Map<String, Object?> payload) async {
    Socket? socket;
    try {
      socket =
          await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      socket.writeln(jsonEncode(payload));
      await socket.flush();
      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 90));
      final json = jsonDecode(line) as Map<String, dynamic>;
      final decision =
          switch ((json['decision'] as String? ?? '').toLowerCase()) {
        'approved' => TerminalDecision.approved,
        'declined' => TerminalDecision.declined,
        'cancelled' => TerminalDecision.cancelled,
        _ => TerminalDecision.unknown,
      };
      final authorizationCode = json['authorizationCode'] as String? ?? '';
      if (decision == TerminalDecision.approved && authorizationCode.isEmpty) {
        throw const HardwareFailure('POS_INVALID_RESPONSE',
            'POS onay verdi fakat provizyon kodu döndürmedi.');
      }
      return TerminalPaymentResult(
        decision: decision,
        transactionId: json['transactionId'] as String? ??
            payload['transactionId'] as String? ??
            '',
        authorizationCode: authorizationCode,
        errorCode: json['errorCode'] as String?,
        errorMessage: json['errorMessage'] as String?,
      );
    } catch (error) {
      if (error is HardwareFailure) rethrow;
      throw HardwareFailure(
          'POS_BRIDGE_FAILED', 'POS köprüsüyle iletişim kurulamadı: $error');
    } finally {
      await socket?.close();
    }
  }

  @override
  Future<TerminalCapabilities> probe() async {
    Socket? socket;
    try {
      socket =
          await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      socket.writeln(jsonEncode({
        'operation': 'capabilities',
        'vendor': vendor,
        'protocol': protocol,
      }));
      await socket.flush();
      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 10));
      final response = jsonDecode(line) as Map<String, dynamic>;
      return TerminalCapabilities(
        vendor: response['vendor'] as String? ?? vendor,
        model: response['model'] as String? ?? '',
        protocol: response['protocol'] as String? ?? protocol,
        paired: response['paired'] == true,
        saleSupported: response['saleSupported'] == true,
      );
    } catch (error) {
      throw HardwareFailure(
          'POS_PROBE_FAILED', 'POS köprüsü hazır değil: $error');
    } finally {
      await socket?.close();
    }
  }

  @override
  Future<TerminalPaymentResult> sale(PaymentRequest request) => _send({
        'operation': 'sale',
        'transactionId': request.transactionId,
        'idempotencyKey': request.idempotencyKey,
        'amountMinor': (request.amount * 100).round(),
        'currency': request.currency,
        'vendor': vendor,
        'protocol': protocol,
      });

  @override
  Future<TerminalPaymentResult> query(String transactionId) =>
      _send({'operation': 'query', 'transactionId': transactionId});

  @override
  Future<TerminalPaymentResult> voidPayment(String transactionId) =>
      _send({'operation': 'void', 'transactionId': transactionId});

  @override
  Future<void> cancelActive() async {
    await _send({'operation': 'cancel'});
  }
}

class UnconfiguredPaymentTerminal implements IPaymentTerminalAdapter {
  @override
  String get adapterId => 'pos-unconfigured';
  HardwareFailure get _failure => const HardwareFailure('POS_NOT_CONFIGURED',
      'Fiziksel POS köprüsü IP ve port ayarı yapılmamış.');
  @override
  Future<TerminalCapabilities> probe() => Future.error(_failure);
  @override
  Future<TerminalPaymentResult> sale(PaymentRequest request) =>
      Future.error(_failure);
  @override
  Future<TerminalPaymentResult> query(String transactionId) =>
      Future.error(_failure);
  @override
  Future<TerminalPaymentResult> voidPayment(String transactionId) =>
      Future.error(_failure);
  @override
  Future<void> cancelActive() => Future.error(_failure);
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
  Future<TerminalCapabilities> probe() async => const TerminalCapabilities(
        vendor: 'simulator',
        model: 'test-only',
        protocol: 'simulation',
        paired: true,
        saleSupported: true,
      );

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
