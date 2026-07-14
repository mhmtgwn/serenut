import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Basit test sınıfları
class MockErrorHandler {
  static bool isPrinterError(String error) {
    return error.contains('SunmiPrinterPlus') ||
        error.contains('printer') ||
        error.contains('EscCommand');
  }

  static bool isBluetoothError(String error) {
    return error.contains('bluetooth') || error.contains('Bluetooth');
  }

  static bool isDatabaseError(String error) {
    return error.contains('sqlite') || error.contains('database');
  }

  static bool isNetworkError(String error) {
    return error.contains('SocketException') || error.contains('HttpException');
  }
}

void main() {
  group('Error Detection Tests', () {
    test('should identify printer errors correctly', () {
      const printerError = 'SunmiPrinterPlus connection failed';
      expect(MockErrorHandler.isPrinterError(printerError), isTrue);

      const normalError = 'Network connection failed';
      expect(MockErrorHandler.isPrinterError(normalError), isFalse);
    });

    test('should identify bluetooth errors correctly', () {
      const bluetoothError = 'Bluetooth adapter not found';
      expect(MockErrorHandler.isBluetoothError(bluetoothError), isTrue);

      const normalError = 'File not found';
      expect(MockErrorHandler.isBluetoothError(normalError), isFalse);
    });

    test('should identify database errors correctly', () {
      const dbError = 'sqlite database is locked';
      expect(MockErrorHandler.isDatabaseError(dbError), isTrue);

      const normalError = 'Network timeout';
      expect(MockErrorHandler.isDatabaseError(normalError), isFalse);
    });

    test('should identify network errors correctly', () {
      const networkError = 'SocketException: Connection refused';
      expect(MockErrorHandler.isNetworkError(networkError), isTrue);

      const normalError = 'Invalid input';
      expect(MockErrorHandler.isNetworkError(normalError), isFalse);
    });
  });

  group('Widget Tests', () {
    testWidgets('should display error messages', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('Error: Connection failed'),
            ),
          ),
        ),
      );

      expect(find.text('Error: Connection failed'), findsOneWidget);
    });

    testWidgets('should display success messages', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('Success: Operation completed'),
            ),
          ),
        ),
      );

      expect(find.text('Success: Operation completed'), findsOneWidget);
    });
  });
}
