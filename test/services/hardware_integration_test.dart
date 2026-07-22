import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/hardware/payment_terminal_service.dart';
import 'package:serenutos/domain/hardware/scale_service.dart';
import 'package:serenutos/domain/services/payment_fsm.dart';

void main() {
  group('ScaleFrameParser', () {
    test('parses stable kilogram frame', () {
      final reading = ScaleFrameParser.parse('ST,GS,+001.245kg',
          deviceId: 'test', sequence: 1);
      expect(reading?.netGrams, 1245);
      expect(reading?.stable, isTrue);
    });

    test('parses unstable grams frame with decimal comma', () {
      final reading = ScaleFrameParser.parse('US,NT,+735,0 g',
          deviceId: 'test', sequence: 2);
      expect(reading?.netGrams, 735);
      expect(reading?.stable, isFalse);
    });

    test('ignores frames without a weight', () {
      expect(ScaleFrameParser.parse('READY', deviceId: 'test', sequence: 3),
          isNull);
    });

    test('uses configured unit when device omits the unit', () {
      final kg = ScaleFrameParser.parse('ST,+1.250',
          deviceId: 'test', sequence: 4, defaultUnit: 'kg');
      final grams = ScaleFrameParser.parse('ST,+1250',
          deviceId: 'test', sequence: 5, defaultUnit: 'g');
      expect(kg?.netGrams, 1250);
      expect(grams?.netGrams, 1250);
    });
  });

  test('TCP POS requires explicit approval and authorization code', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final serverSubscription = server.listen((socket) {
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .then((line) {
        final request = jsonDecode(line) as Map<String, dynamic>;
        socket.writeln(jsonEncode({
          'decision': 'approved',
          'transactionId': request['transactionId'],
          'authorizationCode': 'BANK-123',
        }));
        socket.close();
      });
    });

    final adapter = TcpPaymentTerminalAdapter(
        host: InternetAddress.loopbackIPv4.address, port: server.port);
    final result = await adapter.sale(PaymentRequest(
      transactionId: 'sale-1',
      amount: 12.34,
      idempotencyKey: 'key-1',
      currency: 'TRY',
    ));
    expect(result.decision, TerminalDecision.approved);
    expect(result.authorizationCode, 'BANK-123');
    await serverSubscription.cancel();
    await server.close();
  });
}
