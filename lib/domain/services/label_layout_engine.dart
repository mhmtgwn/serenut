// lib/domain/services/label_layout_engine.dart
import 'package:intl/intl.dart';
import 'package:serenutos/domain/models/label_model.dart';

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
  static const List<int> lf = [0x0A];
  static const List<int> cut = [0x1D, 0x56, 0x41, 0x08];

  /// Generate ESC/POS bytes for a single label
  static List<int> generateLabelBytes(LabelModel model, {int width = 32}) {
    final List<int> bytes = [];

    bytes.addAll(init);
    bytes.addAll([0x1C, 0x2E]); // Cancel Chinese character mode
    bytes.addAll([0x1B, 0x74, 0x0D]); // Select Code Page CP857 (Turkish)

    bytes.addAll(alignCenter);
    bytes.addAll(boldOn);
    bytes.addAll(sizeLarge);
    bytes.addAll(_textToBytes('${model.productName}\n'));
    bytes.addAll(sizeNormal);
    bytes.addAll(boldOff);

    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // Align Left for details
    bytes.addAll(alignLeft);
    bytes.addAll(_textToBytes('Miktar: ${_formatQty(model.weight)} kg\n'));
    bytes.addAll(_textToBytes('Fiyat: ₺${model.price.toStringAsFixed(2)}\n'));
    bytes.addAll(_textToBytes('Tarih: ${DateFormat('dd.MM.yyyy HH:mm').format(model.timestamp)}\n'));
    
    if (model.batchNo != null && model.batchNo!.isNotEmpty) {
      bytes.addAll(_textToBytes('Batch No: ${model.batchNo}\n'));
    }
    
    if (model.barcode != null && model.barcode!.isNotEmpty) {
      bytes.addAll(_textToBytes('Barkod: ${model.barcode}\n'));
    }

    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // QR Code
    bytes.addAll(alignCenter);
    bytes.addAll(_generateQrCodeBytes(model.qrData));
    bytes.addAll(lf);
    bytes.addAll(cut);

    return bytes;
  }

  static String _formatQty(double qty) {
    if (qty == qty.toInt()) {
      return qty.toInt().toString();
    }
    return qty.toStringAsFixed(3); // Standard weight representation (grams)
  }

  // Converts text to CP857 (Turkish) bytes safely
  static List<int> _textToBytes(String text) {
    final List<int> bytes = [];
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      switch (char) {
        case 'ğ': bytes.add(0xA7); break;
        case 'Ğ': bytes.add(0xA6); break;
        case 'ş': bytes.add(0x9F); break;
        case 'Ş': bytes.add(0x9E); break;
        case 'ı': bytes.add(0x8D); break;
        case 'İ': bytes.add(0x98); break;
        case 'ç': bytes.add(0x87); break;
        case 'Ç': bytes.add(0x80); break;
        case 'ö': bytes.add(0x94); break;
        case 'Ö': bytes.add(0x99); break;
        case 'ü': bytes.add(0x81); break;
        case 'Ü': bytes.add(0x9A); break;
        case '₺': 
          bytes.addAll('TL'.codeUnits); 
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
