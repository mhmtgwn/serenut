import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;
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
    bool showBusinessName = true,
    bool showBrand = true,
    bool showBarcode = true,
    bool showPrice = true,
    bool showVat = true,
    String fontSize = 'Orta',
    String? logoPath,
  }) {
    final safeWidth = widthMm.clamp(30, 100);
    final safeHeight = heightMm.clamp(20, 100);
    final safeGap = gapMm.clamp(0, 10);
    final safeDpi = dpi == 300 ? 300 : 203;
    final widthDots = (safeWidth * safeDpi / 25.4).round();
    final heightDots = (safeHeight * safeDpi / 25.4).round();
    int sx(num value) => (value * widthDots / 400).round();
    int sy(num value) => (value * heightDots / 240).round();

    final fontScale = switch (fontSize) {
      'Küçük' => 0.85,
      'Büyük' => 1.15,
      _ => 1.0,
    };

    final barcode = _barcode(model.barcode ?? '');

    final commands = StringBuffer()
      ..writeln('SIZE $safeWidth mm,$safeHeight mm')
      ..writeln('GAP $safeGap mm,0 mm')
      ..writeln('DENSITY 8')
      ..writeln('DIRECTION 1')
      ..writeln('REFERENCE 0,0')
      ..writeln('CLS');

    int currentY = sy(6);

    // 1. Top Logo / Header (Bitmap Logo or Centered Business Name)
    if (showBusinessName) {
      final bitmapCmd = _generateTsplBitmap(logoPath, widthDots, currentY);
      if (bitmapCmd != null) {
        commands.writeln(bitmapCmd);
        currentY += sy(36 * fontScale).round();
      } else {
        final logoText = model.businessName?.trim().isNotEmpty == true
            ? _ascii(model.businessName!.trim())
            : 'SERENUT OS';
        final fontType = fontScale < 0.9 ? '1' : '2';
        final charW = fontType == '2' ? 12 : 8;
        final textW = logoText.length * charW * fontScale;
        final centerX =
            ((widthDots - textW) / 2).clamp(10, widthDots - 10).round();
        commands
            .writeln('TEXT $centerX,$currentY,"$fontType",0,1,1,"$logoText"');
        currentY += sy(20 * fontScale).round();
      }
    }

    // 2. Brand (if enabled)
    if (showBrand && model.brand?.trim().isNotEmpty == true) {
      final brandText = _ascii(model.brand!.trim());
      final textW = brandText.length * 8 * fontScale;
      final centerX =
          ((widthDots - textW) / 2).clamp(10, widthDots - 10).round();
      commands.writeln('TEXT $centerX,$currentY,"1",0,1,1,"$brandText"');
      currentY += sy(16 * fontScale).round();
    }

    // 3. Middle: dominant product name, matching the shelf-label hierarchy.
    final nameClean = _fit(model.productName, 44);
    if (nameClean.length <= 14) {
      final f = fontScale < 0.9 ? '3' : '4';
      final charW = f == '4' ? 24 : 16;
      final textW = nameClean.length * charW * fontScale;
      final centerX =
          ((widthDots - textW) / 2).clamp(10, widthDots - 10).round();
      commands.writeln('TEXT $centerX,$currentY,"$f",0,1,1,"$nameClean"');
      currentY += sy(38 * fontScale).round();
    } else if (nameClean.length <= 22) {
      final textW = nameClean.length * 16 * fontScale;
      final centerX =
          ((widthDots - textW) / 2).clamp(10, widthDots - 10).round();
      commands.writeln('TEXT $centerX,$currentY,"3",0,1,1,"$nameClean"');
      currentY += sy(32 * fontScale).round();
    } else {
      final lines = _wrapProductName(nameClean, (22 / fontScale).round());
      for (final line in lines) {
        final textW = line.length * 12 * fontScale;
        final centerX =
            ((widthDots - textW) / 2).clamp(10, widthDots - 10).round();
        commands.writeln('TEXT $centerX,$currentY,"2",0,1,1,"$line"');
        currentY += sy(20 * fontScale).round();
      }
    }

    currentY += sy(4);

    // 4. Horizontal Separator Line
    commands.writeln('BAR ${sx(16)},$currentY,${widthDots - sx(32)},${sy(2)}');
    currentY += sy(8);

    // 5. Bottom Layout (Left: Barcode | Right: Price & KDV)
    final bottomY = currentY;

    // Bottom Left: Barcode (if enabled)
    if (showBarcode && barcode.isNotEmpty) {
      commands.writeln('TEXT ${sx(16)},$bottomY,"1",0,1,1,"Kod: $barcode"');
      final barcodeY = bottomY + sy(14);
      final barcodeHeight = sy(28 * fontScale).clamp(14, 40).round();
      commands.writeln(
        'BARCODE ${sx(16)},$barcodeY,"128",$barcodeHeight,0,0,2,3,"$barcode"',
      );
    }

    // Bottom right: currency, dominant whole amount and superscript decimals.
    // Keeping these as separate fields reproduces the visual hierarchy of a
    // shelf price tag without letting a long combined string cross the edge.
    if (showPrice) {
      final priceParts = model.price.toStringAsFixed(2).split('.');
      final whole = priceParts.first;
      final cents = priceParts.length > 1 ? priceParts.last : '00';
      const vatStr = '(KDV Dahil)';

      if (showBarcode && barcode.isNotEmpty) {
        final currencyX = sx(190);
        final wholeX = sx(218);
        final centsX = widthDots - sx(38);
        final wholeMultiplier = whole.length <= 3 ? 2 : 1;
        commands.writeln('TEXT $currencyX,${bottomY + sy(22)},"2",0,1,1,"TL"');
        commands.writeln(
            'TEXT $wholeX,$bottomY,"4",0,$wholeMultiplier,$wholeMultiplier,"$whole"');
        commands.writeln('TEXT $centsX,$bottomY,"2",0,1,1,"$cents"');
        if (showVat) {
          commands.writeln(
              'TEXT $currencyX,${bottomY + sy(70)},"1",0,1,1,"$vatStr"');
        }
      } else {
        final priceStr = 'TL $whole.$cents';
        final textW = priceStr.length * 16 * fontScale;
        final priceX =
            ((widthDots - textW) / 2).clamp(10, widthDots - 10).round();
        commands.writeln('TEXT $priceX,$bottomY,"4",0,1,1,"$priceStr"');
        if (showVat) {
          final vatW = vatStr.length * 8 * fontScale;
          final vatX =
              ((widthDots - vatW) / 2).clamp(10, widthDots - 10).round();
          commands
              .writeln('TEXT $vatX,${bottomY + sy(30)},"1",0,1,1,"$vatStr"');
        }
      }
    }

    commands.writeln('PRINT ${copies.clamp(1, 20)},1');
    return latin1.encode(commands.toString().replaceAll('\n', '\r\n'));
  }

  /// Generates TSPL commands for Order Package / Kitchen / Item labels with options.
  static List<int> generateOrderLabelBytes({
    required String orderIdShort,
    required String customerName,
    required String productName,
    required double quantity,
    List<Map<String, dynamic>>? items,
    String? note,
    DateTime? timestamp,
    double? totalAmount,
    int? itemsCount,
    int widthMm = 50,
    int heightMm = 30,
    int gapMm = 2,
    int dpi = 203,
    int copies = 1,
    bool showBusinessName = true,
    bool showCustomerName = true,
    bool showOrderNo = true,
    bool showDate = true,
    bool showTotalAmount = true,
    bool showItemsCount = true,
    String fontSize = 'Orta',
    String? businessName,
  }) {
    final safeWidth = widthMm.clamp(30, 100);
    final safeHeight = heightMm.clamp(20, 100);
    final safeGap = gapMm.clamp(0, 10);
    final safeDpi = dpi == 300 ? 300 : 203;
    final widthDots = (safeWidth * safeDpi / 25.4).round();
    final heightDots = (safeHeight * safeDpi / 25.4).round();
    int sx(num value) => (value * widthDots / 400).round();
    int sy(num value) => (value * heightDots / 240).round();

    final timeStr = (showDate && timestamp != null)
        ? '${timestamp.day.toString().padLeft(2, '0')}.${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}'
        : '';
    final qtyStr = quantity % 1 == 0
        ? quantity.toInt().toString()
        : quantity.toStringAsFixed(1);
    final custClean = _ascii(customerName.trim());
    final prodClean = _ascii(productName.trim());
    final noteClean =
        note != null && note.trim().isNotEmpty ? _ascii(note.trim()) : null;

    final commands = StringBuffer()
      ..writeln('SIZE $safeWidth mm,$safeHeight mm')
      ..writeln('GAP $safeGap mm,0 mm')
      ..writeln('DENSITY 8')
      ..writeln('DIRECTION 1')
      ..writeln('REFERENCE 0,0')
      ..writeln('CLS');

    int currentY = sy(6);

    // 1. Business Header (if enabled)
    if (showBusinessName &&
        businessName != null &&
        businessName.trim().isNotEmpty) {
      final bizClean = _fit(businessName, 28);
      commands.writeln('TEXT ${sx(110)},$currentY,"2",0,1,1,"$bizClean"');
      currentY += sy(20);
    }

    // 2. Header: Sipariş No & Tarih
    if (showOrderNo) {
      final orderNo = _fit(orderIdShort, 12);
      commands
          .writeln('TEXT ${sx(16)},$currentY,"2",0,1,1,"SIPARIS #$orderNo"');
    }
    if (showDate && timeStr.isNotEmpty) {
      commands.writeln('TEXT ${sx(220)},$currentY,"1",0,1,1,"$timeStr"');
    }
    if (showOrderNo || (showDate && timeStr.isNotEmpty)) {
      currentY += sy(20);
    }

    // 3. Customer Info ("Müşteri")
    if (showCustomerName) {
      final whoText = custClean.isNotEmpty
          ? 'Musteri: ${_fit(custClean, 22)}'
          : 'Musteri: Genel';
      commands.writeln('TEXT ${sx(16)},$currentY,"2",0,1,1,"$whoText"');
      currentY += sy(22);
    }

    // 4. Separator Line
    commands.writeln('BAR ${sx(16)},$currentY,${widthDots - sx(32)},${sy(2)}');
    currentY += sy(8);

    // 5. Items Count & Product Quantity / Items List
    if (showItemsCount && itemsCount != null) {
      commands.writeln(
          'TEXT ${sx(16)},$currentY,"1",0,1,1,"- $itemsCount Parca Urun / Paket"');
      currentY += sy(18);
    }

    if (items != null && items.isNotEmpty) {
      commands.writeln('TEXT ${sx(16)},$currentY,"1",0,1,1,"URUN ICERIGI:"');
      currentY += sy(16);
      for (final item in items) {
        final name = _fit(
            (item['product_name'] ?? item['name'] ?? 'Urun').toString(), 22);
        final itemQty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
        final itemQtyStr = itemQty % 1 == 0
            ? itemQty.toInt().toString()
            : itemQty.toStringAsFixed(1);
        final lineStr = '- ${itemQtyStr}x $name';
        commands.writeln('TEXT ${sx(16)},$currentY,"2",0,1,1,"$lineStr"');
        currentY += sy(18);
      }
    } else {
      final itemTitle = '$qtyStr x $prodClean';
      if (itemTitle.length <= 18) {
        commands.writeln('TEXT ${sx(16)},$currentY,"3",0,1,1,"$itemTitle"');
        currentY += sy(26);
      } else {
        commands.writeln('TEXT ${sx(16)},$currentY,"2",0,1,1,"$itemTitle"');
        currentY += sy(20);
      }
    }

    if (noteClean != null) {
      commands.writeln(
          'TEXT ${sx(16)},$currentY,"1",0,1,1,"Not: ${_fit(noteClean, 38)}"');
      currentY += sy(16);
    }

    // 6. Total Amount & Order Barcode Footer
    if (showTotalAmount && totalAmount != null) {
      final totalStr = 'TOPLAM: TL ${totalAmount.toStringAsFixed(2)}';
      commands.writeln('TEXT ${sx(16)},$currentY,"3",0,1,1,"$totalStr"');
      currentY += sy(26);
    }

    final barcodeY = heightDots - sy(48);
    final barcodeHeight = sy(28).clamp(14, 36);
    final cleanBarcode = _barcode(orderIdShort);
    if (cleanBarcode.isNotEmpty) {
      commands.writeln(
        'BARCODE ${sx(16)},$barcodeY,"128",$barcodeHeight,0,0,2,3,"$cleanBarcode"',
      );
      commands.writeln(
          'TEXT ${sx(220)},${barcodeY + sy(8)},"1",0,1,1,"#$orderIdShort"');
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

  static String _fit(String value, int maxLength) {
    final normalized = _ascii(value.trim().replaceAll(RegExp(r'\s+'), ' '))
        .replaceAll('"', "'");
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 2)}..';
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

  static String? _generateTsplBitmap(
      String? logoPath, int widthDots, int currentY) {
    if (logoPath == null || logoPath.trim().isEmpty || kIsWeb) return null;
    try {
      final file = File(logoPath);
      if (!file.existsSync()) return null;
      final bytes = file.readAsBytesSync();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      int targetWidth = 120;
      int targetHeight = (decoded.height * (targetWidth / decoded.width))
          .round()
          .clamp(10, 32);
      targetWidth = (targetWidth ~/ 8) * 8; // Multiple of 8
      if (targetWidth < 8) targetWidth = 8;
      final widthBytes = targetWidth ~/ 8;

      final resized =
          img.copyResize(decoded, width: targetWidth, height: targetHeight);
      final centerX =
          ((widthDots - targetWidth) / 2).clamp(10, widthDots - 10).round();

      final List<int> rasterBytes = [];
      for (int y = 0; y < targetHeight; y++) {
        for (int x = 0; x < widthBytes; x++) {
          int b = 0;
          for (int bit = 0; bit < 8; bit++) {
            final px = x * 8 + bit;
            if (px < targetWidth) {
              final p = resized.getPixel(px, y);
              final lum = img.getLuminance(p);
              if (lum < 128) {
                b |= (0x80 >> bit);
              }
            }
          }
          rasterBytes.add(b);
        }
      }

      final hexData = rasterBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join('');
      return 'BITMAP $centerX,$currentY,$widthBytes,$targetHeight,0,$hexData';
    } catch (_) {
      return null;
    }
  }
}
