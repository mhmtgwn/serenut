// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/infrastructure/services/printer_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

class MockSocket implements Socket {
  final List<int> writtenBytes = [];

  @override
  void add(List<int> data) => writtenBytes.addAll(data);
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Label Printer Routing Tests', () {
    test(
        'Ensures printerName is set to network when printing labels to bypass Sunmi/USB overrides',
        () {
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
      final labelPort = settings.labelPrinterPort;

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

    test('Windows etiket yazıcısı adı ayarlarda korunur', () {
      final settings = Settings(
        businessName: 'Test Market',
        businessPhone: '123456',
        businessAddress: 'Address',
        labelPrinterEnabled: true,
        labelPrinterName: 'TSC TE200',
        labelPrinterLanguage: 'tspl',
        labelWidthMm: 50,
        labelHeightMm: 30,
        createdAt: DateTime.now(),
      );

      final restored = Settings.fromMap(settings.toMap());
      expect(restored.labelPrinterName, 'TSC TE200');
      expect(restored.labelPrinterLanguage, 'tspl');
      expect(restored.labelWidthMm, 50);
      expect(restored.labelHeightMm, 30);
    });

    test(
        'PrinterService printOrderLabels automatically routes to network and uses labelPrinterIp',
        () async {
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

    test('PrinterService never sends label bytes to the receipt printer',
        () async {
      final settings = Settings(
        businessName: 'Test Market',
        businessPhone: '123456',
        businessAddress: 'Address',
        printerName: 'network',
        printerIp: '192.168.1.50',
        printerPort: 9200,
        createdAt: DateTime.now(),
      );

      final service = PrinterService((ip, port, {timeout}) async {
        return MockSocket();
      }, null);

      final order = OrderEntity(
        id: 'order-fallback',
        customerId: 'customer-1',
        status: 'pending',
        createdAt: DateTime.now(),
        items: [
          {'product_id': 'prod-1', 'quantity': 1.0, 'unit_price': 10.0}
        ],
      );

      await expectLater(
        service.printOrderLabels(order, order.items, settings),
        throwsA(isA<StateError>()),
      );
    });

    test('PrinterService reports a missing label and main printer', () async {
      final settings = Settings(
        businessName: 'Test Market',
        businessPhone: '123456',
        businessAddress: 'Address',
        createdAt: DateTime.now(),
      );
      final service = PrinterService((ip, port, {timeout}) async {
        return MockSocket();
      }, null);
      final order = OrderEntity(
        id: 'order-no-printer',
        customerId: 'customer-1',
        status: 'pending',
        createdAt: DateTime.now(),
        items: [
          {'product_id': 'prod-1', 'quantity': 1.0, 'unit_price': 10.0}
        ],
      );

      await expectLater(
        service.printOrderLabels(order, order.items, settings),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Etiket yazıcısı tanımlı değil.',
          ),
        ),
      );
    });

    test('one continuous order label grows to include every item', () async {
      final settings = Settings(
        businessName: 'Test Market',
        businessPhone: '123456',
        businessAddress: 'Address',
        labelPrinterEnabled: true,
        labelPrinterName: 'network',
        labelPrinterIp: '192.168.1.150',
        labelPrinterPort: 9100,
        labelPrinterLanguage: 'tspl',
        createdAt: DateTime.now(),
      );
      final socket = MockSocket();
      final service =
          PrinterService((ip, port, {timeout}) async => socket, null);
      final items = <Map<String, dynamic>>[
        {
          'product_id': 'prod-1',
          'product_name': 'Birinci Urun',
          'quantity': 1.0,
          'unit_price': 10.0,
        },
        {
          'product_id': 'prod-2',
          'product_name': 'Ikinci Urun',
          'quantity': 2.0,
          'unit_price': 20.0,
        },
        {
          'product_id': 'prod-3',
          'product_name': 'Ucuncu Urun',
          'quantity': 3.0,
          'unit_price': 30.0,
        },
        {
          'product_id': 'prod-4',
          'product_name': 'Dorduncu Urun',
          'quantity': 4.0,
          'unit_price': 40.0,
        },
        {
          'product_id': 'prod-5',
          'product_name': 'Besinci Urun',
          'quantity': 5.0,
          'unit_price': 50.0,
        },
      ];
      final order = OrderEntity(
        id: 'order-two-items',
        customerId: 'customer-1',
        status: 'pending',
        createdAt: DateTime.now(),
        items: items,
      );

      await service.printOrderLabels(order, items, settings);

      final output = String.fromCharCodes(socket.writtenBytes);
      expect('Birinci Urun'.allMatches(output), hasLength(1));
      expect('Ikinci Urun'.allMatches(output), hasLength(1));
      expect('Ucuncu Urun'.allMatches(output), hasLength(1));
      expect('Dorduncu Urun'.allMatches(output), hasLength(1));
      expect('Besinci Urun'.allMatches(output), hasLength(1));
      expect(output, isNot(contains('diger urun')));
      // A single dynamically growing order label must still respect the
      // configured physical media gap; "continuous" describes one print job,
      // not gapless paper.
      expect(output, contains('GAP ${settings.labelGapMm} mm,0 mm'));
      final size = RegExp(r'SIZE 50 mm,(\d+) mm').firstMatch(output);
      expect(size, isNotNull);
      expect(int.parse(size!.group(1)!), greaterThan(30));
      expect('PRINT 1,1'.allMatches(output), hasLength(1));
    });
  });
}
