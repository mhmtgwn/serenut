import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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
    final widthDots = (printableWidthDots == null || (printableWidthDots == 384 && safeWidth > 54))
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
        final barcodeWidth = (barcode.length * 11 + 35) * 1;
        final priceLeft = (horizontalPadding + barcodeWidth + 12).clamp(
          (widthDots * 0.40).round(),
          (widthDots * 0.58).round(),
        );
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
    // On <=54mm rolls (such as standard 50mm, 40mm), clamp to 384 dots (max physical width of standard 2-inch printhead)
    final maxPhysicalDots =
        safeWidth <= 54 ? math.min(mediaWidthDots, 384) : mediaWidthDots;
    final widthDots = (printableWidthDots == null ||
            (printableWidthDots == 384 && safeWidth > 54))
        ? maxPhysicalDots
        : printableWidthDots.clamp(140, maxPhysicalDots);

    final isVeryWide = widthDots >= 540; // >= 68mm
    int sy(num value) => (value * safeDpi / 203).round();

    // Thermal label margins: provide a comfortable left padding and generous right safety margin
    // so physical roll drift / mechanical margins never cause right edge collision and wrap-around.
    final paddingX = (widthDots * 0.04).clamp(10.0, 20.0).round();
    final rightMargin = (widthDots * 0.08).clamp(24.0, 48.0).round();
    final usableW = widthDots - paddingX - rightMargin;

    final bodyFont = isVeryWide ? '3' : '2';
    final bodyFontPitch = isVeryWide ? 19 : 15;
    final fontScale = switch (fontSize) {
      'Küçük' => 0.90,
      'Büyük' => 1.30,
      _ => 1.10,
    };
    final rowHeight = sy((20 * fontScale).clamp(16.0, 30.0).round());
    final maxBodyChars = (usableW / bodyFontPitch).floor().clamp(4, 90);

    final custClean = _ascii(customerName.trim());
    final prodClean = _ascii(productName.trim());
    final phoneClean = _ascii(customerPhone?.trim() ?? '');
    final noteClean =
        note != null && note.trim().isNotEmpty ? _ascii(note.trim()) : null;

    final timeStr = (showDate && timestamp != null)
        ? '${timestamp.day.toString().padLeft(2, '0')}.${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}'
        : '';
    final qtyStr = quantity % 1 == 0
        ? quantity.toInt().toString()
        : quantity.toStringAsFixed(1);

    final hasCustomBizName = showBusinessName &&
        businessName != null &&
        businessName.trim().isNotEmpty &&
        !businessName.trim().toUpperCase().contains('SERENUT');
    final hasOrderNo = showOrderNo && orderIdShort.trim().isNotEmpty;
    final hasDate = showDate && timeStr.isNotEmpty;

    // ── Pre-calculate Exact Dot Height ──
    int calculatedDots = sy(4);
    if (hasCustomBizName) {
      calculatedDots += sy(24);
    }
    if (hasOrderNo && hasDate) {
      calculatedDots += rowHeight;
    } else if (hasOrderNo || hasDate) {
      calculatedDots += rowHeight;
    }
    if (showCustomerName) {
      calculatedDots += rowHeight;
      if (phoneClean.isNotEmpty) {
        final whoText =
            custClean.isNotEmpty ? 'Musteri: $custClean' : 'Musteri: Genel';
        final phoneText = 'Tel: $phoneClean';
        if (whoText.length + phoneText.length + 2 > maxBodyChars) {
          calculatedDots += rowHeight;
        }
      }
    }
    if (previousDebt > 0.001) calculatedDots += rowHeight;
    calculatedDots += sy(8); // Separator 1

    if (showItemsCount &&
        itemsCount != null &&
        (items == null || items.isEmpty)) {
      calculatedDots += rowHeight;
    }

    if (items != null && items.isNotEmpty) {
      for (final item in items) {
        final rawName =
            _ascii((item['product_name'] ?? item['name'] ?? 'Urun').toString());
        final nameLines = _splitText(rawName, maxBodyChars, maxLines: 2);
        calculatedDots += (nameLines.length * rowHeight);
        calculatedDots += rowHeight; // Detail / line total
      }
    } else {
      final nameLines = _splitText(prodClean, maxBodyChars, maxLines: 2);
      calculatedDots += nameLines.length * rowHeight;
      calculatedDots += rowHeight;
    }

    calculatedDots += sy(8); // Separator 2
    calculatedDots += rowHeight; // Payment status
    if (noteClean != null) calculatedDots += rowHeight;
    if (showTotalAmount && totalAmount != null) calculatedDots += sy(26);
    calculatedDots += sy(38); // Footer & QR Code clearance

    // Prevent vertical overflow by not adding unnecessary phantom padding
    final requiredHeightMm = (calculatedDots * 25.4 / safeDpi).ceil();
    final requestedHeightMm = heightMm.clamp(15, 1000);
    final safeHeight = requiredHeightMm > requestedHeightMm
        ? requiredHeightMm
        : requestedHeightMm;
    final heightDots = (safeHeight * safeDpi / 25.4).round();

    final commands = _TsplBuffer()
      ..writeln('SIZE $safeWidth mm,$safeHeight mm')
      ..writeln('GAP $safeGap mm,0 mm')
      ..writelnIf(autoDetectGap, 'GAPDETECT')
      ..writeln('DENSITY 8')
      ..writeln('DIRECTION ${direction == 1 ? 1 : 0}')
      ..writeln('REFERENCE 0,0')
      ..writeln('CLS');

    int currentY = sy(4);

    // ── 1. Business Header ──
    if (hasCustomBizName) {
      final bizText = _fit(_ascii(businessName.trim()), maxBodyChars);
      final layout = _widestTextLayout(
        bizText,
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
        bizText,
      );
      currentY += layout.height + sy(2);
    }

    // ── 2. Order # & Date (Brought close together, never pushed to the far-right edge) ──
    if (hasOrderNo && hasDate) {
      final dateText = timeStr;
      final dateWidth = (dateText.length * bodyFontPitch) + 4;
      final maxDateX = math.max(paddingX + 10, widthDots - rightMargin - dateWidth);
      final minDateX = math.min(paddingX + 60, maxDateX);
      final rawDateX = math.min((widthDots * 0.50).round(), maxDateX);
      final dateX = rawDateX.clamp(minDateX, maxDateX);

      final availableOrderChars =
          ((dateX - paddingX - 6) / bodyFontPitch).floor();
      final orderNo =
          _fit(orderIdShort, (availableOrderChars - 5).clamp(3, 25));

      commands.writeln(
          'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"Sip #$orderNo"');
      commands.writeln('TEXT $dateX,$currentY,"$bodyFont",0,1,1,"$dateText"');
      currentY += rowHeight;
    } else if (hasOrderNo) {
      final orderNo = _fit(orderIdShort, (maxBodyChars - 5).clamp(4, 30));
      commands.writeln(
          'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"Sip #$orderNo"');
      currentY += rowHeight;
    } else if (hasDate) {
      commands.writeln(
          'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"$timeStr"');
      currentY += rowHeight;
    }

    // ── 3. Customer Info (Brought close together, never pushed to the far-right edge) ──
    if (showCustomerName) {
      final whoText = custClean.isNotEmpty
          ? 'Mus: ${_fit(custClean, (maxBodyChars - 5).clamp(4, 60))}'
          : 'Mus: Genel';
      if (phoneClean.isNotEmpty) {
        final phoneText = 'Tel: ${_fit(phoneClean, 20)}';
        final phoneWidth = (phoneText.length * bodyFontPitch) + 4;
        final maxPhoneX =
            math.max(paddingX + 10, widthDots - rightMargin - phoneWidth);
        final minPhoneX = math.min(paddingX + 60, maxPhoneX);
        final rawPhoneX = math.min((widthDots * 0.52).round(), maxPhoneX);
        final phoneX = rawPhoneX.clamp(minPhoneX, maxPhoneX);

        final availableWhoChars =
            ((phoneX - paddingX - 6) / bodyFontPitch).floor();
        if (whoText.length <= availableWhoChars) {
          commands.writeln(
              'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"$whoText"');
          commands.writeln(
              'TEXT $phoneX,$currentY,"$bodyFont",0,1,1,"$phoneText"');
          currentY += rowHeight;
        } else {
          commands.writeln(
              'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"$whoText"');
          currentY += rowHeight;
          commands.writeln(
              'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"$phoneText"');
          currentY += rowHeight;
        }
      } else {
        commands.writeln(
            'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"$whoText"');
        currentY += rowHeight;
      }
    }
    if (previousDebt > 0.001) {
      commands.writeln(
        'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"Brc: TL ${previousDebt.toStringAsFixed(2)}"',
      );
      currentY += rowHeight;
    }

    // ── 4. Separator Line 1 (Full horizontal span across entire label) ──
    final barH = (heightDots * 0.01).clamp(1, 2).round();
    commands.writeln('BAR $paddingX,$currentY,$usableW,$barH');
    currentY += barH + sy(3);

    // ── 5. Items Breakdown (Adaptive layout, items and amounts grouped together) ──
    if (showItemsCount &&
        itemsCount != null &&
        (items == null || items.isEmpty)) {
      commands.writeln(
        'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"${_fit('- $itemsCount Parca Urun / Paket', maxBodyChars)}"',
      );
      currentY += rowHeight;
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
        final rightTotal =
            lineTotal == null ? '' : '${lineTotal.toStringAsFixed(2)} TL';

        // Line 1: Product Name
        final nameLines = _splitText(rawName, maxBodyChars, maxLines: 2);
        for (final line in nameLines) {
          commands.writeln('TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"$line"');
          currentY += rowHeight;
        }

        // Line 2: Quantity x Unit Price & Line Total (Grouped together, not pushed to edge)
        final leftDetail = unitPrice == null
            ? '  $itemQtyStr adet'
            : '  ${itemQtyStr}x ${unitPrice.toStringAsFixed(2)} TL';
        final lineDetail = rightTotal.isNotEmpty
            ? '$leftDetail  ($rightTotal)'
            : leftDetail;
        commands.writeln(
          'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"${_fit(lineDetail, maxBodyChars)}"',
        );
        currentY += rowHeight;
      }
    } else {
      final nameLines = _splitText(prodClean, maxBodyChars, maxLines: 2);
      for (final line in nameLines) {
        commands.writeln('TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"$line"');
        currentY += rowHeight;
      }
      final detail = totalAmount != null
          ? '  $qtyStr adet  (${totalAmount.toStringAsFixed(2)} TL)'
          : '  $qtyStr adet';
      commands.writeln('TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"${_fit(detail, maxBodyChars)}"');
      currentY += rowHeight;
    }

    // ── 6. Separator Line 2 (Full horizontal span) ──
    commands.writeln('BAR $paddingX,$currentY,$usableW,$barH');
    currentY += barH + sy(3);

    // ── 7. Payment Status & Note ──
    commands.writeln(
      'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"Odm: ${_fit(_ascii(paymentStatus), (maxBodyChars - 5).clamp(4, 60))}"',
    );
    currentY += rowHeight;

    if (noteClean != null) {
      commands.writeln(
        'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"Not: ${_fit(noteClean, (maxBodyChars - 5).clamp(4, 60))}"',
      );
      currentY += rowHeight;
    }

    // ── 8. Total Amount & QR Footer (Anchored inside label dots, spreading horizontally) ──
    final availableFooterSpace = heightDots - currentY;
    final footerY = (availableFooterSpace < sy(32))
        ? (heightDots - sy(30)).clamp(currentY, heightDots - sy(24))
        : currentY + sy(2);

    final qrCellWidth = isVeryWide ? 3 : ((widthDots < 440) ? 2 : 3);
    final qrBoxSize = qrCellWidth * 30; // 60 dots for cellWidth 2, 90 dots for cellWidth 3
    final qrX = (widthDots - math.max(rightMargin * 1.5, 36) - qrBoxSize)
        .round()
        .clamp(paddingX + 100, widthDots - qrBoxSize - 28);

    if (showTotalAmount && totalAmount != null) {
      final totalStr = 'TOPLAM: TL ${totalAmount.toStringAsFixed(2)}';
      final safeAvailableWidth =
          (qrX - paddingX - 10).clamp(60, widthDots).round();
      final footerTextChars = ((safeAvailableWidth) ~/ 8).clamp(8, 50);
      final safeTotal = _fit(totalStr, footerTextChars);
      final totalLayout = _widestTextLayout(safeTotal, safeAvailableWidth, maxHeight: (isVeryWide ? sy(32) : sy(26)));
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
      commands.writeln(
        'QRCODE $qrX,$footerY,L,$qrCellWidth,A,0,"$qrValue"',
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
