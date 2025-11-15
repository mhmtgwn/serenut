import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import '../helpers/printer_helper.dart';
import 'database_service.dart';
import '../utils/error_handler.dart';

class ReceiptService {
  static final ReceiptService _instance = ReceiptService._internal();
  factory ReceiptService() => _instance;
  ReceiptService._internal();

  final PrinterHelper _printerHelper = PrinterHelper();

  /// Sipariş fişi oluştur ve yazdır
  Future<bool> printOrderReceipt({
    required Map<String, dynamic> order,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> businessInfo,
    bool showPreview = false,
  }) async {
    try {
      // Fiş verilerini oluştur
      final receiptData = _generateReceiptData(
        order: order,
        customer: customer,
        items: items,
        businessInfo: businessInfo,
      );

      if (showPreview) {
        // Önizleme göster (gelecekte implement edilebilir)
        return true;
      }

      // Fişi yazdır
      return await _printReceipt(receiptData);
    } catch (e) {
      return false;
    }
  }

  /// Fiş verilerini oluştur
  Map<String, dynamic> _generateReceiptData({
    required Map<String, dynamic> order,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> businessInfo,
  }) {
    final now = DateTime.now();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return {
      'businessName': businessInfo['businessName'] ?? 'İŞLETME',
      'address': businessInfo['address'] ?? '',
      'phone': businessInfo['phone'] ?? '',
      'taxInfo': businessInfo['taxInfo'] ?? '',
      'receiptNumber': 'FİŞ #${order['id']}',
      'date': dateFormat.format(now),
      'customerName': customer['name'],
      'customerPhone': customer['phone'] ?? '',
      'customerAddress': customer['address'] ?? '',
      'items': items.map((item) => {
        'name': item['productName'],
        'quantity': item['quantity'],
        'unitPrice': item['unitPrice'],
        'subtotal': item['subtotal'],
      }).toList(),
      'subtotal': order['totalAmount'],
      'tax': 0.0, // KDV hesaplaması eklenebilir
      'total': order['totalAmount'],
      'paidAmount': order['paidAmount'],
      'remainingAmount': order['remainingAmount'],
      'paymentMethod': order['paymentMethod'],
      'orderStatus': order['orderStatus'],
      'notes': order['notes'] ?? '',
      'footerNote': businessInfo['footerNote'] ?? 'Teşekkür ederiz!',
    };
  }

  /// Fişi yazdır
  Future<bool> _printReceipt(Map<String, dynamic> receiptData) async {
    try {
      // Fiş başlığı
      final title = receiptData['businessName'] as String;
      
      // Fiş öğeleri
      final items = (receiptData['items'] as List).map((item) => {
        'name': item['name'] as String,
        'quantity': item['quantity'] as double,
        'price': item['unitPrice'] as double,
        'subtotal': item['subtotal'] as double,
      }).toList();
      
      final total = receiptData['total'] as double;
      final paymentMethod = receiptData['paymentMethod'] as String;

      // Fiş yazıcısı olarak atanmış cihazı bul
      final db = DatabaseService.instance;
      final receiptPrinter = await db.getReceiptPrinter();
      
      if (receiptPrinter == null) {
        debugPrint('Fiş yazıcısı atanmamış');
        ErrorHandler.reportError(
          'Yazıcı Hatası',
          'Fiş yazıcısı atanmamış. Lütfen ayarlardan bir yazıcı atayın.',
        );
        return false;
      }

      // Yazıcıya fiş gönder
      debugPrint('Fiş yazdırma başlatılıyor - Yazıcı: ${receiptPrinter['name']} (${receiptPrinter['id']})');
      
      final success = await _printerHelper.printReceipt(
        printerId: receiptPrinter['id'],
        title: title,
        subtitle: receiptData['receiptNumber'] as String,
        items: items,
        total: total,
        paymentMethod: paymentMethod,
      );
      
      if (success) {
        debugPrint('Fiş başarıyla yazdırıldı');
      } else {
        debugPrint('Fiş yazdırma başarısız');
        ErrorHandler.reportError(
          'Yazdırma Hatası',
          'Fiş yazdırılamadı. Yazıcı bağlantısını kontrol edin.',
        );
      }
      
      return success;
    } catch (e) {
      debugPrint('Fiş yazdırma hatası: $e');
      ErrorHandler.reportError(
        'Fiş Yazdırma Hatası',
        'Fiş yazdırılırken bir sorun oluştu.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Belirli yazıcı ile sipariş fişi yazdır
  Future<bool> printOrderReceiptWithPrinter({
    required String printerId,
    required Map<String, dynamic> order,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> businessInfo,
    bool showPreview = false,
  }) async {
    try {
      debugPrint('Belirli yazıcı ile fiş yazdırılıyor: $printerId');
      
      // Fiş verilerini oluştur
      final receiptData = _generateReceiptData(
        order: order,
        customer: customer,
        items: items,
        businessInfo: businessInfo,
      );

      if (showPreview) {
        // Önizleme göster (gelecekte implement edilebilir)
        return true;
      }

      // Fiş başlığı
      final title = receiptData['businessName'] as String;
      
      // Fiş öğeleri
      final receiptItems = (receiptData['items'] as List).map((item) => {
        'name': item['name'] as String,
        'quantity': item['quantity'] as double,
        'price': item['unitPrice'] as double,
        'subtotal': item['subtotal'] as double,
      }).toList();
      
      final total = receiptData['total'] as double;
      final paymentMethod = receiptData['paymentMethod'] as String;

      // Belirli yazıcı ile fişi yazdır
      debugPrint('Fiş yazdırma başlatılıyor - Yazıcı ID: $printerId');
      
      final success = await _printerHelper.printReceipt(
        printerId: printerId,
        title: title,
        subtitle: receiptData['receiptNumber'] as String,
        items: receiptItems,
        total: total,
        paymentMethod: paymentMethod,
      );
      
      if (success) {
        debugPrint('Fiş başarıyla yazdırıldı');
      } else {
        debugPrint('Fiş yazdırma başarısız');
        ErrorHandler.reportError(
          'Yazdırma Hatası',
          'Fiş yazdırılamadı. Yazıcı bağlantısını kontrol edin.',
        );
      }
      
      return success;
    } catch (e) {
      debugPrint('Fiş yazdırma hatası: $e');
      ErrorHandler.reportError(
        'Fiş Yazdırma Hatası',
        'Fiş yazdırılırken bir sorun oluştu.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Fiş önizleme verilerini al
  Map<String, dynamic> getReceiptPreview({
    required Map<String, dynamic> order,
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> businessInfo,
  }) {
    return _generateReceiptData(
      order: order,
      customer: customer,
      items: items,
      businessInfo: businessInfo,
    );
  }
}
