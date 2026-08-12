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
  static List<int> generateLabelBytes(
    LabelModel model, {
    int width = 32,
    List<int> logoBytes = const [],
    bool showBusinessName = true,
    bool showBrand = true,
    bool showBarcode = true,
    bool showPrice = true,
    bool showVat = true,
  }) {
    final List<int> bytes = [];

    bytes.addAll(init);
    bytes.addAll([0x1C, 0x2E]); // Cancel Chinese character mode
    bytes.addAll([0x1B, 0x74, 0x0D]); // Select Code Page CP857 (Turkish)

    if (logoBytes.isNotEmpty) {
      bytes.addAll(alignCenter);
      bytes.addAll(logoBytes);
      bytes.addAll(lf);
    }
    if (showBusinessName && model.businessName?.trim().isNotEmpty == true) {
      bytes.addAll(alignCenter);
      bytes.addAll(boldOn);
      bytes.addAll(_textToBytes('${model.businessName}\n'));
      bytes.addAll(boldOff);
    }

    bytes.addAll(alignCenter);
    bytes.addAll(boldOn);
    if (showBrand && model.brand?.trim().isNotEmpty == true) {
      bytes.addAll(sizeNormal);
      bytes.addAll(_textToBytes('${model.brand}\n'));
    }

    // Product Name: Short -> sizeLarge, Long -> multi-line sizeNormal
    final maxLargeChars = width ~/ 2;
    if (model.productName.length <= maxLargeChars) {
      bytes.addAll(sizeLarge);
      bytes.addAll(_textToBytes('${model.productName}\n'));
      bytes.addAll(sizeNormal);
    } else {
      bytes.addAll(sizeNormal);
      final lines = _wrapText(model.productName, width);
      for (final line in lines) {
        bytes.addAll(_textToBytes('$line\n'));
      }
    }
    bytes.addAll(boldOff);

    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // Align Right / Prominent for Price with Unit
    if (showPrice) {
      bytes.addAll(alignRight);
      bytes.addAll(boldOn);
      bytes.addAll(sizeLarge);
      final vatText = showVat ? ' (KDV Dahil)' : '';
      bytes.addAll(
          _textToBytes('${model.price.toStringAsFixed(2)} TL$vatText\n'));
      bytes.addAll(sizeNormal);
      bytes.addAll(boldOff);
    }

    // Compact Barcode Lines (no numbers underneath)
    if (showBarcode &&
        model.barcode != null &&
        model.barcode!.trim().isNotEmpty) {
      final code = model.barcode!.trim();
      bytes.addAll(alignCenter);
      // Select barcode height (32 dots)
      bytes.addAll([0x1D, 0x68, 0x20]);
      // Select HRI character position: 0 = Not printed
      bytes.addAll([0x1D, 0x48, 0x00]);
      // Select barcode width
      bytes.addAll([0x1D, 0x77, 0x02]);
      // Print CODE128 barcode
      final codeBytes = code.codeUnits;
      bytes.addAll([0x1D, 0x6B, 0x49, codeBytes.length + 2, 0x7B, 0x42]);
      bytes.addAll(codeBytes);
      bytes.addAll(lf);
    }

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
}
