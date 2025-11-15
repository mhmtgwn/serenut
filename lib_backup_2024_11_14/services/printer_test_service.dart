import 'package:flutter/foundation.dart';
import 'receipt_service.dart';
import '../utils/error_handler.dart';

/// Yazıcı test servisi
class PrinterTestService {
  static final PrinterTestService _instance = PrinterTestService._internal();
  factory PrinterTestService() => _instance;
  PrinterTestService._internal();

  final ReceiptService _receiptService = ReceiptService();

  /// Test fişi yazdır
  Future<bool> printTestReceipt() async {
    try {
      debugPrint('Test fişi yazdırılıyor...');

      // Test verileri oluştur
      final testOrder = {
        'id': 999,
        'customerId': 1,
        'customerName': 'Test Müşteri',
        'customerPhone': '0555 123 45 67',
        'orderDate': DateTime.now().toIso8601String(),
        'totalAmount': 150.75,
        'paidAmount': 150.75,
        'remainingAmount': 0.0,
        'orderStatus': 'completed',
        'paymentMethod': 'Nakit',
        'notes': 'Test sipariş notu',
      };

      final testCustomer = {
        'id': 1,
        'name': 'Test Müşteri',
        'phone': '0555 123 45 67',
        'address': 'Test Adres, Test Mahalle, Test İlçe',
        'email': 'test@example.com',
      };

      final testItems = [
        {
          'id': 1,
          'orderId': 999,
          'productId': 1,
          'productName': 'Test Ürün 1',
          'quantity': 2.0,
          'unitPrice': 25.50,
          'subtotal': 51.0,
        },
        {
          'id': 2,
          'orderId': 999,
          'productId': 2,
          'productName': 'Test Ürün 2',
          'quantity': 1.0,
          'unitPrice': 99.75,
          'subtotal': 99.75,
        },
      ];

      final testBusinessInfo = {
        'businessName': 'SHAMAN POS TEST',
        'address': 'Test İşletme Adresi',
        'phone': '0212 555 00 00',
        'taxInfo': 'VD: Test VD No: 1234567890',
        'footerNote': 'Test için teşekkürler!',
      };

      // Test fişini yazdır
      final success = await _receiptService.printOrderReceipt(
        order: testOrder,
        customer: testCustomer,
        items: testItems,
        businessInfo: testBusinessInfo,
      );

      if (success) {
        debugPrint('Test fişi başarıyla yazdırıldı');
        ErrorHandler.showSuccess('Test fişi başarıyla yazdırıldı');
      } else {
        debugPrint('Test fişi yazdırılamadı');
        ErrorHandler.reportError(
          'Test Hatası',
          'Test fişi yazdırılamadı',
        );
      }

      return success;
    } catch (e) {
      debugPrint('Test fişi yazdırma hatası: $e');
      ErrorHandler.reportError(
        'Test Hatası',
        'Test fişi yazdırılırken bir hata oluştu',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Basit test yazdırma
  Future<bool> printSimpleTest() async {
    try {
      debugPrint('Basit test yazdırılıyor...');

      // Minimal test verileri
      final testOrder = {
        'id': 888,
        'totalAmount': 10.0,
        'paidAmount': 10.0,
        'remainingAmount': 0.0,
        'paymentMethod': 'Test',
        'notes': '',
      };

      final testCustomer = {
        'name': 'Test',
        'phone': '',
        'address': '',
      };

      final testItems = [
        {
          'productName': 'Test Item',
          'quantity': 1.0,
          'unitPrice': 10.0,
          'subtotal': 10.0,
        },
      ];

      final testBusinessInfo = {
        'businessName': 'TEST',
        'address': '',
        'phone': '',
        'taxInfo': '',
        'footerNote': 'Test',
      };

      final success = await _receiptService.printOrderReceipt(
        order: testOrder,
        customer: testCustomer,
        items: testItems,
        businessInfo: testBusinessInfo,
      );

      if (success) {
        debugPrint('Basit test başarılı');
        ErrorHandler.showSuccess('Basit test başarılı');
      } else {
        debugPrint('Basit test başarısız');
      }

      return success;
    } catch (e) {
      debugPrint('Basit test hatası: $e');
      return false;
    }
  }
}
