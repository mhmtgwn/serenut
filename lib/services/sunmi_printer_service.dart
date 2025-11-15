import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order.dart';

class SunmiPrinterService {
  // Yazıcı durumunu kontrol et
  Future<bool> isConnected() async {
    try {
      return await SunmiPrinter.bindingPrinter() ?? false;
    } catch (e) {
      return false;
    }
  }

  // Yazıcı bilgilerini al
  Future<Map<String, dynamic>> getPrinterInfo() async {
    try {
      final printerVersion = await SunmiPrinter.printerVersion();
      final serialNumber = await SunmiPrinter.serialNumber();
      final printerModal = await SunmiPrinter.printerModal();

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

      await SunmiPrinter.initPrinter();

      // Şirket başlığı
      await SunmiPrinter.printText(
        companyName,
        style: SunmiTextStyle(
          bold: true,
          fontSize: 32,
          align: SunmiPrintAlign.CENTER,
        ),
      );
      await SunmiPrinter.lineWrap(1);

      // Şirket bilgileri
      if (companyPhone.isNotEmpty) {
        await SunmiPrinter.printText(
          'Tel: $companyPhone',
          style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
        );
      }
      if (companyAddress.isNotEmpty) {
        await SunmiPrinter.printText(
          companyAddress,
          style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
        );
      }
      if (companyTax.isNotEmpty) {
        await SunmiPrinter.printText(
          'Vergi No: $companyTax',
          style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
        );
      }

      await SunmiPrinter.line();
      await SunmiPrinter.lineWrap(1);

      // Sipariş bilgileri
      await SunmiPrinter.printText(
        'SİPARİŞ FİŞİ',
        style: SunmiTextStyle(
          bold: true,
          fontSize: 28,
          align: SunmiPrintAlign.LEFT,
        ),
      );
      await SunmiPrinter.lineWrap(1);

      await SunmiPrinter.printText('Sipariş No: ${order.orderNumber}');
      await SunmiPrinter.printText('Müşteri: ${order.customerName}');
      if (order.customerPhone.isNotEmpty) {
        await SunmiPrinter.printText('Tel: ${order.customerPhone}');
      }
      await SunmiPrinter.printText('Tarih: ${_formatDate(order.createdAt)}');

      await SunmiPrinter.line();
      await SunmiPrinter.lineWrap(1);

      // Ürünler
      await SunmiPrinter.printText(
        'ÜRÜNLER',
        style: SunmiTextStyle(bold: true),
      );
      await SunmiPrinter.lineWrap(1);

      for (var item in items) {
        // Ürün adı
        await SunmiPrinter.printText(
          item.productName,
          style: SunmiTextStyle(bold: true),
        );

        // Miktar x Fiyat = Toplam
        final line =
            '${item.quantity} x ₺${item.price.toStringAsFixed(2)} = ₺${item.subtotal.toStringAsFixed(2)}';
        await SunmiPrinter.printText(line);
        await SunmiPrinter.lineWrap(1);
      }

      await SunmiPrinter.line();
      await SunmiPrinter.lineWrap(1);

      // Toplam
      await SunmiPrinter.printText(
        'Ara Toplam: ₺${order.total.toStringAsFixed(2)}',
        style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT),
      );

      if (order.paidAmount > 0) {
        await SunmiPrinter.printText(
          'Ödenen: ₺${order.paidAmount.toStringAsFixed(2)}',
          style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT),
        );
      }

      if (order.remainingAmount > 0) {
        await SunmiPrinter.printText(
          'Kalan: ₺${order.remainingAmount.toStringAsFixed(2)}',
          style: SunmiTextStyle(
            bold: true,
            align: SunmiPrintAlign.RIGHT,
          ),
        );
      }

      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printText(
        'TOPLAM: ₺${order.total.toStringAsFixed(2)}',
        style: SunmiTextStyle(
          bold: true,
          fontSize: 32,
          align: SunmiPrintAlign.RIGHT,
        ),
      );

      await SunmiPrinter.line();
      await SunmiPrinter.lineWrap(1);

      // Ödeme bilgisi
      final paymentText = order.paymentMethod == 'cash' ? 'NAKİT' : 'KART';
      await SunmiPrinter.printText(
        'Ödeme: $paymentText',
        style: SunmiTextStyle(
          bold: true,
          align: SunmiPrintAlign.CENTER,
        ),
      );

      // Durum
      final statusText = _getStatusText(order.status);
      await SunmiPrinter.printText(
        'Durum: $statusText',
        style: SunmiTextStyle(
          bold: true,
          align: SunmiPrintAlign.CENTER,
        ),
      );

      // Not varsa
      if (order.notes != null && order.notes!.isNotEmpty) {
        await SunmiPrinter.lineWrap(1);
        await SunmiPrinter.printText('Not: ${order.notes}');
      }

      await SunmiPrinter.lineWrap(2);
      await SunmiPrinter.printText(
        'Teşekkür ederiz!',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
      );
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printText(
        'www.shamanpos.com',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
      );

      await SunmiPrinter.lineWrap(3);
      await SunmiPrinter.cut();

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

      await SunmiPrinter.initPrinter();

      await SunmiPrinter.printText(
        'SHAMAN POS',
        style: SunmiTextStyle(
          bold: true,
          fontSize: 40,
          align: SunmiPrintAlign.CENTER,
        ),
      );
      await SunmiPrinter.lineWrap(2);

      await SunmiPrinter.printText(
        'TEST YAZDIR',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
      );
      await SunmiPrinter.lineWrap(1);

      await SunmiPrinter.printText(
        DateTime.now().toString(),
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
      );

      await SunmiPrinter.lineWrap(2);
      await SunmiPrinter.printText(
        'Yazıcı çalışıyor! ✓',
        style: SunmiTextStyle(
          bold: true,
          align: SunmiPrintAlign.CENTER,
        ),
      );

      await SunmiPrinter.lineWrap(3);
      await SunmiPrinter.cut();

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
