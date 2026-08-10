import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/printing/printing_engine.dart';
import 'package:serenutos/infrastructure/printing/printing_transports.dart';

void main() {
  test('tcp transport sends rendered bytes to the configured endpoint',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = <int>[];
    final receivedDone = server.first.then((socket) async {
      await for (final chunk in socket) {
        received.addAll(chunk);
      }
    });
    final bytes = Uint8List.fromList([27, 64, 10, 29, 86]);

    final observation = await TcpPrintTransport().send(
      bytes: bytes,
      copies: 1,
      configuration: {'host': '127.0.0.1', 'port': server.port},
    );
    await receivedDone;
    await server.close();

    expect(received, bytes);
    expect(observation.details['bytesAccepted'], bytes.length);
  });

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

  test('bluetooth connects once and writes every requested copy', () async {
    var connections = 0;
    final writes = <List<int>>[];
    final transport = BluetoothPrintTransport(
      connect: (address) async {
        expect(address, 'AA:BB:CC');
        connections++;
        return true;
      },
      rawPrint: (bytes) async {
        writes.add(List<int>.from(bytes));
        return true;
      },
    );
    final bytes = Uint8List.fromList([1, 2, 3]);

    await transport.send(
      bytes: bytes,
      copies: 2,
      configuration: const {'address': 'AA:BB:CC'},
    );

    expect(connections, 1);
    expect(writes, [bytes, bytes]);
  });

  test('embedded transport writes raw bytes for every copy', () async {
    final writes = <List<int>>[];
    final transport = EmbeddedPrintTransport(
      rawPrint: (bytes) async {
        writes.add(List<int>.from(bytes));
        return true;
      },
    );
    final bytes = Uint8List.fromList([27, 64, 10]);

    await transport.send(
      bytes: bytes,
      copies: 2,
      configuration: const {},
    );

    expect(writes, [bytes, bytes]);
  });

  test('cloud relay preserves target, rendered bytes and local idempotency key',
      () async {
    late Map<String, Object?> request;
    final transport = CloudRelayPrintTransport.withQueue(({
      required hardwareId,
      required operation,
      required bytes,
      required copies,
      required idempotencyKey,
    }) async {
      request = {
        'hardwareId': hardwareId,
        'operation': operation,
        'bytes': bytes,
        'copies': copies,
        'idempotencyKey': idempotencyKey,
      };
      return 'remote-job-1';
    });

    final observation = await transport.send(
      bytes: Uint8List.fromList([27, 64, 10]),
      copies: 2,
      configuration: const {
        'hardwareId': 'activation-1:receipt-primary',
        'jobId': 'local-job-1',
        'documentKind': 'receipt',
      },
    );

    expect(request, {
      'hardwareId': 'activation-1:receipt-primary',
      'operation': 'printReceipt',
      'bytes': [27, 64, 10],
      'copies': 2,
      'idempotencyKey': 'local-job-1',
    });
    expect(observation.details['remoteJobId'], 'remote-job-1');
    expect(observation.physicalConfirmationRequired, isTrue);
  });
}
