// test/services/printer_service_test.dart
// Phase 4 — Printer Service and ESC/POS Formatting Tests
// Generated: 21 Jun 2026

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/printer_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';

/// Minimal mock Socket implementation using noSuchMethod to satisfy interface
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
  group('PrinterService ESC/POS Formatting & Socket Output Tests', () {
    late MockSocket mockSocket;
    late PrinterService printerService;
    late Settings testSettings;

    setUp(() {
      mockSocket = MockSocket();

      // Inject mock socket connector
      printerService = PrinterService((ip, port, {timeout}) async {
        return mockSocket;
      });

      testSettings = Settings(
        businessName: 'Deneme Market',
        businessPhone: '555-555-5555',
        businessAddress: 'Istanbul, TR',
        printerIp: '192.168.1.50',
        printerPort: 9100,
        paperWidth: 80,
        printQRCode: true,
        currency: 'TL',
      );
    });

    test('testConnection sends initial commands, test labels and paper cut',
        () async {
      await printerService.testConnection('192.168.1.50', 9100);

      expect(mockSocket.writtenBytes, isNotEmpty);
      expect(mockSocket.isClosed, isTrue);
      expect(mockSocket.isFlushed, isTrue);

      // Verify initialization commands exist: [ESC @]
      expect(
          mockSocket.writtenBytes.sublist(0, 2), equals(EscPosCommands.init));

      // Verify text label is sent in bytes
      final writtenText = String.fromCharCodes(mockSocket.writtenBytes);
      expect(writtenText, contains('SERENUT POS'));
      expect(
          _containsBytes(mockSocket.writtenBytes, [89, 97, 122, 141, 99, 141]),
          isTrue); // 'Yazıcı'
    });

    test(
        'printSaleReceipt outputs formatted receipt with items, totals and QR code',
        () async {
      final sale = SaleEntity(
        id: 'sale-test-id-12345',
        customerId: 'cust-1',
        totalAmount: 120.0,
        paidAmount: 80.0,
        paymentMethod: 'Vadeli',
        status: 'completed',
        createdAt: DateTime(2026, 6, 21, 14, 30),
        items: [],
      );

      final items = [
        {
          'product_id': 'Elma',
          'quantity': 2,
          'unit_price': 10.0,
        },
        {
          'product_id': 'Süt', // Contains Turkish character
          'quantity': 3,
          'unit_price': 30.0,
        }
      ];

      await printerService.printSaleReceipt(sale, items, null, testSettings);

      expect(mockSocket.isClosed, isTrue);

      final writtenText = String.fromCharCodes(mockSocket.writtenBytes);

      // Verify native Turkish representation in CP857 bytes
      expect(
          _containsBytes(mockSocket.writtenBytes,
              [83, 129, 116, 32, 40, 51, 32, 120, 32, 51, 48, 46, 48, 48, 41]),
          isTrue); // 'Süt (3 x 30.00)'
      expect(writtenText, contains('Elma (2 x 10.00)'));

      // Verify totals exist
      expect(writtenText, contains('TOPLAM: 120.00 TL'));
      expect(
          _containsBytes(mockSocket.writtenBytes, [
            153,
            100,
            101,
            110,
            101,
            110,
            58,
            32,
            56,
            48,
            46,
            48,
            48,
            32,
            84,
            76
          ]),
          isTrue); // 'Ödenen: 80.00 TL'
      expect(
          _containsBytes(mockSocket.writtenBytes, [
            75,
            97,
            108,
            97,
            110,
            32,
            66,
            111,
            114,
            135,
            58,
            32,
            52,
            48,
            46,
            48,
            48,
            32,
            84,
            76
          ]),
          isTrue); // 'Kalan Borç: 40.00 TL'

      // Verify QR command prefix: [0x1D, 0x28, 0x6B] (GS ( k)
      expect(mockSocket.writtenBytes, contains(0x1D));
      expect(mockSocket.writtenBytes, contains(0x28));
      expect(mockSocket.writtenBytes, contains(0x6B));

      // Verify cut command is present at the end
      final len = mockSocket.writtenBytes.length;
      expect(
          mockSocket.writtenBytes.sublist(len - 4), equals(EscPosCommands.cut));
    });

    test(
        'printOrderReceipt formats detailed receipt with items, totals and QR code',
        () async {
      final order = OrderEntity(
        id: 'order-test-id-999',
        customerId: 'cust-1',
        status: 'preparing',
        createdAt: DateTime(2026, 6, 23, 20, 17),
        items: [],
      );

      final items = [
        {'product_id': 'Cay', 'quantity': 5, 'unit_price': 10.0},
        {'product_id': 'Borek', 'quantity': 2, 'unit_price': 25.0},
      ];

      await printerService.printOrderReceipt(order, items, null, testSettings,
          paidAmount: 30.0);

      final writtenText = String.fromCharCodes(mockSocket.writtenBytes);
      expect(
          _containsBytes(mockSocket.writtenBytes, [
            42,
            42,
            42,
            32,
            83,
            152,
            80,
            65,
            82,
            152,
            158,
            32,
            70,
            152,
            158,
            152,
            32,
            42,
            42,
            42
          ]),
          isTrue); // '*** SİPARİŞ FİŞİ ***'
      expect(writtenText, contains('Cay (5 x 10.00)'));
      expect(writtenText, contains('Borek (2 x 25.00)'));
      expect(writtenText, contains('TOPLAM: 100.00 TL'));
      expect(
          _containsBytes(mockSocket.writtenBytes, [
            153,
            100,
            101,
            110,
            101,
            110,
            58,
            32,
            51,
            48,
            46,
            48,
            48,
            32,
            84,
            76
          ]),
          isTrue); // 'Ödenen: 30.00 TL'
      expect(
          _containsBytes(mockSocket.writtenBytes, [
            75,
            97,
            108,
            97,
            110,
            32,
            66,
            111,
            114,
            135,
            58,
            32,
            55,
            48,
            46,
            48,
            48,
            32,
            84,
            76
          ]),
          isTrue); // 'Kalan Borç: 70.00 TL'
      expect(writtenText, contains('order|order-test-id-999'));
    });

    test('printXReport outputs correct Ara Rapor layout and categories',
        () async {
      final summary = ReportSummary(
        totalRevenue: 500.0,
        totalSales: 4,
        totalDebt: 100.0,
        totalCollected: 400.0,
        avgBasket: 125.0,
        newCustomers: 2,
        range: DateRange.today(),
      );

      final categories = [
        const CategoryRevenue(
          categoryId: '1',
          categoryName: 'Gıda',
          totalAmount: 350.0,
          saleCount: 3,
          percentage: 70.0,
        ),
        const CategoryRevenue(
          categoryId: '2',
          categoryName: 'Temizlik',
          totalAmount: 150.0,
          saleCount: 1,
          percentage: 30.0,
        ),
      ];

      await printerService.printXReport(summary, categories, testSettings);

      final writtenText = String.fromCharCodes(mockSocket.writtenBytes);
      expect(
          _containsBytes(mockSocket.writtenBytes, [
            71,
            154,
            78,
            32,
            152,
            128,
            152,
            32,
            88,
            32,
            82,
            65,
            80,
            79,
            82,
            85
          ]),
          isTrue); // 'GÜN İÇİ X RAPORU'
      expect(writtenText, contains('Toplam Ciro:'));
      expect(writtenText, contains('500.00 TL'));
      expect(
          _containsBytes(mockSocket.writtenBytes,
              [83, 97, 116, 141, 159, 32, 83, 97, 121, 141, 115, 141, 58]),
          isTrue); // 'Satış Sayısı:'
      expect(writtenText, contains('4'));
      expect(
          _containsBytes(mockSocket.writtenBytes,
              [71, 141, 100, 97, 32, 40, 55, 48, 37, 41]),
          isTrue); // 'Gıda (70%)'
      expect(writtenText, contains('Temizlik (30%)'));
      expect(writtenText, contains('*** RAPOR SONU ***'));
    });

    test('printZReport outputs final daily closeout slip', () async {
      final summary = ReportSummary(
        totalRevenue: 1000.0,
        totalSales: 8,
        totalDebt: 200.0,
        totalCollected: 800.0,
        avgBasket: 125.0,
        newCustomers: 3,
        range: DateRange.today(),
      );

      final categories = [
        const CategoryRevenue(
          categoryId: '1',
          categoryName: 'Genel',
          totalAmount: 1000.0,
          saleCount: 8,
          percentage: 100.0,
        ),
      ];

      await printerService.printZReport(summary, categories, testSettings);

      final writtenText = String.fromCharCodes(mockSocket.writtenBytes);
      expect(
          _containsBytes(mockSocket.writtenBytes, [
            71,
            154,
            78,
            32,
            83,
            79,
            78,
            85,
            32,
            90,
            32,
            82,
            65,
            80,
            79,
            82,
            85
          ]),
          isTrue); // 'GÜN SONU Z RAPORU'
      expect(writtenText, contains('Z No:'));
      expect(writtenText, contains('TOPLAM TAHSILAT:'));
      expect(writtenText, contains('800.00 TL'));
      expect(
          _containsBytes(mockSocket.writtenBytes, [
            71,
            154,
            78,
            32,
            83,
            79,
            78,
            85,
            32,
            75,
            65,
            80,
            65,
            78,
            77,
            73,
            158,
            84,
            73,
            82
          ]),
          isTrue); // 'GÜN SONU KAPANMIŞTIR'
    });

    test('printCollectionReceipt formats collection receipt correctly',
        () async {
      final customer = CustomerEntity(
        id: 'cust-test',
        name: 'Ahmet Yilmaz',
        phone: '05551234567',
        email: 'ahmet@test.com',
        balance: -60.50, // Updated balance after collection
        createdAt: DateTime.now(),
      );

      await printerService.printCollectionReceipt(
        customer,
        150.0,
        'cash',
        'Kismi odeme alindi',
        testSettings,
      );

      expect(mockSocket.isClosed, isTrue);

      final writtenText = String.fromCharCodes(mockSocket.writtenBytes);
      expect(
          _containsBytes(mockSocket.writtenBytes, [
            84,
            65,
            72,
            83,
            152,
            76,
            65,
            84,
            32,
            77,
            65,
            75,
            66,
            85,
            90,
            85
          ]),
          isTrue); // 'TAHSİLAT MAKBUZU'
      expect(writtenText, contains('Ahmet Yilmaz'));
      expect(writtenText,
          contains('Nakit')); // 'cash' translated to Nakit by _getPaymentLabel
      expect(writtenText, contains('Not: Kismi odeme alindi'));
      expect(writtenText, contains('150.00 TL'));
      // Kalan Borç: 60.50 TL (in CP857 bytes)
      expect(
          _containsBytes(mockSocket.writtenBytes, [
            75,
            97,
            108,
            97,
            110,
            32,
            66,
            111,
            114,
            135,
            58,
            32,
            54,
            48,
            46,
            53,
            48,
            32,
            84,
            76
          ]),
          isTrue);
    });

    test(
        'printSaleReceipt and printOrderReceipt display customer debt and credit correctly',
        () async {
      final customer = CustomerEntity(
        id: 'cust-test',
        name: 'Ahmet Yilmaz',
        phone: '05551234567',
        email: 'ahmet@test.com',
        balance: -250.50, // Negative balance = debt
        createdAt: DateTime.now(),
      );

      final sale = SaleEntity(
        id: 'sale-test-id-98765',
        customerId: customer.id,
        totalAmount: 100.0,
        paidAmount: 100.0,
        paymentMethod: 'Nakit',
        status: 'completed',
        createdAt: DateTime(2026, 6, 24, 19, 0),
        items: [],
      );

      await printerService.printSaleReceipt(sale, [], customer, testSettings);

      final writtenText = String.fromCharCodes(mockSocket.writtenBytes);
      expect(writtenText, contains('Ahmet Yilmaz'));
      expect(
          _containsBytes(mockSocket.writtenBytes, [
            71,
            101,
            135,
            109,
            105,
            159,
            32,
            66,
            111,
            114,
            135,
            58,
            32,
            50,
            53,
            48,
            46,
            53,
            48,
            32,
            84,
            76
          ]),
          isTrue); // 'Geçmiş Borç: 250.50 TL'
    });
  });
}

bool _containsBytes(List<int> source, List<int> pattern) {
  if (pattern.isEmpty) return true;
  if (source.length < pattern.length) return false;

  for (int i = 0; i <= source.length - pattern.length; i++) {
    bool match = true;
    for (int j = 0; j < pattern.length; j++) {
      if (source[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}
