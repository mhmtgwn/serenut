import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../../shared/utils/debug_config.dart';
import 'bluetooth_service.dart';

/// Sipariş fişi yazdırma servisi
class OrderReceiptService {
  static final OrderReceiptService instance = OrderReceiptService._init();
  final BluetoothService _bluetoothService = BluetoothService.instance;
  static const MethodChannel _printerChannel =
      MethodChannel('com.sunmi.printer');

  OrderReceiptService._init();

  /// Sipariş fişi yazdır
  Future<bool> printOrderReceipt({
    required String connection, // 'bluetooth' veya 'internal'
    String? address, // Bluetooth adresi
    required String protocol, // 'esc_pos', 'tsc', 'cpcl', 'zpl'
    required int paperWidth, // mm cinsinden
    // Logo
    bool printLogo = true,
    // Firma bilgileri
    required String companyName,
    String? companyAddress,
    String? companyPhone,
    String? companyTaxNo,
    // Müşteri bilgileri
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    // Sipariş bilgileri
    required String orderNumber,
    required DateTime orderDate,
    required List<OrderItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    double? previousDebt, // Eski borç
    double? payment, // Ödenen
    double? remaining, // Kalan
    // Footer
    String? thankYouMessage,
    bool printBarcode = true,
    bool printQRCode = false,
  }) async {
    try {
      DebugConfig.logDebug('Sipariş fişi yazdırılıyor: $orderNumber');

      // Protokole göre komutları oluştur
      final Uint8List commands = await _createOrderReceipt(
        protocol: protocol,
        paperWidth: paperWidth,
        printLogo: printLogo,
        companyName: companyName,
        companyAddress: companyAddress,
        companyPhone: companyPhone,
        companyTaxNo: companyTaxNo,
        customerName: customerName,
        customerPhone: customerPhone,
        customerAddress: customerAddress,
        orderNumber: orderNumber,
        orderDate: orderDate,
        items: items,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        total: total,
        previousDebt: previousDebt,
        payment: payment,
        remaining: remaining,
        thankYouMessage: thankYouMessage,
        printBarcode: printBarcode,
        printQRCode: printQRCode,
      );

      // Bağlantı tipine göre yazdır
      if (connection == 'bluetooth') {
        return await _printViaBluetooth(commands);
      } else if (connection == 'internal') {
        return await _printViaInternal(commands);
      }

      return false;
    } catch (e) {
      DebugConfig.logError('Sipariş fişi yazdırma hatası', e);
      return false;
    }
  }

  /// Bluetooth üzerinden yazdır
  Future<bool> _printViaBluetooth(Uint8List data) async {
    try {
      final success = await _bluetoothService.sendData(data);
      if (success) {
        DebugConfig.logSuccess('Sipariş fişi başarıyla gönderildi');
      } else {
        DebugConfig.logError('Sipariş fişi gönderilemedi', null);
      }
      return success;
    } catch (e) {
      DebugConfig.logError('Bluetooth yazdırma hatası', e);
      return false;
    }
  }

  /// Dahili yazıcı üzerinden yazdır
  Future<bool> _printViaInternal(Uint8List data) async {
    try {
      final Map<String, dynamic> params = {'data': data};
      final bool result =
          await _printerChannel.invokeMethod('printRawData', params);
      if (result) {
        DebugConfig.logSuccess('Dahili yazıcıya sipariş fişi gönderildi');
      } else {
        DebugConfig.logError('Dahili yazıcı yazdırma başarısız', null);
      }
      return result;
    } catch (e) {
      DebugConfig.logError('Dahili yazıcı hatası', e);
      return false;
    }
  }

  /// Protokole göre sipariş fişi oluştur
  Future<Uint8List> _createOrderReceipt({
    required String protocol,
    required int paperWidth,
    required bool printLogo,
    required String companyName,
    String? companyAddress,
    String? companyPhone,
    String? companyTaxNo,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    required String orderNumber,
    required DateTime orderDate,
    required List<OrderItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    double? previousDebt,
    double? payment,
    double? remaining,
    String? thankYouMessage,
    required bool printBarcode,
    required bool printQRCode,
  }) async {
    switch (protocol.toLowerCase()) {
      case 'esc_pos':
        return await _createEscPosReceipt(
          paperWidth: paperWidth,
          printLogo: printLogo,
          companyName: companyName,
          companyAddress: companyAddress,
          companyPhone: companyPhone,
          companyTaxNo: companyTaxNo,
          customerName: customerName,
          customerPhone: customerPhone,
          customerAddress: customerAddress,
          orderNumber: orderNumber,
          orderDate: orderDate,
          items: items,
          subtotal: subtotal,
          discount: discount,
          tax: tax,
          total: total,
          previousDebt: previousDebt,
          payment: payment,
          remaining: remaining,
          thankYouMessage: thankYouMessage,
          printBarcode: printBarcode,
          printQRCode: printQRCode,
        );
      default:
        DebugConfig.logWarning(
            'Bilinmeyen protokol: $protocol, ESC/POS kullanılıyor');
        return await _createEscPosReceipt(
          paperWidth: paperWidth,
          printLogo: printLogo,
          companyName: companyName,
          companyAddress: companyAddress,
          companyPhone: companyPhone,
          companyTaxNo: companyTaxNo,
          customerName: customerName,
          customerPhone: customerPhone,
          customerAddress: customerAddress,
          orderNumber: orderNumber,
          orderDate: orderDate,
          items: items,
          subtotal: subtotal,
          discount: discount,
          tax: tax,
          total: total,
          previousDebt: previousDebt,
          payment: payment,
          remaining: remaining,
          thankYouMessage: thankYouMessage,
          printBarcode: printBarcode,
          printQRCode: printQRCode,
        );
    }
  }

  /// ESC/POS sipariş fişi oluştur
  Future<Uint8List> _createEscPosReceipt({
    required int paperWidth,
    required bool printLogo,
    required String companyName,
    String? companyAddress,
    String? companyPhone,
    String? companyTaxNo,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    required String orderNumber,
    required DateTime orderDate,
    required List<OrderItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    double? previousDebt,
    double? payment,
    double? remaining,
    String? thankYouMessage,
    required bool printBarcode,
    required bool printQRCode,
  }) async {
    List<int> bytes = [];

    try {
      // ESC @ - Yazıcıyı sıfırla
      bytes.addAll([27, 64]);

      // ==================== LOGO ====================
      if (printLogo) {
        int maxWidth = paperWidth <= 58 ? 150 : (paperWidth <= 80 ? 200 : 250);
        final logo = await _loadAndProcessLogo(maxWidth);
        bytes.addAll(_formatLogoEscPos(logo));
      }

      // ==================== FİRMA BİLGİLERİ ====================
      bytes.addAll([27, 97, 1]); // Ortala
      bytes.addAll([27, 69, 1, 29, 33, 17]); // Kalın + Büyük
      bytes.addAll('$companyName\n'.codeUnits);
      bytes.addAll([27, 69, 0, 29, 33, 0]); // Normal

      if (companyAddress != null) {
        bytes.addAll([27, 97, 1]); // Ortala
        bytes.addAll('$companyAddress\n'.codeUnits);
      }

      if (companyPhone != null) {
        bytes.addAll([27, 97, 1]); // Ortala
        bytes.addAll('Tel: $companyPhone\n'.codeUnits);
      }

      if (companyTaxNo != null) {
        bytes.addAll([27, 97, 1]); // Ortala
        bytes.addAll('Vergi No: $companyTaxNo\n'.codeUnits);
      }

      bytes.addAll('\n'.codeUnits);
      bytes.addAll([27, 97, 1]); // Ortala
      bytes.addAll('--------------------------------\n'.codeUnits);

      // ==================== SİPARİŞ BİLGİLERİ ====================
      bytes.addAll([27, 97, 0]); // Sol hizala
      bytes.addAll([27, 69, 1]); // Kalın
      bytes.addAll('SIPARIS FISI\n'.codeUnits);
      bytes.addAll([27, 69, 0]); // Normal

      bytes.addAll('Siparis No: $orderNumber\n'.codeUnits);

      final dateStr =
          '${orderDate.day.toString().padLeft(2, '0')}/${orderDate.month.toString().padLeft(2, '0')}/${orderDate.year}';
      final timeStr =
          '${orderDate.hour.toString().padLeft(2, '0')}:${orderDate.minute.toString().padLeft(2, '0')}';
      bytes.addAll('Tarih: $dateStr $timeStr\n'.codeUnits);

      bytes.addAll('--------------------------------\n'.codeUnits);

      // ==================== MÜŞTERİ BİLGİLERİ ====================
      if (customerName != null ||
          customerPhone != null ||
          customerAddress != null) {
        bytes.addAll([27, 69, 1]); // Kalın
        bytes.addAll('MUSTERI BILGILERI\n'.codeUnits);
        bytes.addAll([27, 69, 0]); // Normal

        if (customerName != null) {
          bytes.addAll('Ad: $customerName\n'.codeUnits);
        }

        if (customerPhone != null) {
          bytes.addAll('Tel: $customerPhone\n'.codeUnits);
        }

        if (customerAddress != null) {
          bytes.addAll('Adres: $customerAddress\n'.codeUnits);
        }

        bytes.addAll('--------------------------------\n'.codeUnits);
      }

      // ==================== ÜRÜN LİSTESİ ====================
      bytes.addAll([27, 69, 1]); // Kalın
      bytes.addAll('URUNLER\n'.codeUnits);
      bytes.addAll([27, 69, 0]); // Normal

      for (var item in items) {
        // Ürün adı
        bytes.addAll('${item.name}\n'.codeUnits);

        // Miktar x Fiyat = Toplam
        final itemLine =
            '  ${item.quantity} x ${_formatPrice(item.price)} = ${_formatPrice(item.total)}';
        bytes.addAll('$itemLine\n'.codeUnits);
      }

      bytes.addAll('--------------------------------\n'.codeUnits);

      // ==================== TOPLAM BİLGİLERİ ====================
      bytes.addAll([27, 97, 2]); // Sağa hizala

      bytes.addAll('Ara Toplam: ${_formatPrice(subtotal)}\n'.codeUnits);

      if (discount > 0) {
        bytes.addAll('Indirim: -${_formatPrice(discount)}\n'.codeUnits);
      }

      if (tax > 0) {
        bytes.addAll('KDV: ${_formatPrice(tax)}\n'.codeUnits);
      }

      bytes.addAll([27, 69, 1, 29, 33, 17]); // Kalın + Büyük
      bytes.addAll('TOPLAM: ${_formatPrice(total)}\n'.codeUnits);
      bytes.addAll([27, 69, 0, 29, 33, 0]); // Normal

      // Eski borç varsa
      if (previousDebt != null && previousDebt > 0) {
        bytes.addAll('\n'.codeUnits);
        bytes.addAll('Eski Borc: ${_formatPrice(previousDebt)}\n'.codeUnits);
        bytes.addAll([27, 69, 1]); // Kalın
        bytes.addAll(
            'Genel Toplam: ${_formatPrice(total + previousDebt)}\n'.codeUnits);
        bytes.addAll([27, 69, 0]); // Normal
      }

      // Ödeme bilgileri
      if (payment != null && payment > 0) {
        bytes.addAll('\n'.codeUnits);
        bytes.addAll('Odenen: ${_formatPrice(payment)}\n'.codeUnits);
      }

      if (remaining != null && remaining > 0) {
        bytes.addAll([27, 69, 1]); // Kalın
        bytes.addAll('Kalan: ${_formatPrice(remaining)}\n'.codeUnits);
        bytes.addAll([27, 69, 0]); // Normal
      } else if (remaining != null && remaining < 0) {
        bytes.addAll([27, 69, 1]); // Kalın
        bytes.addAll('Para Ustu: ${_formatPrice(-remaining)}\n'.codeUnits);
        bytes.addAll([27, 69, 0]); // Normal
      }

      bytes.addAll([27, 97, 0]); // Sol hizala
      bytes.addAll('--------------------------------\n'.codeUnits);

      // ==================== BARKOD / QR KOD ====================
      if (printBarcode) {
        bytes.addAll([27, 97, 1]); // Ortala
        bytes.addAll('\n'.codeUnits);

        // Barkod yazdır - CODE128
        bytes.addAll([29, 107, 73]); // GS k 73 (CODE128)
        final barcodeData = '{B$orderNumber';
        bytes.addAll([barcodeData.length]); // Uzunluk
        bytes.addAll(barcodeData.codeUnits); // Barkod verisi

        bytes.addAll('\n'.codeUnits);
        bytes.addAll('$orderNumber\n'.codeUnits);
      }

      if (printQRCode) {
        bytes.addAll([27, 97, 1]); // Ortala
        bytes.addAll('\n'.codeUnits);

        // QR Kod yazdır
        final qrData = 'ORDER:$orderNumber';
        final qrDataBytes = qrData.codeUnits;

        // QR kod model ayarla
        bytes.addAll([29, 40, 107, 4, 0, 49, 65, 50, 0]); // Model 2

        // QR kod boyutu ayarla
        bytes.addAll([29, 40, 107, 3, 0, 49, 67, 5]); // Size 5

        // QR kod hata düzeltme seviyesi
        bytes.addAll([29, 40, 107, 3, 0, 49, 69, 49]); // Level M

        // QR kod verisi
        final qrLen = qrDataBytes.length + 3;
        bytes.addAll([29, 40, 107, qrLen % 256, qrLen ~/ 256, 49, 80, 48]);
        bytes.addAll(qrDataBytes);

        // QR kodu yazdır
        bytes.addAll([29, 40, 107, 3, 0, 49, 81, 48]);

        bytes.addAll('\n\n'.codeUnits);
      }

      // ==================== TEŞEKKÜR MESAJI ====================
      if (thankYouMessage != null) {
        bytes.addAll([27, 97, 1]); // Ortala
        bytes.addAll('\n'.codeUnits);
        bytes.addAll('$thankYouMessage\n'.codeUnits);
      }

      // ==================== KAĞIT KES ====================
      bytes.addAll('\n\n\n'.codeUnits);
      bytes.addAll([29, 86, 1]); // Kağıt kes

      DebugConfig.logSuccess(
          'ESC/POS sipariş fişi oluşturuldu: ${bytes.length} byte');

      return Uint8List.fromList(bytes);
    } catch (e) {
      DebugConfig.logError('ESC/POS sipariş fişi oluşturma hatası', e);
      return Uint8List(0);
    }
  }

  /// Logo yükle ve işle
  Future<img.Image?> _loadAndProcessLogo(int maxWidth) async {
    try {
      final ByteData data = await rootBundle.load('assets/logo.png');
      final Uint8List imageBytes = data.buffer.asUint8List();
      img.Image? image = img.decodeImage(imageBytes);

      if (image == null) return null;

      if (maxWidth < 100) maxWidth = 150;

      if (image.width > maxWidth) {
        final aspectRatio = image.height / image.width;
        final newHeight = (maxWidth * aspectRatio).round();
        image = img.copyResize(
          image,
          width: maxWidth,
          height: newHeight,
          interpolation: img.Interpolation.linear,
        );
      }

      // Şeffaflık kontrolü
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          final alpha = pixel.a.toInt();
          if (alpha < 128) {
            image.setPixelRgba(x, y, 255, 255, 255, 255);
          }
        }
      }

      image = img.grayscale(image);
      image = img.adjustColor(image, contrast: 1.3, brightness: 1.1);

      // Threshold
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          final gray = pixel.r.toInt();
          final newColor = gray < 150 ? 0 : 255;
          image.setPixelRgba(x, y, newColor, newColor, newColor, 255);
        }
      }

      return image;
    } catch (e) {
      DebugConfig.logError('Logo yükleme hatası', e);
      return null;
    }
  }

  /// Logo formatla - ESC/POS
  List<int> _formatLogoEscPos(img.Image? image) {
    List<int> bytes = [];

    try {
      if (image != null && image.width >= 50 && image.height >= 20) {
        bytes.addAll([27, 97, 1]); // Ortala

        int widthBytes = (image.width + 7) ~/ 8;
        bytes.addAll([29, 118, 48, 0]);
        bytes.addAll([widthBytes % 256, widthBytes ~/ 256]);
        bytes.addAll([image.height % 256, image.height ~/ 256]);

        for (int y = 0; y < image.height; y++) {
          for (int x = 0; x < widthBytes; x++) {
            int byte = 0;
            for (int bit = 0; bit < 8; bit++) {
              int px = x * 8 + bit;
              if (px < image.width) {
                final pixel = image.getPixel(px, y);
                if (pixel.r.toInt() < 128) {
                  byte |= (1 << (7 - bit));
                }
              }
            }
            bytes.add(byte);
          }
        }
        bytes.addAll('\n'.codeUnits);
      }
    } catch (e) {
      DebugConfig.logError('Logo formatla hatası', e);
    }
    return bytes;
  }

  /// Fiyat formatla
  String _formatPrice(double price) {
    return price.toStringAsFixed(2) + ' TL';
  }
}

/// Sipariş ürün modeli
class OrderItem {
  final String name;
  final double quantity;
  final double price;
  final double total;

  OrderItem({
    required this.name,
    required this.quantity,
    required this.price,
    required this.total,
  });
}
