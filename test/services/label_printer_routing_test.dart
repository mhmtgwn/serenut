import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/services/i_printer_service.dart';
import 'package:serenutos/infrastructure/services/printer_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

class MockSocket implements Socket {
  @override
  void add(List<int> data) {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Label Printer Routing Tests', () {
    test('Ensures printerName is set to network when printing labels to bypass Sunmi/USB overrides', () {
      final settings = Settings(
        businessName: 'Test Market',
        businessPhone: '123456',
        businessAddress: 'Address',
        printerName: 'sunmi',
        printerIp: '',
        printerPort: 9100,
        labelPrinterIp: '192.168.1.100',
        labelPrinterPort: 9100,
        createdAt: DateTime.now(),
      );

      final labelIp = settings.labelPrinterIp ?? '';
      final labelPort = settings.labelPrinterPort ?? 9100;
      
      // Simulate copyWith logic in our updated pages
      final labelSettings = settings.copyWith(
        printerName: 'network',
        printerIp: labelIp.isNotEmpty ? labelIp : settings.printerIp,
        printerPort: labelPort,
      );

      expect(labelSettings.printerName, 'network');
      expect(labelSettings.printerIp, '192.168.1.100');
      expect(labelSettings.printerPort, 9100);
      
      // Original settings must not be altered
      expect(settings.printerName, 'sunmi');
    });

    test('PrinterService printOrderLabels automatically routes to network and uses labelPrinterIp', () async {
      final settings = Settings(
        businessName: 'Test Market',
        businessPhone: '123456',
        businessAddress: 'Address',
        printerName: 'sunmi',
        printerIp: '192.168.1.50', // Receipt printer IP
        printerPort: 9100,
        labelPrinterIp: '192.168.1.150', // Label printer IP
        labelPrinterPort: 9100,
        createdAt: DateTime.now(),
      );

      String? connectedIp;
      int? connectedPort;

      final service = PrinterService((ip, port, {timeout}) async {
        connectedIp = ip;
        connectedPort = port;
        return MockSocket();
      }, null);

      final order = OrderEntity(
        id: 'order-123',
        customerId: 'customer-1',
        status: 'pending',
        createdAt: DateTime.now(),
        items: [
          {'product_id': 'prod-1', 'quantity': 2.0, 'unit_price': 10.0}
        ],
      );

      await service.printOrderLabels(order, order.items, settings);

      // Verify it connected to label printer IP (192.168.1.150) instead of receipt IP (192.168.1.50)
      expect(connectedIp, '192.168.1.150');
      expect(connectedPort, 9100);
    });
  });
}
