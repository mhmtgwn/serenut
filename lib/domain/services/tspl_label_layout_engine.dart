import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;
import 'package:serenutos/domain/models/label_model.dart';

/// Dynamic-size TSPL shelf-label and order-label renderer.
///
/// Automatically scales all fonts, barcode dimensions, spacing and layout boundaries
/// according to exact physical stock dimensions (widthMm x heightMm) and DPI
/// to prevent any horizontal or vertical overflows.
class TsplLabelLayoutEngine {
  /// Generates TSPL commands for Product / Shelf labels.
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
    final safeWidth = widthMm.clamp(20, 120);
    final safeHeight = heightMm.clamp(15, 120);
    final safeGap = gapMm.clamp(0, 10);
    final safeDpi = dpi == 300 ? 300 : 203;

    final mediaWidthDots = (safeWidth * safeDpi / 25.4).round();
    final widthDots = printableWidthDots == null
        ? mediaWidthDots
        : printableWidthDots.clamp(140, mediaWidthDots);
    final heightDots = (safeHeight * safeDpi / 25.4).round();

    // Scale factors relative to 50x30 mm reference label (400x240 dots)
    final dimScaleY = heightDots / 240.0;

    int sy(num value) => (value * dimScaleY).round();

    final horizontalPadding = (widthDots * 0.04).clamp(6.0, 24.0).round();
    final usableWidth = widthDots - (horizontalPadding * 2);

    final fontScale = switch (fontSize) {
      'Küçük' => 0.95,
      'Büyük' => 1.30,
      _ => 1.15,
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

    int currentY = (heightDots * 0.03).clamp(2, 12).round();

    // ── 1. Top Header: Logo or Business Name ──────────────────────────────
    if (showBusinessName) {
      final maxHeaderHeight = (heightDots * 0.16 * fontScale).clamp(10, 44).round();
      final bitmapCmd = _generateTsplBitmap(
        logoPath,
        logoBytes,
        widthDots,
        currentY,
        maxHeight: maxHeaderHeight,
      );
      if (bitmapCmd != null) {
        commands.addAll(bitmapCmd.bytes);
        currentY += bitmapCmd.height + sy(2);
      } else if (model.businessName?.trim().isNotEmpty == true) {
        final bizText = model.businessName!.trim();
        final maxChars = (usableWidth / 12).floor().clamp(4, 60);
        final bizClean = _fit(bizText, maxChars);
        final layout = _widestTextLayout(
          bizClean,
          usableWidth,
          maxHeight: maxHeaderHeight,
        );
        final centerX = ((widthDots - layout.width) / 2)
            .round()
            .clamp(horizontalPadding, widthDots - horizontalPadding);
        commands.boldText(
          centerX,
          currentY,
          layout.font,
          layout.xMultiplier,
          layout.yMultiplier,
          bizClean,
        );
        currentY += layout.height + sy(2);
      }
    }

    // ── 2. Brand Name (if enabled) ────────────────────────────────────────
    if (showBrand && model.brand?.trim().isNotEmpty == true) {
      final maxBrandChars = (usableWidth / 8).floor().clamp(4, 60);
      final brandText = _fit(model.brand!, maxBrandChars);
      final maxBrandHeight = (heightDots * 0.10 * fontScale).clamp(8, 22).round();
      final layout = _widestTextLayout(
        brandText,
        usableWidth,
        maxHeight: maxBrandHeight,
      );
      final centerX = ((widthDots - layout.width) / 2)
          .round()
          .clamp(horizontalPadding, widthDots - horizontalPadding);
      commands.writeln(
        'TEXT $centerX,$currentY,"${layout.font}",0,${layout.xMultiplier},${layout.yMultiplier},"$brandText"',
      );
      currentY += layout.height + sy(1);
    }

    // ── 3. Product Name (Middle Section) ─────────────────────────────────
    final nameClean = _ascii(model.productName);
    final availableNameBudget = (heightDots * 0.38 * fontScale).clamp(24, 110).round();
    final singleLineMaxChars = (usableWidth / 12).floor().clamp(4, 60);

    if (nameClean.length <= singleLineMaxChars) {
      final layout = _widestTextLayout(
        nameClean,
        usableWidth,
        maxHeight: availableNameBudget,
      );
      final centerX = ((widthDots - layout.width) / 2)
          .round()
          .clamp(horizontalPadding, widthDots - horizontalPadding);
      commands.boldText(
        centerX,
        currentY,
        layout.font,
        layout.xMultiplier,
        layout.yMultiplier,
        nameClean,
      );
      currentY += layout.height + sy(2);
    } else {
      final maxLineChars = (usableWidth / 10).floor().clamp(4, 60);
      final lines = _wrapProductName(nameClean, maxLineChars);
      final lineMaxHeight = (availableNameBudget / lines.length).floor().clamp(10, 36);

      for (final rawLine in lines) {
        final line = _fit(rawLine, maxLineChars);
        final layout = _widestTextLayout(
          line,
          usableWidth,
          maxHeight: lineMaxHeight,
        );
        final centerX = ((widthDots - layout.width) / 2)
            .round()
            .clamp(horizontalPadding, widthDots - horizontalPadding);
        commands.boldText(
          centerX,
          currentY,
          layout.font,
          layout.xMultiplier,
          layout.yMultiplier,
          line,
        );
        currentY += layout.height + sy(1);
      }
      currentY += sy(1);
    }

    // Ensure space for bottom price/barcode section
    final minBottomHeight = (heightDots * 0.35).clamp(36, 120).round();
    final maxCurrentY = heightDots - minBottomHeight;
    if (currentY > maxCurrentY) {
      currentY = maxCurrentY;
    }

    // ── 4. Horizontal Separator Line BAR ─────────────────────────────────
    final barHeight = (heightDots * 0.01).clamp(1, 3).round();
    commands.writeln(
      'BAR $horizontalPadding,$currentY,${widthDots - (horizontalPadding * 2)},$barHeight',
    );
    currentY += barHeight + sy(2);

    // ── 5. Bottom Section (Left: Barcode | Right: Price & KDV) ────────────
    final bottomY = currentY;
    final bottomHeight = (heightDots - bottomY - sy(4)).clamp(20, heightDots).round();

    // Bottom Left: Barcode
    if (showBarcode && barcode.isNotEmpty) {
      final barcodeHeight = (bottomHeight * 0.65).clamp(16, 72).round();
      const narrowBar = 1;
      commands.writeln(
        'BARCODE $horizontalPadding,$bottomY,"128",$barcodeHeight,0,0,$narrowBar,2,"$barcode"',
      );
    }

    // Bottom Right or Centered: Price & KDV
    if (showPrice) {
      final priceParts = model.price.toStringAsFixed(2).split('.');
      final whole = priceParts.first;
      final cents = priceParts.length > 1 ? priceParts.last : '00';
      const vatStr = '(KDV Dahil)';

      if (showBarcode && barcode.isNotEmpty) {
        final priceLeft = (widthDots * 0.44).round();
        final availablePriceWidth = (widthDots - priceLeft - horizontalPadding).clamp(40, widthDots);
        final priceText = '$whole,$cents';
        const currencyWidth = 14;
        const gap = 2;

        final priceLayout = _widestTextLayout(
          priceText,
          availablePriceWidth - currencyWidth - gap,
          maxHeight: (bottomHeight * 0.65).round(),
        );

        final priceWidth = priceLayout.width;
        final totalPriceWidth = currencyWidth + gap + priceWidth;
        final currencyX = (priceLeft + ((availablePriceWidth - totalPriceWidth) / 2))
            .round()
            .clamp(priceLeft, widthDots - horizontalPadding);
        final priceX = currencyX + currencyWidth + gap;

        commands.writeln('TEXT $currencyX,${bottomY + sy(4)},"2",0,1,1,"TL"');
        commands.boldText(
          priceX,
          bottomY,
          priceLayout.font,
          priceLayout.xMultiplier,
          priceLayout.yMultiplier,
          priceText,
        );
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
        final textW = priceStr.length * priceCharWidth;
        final priceX = ((widthDots - textW) / 2)
            .clamp(horizontalPadding, widthDots - horizontalPadding)
            .round();
        commands.writeln('TEXT $priceX,$bottomY,"$priceFont",0,1,1,"$priceStr"');
        if (showVat) {
          final vatY = bottomY + bottomHeight - sy(10);
          final vatX = ((widthDots - (vatStr.length * 8)) / 2)
              .round()
              .clamp(horizontalPadding, widthDots - horizontalPadding);
          commands.writeln('TEXT $vatX,$vatY,"1",0,1,1,"$vatStr"');
        }
      }
    }

    commands.writeln('PRINT ${copies.clamp(1, 20)},1');
    return commands.bytes;
  }

  /// Generates TSPL commands for Order Package / Kitchen / Item labels.
  /// Note: Sipariş etiketlerinde logo basılmaz (requirement #2).
  static List<int> generateOrderLabelBytes({
    required String orderIdShort,
    required String customerName,
    String? customerPhone,
    String? customerNo,
    double previousDebt = 0,
    String paymentStatus = 'Bilinmiyor',
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
    final safeWidth = widthMm.clamp(20, 150);
    final safeGap = gapMm.clamp(0, 10);
    final safeDpi = dpi == 300 ? 300 : 203;

    final mediaWidthDots = (safeWidth * safeDpi / 25.4).round();
    final widthDots = printableWidthDots == null
        ? mediaWidthDots
        : printableWidthDots.clamp(140, mediaWidthDots);

    int sx(num value) => (value * widthDots / 400).round();
    int sy(num value) => (value * safeDpi / 203).round();

    final paddingX = (widthDots * 0.04).clamp(6.0, 24.0).round();
    final usableW = widthDots - (paddingX * 2);

    final maxFont1Chars = (usableW / 8).floor().clamp(4, 80);
    final maxFont2Chars = (usableW / 12).floor().clamp(4, 60);

    final custClean = _ascii(customerName.trim());
    final prodClean = _ascii(productName.trim());
    final customerNoClean = _ascii(customerNo?.trim() ?? '');
    final phoneClean = _ascii(customerPhone?.trim() ?? '');
    final noteClean =
        note != null && note.trim().isNotEmpty ? _ascii(note.trim()) : null;

    final timeStr = (showDate && timestamp != null)
        ? '${timestamp.day.toString().padLeft(2, '0')}.${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}'
        : '';
    final qtyStr = quantity % 1 == 0
        ? quantity.toInt().toString()
        : quantity.toStringAsFixed(1);

    // ── Pre-calculate Exact Dot Height ──
    int calculatedDots = sy(6);
    if (showBusinessName) {
      calculatedDots += sy(24);
    }
    if (showOrderNo) calculatedDots += sy(20);
    if (showDate && timeStr.isNotEmpty) calculatedDots += sy(20);
    if (showCustomerName) calculatedDots += sy(20);
    if (customerNoClean.isNotEmpty) calculatedDots += sy(16);
    if (phoneClean.isNotEmpty) calculatedDots += sy(16);
    if (previousDebt > 0.001) calculatedDots += sy(16);
    calculatedDots += sy(12); // Separator 1

    if (showItemsCount &&
        itemsCount != null &&
        (items == null || items.isEmpty)) {
      calculatedDots += sy(18);
    }

    if (items != null && items.isNotEmpty) {
      for (final item in items) {
        final rawName =
            _ascii((item['product_name'] ?? item['name'] ?? 'Urun').toString());
        final nameLines = _splitText(rawName, maxFont1Chars, maxLines: 2);
        calculatedDots += (nameLines.length * sy(18));
        calculatedDots += sy(18); // Detail / line total
        calculatedDots += sy(2);
      }
    } else {
      final nameLines = _splitText(prodClean, maxFont2Chars, maxLines: 2);
      calculatedDots += nameLines.length * sy(20);
      calculatedDots += sy(18);
    }

    calculatedDots += sy(12); // Separator 2
    calculatedDots += sy(18); // Payment status
    if (noteClean != null) calculatedDots += sy(20);
    if (showTotalAmount && totalAmount != null) calculatedDots += sy(28);
    calculatedDots += sy(55); // Footer & QR Code clearance + bottom padding

    final requiredHeightMm = (calculatedDots * 25.4 / safeDpi).ceil() + 6;
    final requestedHeightMm = heightMm.clamp(15, 1000);
    final safeHeight = requestedHeightMm > requiredHeightMm
        ? requestedHeightMm
        : requiredHeightMm;
    final heightDots = (safeHeight * safeDpi / 25.4).round();

    final commands = _TsplBuffer()
      ..writeln('SIZE $safeWidth mm,$safeHeight mm')
      ..writeln('GAP $safeGap mm,0 mm')
      ..writelnIf(autoDetectGap, 'GAPDETECT')
      ..writeln('DENSITY 8')
      ..writeln('DIRECTION ${direction == 1 ? 1 : 0}')
      ..writeln('REFERENCE 0,0')
      ..writeln('CLS');

    int currentY = sy(6);

    // ── 1. Business Header ──
    if (showBusinessName) {
      final bizText = _ascii((businessName != null && businessName.trim().isNotEmpty)
          ? businessName.trim()
          : 'SERENUT OS');
      final bizClean = _fit(bizText, maxFont2Chars);
      final layout = _widestTextLayout(
        bizClean,
        usableW,
        maxHeight: (heightDots * 0.14).clamp(10, 28).round(),
      );
      final bizX = ((widthDots - layout.width) / 2)
          .round()
          .clamp(paddingX, widthDots - paddingX);
      commands.boldText(
        bizX,
        currentY,
        layout.font,
        layout.xMultiplier,
        layout.yMultiplier,
        bizClean,
      );
      currentY += layout.height + sy(3);
    }

    // ── 2. Order # & Date ──
    if (showOrderNo) {
      final orderNo = _fit(orderIdShort, (maxFont2Chars - 9).clamp(4, 20));
      commands.writeln('TEXT $paddingX,$currentY,"1",0,1,1,"SIPARIS #$orderNo"');
      currentY += sy(18);
    }
    if (showDate && timeStr.isNotEmpty) {
      final safeTime = _fit(timeStr, maxFont1Chars);
      commands.writeln('TEXT $paddingX,$currentY,"1",0,1,1,"$safeTime"');
      currentY += sy(18);
    }

    // ── 3. Customer Info ──
    if (showCustomerName) {
      final whoText = custClean.isNotEmpty
          ? 'Musteri: ${_fit(custClean, (maxFont2Chars - 9).clamp(4, 40))}'
          : 'Musteri: Genel';
      commands.writeln('TEXT $paddingX,$currentY,"1",0,1,1,"$whoText"');
      currentY += sy(18);
    }
    if (customerNoClean.isNotEmpty) {
      commands.writeln(
        'TEXT $paddingX,$currentY,"1",0,1,1,"Mus. No: ${_fit(customerNoClean, (maxFont1Chars - 9).clamp(4, 40))}"',
      );
      currentY += sy(16);
    }
    if (phoneClean.isNotEmpty) {
      commands.writeln(
        'TEXT $paddingX,$currentY,"1",0,1,1,"Tel: ${_fit(phoneClean, (maxFont1Chars - 5).clamp(4, 60))}"',
      );
      currentY += sy(16);
    }
    if (previousDebt > 0.001) {
      commands.writeln(
        'TEXT $paddingX,$currentY,"1",0,1,1,"Eski borc: TL ${previousDebt.toStringAsFixed(2)}"',
      );
      currentY += sy(16);
    }

    // ── 4. Separator Line 1 ──
    final barH = (heightDots * 0.01).clamp(1, 2).round();
    commands.writeln('BAR $paddingX,$currentY,${widthDots - paddingX * 2},$barH');
    currentY += barH + sy(4);

    // ── 5. Items Breakdown ──
    if (showItemsCount &&
        itemsCount != null &&
        (items == null || items.isEmpty)) {
      commands.writeln(
        'TEXT $paddingX,$currentY,"1",0,1,1,"${_fit('- $itemsCount Parca Urun / Paket', maxFont1Chars)}"',
      );
      currentY += sy(16);
    }

    if (items != null && items.isNotEmpty) {
      for (final item in items) {
        final rawName =
            _ascii((item['product_name'] ?? item['name'] ?? 'Urun').toString());
        final itemQty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
        final itemQtyStr = itemQty % 1 == 0
            ? itemQty.toInt().toString()
            : itemQty.toStringAsFixed(1);
        final unitPrice =
            (item['unit_price'] as num? ?? item['unitPrice'] as num?)
                ?.toDouble();
        final lineTotal = item['total'] != null
            ? (item['total'] as num).toDouble()
            : item['line_total'] != null
                ? (item['line_total'] as num).toDouble()
                : unitPrice == null
                    ? null
                    : unitPrice * itemQty;

        // Line 1: Product Name (wrapped if long)
        final nameLines = _splitText(rawName, maxFont1Chars, maxLines: 2);
        for (final line in nameLines) {
          commands.writeln('TEXT $paddingX,$currentY,"1",0,1,1,"$line"');
          currentY += sy(18);
        }

        // Line 2: Quantity x Unit Price (Left) & Line Total (Right)
        final leftDetail = unitPrice == null
            ? '  $itemQtyStr adet'
            : '  ${itemQtyStr}x ${unitPrice.toStringAsFixed(2)} TL';
        final rightTotal =
            lineTotal == null ? '' : '${lineTotal.toStringAsFixed(2)} TL';

        final safeLeft = _fit(
          leftDetail,
          (maxFont1Chars - rightTotal.length - 1).clamp(4, maxFont1Chars),
        );
        commands.writeln('TEXT $paddingX,$currentY,"1",0,1,1,"$safeLeft"');

        if (rightTotal.isNotEmpty) {
          final rightX = (widthDots - paddingX - (rightTotal.length * 8))
              .clamp(paddingX, widthDots - paddingX);
          commands.writeln('TEXT $rightX,$currentY,"1",0,1,1,"$rightTotal"');
        }
        currentY += sy(18);
      }
    } else {
      final nameLines = _splitText(prodClean, maxFont2Chars, maxLines: 2);
      for (final line in nameLines) {
        commands.writeln('TEXT $paddingX,$currentY,"2",0,1,1,"$line"');
        currentY += sy(20);
      }
      final detail = '  $qtyStr adet';
      commands.writeln('TEXT $paddingX,$currentY,"1",0,1,1,"$detail"');
      if (totalAmount != null) {
        final totalText = '${totalAmount.toStringAsFixed(2)} TL';
        final rightX = (widthDots - paddingX - (totalText.length * 8))
            .clamp(paddingX, widthDots - paddingX);
        commands.writeln('TEXT $rightX,$currentY,"1",0,1,1,"$totalText"');
      }
      currentY += sy(18);
    }

    // ── 6. Separator Line 2 ──
    commands.writeln('BAR $paddingX,$currentY,${widthDots - paddingX * 2},$barH');
    currentY += barH + sy(4);

    // ── 7. Payment Status & Note ──
    commands.writeln(
      'TEXT $paddingX,$currentY,"1",0,1,1,"Odeme: ${_fit(_ascii(paymentStatus), (maxFont1Chars - 7).clamp(4, 60))}"',
    );
    currentY += sy(18);

    if (noteClean != null) {
      commands.writeln(
        'TEXT $paddingX,$currentY,"1",0,1,1,"Not: ${_fit(noteClean, (maxFont1Chars - 5).clamp(4, 60))}"',
      );
      currentY += sy(20);
    }

    // ── 8. Total Amount & QR Footer ──
    currentY += sy(4);
    final footerY = currentY;

    if (showTotalAmount && totalAmount != null) {
      final totalStr = 'TOPLAM: TL ${totalAmount.toStringAsFixed(2)}';
      final footerTextChars = ((widthDots - sx(110)) ~/ 8).clamp(8, 50);
      final safeTotal = _fit(totalStr, footerTextChars);
      final totalLayout = _widestTextLayout(safeTotal, widthDots - sx(110), maxHeight: sy(26));
      commands.boldText(
        paddingX,
        footerY,
        totalLayout.font,
        totalLayout.xMultiplier,
        totalLayout.yMultiplier,
        safeTotal,
      );
    }

    final qrValue = _ascii(orderIdShort).replaceAll('"', "'");
    if (qrValue.isNotEmpty) {
      final qrX = widthDots - sx(82);
      final qrCellWidth = (widthDots < 300) ? 2 : 3;
      commands.writeln(
        'QRCODE $qrX,$footerY,L,$qrCellWidth,A,0,M2,S7,"$qrValue"',
      );
    }

    commands.writeln('PRINT ${copies.clamp(1, 20)},1');
    return commands.bytes;
  }

  static List<String> _splitText(
    String text,
    int maxCharsPerLine, {
    int maxLines = 2,
  }) {
    final clean = _ascii(text.trim().replaceAll(RegExp(r'\s+'), ' '))
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
        if (lines.length == maxLines - 1) break;
      }
    }
    if (currentLine.isNotEmpty && lines.length < maxLines) {
      lines.add(currentLine);
    }

    if (lines.length == maxLines && lines.last.length > maxCharsPerLine) {
      lines.last = '${lines.last.substring(0, maxCharsPerLine - 2)}..';
    }

    return lines.isEmpty ? [clean] : lines;
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
    return sanitized.length <= 20 ? sanitized : '';
  }

  static String _fit(String value, int maxLength) {
    final normalized = _ascii(value.trim().replaceAll(RegExp(r'\s+'), ' '))
        .replaceAll('"', "'");
    if (maxLength <= 2) return normalized.isNotEmpty ? normalized[0] : '';
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 2)}..';
  }

  /// Selects the widest built-in-font/multiplier combination that remains
  /// inside [maxWidth] and [maxHeight].
  static ({
    String font,
    int xMultiplier,
    int yMultiplier,
    int width,
    int height,
  }) _widestTextLayout(String text, int maxWidth, {int? maxHeight}) {
    if (text.isEmpty) {
      return (font: '1', xMultiplier: 1, yMultiplier: 1, width: 0, height: 12);
    }

    const candidates = [
      (font: '4', charWidth: 24, charHeight: 32, xMultiplier: 3, yMultiplier: 2),
      (font: '4', charWidth: 24, charHeight: 32, xMultiplier: 2, yMultiplier: 2),
      (font: '2', charWidth: 12, charHeight: 20, xMultiplier: 3, yMultiplier: 3),
      (font: '3', charWidth: 16, charHeight: 24, xMultiplier: 2, yMultiplier: 2),
      (font: '4', charWidth: 24, charHeight: 32, xMultiplier: 1, yMultiplier: 2),
      (font: '2', charWidth: 12, charHeight: 20, xMultiplier: 2, yMultiplier: 2),
      (font: '3', charWidth: 16, charHeight: 24, xMultiplier: 1, yMultiplier: 2),
      (font: '2', charWidth: 12, charHeight: 20, xMultiplier: 1, yMultiplier: 2),
      (font: '1', charWidth: 8, charHeight: 12, xMultiplier: 1, yMultiplier: 2),
      (font: '2', charWidth: 12, charHeight: 20, xMultiplier: 1, yMultiplier: 1),
      (font: '1', charWidth: 8, charHeight: 12, xMultiplier: 1, yMultiplier: 1),
    ];

    for (final candidate in candidates) {
      final width = text.length * candidate.charWidth * candidate.xMultiplier;
      final height = candidate.charHeight * candidate.yMultiplier;
      if (width <= maxWidth && (maxHeight == null || height <= maxHeight)) {
        return (
          font: candidate.font,
          xMultiplier: candidate.xMultiplier,
          yMultiplier: candidate.yMultiplier,
          width: width,
          height: height,
        );
      }
    }

    return (
      font: '1',
      xMultiplier: 1,
      yMultiplier: 1,
      width: text.length * 8,
      height: 12,
    );
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

      var targetWidth = (widthDots * 0.52).round().clamp(80, 240).toInt();
      int targetHeight = (decoded.height * (targetWidth / decoded.width))
          .round()
          .clamp(8, maxHeight);
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
      for (int y = 0; y < targetHeight; y++) {
        for (int x = 0; x < widthBytes; x++) {
          int b = 0;
          for (int bit = 0; bit < 8; bit++) {
            final px = x * 8 + bit;
            if (px < targetWidth) {
              final p = resized.getPixel(px, y);
              final backgroundDistance = (p.r - backgroundR).abs() +
                  (p.g - backgroundG).abs() +
                  (p.b - backgroundB).abs();
              final isForeground = transparentCanvas
                  ? p.a >= 32
                  : p.a >= 128 && backgroundDistance >= 45;
              if (isForeground) {
                b |= (0x80 >> bit);
              }
            }
          }
          rasterBytes.add(b ^ 0xFF);
        }
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
