import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:serenutos/infrastructure/services/printer_service.dart';
import 'package:serenutos/infrastructure/services/resilient_scanner_service.dart';
import 'package:serenutos/domain/models/settings.dart';

class MockSocket implements Socket {
  final List<int> writtenBytes = [];
  bool isClosed = false;
  bool isFlushed = false;

  @override
  void add(List<int> data) {
    writtenBytes.addAll(data);
  }

  @override
  Future<void> flush() async {
    isFlushed = true;
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Device Failure Resilience Tests', () {
    late MockSocket mockSocket;
    late Settings testSettings;

    setUp(() {
      mockSocket = MockSocket();
      testSettings = Settings(
        businessName: 'Resilient Market',
        businessPhone: '555-555-5555',
        businessAddress: 'TR',
        printerIp: '192.168.1.50',
        printerPort: 9100,
        paperWidth: 80,
      );
    });

    test('PrinterService should auto-reconnect and succeed if connection fails twice but succeeds on the 3rd attempt', () async {
      int attempts = 0;
      final printerService = PrinterService((ip, port, {timeout}) async {
        attempts++;
        if (attempts < 3) {
          throw const SocketException('Connection refused');
        }
        return mockSocket;
      });

      // Execute test print
      await printerService.testPrinterConnection(testSettings);
      
      expect(attempts, equals(3));
      expect(mockSocket.isClosed, isTrue);
    });

    test('PrinterService should put print job in failed queue when all retry attempts fail', () async {
      final printerService = PrinterService((ip, port, {timeout}) async {
        throw const SocketException('Printer host is unreachable');
      });

      // Enqueue job
      printerService.enqueue('Test Receipt', () async {
        await printerService.testPrinterConnection(testSettings);
      });

      // Wait for queue to process and fail (needs at least 2 seconds due to retries delay)
      await Future.delayed(const Duration(milliseconds: 2500));

      expect(printerService.queue.length, equals(1));
      expect(printerService.queue.first.status, equals('failed'));
    });

    test('ResilientScannerService should reconnect and successfully scan barcode on 3rd attempt after MethodChannel exceptions', () async {
      int scanAttempts = 0;
      
      // Setup mock method channel for scanner
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.sunmi.scanner'), (MethodCall methodCall) async {
        if (methodCall.method == 'startScan') {
          scanAttempts++;
          if (scanAttempts < 3) {
            throw PlatformException(code: 'UNAVAILABLE', message: 'Scanner disconnected');
          }
          return '9876543210123';
        }
        return null;
      });

      final scannerService = ResilientScannerService();
      scannerService.clearBuffer();

      final code = await scannerService.startResilientScan();
      
      expect(code, equals('9876543210123'));
      expect(scanAttempts, equals(3));
      expect(scannerService.buffer.contains('9876543210123'), isTrue);

      // Clean mock
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.sunmi.scanner'), null);
    });
  });
}
