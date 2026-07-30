import 'dart:convert';

import 'package:serenutos/domain/models/label_model.dart';

/// Dynamic-size TSPL shelf-label renderer.
///
/// Unlike receipt printers, label printers need physical stock dimensions,
/// inter-label gap and DPI before any content is positioned. Coordinates below
/// are dynamically calculated from reference dots to prevent overlapping elements.
class TsplLabelLayoutEngine {
  static List<int> generateLabelBytes(
    LabelModel model, {
    int widthMm = 50,
    int heightMm = 30,
    int gapMm = 2,
    int dpi = 203,
    int copies = 1,
  }) {
    final safeWidth = widthMm.clamp(30, 100);
    final safeHeight = heightMm.clamp(20, 100);
    final safeGap = gapMm.clamp(0, 10);
    final safeDpi = dpi == 300 ? 300 : 203;
    final widthDots = (safeWidth * safeDpi / 25.4).round();
    final heightDots = (safeHeight * safeDpi / 25.4).round();
    int sx(num value) => (value * widthDots / 400).round();
    int sy(num value) => (value * heightDots / 240).round();

    final company = _fit(model.businessName ?? '', 32);
    final brand = _fit(model.brand ?? '', 28);
    final priceStr = '${model.price.toStringAsFixed(2)} TL';
    final unitShelf = [
      if (model.unit.isNotEmpty) 'Birim: ${_fit(model.unit, 10)}',
      if (model.shelfCode?.trim().isNotEmpty == true)
        'Raf: ${_fit(model.shelfCode!, 10)}',
    ].join('   ');
    final barcode = _barcode(model.barcode ?? '');

    final commands = StringBuffer()
      ..writeln('SIZE $safeWidth mm,$safeHeight mm')
      ..writeln('GAP $safeGap mm,0 mm')
      ..writeln('DENSITY 8')
      ..writeln('DIRECTION 1')
      ..writeln('REFERENCE 0,0')
      ..writeln('CLS');

    int currentY = sy(6);

    // 1. Company Name Header
    if (company.isNotEmpty) {
      commands.writeln('TEXT ${sx(8)},$currentY,"1",0,1,1,"$company"');
      currentY += sy(18);
    }

    // 2. Brand / Category
    if (brand.isNotEmpty) {
      commands.writeln('TEXT ${sx(8)},$currentY,"1",0,1,1,"$brand"');
      currentY += sy(16);
    }

    // 3. Multi-line Product Name (1 or 2 lines)
    final maxCharsPerLine = safeWidth >= 60 ? 28 : (safeWidth >= 45 ? 22 : 16);
    final productLines = _wrapProductName(model.productName, maxCharsPerLine);
    for (final line in productLines) {
      commands.writeln('TEXT ${sx(8)},$currentY,"2",0,1,1,"$line"');
      currentY += sy(24);
    }

    currentY += sy(2);

    // 4. Price (Clean, prominent)
    commands.writeln('TEXT ${sx(8)},$currentY,"3",0,1,2,"$priceStr"');
    currentY += sy(42);

    // 5. Unit & Shelf Code
    if (unitShelf.isNotEmpty) {
      commands.writeln('TEXT ${sx(8)},$currentY,"1",0,1,1,"$unitShelf"');
      currentY += sy(18);
    }

    // 6. Barcode
    if (barcode.isNotEmpty) {
      final barcodeHeight = sy(36).clamp(18, 55);
      commands.writeln(
        'BARCODE ${sx(8)},$currentY,"128",$barcodeHeight,1,0,2,4,"$barcode"',
      );
    }

    commands.writeln('PRINT ${copies.clamp(1, 20)},1');
    return latin1.encode(commands.toString().replaceAll('\n', '\r\n'));
  }

  static List<String> _wrapProductName(String name, int maxCharsPerLine) {
    final clean = _ascii(name.trim().replaceAll(RegExp(r'\s+'), ' '))
        .replaceAll('"', "'");
    if (clean.length <= maxCharsPerLine) return [clean];

    final words = clean.split(' ');
    final lines = <String>[];
    var currentLine = '';

    for (final word in words) {
      if (currentLine.isEmpty) {
        currentLine = word;
      } else if (currentLine.length + word.length + 1 <= maxCharsPerLine) {
        currentLine = '$currentLine $word';
      } else {
        lines.add(currentLine);
        currentLine = word;
        if (lines.length == 2) break;
      }
    }
    if (currentLine.isNotEmpty && lines.length < 2) {
      lines.add(currentLine);
    }

    if (lines.length == 2 && lines[1].length > maxCharsPerLine) {
      lines[1] = '${lines[1].substring(0, maxCharsPerLine - 2)}..';
    }

    return lines.isEmpty ? [clean] : lines;
  }

  static String _fit(String value, int maxLength) {
    final normalized = _ascii(value.trim().replaceAll(RegExp(r'\s+'), ' '))
        .replaceAll('"', "'");
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 2)}..';
  }

  static String _barcode(String value) {
    final sanitized = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._\-/]'), '');
    return sanitized.length <= 40 ? sanitized : sanitized.substring(0, 40);
  }

  static String _ascii(String value) {
    const replacements = {
      'ç': 'c',
      'Ç': 'C',
      'ğ': 'g',
      'Ğ': 'G',
      'ı': 'i',
      'İ': 'I',
      'ö': 'o',
      'Ö': 'O',
      'ş': 's',
      'Ş': 'S',
      'ü': 'u',
      'Ü': 'U',
      '₺': 'TL',
    };
    return value.split('').map((char) => replacements[char] ?? char).join();
  }
}
