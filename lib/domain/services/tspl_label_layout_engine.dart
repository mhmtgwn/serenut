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

    final barcode = _barcode(model.barcode ?? '');

    final commands = StringBuffer()
      ..writeln('SIZE $safeWidth mm,$safeHeight mm')
      ..writeln('GAP $safeGap mm,0 mm')
      ..writeln('DENSITY 8')
      ..writeln('DIRECTION 1')
      ..writeln('REFERENCE 0,0')
      ..writeln('CLS');

    int currentY = sy(6);

    // 1. Top Logo / Header (Centered)
    final logoText = model.businessName?.trim().isNotEmpty == true
        ? _ascii(model.businessName!.trim())
        : 'SERENUT OS';
    commands.writeln('TEXT ${sx(110)},$currentY,"2",0,1,1,"$logoText"');
    currentY += sy(22);

    // 2. Middle: Auto-scaling Product Name
    final nameClean = _ascii(model.productName.trim());
    if (nameClean.length <= 14) {
      commands.writeln('TEXT ${sx(16)},$currentY,"4",0,1,1,"$nameClean"');
      currentY += sy(36);
    } else if (nameClean.length <= 26) {
      commands.writeln('TEXT ${sx(16)},$currentY,"3",0,1,1,"$nameClean"');
      currentY += sy(30);
    } else {
      final lines = _wrapProductName(nameClean, 22);
      for (final line in lines) {
        commands.writeln('TEXT ${sx(16)},$currentY,"2",0,1,1,"$line"');
        currentY += sy(22);
      }
    }

    currentY += sy(4);

    // 3. Horizontal Separator Line (matching price-tag sample)
    commands.writeln('BAR ${sx(16)},$currentY,${widthDots - sx(32)},${sy(2)}');
    currentY += sy(8);

    // 4. Bottom Split Layout (Left: Kod & Barcode lines | Right: Huge Auto-scaling Price)
    final bottomY = currentY;

    // Bottom Left: Kod & Barcode
    if (barcode.isNotEmpty) {
      commands.writeln('TEXT ${sx(16)},$bottomY,"1",0,1,1,"Kod: $barcode"');
      final barcodeY = bottomY + sy(16);
      final barcodeHeight = sy(32).clamp(16, 45);
      commands.writeln(
        'BARCODE ${sx(16)},$barcodeY,"128",$barcodeHeight,0,0,2,3,"$barcode"',
      );
    }

    // Bottom Right: Huge Price with Superscript Kuruş
    final priceParts = model.price.toStringAsFixed(2).split('.');
    final lira = priceParts[0];
    final kurus = priceParts[1];
    final priceX = sx(200);

    if (lira.length <= 5) {
      commands.writeln('TEXT $priceX,${bottomY + sy(10)},"2",0,1,1,"TL"');
      final liraX = priceX + sx(28);
      commands.writeln('TEXT $liraX,$bottomY,"4",0,1,2,"$lira"');
      final kurusX = liraX + lira.length * sx(24) + sx(4);
      commands.writeln('TEXT $kurusX,$bottomY,"2",0,1,1,"$kurus"');
    } else {
      commands.writeln('TEXT $priceX,${bottomY + sy(6)},"2",0,1,1,"TL"');
      final liraX = priceX + sx(24);
      commands.writeln('TEXT $liraX,$bottomY,"3",0,1,2,"$lira"');
      final kurusX = liraX + lira.length * sx(18) + sx(4);
      commands.writeln('TEXT $kurusX,$bottomY,"1",0,1,1,"$kurus"');
    }

    commands.writeln('PRINT ${copies.clamp(1, 20)},1');
    return latin1.encode(commands.toString().replaceAll('\n', '\r\n'));
  }

  /// Generates TSPL commands specifically for Order Package / Kitchen / Item labels.
  ///
  /// Does NOT print logos, shelf prices, or store tags.
  /// Focuses purely on Order ID, Customer ("kimin"), Product & Quantity ("ürünler"), and Order Barcode.
  static List<int> generateOrderLabelBytes({
    required String orderIdShort,
    required String customerName,
    required String productName,
    required double quantity,
    String? note,
    DateTime? timestamp,
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

    final timeStr = timestamp != null
        ? '${timestamp.day.toString().padLeft(2, '0')}.${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}'
        : '';
    final qtyStr = quantity % 1 == 0
        ? quantity.toInt().toString()
        : quantity.toStringAsFixed(1);
    final custClean = _ascii(customerName.trim());
    final prodClean = _ascii(productName.trim());
    final noteClean = note != null && note.trim().isNotEmpty
        ? _ascii(note.trim())
        : null;

    final commands = StringBuffer()
      ..writeln('SIZE $safeWidth mm,$safeHeight mm')
      ..writeln('GAP $safeGap mm,0 mm')
      ..writeln('DENSITY 8')
      ..writeln('DIRECTION 1')
      ..writeln('REFERENCE 0,0')
      ..writeln('CLS');

    int currentY = sy(6);

    // 1. Header: Sipariş No & Tarih (No logo)
    commands.writeln('TEXT ${sx(16)},$currentY,"2",0,1,1,"SIPARIS #$orderIdShort"');
    if (timeStr.isNotEmpty) {
      commands.writeln('TEXT ${sx(220)},$currentY,"1",0,1,1,"$timeStr"');
    }
    currentY += sy(20);

    // 2. Customer Info ("Kimin")
    final whoText = custClean.isNotEmpty ? 'Musteri: $custClean' : 'Musteri: Genel';
    commands.writeln('TEXT ${sx(16)},$currentY,"2",0,1,1,"$whoText"');
    currentY += sy(22);

    // 3. Separator Line
    commands.writeln('BAR ${sx(16)},$currentY,${widthDots - sx(32)},${sy(2)}');
    currentY += sy(8);

    // 4. Product & Quantity ("Ürünler vs.")
    final itemTitle = '$qtyStr x $prodClean';
    if (itemTitle.length <= 18) {
      commands.writeln('TEXT ${sx(16)},$currentY,"3",0,1,1,"$itemTitle"');
      currentY += sy(28);
    } else {
      commands.writeln('TEXT ${sx(16)},$currentY,"2",0,1,1,"$itemTitle"');
      currentY += sy(22);
    }

    if (noteClean != null) {
      commands.writeln('TEXT ${sx(16)},$currentY,"1",0,1,1,"Not: $noteClean"');
      currentY += sy(16);
    }

    // 5. Order Barcode / Footer at Bottom Left
    final barcodeY = heightDots - sy(48);
    final barcodeHeight = sy(28).clamp(14, 36);
    final cleanBarcode = _barcode(orderIdShort);
    if (cleanBarcode.isNotEmpty) {
      commands.writeln(
        'BARCODE ${sx(16)},$barcodeY,"128",$barcodeHeight,0,0,2,3,"$cleanBarcode"',
      );
      commands.writeln('TEXT ${sx(220)},${barcodeY + sy(8)},"1",0,1,1,"#$orderIdShort"');
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
