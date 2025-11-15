import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order.dart';

class SunmiPrinterService {
  SunmiPrinter get _printer => SunmiPrinter.instance;

  // Yazıcı durumunu kontrol et
  Future<bool> isConnected() async {
    try {
      return await _printer.bindingPrinter() ?? false;
    } catch (e) {
      return false;
    }
  }

  // Yazıcı bilgilerini al
  Future<Map<String, dynamic>> getPrinterInfo() async {
    try {
      final printerVersion = await _printer.printerVersion();
      final serialNumber = await _printer.serialNumber();
      final printerModal = await _printer.printerModal();

      return {
        'version': printerVersion,
        'serial': serialNumber,
        'model': printerModal,
        'connected': await isConnected(),
      };
    } catch (e) {
      return {
        'version': 'Bilinmiyor',
        'serial': 'Bilinmiyor',
        'model': 'Bilinmiyor',
        'connected': false,
        'error': e.toString(),
      };
    }
  }

  // Sipariş fişi yazdır
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

      await _printer.initPrinter();
      await _printer.setAlignment('center');

      // Logo varsa yazdır (opsiyonel)
      // final logoPath = prefs.getString('company_logo');
      // if (logoPath != null) {
      //   await _printer.printImage(File(logoPath));
      // }

      // Şirket başlığı
      await _printer.printText(companyName);
      await _printer.bold();
      await _printer.lineWrap(1);

      // Şirket bilgileri
      if (companyPhone.isNotEmpty) {
        await _printer.printText('Tel: $companyPhone');
      }
      if (companyAddress.isNotEmpty) {
        await _printer.printText(companyAddress);
      }
      if (companyTax.isNotEmpty) {
        await _printer.printText('Vergi No: $companyTax');
      }

      await _printer.line();
      await _printer.lineWrap(1);

      // Sipariş bilgileri
      await _printer.setAlignment('left');
      await _printer.bold();
      await _printer.printText('SİPARİŞ FİŞİ');
      await _printer.resetBold();
      await _printer.lineWrap(1);

      await _printer.printText('Sipariş No: ${order.orderNumber}');
      await _printer.printText('Müşteri: ${order.customerName}');
      if (order.customerPhone.isNotEmpty) {
        await _printer.printText('Tel: ${order.customerPhone}');
      }
      await _printer.printText('Tarih: ${_formatDate(order.createdAt)}');

      await _printer.line();
      await _printer.lineWrap(1);

      // Ürünler
      await _printer.bold();
      await _printer.printText('ÜRÜNLER');
      await _printer.resetBold();
      await _printer.lineWrap(1);

      for (var item in items) {
        // Ürün adı
        await _printer.bold();
        await _printer.printText(item.productName);
        await _printer.resetBold();

        // Miktar x Fiyat = Toplam
        final line =
            '${item.quantity} x ₺${item.price.toStringAsFixed(2)} = ₺${item.subtotal.toStringAsFixed(2)}';
        await _printer.printText(line);
        await _printer.lineWrap(1);
      }

      await _printer.line();
      await _printer.lineWrap(1);

      // Toplam
      await _printer.setAlignment('right');
      await _printer
          .printText('Ara Toplam: ₺${order.total.toStringAsFixed(2)}');

      if (order.paidAmount > 0) {
        await _printer
            .printText('Ödenen: ₺${order.paidAmount.toStringAsFixed(2)}');
      }

      if (order.remainingAmount > 0) {
        await _printer.bold();
        await _printer
            .printText('Kalan: ₺${order.remainingAmount.toStringAsFixed(2)}');
        await _printer.resetBold();
      }

      await _printer.lineWrap(1);
      await _printer.bold();
      await _printer.printText('TOPLAM: ₺${order.total.toStringAsFixed(2)}');
      await _printer.resetBold();

      await _printer.line();
      await _printer.lineWrap(1);

      // Ödeme bilgisi
      await _printer.setAlignment('center');
      final paymentText = order.paymentMethod == 'cash' ? 'NAKİT' : 'KART';
      await _printer.bold();
      await _printer.printText('Ödeme: $paymentText');

      // Durum
      final statusText = _getStatusText(order.status);
      await _printer.printText('Durum: $statusText');
      await _printer.resetBold();

      // Not varsa
      if (order.notes != null && order.notes!.isNotEmpty) {
        await _printer.lineWrap(1);
        await _printer.printText('Not: ${order.notes}');
      }

      await _printer.lineWrap(2);
      await _printer.printText('Teşekkür ederiz!');
      await _printer.lineWrap(1);
      await _printer.printText('www.shamanpos.com');

      await _printer.lineWrap(3);
      await _printer.cut();

      return true;
    } catch (e) {
      print('Yazdırma hatası: $e');
      return false;
    }
  }

  // Test yazdırma
  Future<bool> printTest() async {
    try {
      final connected = await isConnected();
      if (!connected) {
        throw Exception('Yazıcı bağlı değil');
      }

      await _printer.initPrinter();
      await _printer.setAlignment('center');

      await _printer.printText('SHAMAN POS', bold: true);
      await _printer.lineWrap(2);

      await _printer.printText('TEST YAZDIR');
      await _printer.lineWrap(1);

      await _printer.printText(DateTime.now().toString());

      await _printer.lineWrap(2);
      await _printer.printText('Yazıcı çalışıyor! ✓');

      await _printer.lineWrap(3);
      await _printer.cut();

      return true;
    } catch (e) {
      print('Test yazdırma hatası: $e');
      return false;
    }
  }

  // Yardımcı fonksiyonlar
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
