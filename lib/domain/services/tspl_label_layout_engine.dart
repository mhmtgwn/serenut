import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
    int? printableWidthDots,
    int direction = 0,
    int copies = 1,
    bool showBusinessName = true,
    bool showBrand = true,
    bool showBarcode = true,
    bool showPrice = true,
    bool showVat = true,
    String fontSize = 'Orta',
    String? logoPath,
    List<int>? logoBytes,
  }) {
    final safeWidth = widthMm.clamp(30, 100);
    final safeHeight = heightMm.clamp(20, 100);
    final safeGap = gapMm.clamp(0, 10);
    final safeDpi = dpi == 300 ? 300 : 203;
    final mediaWidthDots = (safeWidth * safeDpi / 25.4).round();
    final widthDots = printableWidthDots == null
        ? mediaWidthDots
        : printableWidthDots.clamp(200, mediaWidthDots);
    final heightDots = (safeHeight * safeDpi / 25.4).round();
    int sx(num value) => (value * widthDots / 400).round();
    int sy(num value) => (value * heightDots / 240).round();
    final fontScale = switch (fontSize) {
      'Küçük' => 0.85,
      'Büyük' => 1.15,
      _ => 1.0,
    };

    final barcode = _barcode(model.barcode ?? '');

    final commands = _TsplBuffer()
      ..writeln('SIZE $safeWidth mm,$safeHeight mm')
      ..writeln('GAP $safeGap mm,0 mm')
      ..writeln('DENSITY 8')
      ..writeln('DIRECTION ${direction == 1 ? 1 : 0}')
      ..writeln('REFERENCE 0,0')
      ..writeln('CLS');

    int currentY = sy(6);

    // 1. Top Logo / Header (Bitmap Logo or Centered Business Name)
    if (showBusinessName) {
      final bitmapCmd =
          _generateTsplBitmap(logoPath, logoBytes, widthDots, currentY);
      if (bitmapCmd != null) {
        commands.addAll(bitmapCmd);
        currentY += sy(36 * fontScale).round();
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
    final usableNameWidth = widthDots - sx(32);
    final maxLargeChars = (usableNameWidth / 24).floor().clamp(1, 44);
    final maxMediumChars = (usableNameWidth / 16).floor().clamp(1, 44);
    if (nameClean.length <= maxLargeChars) {
      final f = fontScale < 0.9 ? '3' : '4';
      final charW = f == '4' ? 24 : 16;
      final textW = nameClean.length * charW * fontScale;
      final centerX =
          ((widthDots - textW) / 2).clamp(10, widthDots - 10).round();
      commands.writeln('TEXT $centerX,$currentY,"$f",0,1,2,"$nameClean"');
      currentY += sy(50 * fontScale).round();
    } else if (nameClean.length <= maxMediumChars) {
      final textW = nameClean.length * 16 * fontScale;
      final centerX =
          ((widthDots - textW) / 2).clamp(10, widthDots - 10).round();
      commands.writeln('TEXT $centerX,$currentY,"3",0,1,2,"$nameClean"');
      currentY += sy(42 * fontScale).round();
    } else {
      final maxLineChars = (usableNameWidth / 16).floor().clamp(4, 44);
      final lines = _wrapProductName(nameClean, maxLineChars);
      for (final rawLine in lines) {
        final line = _fit(rawLine, maxLineChars);
        final textW = line.length * 16 * fontScale;
        final centerX =
            ((widthDots - textW) / 2).clamp(10, widthDots - 10).round();
        commands.writeln('TEXT $centerX,$currentY,"3",0,1,1,"$line"');
        currentY += sy(26 * fontScale).round();
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
      final barcodeY = bottomY;
      final barcodeHeight = sy(40 * fontScale).clamp(24, 48).round();
      commands.writeln(
        'BARCODE ${sx(16)},$barcodeY,"128",$barcodeHeight,0,0,1,1,"$barcode"',
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
        final priceLeft = (widthDots * 0.47).round();
        final priceRight = widthDots - sx(12);
        final availablePriceWidth = priceRight - priceLeft;
        final priceText = '$whole,$cents';
        const currencyWidth = 16;
        const gap = 2;
        final priceFont =
            currencyWidth + gap + priceText.length * 24 <= availablePriceWidth
                ? '4'
                : (currencyWidth + gap + priceText.length * 16 <=
                        availablePriceWidth
                    ? '3'
                    : '2');
        final priceCharWidth =
            priceFont == '4' ? 24 : (priceFont == '3' ? 16 : 12);
        final priceWidth = priceText.length * priceCharWidth;
        final totalPriceWidth = currencyWidth + gap + priceWidth;
        final currencyX = (priceLeft +
                ((availablePriceWidth - totalPriceWidth) / 2).clamp(0, 999))
            .round();
        final priceX = currencyX + currencyWidth + gap;
        commands.writeln('TEXT $currencyX,${bottomY + sy(22)},"2",0,1,1,"TL"');
        commands
            .writeln('TEXT $priceX,$bottomY,"$priceFont",0,1,2,"$priceText"');
        if (showVat) {
          commands.writeln(
              'TEXT $currencyX,${bottomY + sy(70)},"1",0,1,1,"$vatStr"');
        }
      } else {
        final priceStr = 'TL $whole.$cents';
        final usablePriceWidth = widthDots - sx(24);
        final priceFont = priceStr.length * 24 <= usablePriceWidth
            ? '4'
            : (priceStr.length * 16 <= usablePriceWidth ? '3' : '2');
        final priceCharWidth =
            priceFont == '4' ? 24 : (priceFont == '3' ? 16 : 12);
        final textW = priceStr.length * priceCharWidth * fontScale;
        final priceX =
            ((widthDots - textW) / 2).clamp(10, widthDots - 10).round();
        commands
            .writeln('TEXT $priceX,$bottomY,"$priceFont",0,1,1,"$priceStr"');
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
    return commands.bytes;
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
    int? printableWidthDots,
    int direction = 0,
    int copies = 1,
    bool showBusinessName = true,
    bool showCustomerName = true,
    bool showOrderNo = true,
    bool showDate = true,
    bool showTotalAmount = true,
    bool showItemsCount = true,
    String fontSize = 'Orta',
    String? businessName,
    List<int>? logoBytes,
  }) {
    final safeWidth = widthMm.clamp(30, 100);
    final safeHeight = heightMm.clamp(20, 100);
    final safeGap = gapMm.clamp(0, 10);
    final safeDpi = dpi == 300 ? 300 : 203;
    final mediaWidthDots = (safeWidth * safeDpi / 25.4).round();
    final widthDots = printableWidthDots == null
        ? mediaWidthDots
        : printableWidthDots.clamp(200, mediaWidthDots);
    final heightDots = (safeHeight * safeDpi / 25.4).round();
    int sx(num value) => (value * widthDots / 400).round();
    int sy(num value) => (value * heightDots / 240).round();
    final maxFont1Chars = ((widthDots - sx(32)) ~/ 8).clamp(4, 80);
    final maxFont2Chars = ((widthDots - sx(32)) ~/ 12).clamp(4, 60);
    final maxFont3Chars = ((widthDots - sx(32)) ~/ 16).clamp(4, 40);

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

    final commands = _TsplBuffer()
      ..writeln('SIZE $safeWidth mm,$safeHeight mm')
      ..writeln('GAP $safeGap mm,0 mm')
      ..writeln('DENSITY 8')
      // Product and order labels share the same physical media path. Keeping
      // one direction prevents order labels from being rotated relative to
      // product labels on the same routed device.
      ..writeln('DIRECTION ${direction == 1 ? 1 : 0}')
      ..writeln('REFERENCE 0,0')
      ..writeln('CLS');

    int currentY = sy(6);

    // 1. Business Header (if enabled)
    if (showBusinessName) {
      final bitmap = _generateTsplBitmap(null, logoBytes, widthDots, currentY);
      if (bitmap != null) {
        commands.addAll(bitmap);
        currentY += sy(26);
      } else if (businessName != null && businessName.trim().isNotEmpty) {
        final bizClean = _fit(businessName, maxFont2Chars);
        final bizX = ((widthDots - bizClean.length * 12) / 2)
            .round()
            .clamp(sx(16), widthDots - sx(16));
        commands.writeln('TEXT $bizX,$currentY,"2",0,1,1,"$bizClean"');
        currentY += sy(20);
      }
    }

    // 2. Header: Sipariş No & Tarih
    final dateSharesHeader =
        showOrderNo && showDate && timeStr.isNotEmpty && widthDots >= 360;
    if (showOrderNo) {
      final orderNo = _fit(orderIdShort, (maxFont2Chars - 9).clamp(4, 12));
      commands
          .writeln('TEXT ${sx(16)},$currentY,"2",0,1,1,"SIPARIS #$orderNo"');
      if (dateSharesHeader) {
        commands.writeln(
            'TEXT ${widthDots - sx(180)},$currentY,"1",0,1,1,"${_fit(timeStr, 14)}"');
      }
      currentY += sy(30);
    }
    if (showDate && timeStr.isNotEmpty && !dateSharesHeader) {
      final safeTime = _fit(timeStr, maxFont1Chars);
      commands.writeln('TEXT ${sx(16)},$currentY,"1",0,1,1,"$safeTime"');
      currentY += sy(16);
    }

    // 3. Customer Info ("Müşteri")
    if (showCustomerName) {
      final whoText = custClean.isNotEmpty
          ? 'Musteri: ${_fit(custClean, (maxFont2Chars - 9).clamp(4, 40))}'
          : 'Musteri: Genel';
      commands.writeln('TEXT ${sx(16)},$currentY,"2",0,1,1,"$whoText"');
      currentY += sy(32);
    }

    // 4. Separator Line
    commands.writeln('BAR ${sx(16)},$currentY,${widthDots - sx(32)},${sy(2)}');
    currentY += sy(8);

    // 5. Items Count & Product Quantity / Items List
    if (showItemsCount &&
        itemsCount != null &&
        (items == null || items.isEmpty)) {
      commands.writeln(
          'TEXT ${sx(16)},$currentY,"1",0,1,1,"${_fit('- $itemsCount Parca Urun / Paket', maxFont1Chars)}"');
      currentY += sy(18);
    }

    final footerY = heightDots - sy(70);
    final reservedAfterItems =
        (showTotalAmount && totalAmount != null ? sy(26) : 0) + sy(4);
    var hiddenItemCount = 0;

    if (items != null && items.isNotEmpty) {
      final availableForItems =
          (footerY - currentY - reservedAfterItems).clamp(0, heightDots);
      final maxItemLines = (availableForItems ~/ sy(28)).clamp(0, 4);
      final visibleCount =
          items.length <= maxItemLines ? items.length : maxItemLines;

      for (var index = 0; index < visibleCount; index++) {
        final item = items[index];
        final name = _fit(
            (item['product_name'] ?? item['name'] ?? 'Urun').toString(),
            (maxFont2Chars - 5).clamp(4, 40));
        final itemQty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
        final itemQtyStr = itemQty % 1 == 0
            ? itemQty.toInt().toString()
            : itemQty.toStringAsFixed(1);
        final lineStr = _fit('- ${itemQtyStr}x $name', maxFont2Chars);
        commands.writeln('TEXT ${sx(16)},$currentY,"2",0,1,1,"$lineStr"');
        currentY += sy(28);
      }

      final remaining = items.length - visibleCount;
      hiddenItemCount = remaining;
      if (remaining > 0 && currentY + sy(18) <= footerY) {
        commands.writeln(
            'TEXT ${sx(16)},$currentY,"1",0,1,1,"+$remaining diger urun"');
        currentY += sy(18);
      }
    } else {
      final itemTitle = '$qtyStr x $prodClean';
      if (itemTitle.length <= maxFont3Chars) {
        commands.writeln('TEXT ${sx(16)},$currentY,"3",0,1,1,"$itemTitle"');
        currentY += sy(26);
      } else {
        commands.writeln(
            'TEXT ${sx(16)},$currentY,"2",0,1,1,"${_fit(itemTitle, maxFont2Chars)}"');
        currentY += sy(20);
      }
    }

    if (noteClean != null &&
        hiddenItemCount == 0 &&
        currentY + sy(24) <= footerY) {
      commands.writeln(
          'TEXT ${sx(16)},$currentY,"1",0,1,1,"Not: ${_fit(noteClean, (maxFont1Chars - 5).clamp(4, 60))}"');
      currentY += sy(24);
    }

    // 6. Total Amount & QR footer. A compact QR is deliberately used here;
    // Code-128 consumed most of the 58 mm width and was not the order design.
    if (showTotalAmount && totalAmount != null) {
      final totalStr = 'TOPLAM: TL ${totalAmount.toStringAsFixed(2)}';
      final totalFont = totalStr.length <= maxFont3Chars ? '3' : '2';
      final safeTotal =
          _fit(totalStr, totalFont == '3' ? maxFont3Chars : maxFont2Chars);
      commands
          .writeln('TEXT ${sx(16)},$currentY,"$totalFont",0,1,1,"$safeTotal"');
      currentY += sy(26);
    }

    final qrValue = _ascii(orderIdShort).replaceAll('"', "'");
    if (qrValue.isNotEmpty) {
      final qrX = widthDots - sx(82);
      commands.writeln(
        'QRCODE $qrX,$footerY,L,3,A,0,M2,S7,"$qrValue"',
      );
    }

    commands.writeln('PRINT ${copies.clamp(1, 20)},1');
    return commands.bytes;
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
    // Never truncate barcode payloads: a shortened code scans as a different
    // product. Long UUID-style identifiers also exceed the left label column.
    return sanitized.length <= 16 ? sanitized : '';
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

  static List<int>? _generateTsplBitmap(
      String? logoPath, List<int>? logoBytes, int widthDots, int currentY) {
    try {
      final List<int> bytes;
      if (logoBytes != null && logoBytes.isNotEmpty) {
        bytes = logoBytes;
      } else {
        if (logoPath == null || logoPath.trim().isEmpty || kIsWeb) return null;
        final file = File(logoPath);
        if (!file.existsSync()) return null;
        bytes = file.readAsBytesSync();
      }
      final decoded = img.decodeImage(Uint8List.fromList(bytes));
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
              // Match the proven collection-receipt monochrome conversion:
              // transparent pixels stay white and only opaque, dark artwork
              // becomes a thermal-printer dot.
              final luminance = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
              if (p.a >= 128 && luminance < 128) {
                b |= (0x80 >> bit);
              }
            }
          }
          rasterBytes.add(b);
        }
      }

      return <int>[
        ...latin1
            .encode('BITMAP $centerX,$currentY,$widthBytes,$targetHeight,0,'),
        ...rasterBytes,
        13,
        10,
      ];
    } catch (_) {
      return null;
    }
  }
}

class _TsplBuffer {
  final List<int> _bytes = <int>[];

  void writeln([Object? value = '']) {
    _bytes.addAll(latin1.encode('${value ?? ''}\r\n'));
  }

  void addAll(List<int> value) => _bytes.addAll(value);

  List<int> get bytes => List<int>.unmodifiable(_bytes);
}
