import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
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
    bool autoDetectGap = false,
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
    final horizontalPadding = sx(8).clamp(4, 16).toInt();
    final fontScale = switch (fontSize) {
      'Küçük' => 0.85,
      'Büyük' => 1.15,
      _ => 1.0,
    };

    final barcode = _barcode(model.barcode ?? '');

    final commands = _TsplBuffer()
      ..writeln('SIZE $safeWidth mm,$safeHeight mm')
      ..writeln('GAP $safeGap mm,0 mm')
      ..writelnIf(autoDetectGap, 'GAPDETECT')
      ..writeln('DENSITY 8')
      ..writeln('DIRECTION ${direction == 1 ? 1 : 0}')
      ..writeln('REFERENCE 0,0')
      ..writeln('CLS');

    int currentY = sy(6);

    // 1. Top Logo / Header (Bitmap Logo or Centered Business Name)
    if (showBusinessName) {
      final bitmapCmd = _generateTsplBitmap(
          logoPath, logoBytes, widthDots, currentY,
          maxHeight: 44);
      if (bitmapCmd != null) {
        commands.addAll(bitmapCmd.bytes);
        currentY += bitmapCmd.height + sy(3);
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
    final usableNameWidth = widthDots - (horizontalPadding * 2);
    final maxLargeChars = (usableNameWidth / 24).floor().clamp(1, 44);
    final maxMediumChars = (usableNameWidth / 16).floor().clamp(1, 44);
    if (nameClean.length <= maxLargeChars) {
      var f = fontScale < 0.9 ? '3' : '4';
      var charW = f == '4' ? 24 : 16;
      var xMultiplier = 1;
      var yMultiplier = 2;
      var bestWidth = nameClean.length * charW;
      for (final candidate in const [
        (font: '4', charWidth: 24, multiplier: 3),
        (font: '4', charWidth: 24, multiplier: 2),
        (font: '2', charWidth: 12, multiplier: 3),
        (font: '3', charWidth: 16, multiplier: 2),
      ]) {
        final candidateWidth =
            nameClean.length * candidate.charWidth * candidate.multiplier;
        if (candidateWidth <= usableNameWidth && candidateWidth > bestWidth) {
          f = candidate.font;
          charW = candidate.charWidth;
          xMultiplier = candidate.multiplier;
          yMultiplier = candidate.font == '2' ? 3 : 2;
          bestWidth = candidateWidth;
        }
      }
      final textW = nameClean.length * charW * xMultiplier * fontScale;
      final centerX =
          ((widthDots - textW) / 2).clamp(10, widthDots - 10).round();
      commands.boldText(
          centerX, currentY, f, xMultiplier, yMultiplier, nameClean);
      currentY += sy(50 * fontScale).round();
    } else if (nameClean.length <= maxMediumChars) {
      final textW = nameClean.length * 16 * fontScale;
      final centerX =
          ((widthDots - textW) / 2).clamp(10, widthDots - 10).round();
      commands.boldText(centerX, currentY, '3', 1, 2, nameClean);
      currentY += sy(42 * fontScale).round();
    } else {
      final maxLineChars = (usableNameWidth / 16).floor().clamp(4, 44);
      final lines = _wrapProductName(nameClean, maxLineChars);
      for (final rawLine in lines) {
        final line = _fit(rawLine, maxLineChars);
        final textW = line.length * 16 * fontScale;
        final centerX =
            ((widthDots - textW) / 2).clamp(10, widthDots - 10).round();
        commands.boldText(centerX, currentY, '3', 1, 2, line);
        currentY += sy(34 * fontScale).round();
      }
    }

    currentY += sy(4);

    // Keep a guaranteed bottom block for price/barcode so a two-line product
    // name can never push the price outside the physical label.
    currentY =
        currentY.clamp(sy(54), heightDots - sy(showVat ? 78 : 66)).toInt();

    // 4. Horizontal Separator Line
    commands.writeln(
        'BAR $horizontalPadding,$currentY,${widthDots - (horizontalPadding * 2)},${sy(2)}');
    currentY += sy(8);

    // 5. Bottom Layout (Left: Barcode | Right: Price & KDV)
    final bottomY = currentY;
    final bottomHeight =
        (heightDots - bottomY - sy(4)).clamp(32, heightDots).toInt();

    // Bottom Left: Barcode (if enabled)
    if (showBarcode && barcode.isNotEmpty) {
      final barcodeY = bottomY;
      final barcodeHeight = (bottomHeight - sy(6)).clamp(30, sy(72)).round();
      commands.writeln(
        'BARCODE $horizontalPadding,$barcodeY,"128",$barcodeHeight,0,0,1,1,"$barcode"',
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
        final priceLeft = (widthDots * 0.43).round();
        final priceRight = widthDots - horizontalPadding;
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
        final priceY =
            bottomY + ((bottomHeight - sy(48)) ~/ 2).clamp(0, 999).toInt();
        commands.writeln('TEXT $currencyX,${priceY + sy(22)},"2",0,1,1,"TL"');
        commands.boldText(priceX, priceY, priceFont, 1, 2, priceText);
        if (showVat) {
          final vatY = bottomY + bottomHeight - sy(10);
          commands.writeln('TEXT $currencyX,$vatY,"1",0,1,1,"$vatStr"');
        }
      } else {
        final priceStr = 'TL $whole.$cents';
        final usablePriceWidth = widthDots - (horizontalPadding * 2);
        final priceFont = priceStr.length * 24 <= usablePriceWidth
            ? '4'
            : (priceStr.length * 16 <= usablePriceWidth ? '3' : '2');
        final priceCharWidth =
            priceFont == '4' ? 24 : (priceFont == '3' ? 16 : 12);
        final textW = priceStr.length * priceCharWidth * fontScale;
        final priceX = ((widthDots - textW) / 2)
            .clamp(horizontalPadding, widthDots - horizontalPadding)
            .round();
        final priceY =
            bottomY + ((bottomHeight - sy(32)) ~/ 2).clamp(0, 999).toInt();
        commands.boldText(priceX, priceY, priceFont, 1, 1, priceStr);
        if (showVat) {
          final vatW = vatStr.length * 8 * fontScale;
          final vatX =
              ((widthDots - vatW) / 2).clamp(10, widthDots - 10).round();
          final vatY = bottomY + bottomHeight - sy(10);
          commands.writeln('TEXT $vatX,$vatY,"1",0,1,1,"$vatStr"');
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
    bool autoDetectGap = false,
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
      ..writelnIf(autoDetectGap, 'GAPDETECT')
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
      final bitmap = _generateTsplBitmap(
        null,
        logoBytes,
        widthDots,
        currentY,
        maxHeight: 16,
      );
      if (bitmap != null) {
        commands.addAll(bitmap.bytes);
        currentY += bitmap.height + sy(3);
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
    if (showOrderNo) {
      final orderNo = _fit(orderIdShort, (maxFont2Chars - 9).clamp(4, 12));
      commands
          .writeln('TEXT ${sx(16)},$currentY,"1",0,1,1,"SIPARIS #$orderNo"');
      currentY += sy(22);
    }
    // Date/time always owns the next line. Sharing the order-number baseline
    // caused the two fields to collide on 58 mm printers.
    if (showDate && timeStr.isNotEmpty) {
      final safeTime = _fit(timeStr, maxFont1Chars);
      commands.writeln('TEXT ${sx(16)},$currentY,"1",0,1,1,"$safeTime"');
      currentY += sy(22);
    }

    // 3. Customer Info ("Müşteri")
    if (showCustomerName) {
      final whoText = custClean.isNotEmpty
          ? 'Musteri: ${_fit(custClean, (maxFont2Chars - 9).clamp(4, 40))}'
          : 'Musteri: Genel';
      commands.writeln('TEXT ${sx(16)},$currentY,"1",0,1,1,"$whoText"');
      currentY += sy(22);
    }

    // 4. Separator Line
    commands.writeln('BAR ${sx(16)},$currentY,${widthDots - sx(32)},${sy(2)}');
    currentY += sy(4);

    // 5. Items Count & Product Quantity / Items List
    if (showItemsCount &&
        itemsCount != null &&
        (items == null || items.isEmpty)) {
      commands.writeln(
          'TEXT ${sx(16)},$currentY,"1",0,1,1,"${_fit('- $itemsCount Parca Urun / Paket', maxFont1Chars)}"');
      currentY += sy(18);
    }

    final footerY = heightDots - sy(70);
    // Total and QR share the fixed footer row (left/right), so item rows do
    // not need to reserve a separate vertical total block.
    final reservedAfterItems = sy(4);
    var hiddenItemCount = 0;

    if (items != null && items.isNotEmpty) {
      final availableForItems =
          (footerY - currentY - reservedAfterItems).clamp(0, heightDots);
      final maxItemLines = (availableForItems ~/ sy(22)).clamp(0, 3);
      final visibleCount =
          items.length <= maxItemLines ? items.length : maxItemLines;

      for (var index = 0; index < visibleCount; index++) {
        final item = items[index];
        final rawName =
            _ascii((item['product_name'] ?? item['name'] ?? 'Urun').toString());
        final itemQty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
        final itemQtyStr = itemQty % 1 == 0
            ? itemQty.toInt().toString()
            : itemQty.toStringAsFixed(1);
        final unitPrice = (item['unit_price'] as num?)?.toDouble();
        final lineTotal = unitPrice == null ? null : unitPrice * itemQty;
        final hiddenSuffix =
            index == visibleCount - 1 && items.length > visibleCount
                ? ' +${items.length - visibleCount}'
                : '';
        final suffix = lineTotal == null
            ? hiddenSuffix
            : ' TL${lineTotal.toStringAsFixed(2)}$hiddenSuffix';
        final nameLimit =
            (maxFont1Chars - itemQtyStr.length - suffix.length - 4)
                .clamp(4, maxFont1Chars);
        final lineStr = _fit(
            '- ${itemQtyStr}x ${_fit(rawName, nameLimit)}$suffix',
            maxFont1Chars);
        commands.writeln('TEXT ${sx(16)},$currentY,"1",0,1,1,"$lineStr"');
        currentY += sy(22);
      }

      final remaining = items.length - visibleCount;
      hiddenItemCount = remaining;
      // Remaining count is appended to the final visible item. A separate
      // summary row would collide with the fixed footer on 30 mm media.
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
      final footerTextChars = ((widthDots - sx(110)) ~/ 8).clamp(8, 50);
      final safeTotal = _fit(totalStr, footerTextChars);
      commands.writeln('TEXT ${sx(16)},$footerY,"1",0,1,1,"$safeTotal"');
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

  static ({List<int> bytes, int height})? _generateTsplBitmap(
    String? logoPath,
    List<int>? logoBytes,
    int widthDots,
    int currentY, {
    int maxHeight = 32,
  }) {
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
      final source = img.decodeImage(Uint8List.fromList(bytes));
      if (source == null) return null;
      final decoded = _cropLogoWhitespace(source);

      var targetWidth = (widthDots * 0.54).round().clamp(136, 216).toInt();
      int targetHeight = (decoded.height * (targetWidth / decoded.width))
          .round()
          .clamp(10, maxHeight);
      targetWidth = (targetWidth ~/ 8) * 8; // Multiple of 8
      if (targetWidth < 8) targetWidth = 8;
      final widthBytes = targetWidth ~/ 8;

      final resized =
          img.copyResize(decoded, width: targetWidth, height: targetHeight);
      final centerX =
          ((widthDots - targetWidth) / 2).clamp(10, widthDots - 10).round();

      final corners = [
        resized.getPixel(0, 0),
        resized.getPixel(targetWidth - 1, 0),
        resized.getPixel(0, targetHeight - 1),
        resized.getPixel(targetWidth - 1, targetHeight - 1),
      ];
      final backgroundAlpha =
          corners.map((p) => p.a).reduce((a, b) => a + b) / corners.length;
      final transparentCanvas = backgroundAlpha < 128;
      final backgroundR =
          corners.map((p) => p.r).reduce((a, b) => a + b) / corners.length;
      final backgroundG =
          corners.map((p) => p.g).reduce((a, b) => a + b) / corners.length;
      final backgroundB =
          corners.map((p) => p.b).reduce((a, b) => a + b) / corners.length;

      final List<int> rasterBytes = [];
      var firedDots = 0;
      for (int y = 0; y < targetHeight; y++) {
        for (int x = 0; x < widthBytes; x++) {
          int b = 0;
          for (int bit = 0; bit < 8; bit++) {
            final px = x * 8 + bit;
            if (px < targetWidth) {
              final p = resized.getPixel(px, y);
              // Preserve the complete mark regardless of its source colours.
              // Transparent artwork treats every visible pixel as logo. For
              // opaque artwork, separate the logo from its corner canvas.
              final backgroundDistance = (p.r - backgroundR).abs() +
                  (p.g - backgroundG).abs() +
                  (p.b - backgroundB).abs();
              final isForeground = transparentCanvas
                  ? p.a >= 32
                  : p.a >= 128 && backgroundDistance >= 45;
              if (isForeground) {
                b |= (0x80 >> bit);
                firedDots++;
              }
            }
          }
          // This label printer's TSPL BITMAP dialect uses 0 for a fired
          // (black) dot and 1 for paper/white. ESC/POS uses the opposite bit
          // polarity, so invert only at the TSPL serialization boundary.
          rasterBytes.add(b ^ 0xFF);
        }
      }

      if (kDebugMode) {
        final preview = rasterBytes
            .take(24)
            .map((value) => value.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        debugPrint(
          '[TSPL_LOGO] ${targetWidth}x$targetHeight bytes=${rasterBytes.length} '
          'blackDots=$firedDots canvas=${transparentCanvas ? 'transparent' : 'opaque'} '
          'polarity=zero-is-black first=$preview',
        );
      }

      return (
        bytes: <int>[
          ...latin1
              .encode('BITMAP $centerX,$currentY,$widthBytes,$targetHeight,0,'),
          ...rasterBytes,
          13,
          10,
        ],
        height: targetHeight,
      );
    } catch (_) {
      return null;
    }
  }

  static img.Image _cropLogoWhitespace(img.Image source) {
    final corner = source.getPixel(0, 0);
    var minX = source.width;
    var minY = source.height;
    var maxX = -1;
    var maxY = -1;

    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final pixel = source.getPixel(x, y);
        final distance = (pixel.r - corner.r).abs() +
            (pixel.g - corner.g).abs() +
            (pixel.b - corner.b).abs();
        final foreground =
            corner.a < 128 ? pixel.a >= 32 : pixel.a >= 128 && distance >= 30;
        if (!foreground) continue;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }

    if (maxX < minX || maxY < minY) return source;
    return img.copyCrop(
      source,
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
    );
  }
}

class _TsplBuffer {
  final List<int> _bytes = <int>[];

  void writeln([Object? value = '']) {
    _bytes.addAll(latin1.encode('${value ?? ''}\r\n'));
  }

  void writelnIf(bool condition, Object value) {
    if (condition) writeln(value);
  }

  /// TSPL built-in fonts have no bold flag. A one-dot overprint gives product
  /// names and prices a stronger, more legible weight on thermal stock.
  void boldText(
    int x,
    int y,
    String font,
    int xMultiplier,
    int yMultiplier,
    String value,
  ) {
    writeln('TEXT $x,$y,"$font",0,$xMultiplier,$yMultiplier,"$value"');
    writeln('TEXT ${x + 1},$y,"$font",0,$xMultiplier,$yMultiplier,"$value"');
  }

  void addAll(List<int> value) => _bytes.addAll(value);

  List<int> get bytes => List<int>.unmodifiable(_bytes);
}
