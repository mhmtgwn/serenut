import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/printing/printing_engine.dart';
import 'package:serenutos/infrastructure/printing/printing_transports.dart';

void main() {
  test('spooler sends the exact rendered bytes for every requested copy',
      () async {
    final received = <List<int>>[];
    final transport = WindowsSpoolerPrintTransport(
      rawPrint: (name, bytes) async {
        expect(name, 'ZDesigner');
        received.add(List<int>.from(bytes));
        return true;
      },
    );
    final bytes = Uint8List.fromList([0, 1, 2, 255]);

    final observation = await transport.send(
      bytes: bytes,
      copies: 2,
      configuration: const {'printerName': 'ZDesigner'},
    );

    expect(received, [bytes, bytes]);
    expect(observation.details['bytesAccepted'], 8);
  });

  test('bluetooth write rejection is reported as uncertain delivery', () async {
    final transport = BluetoothPrintTransport(
      connect: (_) async => true,
      rawPrint: (_) async => false,
    );

    expect(
      () => transport.send(
        bytes: Uint8List.fromList([1]),
        copies: 1,
        configuration: const {'address': 'AA:BB'},
      ),
      throwsA(isA<PrintTransportException>().having(
        (error) => error.deliveryUncertain,
        'deliveryUncertain',
        isTrue,
      )),
    );
  });
}
