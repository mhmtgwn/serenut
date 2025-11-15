import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order.dart';

/// Sunmi dahili yazıcı servisi - MethodChannel ile native API kullanımı
class SunmiPrinterService {
  // Platform kanalı
  static const MethodChannel _channel = MethodChannel('com.sunmi.printer');

  /// Yazıcı durumunu kontrol et
  Future<bool> isConnected() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasPrinter');
      return result ?? false;
    } catch (e) {
      debugPrint('Yazıcı kontrol hatası: $e');
      return false;
    }
  }

  /// Yazıcı bilgilerini al
  Future<Map<String, dynamic>> getPrinterInfo() async {
    try {
      final version = await _channel.invokeMethod<String>('getPrinterVersion');
      final serial = await _channel.invokeMethod<String>('getPrinterSerialNo');
      final model = await _channel.invokeMethod<String>('getPrinterModel');

      return {
        'version': version ?? 'Bilinmiyor',
        'serial': serial ?? 'Bilinmiyor',
        'model': model ?? 'Sunmi',
        'connected': await isConnected(),
      };
    } catch (e) {
      return {
        'version': 'Bilinmiyor',
        'serial': 'Bilinmiyor',
        'model': 'Sunmi',
        'connected': false,
        'error': e.toString(),
      };
    }
  }

  /// Sipariş fişi yazdır
  Future<bool> printOrderReceipt(Order order, List<OrderItem> items) async {
    try {
      final connected = await isConnected();
      if (!connected) {
        throw Exception('Yazıcı bağlı değil');
      }

      // Şirket bilgilerini al
      final prefs = await SharedPreferences.getInstance();
      final companyName = prefs.getString('company_name') ?? 'SHAMAN POS';
      final companyPhone = prefs.getString('company_phone') ?? '';
      final companyAddress = prefs.getString('company_address') ?? '';
      final companyTax = prefs.getString('company_tax') ?? '';

      // Şirket başlığı
      await _printText(companyName, fontSize: 36, bold: true, align: 1);
      await _printText('', fontSize: 24, bold: false, align: 0);

      // Şirket bilgileri
      if (companyPhone.isNotEmpty) {
        await _printText('Tel: $companyPhone',
            fontSize: 24, bold: false, align: 1);
      }
      if (companyAddress.isNotEmpty) {
        await _printText(companyAddress, fontSize: 24, bold: false, align: 1);
      }
      if (companyTax.isNotEmpty) {
        await _printText('Vergi No: $companyTax',
            fontSize: 24, bold: false, align: 1);
      }

      await _printText('--------------------------------',
          fontSize: 24, bold: false, align: 0);
      await _printText('', fontSize: 24, bold: false, align: 0);

      // Sipariş bilgileri
      await _printText('SİPARİŞ FİŞİ', fontSize: 32, bold: true, align: 0);
      await _printText('', fontSize: 24, bold: false, align: 0);

      await _printText('Sipariş No: ${order.orderNumber}',
          fontSize: 24, bold: false, align: 0);
      await _printText('Müşteri: ${order.customerName}',
          fontSize: 24, bold: false, align: 0);
      if (order.customerPhone.isNotEmpty) {
        await _printText('Tel: ${order.customerPhone}',
            fontSize: 24, bold: false, align: 0);
      }
      await _printText('Tarih: ${_formatDate(order.createdAt)}',
          fontSize: 24, bold: false, align: 0);

      await _printText('--------------------------------',
          fontSize: 24, bold: false, align: 0);
      await _printText('', fontSize: 24, bold: false, align: 0);

      // Ürünler
      await _printText('ÜRÜNLER', fontSize: 28, bold: true, align: 0);
      await _printText('', fontSize: 24, bold: false, align: 0);

      for (var item in items) {
        // Ürün adı
        await _printText(item.productName, fontSize: 24, bold: true, align: 0);

        // Miktar x Fiyat = Toplam
        final line =
            '${item.quantity} x ₺${item.price.toStringAsFixed(2)} = ₺${item.subtotal.toStringAsFixed(2)}';
        await _printText(line, fontSize: 24, bold: false, align: 0);
        await _printText('', fontSize: 24, bold: false, align: 0);
      }

      await _printText('--------------------------------',
          fontSize: 24, bold: false, align: 0);
      await _printText('', fontSize: 24, bold: false, align: 0);

      // Toplam
      await _printText('Ara Toplam: ₺${order.total.toStringAsFixed(2)}',
          fontSize: 28, bold: false, align: 2);

      if (order.paidAmount > 0) {
        await _printText('Ödenen: ₺${order.paidAmount.toStringAsFixed(2)}',
            fontSize: 28, bold: false, align: 2);
      }

      if (order.remainingAmount > 0) {
        await _printText('Kalan: ₺${order.remainingAmount.toStringAsFixed(2)}',
            fontSize: 28, bold: true, align: 2);
      }

      await _printText('', fontSize: 24, bold: false, align: 0);
      await _printText('TOPLAM: ₺${order.total.toStringAsFixed(2)}',
          fontSize: 36, bold: true, align: 2);

      await _printText('--------------------------------',
          fontSize: 24, bold: false, align: 0);
      await _printText('', fontSize: 24, bold: false, align: 0);

      // Ödeme bilgisi
      final paymentText = order.paymentMethod == 'cash' ? 'NAKİT' : 'KART';
      await _printText('Ödeme: $paymentText',
          fontSize: 28, bold: true, align: 1);

      // Durum
      final statusText = _getStatusText(order.status);
      await _printText('Durum: $statusText',
          fontSize: 28, bold: true, align: 1);

      // Not varsa
      if (order.notes != null && order.notes!.isNotEmpty) {
        await _printText('', fontSize: 24, bold: false, align: 0);
        await _printText('Not: ${order.notes}',
            fontSize: 24, bold: false, align: 0);
      }

      await _printText('', fontSize: 24, bold: false, align: 0);
      await _printText('', fontSize: 24, bold: false, align: 0);
      await _printText('Teşekkür ederiz!', fontSize: 24, bold: false, align: 1);
      await _printText('www.shamanpos.com',
          fontSize: 24, bold: false, align: 1);

      await _printText('\n\n\n', fontSize: 24, bold: false, align: 0);

      return true;
    } catch (e) {
      debugPrint('Yazdırma hatası: $e');
      return false;
    }
  }

  /// Test yazdırma
  Future<bool> printTest() async {
    try {
      final connected = await isConnected();
      if (!connected) {
        throw Exception('Yazıcı bağlı değil');
      }

      await _printText('SHAMAN POS', fontSize: 40, bold: true, align: 1);
      await _printText('', fontSize: 24, bold: false, align: 0);
      await _printText('', fontSize: 24, bold: false, align: 0);

      await _printText('TEST YAZDIR', fontSize: 28, bold: false, align: 1);
      await _printText('', fontSize: 24, bold: false, align: 0);

      await _printText(DateTime.now().toString(),
          fontSize: 24, bold: false, align: 1);

      await _printText('', fontSize: 24, bold: false, align: 0);
      await _printText('', fontSize: 24, bold: false, align: 0);
      await _printText('Yazıcı çalışıyor! ✓',
          fontSize: 28, bold: true, align: 1);

      await _printText('\n\n\n', fontSize: 24, bold: false, align: 0);

      return true;
    } catch (e) {
      debugPrint('Test yazdırma hatası: $e');
      return false;
    }
  }

  /// Metin yazdır (private helper)
  Future<void> _printText(
    String text, {
    required int fontSize,
    required bool bold,
    required int align, // 0=left, 1=center, 2=right
  }) async {
    try {
      await _channel.invokeMethod('printText', {
        'text': text,
        'fontSize': fontSize,
        'bold': bold,
        'align': align,
      });
    } catch (e) {
      debugPrint('Metin yazdırma hatası: $e');
      rethrow;
    }
  }

  /// Yardımcı fonksiyonlar
  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoDate;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Beklemede';
      case 'preparing':
        return 'Hazırlanıyor';
      case 'ready':
        return 'Hazır';
      case 'delivered':
        return 'Teslim Edildi';
      case 'cancelled':
        return 'İptal';
      default:
        return status;
    }
  }
}
