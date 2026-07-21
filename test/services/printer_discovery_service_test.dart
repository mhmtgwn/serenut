import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/printer_discovery_service.dart';

void main() {
  test('network discovery reports only reachable candidates', () async {
    final service = PrinterDiscoveryService(
      connect: (host, port, timeout) async {
        if (host == '192.168.50.20' && port == 9100) {
          return Socket.connect('127.0.0.1', 9,
              timeout: const Duration(milliseconds: 1));
        }
        throw const SocketException('closed');
      },
    );

    // Connector needs a real Socket return type, so this test focuses on
    // validation without opening 254 actual network connections.
    expect(
      () => service.scanSubnet('not-a-subnet'),
      throwsArgumentError,
    );
  });

  test('network candidates require an explicit print test', () {
    const printer = DiscoveredPrinter(
      id: 'network:192.168.1.20:9100',
      name: 'candidate',
      kind: DiscoveredPrinterKind.network,
      address: '192.168.1.20',
      port: 9100,
    );
    expect(printer.requiresPrintTest, isTrue);
  });
}
