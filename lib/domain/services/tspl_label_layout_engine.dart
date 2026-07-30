import 'dart:convert';

import 'package:serenutos/domain/models/label_model.dart';

/// Fixed-size TSPL shelf-label renderer.
///
/// Unlike receipt printers, label printers need the physical stock dimensions,
/// inter-label gap and DPI before any content is positioned. Coordinates below
/// are scaled from a 50x30 mm / 203 DPI reference layout.
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

    final company = _fit(model.businessName ?? '', 30);
    final brand = _fit(model.brand ?? '', 24);
    final product = _fit(model.productName, 28);
    final price = '${model.price.toStringAsFixed(2)} TL';
    final unitShelf = [
      'Birim: ${_fit(model.unit, 10)}',
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

    if (company.isNotEmpty) {
      commands.writeln('TEXT ${sx(8)},${sy(7)},"1",0,1,1,"$company"');
    }
    if (brand.isNotEmpty) {
      commands.writeln('TEXT ${sx(8)},${sy(28)},"1",0,1,1,"$brand"');
    }
    commands
      ..writeln('TEXT ${sx(8)},${sy(48)},"2",0,1,1,"$product"')
      ..writeln('TEXT ${sx(8)},${sy(78)},"3",0,2,2,"$price"')
      ..writeln('TEXT ${sx(8)},${sy(132)},"1",0,1,1,"$unitShelf"');
    if (barcode.isNotEmpty) {
      commands.writeln(
        'BARCODE ${sx(8)},${sy(154)},"128",${sy(48)},1,0,2,4,"$barcode"',
      );
    }
    commands.writeln('PRINT ${copies.clamp(1, 20)},1');
    return latin1.encode(commands.toString().replaceAll('\n', '\r\n'));
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
