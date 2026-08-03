import 'package:serenutos/domain/models/label_model.dart';
import '../../domain/repositories/base_repository.dart';

class LabelLayoutEngine {
  // ESC/POS Commands
  static const List<int> init = [0x1B, 0x40];
  static const List<int> alignLeft = [0x1B, 0x61, 0x00];
  static const List<int> alignCenter = [0x1B, 0x61, 0x01];
  static const List<int> alignRight = [0x1B, 0x61, 0x02];
  static const List<int> boldOn = [0x1B, 0x45, 0x01];
  static const List<int> boldOff = [0x1B, 0x45, 0x00];
  static const List<int> sizeNormal = [0x1D, 0x21, 0x00];
  static const List<int> sizeLarge = [0x1D, 0x21, 0x11];
  static const List<int> sizeDoubleHeight = [0x1D, 0x21, 0x01];
  static const List<int> lf = [0x0A];
  static const List<int> cut = [0x1D, 0x56, 0x41, 0x08];

  /// Generate ESC/POS bytes for a single label
  static List<int> generateLabelBytes(LabelModel model,
      {int width = 32, List<int> logoBytes = const []}) {
    final List<int> bytes = [];

    bytes.addAll(init);
    bytes.addAll([0x1C, 0x2E]); // Cancel Chinese character mode
    bytes.addAll([0x1B, 0x74, 0x0D]); // Select Code Page CP857 (Turkish)

    // 1. LOGO (Replaces Firm Name)
    if (logoBytes.isNotEmpty) {
      bytes.addAll(alignCenter);
      bytes.addAll(logoBytes);
    }
    
    // 2. PRODUCT NAME (Decorated: White text on Black background)
    bytes.addAll(alignCenter);
    bytes.addAll(boldOn);
    bytes.addAll([0x1B, 0x4D, 0x00]); // Select Font A
    bytes.addAll(sizeNormal); // 1x1
    
    // Invert Color ON (GS B 1) - Siyah arkaplan, beyaz yazı
    bytes.addAll([0x1D, 0x42, 0x01]); 
    
    final lines = _wrapText(model.productName, 32);
    for (int j = 0; j < lines.length && j < 2; j++) {
      // Add padding spaces for a wider black box effect
      String line = lines[j];
      String paddedLine = '  $line  ';
      bytes.addAll(_textToBytes('$paddedLine\n'));
    }
    
    // Invert Color OFF (GS B 0)
    bytes.addAll([0x1D, 0x42, 0x00]); 
    bytes.addAll(boldOff);
    
    // 3. PRICE (Centered, Above Barcode)
    bytes.addAll(alignCenter);

    final pStr = model.price.toStringAsFixed(2);
    final parts = pStr.split('.');
    String intP = parts[0];
    String decP = parts.length > 1 ? ',${parts[1]}' : '';

    bytes.addAll(boldOn);
    bytes.addAll(sizeLarge);
    bytes.addAll(_textToBytes(intP));
    bytes.addAll(sizeNormal);
    
    // Fiyatın TL kısmını da siyah kutu içine alalım (Küçük bir süs)
    bytes.addAll(_textToBytes('$decP '));
    bytes.addAll([0x1D, 0x42, 0x01]); // Invert ON
    bytes.addAll(_textToBytes(' TL '));
    bytes.addAll([0x1D, 0x42, 0x00]); // Invert OFF
    bytes.addAll(_textToBytes('\n')); // LF EKLENDİ! Satır kapatıldı.
    
    bytes.addAll(boldOff);

    // 4. BARCODE (Centered, Shorter, Wider)
    if (model.barcode != null && model.barcode!.trim().isNotEmpty) {
      final code = model.barcode!.trim();
      bytes.addAll(alignCenter);
      
      bytes.addAll([0x1D, 0x68, 0x28]); // Yükseklik 40 (Kısa)
      bytes.addAll([0x1D, 0x48, 0x00]); // HRI (Yazı) Yok
      bytes.addAll([0x1D, 0x77, 0x02]); // Genişlik 2 (Yayvan)
      
      // Subset C Optimizasyonu
      final isNumeric = RegExp(r'^[0-9]+$').hasMatch(code);
      final List<int> codeData = [];
      
      if (isNumeric) {
        if (code.length % 2 == 0) {
          codeData.addAll([0x7B, 0x43]); 
          for (int i = 0; i < code.length; i += 2) {
            codeData.add(int.parse(code.substring(i, i + 2)));
          }
        } else {
          codeData.addAll([0x7B, 0x42]); 
          codeData.add(code.codeUnitAt(0));
          codeData.addAll([0x7B, 0x43]); 
          for (int i = 1; i < code.length; i += 2) {
            codeData.add(int.parse(code.substring(i, i + 2)));
          }
        }
      } else {
        codeData.addAll([0x7B, 0x42]); 
        codeData.addAll(code.codeUnits);
      }
      
      // Barkodu Çiz
      bytes.addAll([0x1D, 0x6B, 0x49, codeData.length, ...codeData]);
      bytes.addAll(lf); // Barkoddan sonra satırı kapat
    }

    bytes.addAll(cut);
    return bytes;
  }

  /// Generate ESC/POS bytes for an Order Label (Sipariş Etiketi)
  static List<int> generateOrderLabelBytes({
    required OrderEntity order,
    required List<Map<String, dynamic>> items,
    CustomerEntity? customer,
    required dynamic settings, // Using dynamic to avoid circular dependencies if settings isn't in domain
    int width = 32,
    List<int> logoBytes = const [],
  }) {
    final List<int> bytes = [];

    bytes.addAll(init);
    bytes.addAll([0x1C, 0x2E]); // Cancel Chinese character mode
    bytes.addAll([0x1B, 0x74, 0x0D]); // Select Code Page CP857 (Turkish)

    // 1. LOGO
    if (logoBytes.isNotEmpty) {
      bytes.addAll(alignCenter);
      bytes.addAll(logoBytes);
      bytes.addAll(lf);
    }

    // 2. HEADER
    bytes.addAll(alignCenter);
    bytes.addAll(boldOn);
    bytes.addAll(sizeDoubleHeight); // 1x2 for header
    bytes.addAll([0x1D, 0x42, 0x01]); // Invert ON (Siyah Arkaplan)
    bytes.addAll(_textToBytes(' SİPARİŞ FİŞİ \n'));
    bytes.addAll([0x1D, 0x42, 0x00]); // Invert OFF
    bytes.addAll(boldOff);
    bytes.addAll(sizeNormal);
    bytes.addAll(lf);

    // 3. CUSTOMER INFO
    bytes.addAll(alignLeft);
    if (customer != null) {
      bytes.addAll(boldOn);
      bytes.addAll(_textToBytes('Müşteri: '));
      bytes.addAll(boldOff);
      bytes.addAll(_textToBytes('${customer.name}\n'));
      
      if (customer.phone.isNotEmpty) {
        bytes.addAll(boldOn);
        bytes.addAll(_textToBytes('Tel: '));
        bytes.addAll(boldOff);
        bytes.addAll(_textToBytes('${customer.phone}\n'));
      }
    } else {
      bytes.addAll(boldOn);
      bytes.addAll(_textToBytes('Müşteri: '));
      bytes.addAll(boldOff);
      bytes.addAll(_textToBytes('${order.customerId}\n'));
    }

    // 4. ORDER METADATA
    // Format Date: DD.MM.YYYY HH:MM
    final d = order.createdAt;
    final dateStr = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    
    bytes.addAll(boldOn);
    bytes.addAll(_textToBytes('Tarih: '));
    bytes.addAll(boldOff);
    bytes.addAll(_textToBytes('$dateStr\n'));

    // Payment/Debt Status (using order.status or a derived status)
    bytes.addAll(boldOn);
    bytes.addAll(_textToBytes('Durum: '));
    bytes.addAll(boldOff);
    // Convert status to readable format
    String statusStr = 'Bekliyor';
    switch (order.status) {
      case 'preparing': statusStr = 'Hazırlanıyor'; break;
      case 'ready': statusStr = 'Hazır'; break;
      case 'delivered': statusStr = 'Teslim Edildi'; break;
      case 'cancelled': statusStr = 'İptal'; break;
    }
    bytes.addAll(_textToBytes('$statusStr\n'));

    // Separator
    bytes.addAll(alignCenter);
    bytes.addAll(_textToBytes('--------------------------------\n'));

    // 5. ITEMS
    bytes.addAll(alignLeft);
    for (final item in items) {
      final name = item['product_name']?.toString().trim().isNotEmpty == true
          ? item['product_name'].toString()
          : item['product_id']?.toString() ?? 'Ürün';
      final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final note = item['note']?.toString();
      
      final qtyStr = qty == qty.toInt() ? qty.toInt().toString() : qty.toString();
      
      bytes.addAll(boldOn);
      bytes.addAll(_textToBytes('$qtyStr x '));
      bytes.addAll(boldOff);
      
      // Wrap product name
      final lines = _wrapText(name, width - 4); // Leave space for "Q x "
      for (int j = 0; j < lines.length; j++) {
        if (j == 0) {
          bytes.addAll(_textToBytes('${lines[j]}\n'));
        } else {
          bytes.addAll(_textToBytes('    ${lines[j]}\n'));
        }
      }
      
      // Print note if any
      if (note != null && note.isNotEmpty) {
        bytes.addAll([0x1B, 0x4D, 0x01]); // Select Font B (Smaller base font)
        bytes.addAll(_textToBytes('    Not: $note\n'));
        bytes.addAll([0x1B, 0x4D, 0x00]); // Revert to Font A
      }
    }

    // 6. ORDER NOTES (If any)
    if (order.notes != null && order.notes!.isNotEmpty) {
      bytes.addAll(alignCenter);
      bytes.addAll(_textToBytes('--------------------------------\n'));
      bytes.addAll(alignLeft);
      bytes.addAll(boldOn);
      bytes.addAll(_textToBytes('Sipariş Notu:\n'));
      bytes.addAll(boldOff);
      final noteLines = _wrapText(order.notes!, width);
      for (final line in noteLines) {
        bytes.addAll(_textToBytes('$line\n'));
      }
    }

    // Separator
    bytes.addAll(alignCenter);
    bytes.addAll(_textToBytes('================================\n'));

    // 7. BARCODE (Order ID)
    final shortId = order.id.length > 8 ? order.id.substring(0, 8) : order.id;
    bytes.addAll([0x1D, 0x68, 0x28]); // Yükseklik 40 (Kısa)
    bytes.addAll([0x1D, 0x48, 0x02]); // HRI (Yazı) Barkodun altında
    bytes.addAll([0x1D, 0x77, 0x02]); // Genişlik 2
    
    // Subset C Optimizasyonu
    final isNumeric = RegExp(r'^[0-9]+$').hasMatch(shortId);
    final List<int> codeData = [];
    
    if (isNumeric) {
      if (shortId.length % 2 == 0) {
        codeData.addAll([0x7B, 0x43]); 
        for (int i = 0; i < shortId.length; i += 2) {
          codeData.add(int.parse(shortId.substring(i, i + 2)));
        }
      } else {
        codeData.addAll([0x7B, 0x42]); 
        codeData.add(shortId.codeUnitAt(0));
        codeData.addAll([0x7B, 0x43]); 
        for (int i = 1; i < shortId.length; i += 2) {
          codeData.add(int.parse(shortId.substring(i, i + 2)));
        }
      }
    } else {
      codeData.addAll([0x7B, 0x42]); 
      codeData.addAll(shortId.codeUnits);
    }
    
    // Barkodu Çiz
    bytes.addAll([0x1D, 0x6B, 0x49, codeData.length, ...codeData]);
    bytes.addAll(lf); // Barkoddan sonra satırı kapat

    bytes.addAll(cut);
    return bytes;
  }


  static List<String> _wrapText(String text, int width) {
    if (text.isEmpty) return [];
    final lines = <String>[];
    var currentLine = '';
    for (final word in text.trim().split(RegExp(r'\s+'))) {
      if (currentLine.isEmpty) {
        currentLine = word;
      } else if (currentLine.length + word.length + 1 <= width) {
        currentLine = '$currentLine $word';
      } else {
        lines.add(currentLine);
        currentLine = word;
      }
    }
    if (currentLine.isNotEmpty) lines.add(currentLine);
    return lines;
  }

  // Converts text to CP857 (Turkish) bytes safely
  static List<int> _textToBytes(String text) {
    final List<int> bytes = [];
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      switch (char) {
        case 'ğ':
          bytes.add(0xA7);
          break;
        case 'Ğ':
          bytes.add(0xA6);
          break;
        case 'ş':
          bytes.add(0x9F);
          break;
        case 'Ş':
          bytes.add(0x9E);
          break;
        case 'ı':
          bytes.add(0x8D);
          break;
        case 'İ':
          bytes.add(0x98);
          break;
        case 'ç':
          bytes.add(0x87);
          break;
        case 'Ç':
          bytes.add(0x80);
          break;
        case 'ö':
          bytes.add(0x94);
          break;
        case 'Ö':
          bytes.add(0x99);
          break;
        case 'ü':
          bytes.add(0x81);
          break;
        case 'Ü':
          bytes.add(0x9A);
          break;
        case '₺':
          bytes.addAll('TL'.codeUnits);
          break;
        case '┌':
          bytes.add(0xDA);
          break;
        case '┐':
          bytes.add(0xBF);
          break;
        case '└':
          bytes.add(0xC0);
          break;
        case '┘':
          bytes.add(0xD9);
          break;
        case '─':
          bytes.add(0xC4);
          break;
        case '│':
          bytes.add(0xB3);
          break;
        default:
          final code = char.codeUnitAt(0);
          if (code <= 127) {
            bytes.add(code);
          } else {
            bytes.add(0x3F); // '?'
          }
      }
    }
    return bytes;
  }

  // Generate Epson ESC/POS QR bytes
  static List<int> _generateQrCodeBytes(String qrText) {
    final textBytes = qrText.codeUnits;
    final len = textBytes.length + 3;
    final lenL = len & 0xFF;
    final lenH = (len >> 8) & 0xFF;

    return [
      ...[0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x04],
      ...[0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x30],
      ...[0x1D, 0x28, 0x6B, lenL, lenH, 0x31, 0x50, 0x30],
      ...textBytes,
      ...[0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30],
    ];
  }
}
