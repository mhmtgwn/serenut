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

    final horizontalPadding = (widthDots * 0.04).clamp(12.0, 24.0).round();
    final usableWidth = widthDots - (horizontalPadding * 2);
    final topGapMargin = (heightDots * 0.05).clamp(10, 22).round();
    final bottomGapMargin = (heightDots * 0.05).clamp(10, 22).round();

    final fontScale = switch (fontSize) {
      'Küçük' => 0.90,
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

    int currentY = topGapMargin;

    // ── 1. Top Header: Logo or Business Name ──────────────────────────────
    if (showBusinessName) {
      final maxHeaderHeight = (heightDots * 0.18 * fontScale).clamp(12, 36).round();
      final bitmapCmd = _generateTsplBitmap(
        logoPath,
        logoBytes,
        widthDots,
        currentY,
        maxHeight: maxHeaderHeight,
      );
      if (bitmapCmd != null) {
        commands.addAll(bitmapCmd.bytes);
        currentY += bitmapCmd.height + sy(3);
      } else if (model.businessName?.trim().isNotEmpty == true) {
        final bizText = model.businessName!.trim();
        final maxChars = (usableWidth / 12).floor().clamp(4, 50);
        final bizClean = _fit(bizText, maxChars);
        final textW = bizClean.length * 12;
        final centerX = ((widthDots - textW) / 2)
            .round()
            .clamp(horizontalPadding, widthDots - horizontalPadding);
        commands.boldText(
          centerX,
          currentY,
          '2',
          1,
          1,
          bizClean,
        );
        currentY += 22;
      }
    }

    // ── 2. Brand Name (if enabled) ────────────────────────────────────────
    if (showBrand && model.brand?.trim().isNotEmpty == true) {
      final maxBrandChars = (usableWidth / 8).floor().clamp(4, 50);
      final brandText = _fit(model.brand!, maxBrandChars);
      final textW = brandText.length * 8;
      final centerX = ((widthDots - textW) / 2)
          .round()
          .clamp(horizontalPadding, widthDots - horizontalPadding);
      commands.writeln(
        'TEXT $centerX,$currentY,"1",0,1,1,"$brandText"',
      );
      currentY += 14;
    }

    // ── 3. Product Name (Middle Section, Proportional) ───────────────────
    final nameClean = _ascii(model.productName);
    final maxFont3Chars = (usableWidth / 16).floor().clamp(6, 26);
    final maxFont2Chars = (usableWidth / 12).floor().clamp(8, 42);

    if (nameClean.length <= maxFont3Chars) {
      final textW = nameClean.length * 16;
      final centerX = ((widthDots - textW) / 2)
          .clamp(horizontalPadding, widthDots - horizontalPadding)
          .round();
      commands.boldText(centerX, currentY, '3', 1, 1, nameClean);
      currentY += 26;
    } else if (nameClean.length <= maxFont2Chars) {
      final textW = nameClean.length * 12;
      final centerX = ((widthDots - textW) / 2)
          .clamp(horizontalPadding, widthDots - horizontalPadding)
          .round();
      commands.boldText(centerX, currentY, '2', 1, 1, nameClean);
      currentY += 22;
    } else {
      final lines = _wrapProductName(nameClean, maxFont2Chars);
      for (final line in lines) {
        final textW = line.length * 12;
        final centerX = ((widthDots - textW) / 2)
            .clamp(horizontalPadding, widthDots - horizontalPadding)
            .round();
        commands.boldText(centerX, currentY, '2', 1, 1, line);
        currentY += 21;
      }
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
      'BAR $horizontalPadding,$currentY,$usableWidth,$barHeight',
    );
    currentY += barHeight + sy(2);

    // ── 5. Bottom Section (Left: Barcode | Right: Price & KDV) ────────────
    final bottomY = currentY;
    final availableBottomHeight = (heightDots - bottomY - bottomGapMargin).clamp(24, heightDots);

    // Bottom Left: Barcode
    if (showBarcode && barcode.isNotEmpty) {
      final barcodeHeight = (availableBottomHeight * 0.60).clamp(18, 48).round();
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
        final barcodeEstimatedWidth = barcode.length * 11 + 35;
        final priceLeft = (horizontalPadding + barcodeEstimatedWidth + 10).clamp(
          (widthDots * 0.42).round(),
          (widthDots * 0.58).round(),
        );
        final availablePriceWidth = (widthDots - priceLeft - horizontalPadding).clamp(40, widthDots);
        final priceText = '$whole,$cents';
        const currencyWidth = 14;
        const gap = 2;

        final priceFont = (currencyWidth + gap + priceText.length * 24 <= availablePriceWidth)
            ? '4'
            : ((currencyWidth + gap + priceText.length * 16 <= availablePriceWidth) ? '3' : '2');
        final priceCharWidth = priceFont == '4' ? 24 : (priceFont == '3' ? 16 : 12);
        final priceWidth = priceText.length * priceCharWidth;
        final totalPriceWidth = currencyWidth + gap + priceWidth;
        final currencyX = (priceLeft + ((availablePriceWidth - totalPriceWidth) / 2))
            .round()
            .clamp(priceLeft, widthDots - horizontalPadding);
        final priceX = currencyX + currencyWidth + gap;
        final priceY = bottomY + sy(2);

        commands.writeln('TEXT $currencyX,${priceY + sy(6)},"2",0,1,1,"TL"');
        commands.boldText(
          priceX,
          priceY,
          priceFont,
          1,
          1,
          priceText,
        );
        if (showVat) {
          final vatY = bottomY + availableBottomHeight - sy(10);
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
        final priceY = bottomY + sy(2);
        commands.boldText(priceX, priceY, priceFont, 1, 1, priceStr);
        if (showVat) {
          const vatW = vatStr.length * 8;
          final vatX = ((widthDots - vatW) / 2).clamp(horizontalPadding, widthDots - horizontalPadding).round();
          final vatY = bottomY + availableBottomHeight - sy(10);
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
    bool paginateOnOverflow = true,
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

    // Symmetric margins: left and right margins are equal so the label is centered and balanced.
    final paddingX = (widthDots * 0.045).clamp(16.0, 32.0).round();
    final usableW = widthDots - (2 * paddingX);
    final barW = usableW;

    final bodyFont = isVeryWide ? '3' : '2';
    // Exact character pitch (in dots) including character glyph width and inter-character spacing:
    // Font '2' is 12x20 dots (pitch: 14 dots); Font '3' is 16x24 dots (pitch: 18 dots).
    final bodyFontPitch = isVeryWide ? 18 : 14;
    final fontScale = switch (fontSize) {
      'Küçük' => 0.90,
      'Büyük' => 1.25,
      _ => 1.05,
    };
    final rowHeight = sy((20 * fontScale).clamp(16.0, 30.0).round());
    final maxBodyChars = ((usableW - 10) / bodyFontPitch).floor().clamp(4, 70);

    final custClean = _ascii(customerName.trim());
    final prodClean = _ascii(productName.trim());
    final phoneClean = _ascii(customerPhone?.trim() ?? '');
    final noteClean =
        note != null && note.trim().isNotEmpty ? _ascii(note.trim()) : null;

    final timeStr = (showDate && timestamp != null)
        ? '${timestamp.day.toString().padLeft(2, '0')}.${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}'
        : '';
    final hasCustomBizName = showBusinessName &&
        businessName != null &&
        businessName.trim().isNotEmpty &&
        !businessName.trim().toUpperCase().contains('SERENUT');
    final hasOrderNo = showOrderNo && orderIdShort.trim().isNotEmpty;
    final hasDate = showDate && timeStr.isNotEmpty;

    final requestedHeightMm = heightMm.clamp(15, 150);
    final labelHeightDots = (requestedHeightMm * safeDpi / 25.4).round();
    final topGapMargin = (labelHeightDots * 0.04).clamp(8, 16).round();
    final bottomGapMargin = (labelHeightDots * 0.08).clamp(24, 40).round();
    final maxSafePageY = labelHeightDots - bottomGapMargin;
    final barH = (labelHeightDots * 0.01).clamp(1, 2).round();

    // ── Pre-calculate Exact Dot Height ──
    int calculatedDots = topGapMargin;
    if (hasCustomBizName) {
      calculatedDots += sy(24);
    }
    if (hasOrderNo || hasDate) {
      calculatedDots += rowHeight;
    }
    if (showCustomerName) {
      calculatedDots += rowHeight;
      if (phoneClean.isNotEmpty) {
        calculatedDots += rowHeight;
      }
    }
    if (previousDebt > 0.001) calculatedDots += rowHeight;
    calculatedDots += sy(8); // Separator 1

    if (showItemsCount &&
        itemsCount != null &&
        (items == null || items.isEmpty)) {
      calculatedDots += rowHeight;
    }

    final List<Map<String, dynamic>> itemsList;
    if (items != null && items.isNotEmpty) {
      itemsList = items;
    } else {
      itemsList = [
        {
          'product_name': prodClean,
          'quantity': quantity,
          if (totalAmount != null) 'total': totalAmount,
        }
      ];
    }

    int itemHeightOf(Map<String, dynamic> item) {
      final rawName =
          _ascii((item['product_name'] ?? item['name'] ?? 'Urun').toString());
      final nameLines = _splitText(rawName, maxBodyChars, maxLines: 2);
      return (nameLines.length * rowHeight) + rowHeight;
    }

    for (final item in itemsList) {
      calculatedDots += itemHeightOf(item);
    }

    calculatedDots += sy(8); // Separator 2
    final prePaymentY = calculatedDots;
    calculatedDots += rowHeight; // Payment status
    if (noteClean != null) calculatedDots += rowHeight;
    if (showTotalAmount && totalAmount != null) calculatedDots += sy(26);

    // QR code starts at paymentY (aligned with payment status)
    final qrCellWidth = isVeryWide ? 3 : ((widthDots < 440) ? 2 : 3);
    final qrBoxSize = qrCellWidth * 30;
    final qrX = (widthDots - paddingX - qrBoxSize)
        .clamp(paddingX + 60, widthDots - paddingX - qrBoxSize);
    final qrValue = _ascii(orderIdShort).replaceAll('"', "'");

    final minBottomForQr = prePaymentY + qrBoxSize + sy(6);
    if (calculatedDots < minBottomForQr) {
      calculatedDots = minBottomForQr;
    } else {
      calculatedDots += bottomGapMargin;
    }

    final dateText = timeStr;
    final dateCharPitch = isVeryWide ? 17 : 13;
    final datePixelWidth = dateText.length * dateCharPitch;
    final safeDateX = (widthDots - paddingX - datePixelWidth)
        .clamp(paddingX + 60, widthDots - paddingX);
    final availableOrderChars =
        ((safeDateX - paddingX - 12) / bodyFontPitch).floor().clamp(3, 30);

    int renderItems(List<Map<String, dynamic>> itemList, int startY, _TsplBuffer buf) {
      var y = startY;
      for (final item in itemList) {
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
          buf.writeln('TEXT $paddingX,$y,"$bodyFont",0,1,1,"$line"');
          y += rowHeight;
        }

        // Line 2: Quantity x Unit Price = Line Total
        final String lineDetail;
        if (unitPrice != null && rightTotal.isNotEmpty) {
          lineDetail = '  ${itemQtyStr}x ${unitPrice.toStringAsFixed(2)} TL = $rightTotal';
        } else if (rightTotal.isNotEmpty) {
          lineDetail = '  $itemQtyStr adet = $rightTotal';
        } else {
          lineDetail = '  $itemQtyStr adet';
        }
        buf.writeln(
          'TEXT $paddingX,$y,"$bodyFont",0,1,1,"${_fit(lineDetail, maxBodyChars)}"',
        );
        y += rowHeight;
      }
      return y;
    }

    final page1HeaderHeight = topGapMargin +
        (hasCustomBizName ? (sy(22) + sy(2)) : 0) +
        ((hasOrderNo || hasDate) ? rowHeight : 0) +
        (showCustomerName ? (rowHeight + (phoneClean.isNotEmpty ? rowHeight : 0)) : 0) +
        (previousDebt > 0.001 ? rowHeight : 0) +
        (barH + sy(3));

    final subsequentHeaderHeight = topGapMargin + rowHeight + (barH + sy(3));

    final closingFooterHeight = (barH + sy(3)) +
        math.max(
          rowHeight +
              (noteClean != null ? rowHeight : 0) +
              (showTotalAmount && totalAmount != null ? sy(26) : 0),
          qrBoxSize,
        ) +
        sy(4);

    var totalItemsHeight = 0;
    for (final item in itemsList) {
      totalItemsHeight += itemHeightOf(item);
    }
    final singlePageTotalNeeded = page1HeaderHeight + totalItemsHeight + closingFooterHeight;
    final fitsInOnePage = singlePageTotalNeeded <= maxSafePageY;

    final shouldPaginate = safeGap > 0 &&
        paginateOnOverflow &&
        itemsList.length >= 4 &&
        !fitsInOnePage;

    List<List<Map<String, dynamic>>> paginateItems() {
      final pages = <List<Map<String, dynamic>>>[];
      var itemIndex = 0;

      // Page 1 budget
      final page1ItemBudget = math.max(
        rowHeight * 2,
        maxSafePageY - page1HeaderHeight - (barH + sy(3)),
      );

      final page1Items = <Map<String, dynamic>>[];
      var page1Used = 0;
      while (itemIndex < itemsList.length) {
        final h = itemHeightOf(itemsList[itemIndex]);
        if (page1Items.isNotEmpty && (page1Used + h > page1ItemBudget)) {
          break;
        }
        page1Items.add(itemsList[itemIndex]);
        page1Used += h;
        itemIndex++;
      }
      if (itemIndex == itemsList.length && page1Items.length > 1) {
        page1Items.removeLast();
        itemIndex--;
      }
      pages.add(page1Items);

      // Subsequent pages budgets
      final closingPageItemBudget = math.max(
        rowHeight * 2,
        maxSafePageY - subsequentHeaderHeight - closingFooterHeight,
      );
      final interItemBudget = math.max(
        rowHeight * 2,
        maxSafePageY - subsequentHeaderHeight - (barH + sy(3)),
      );

      while (itemIndex < itemsList.length) {
        var remainingHeight = 0;
        for (var i = itemIndex; i < itemsList.length; i++) {
          remainingHeight += itemHeightOf(itemsList[i]);
        }
        if (remainingHeight <= closingPageItemBudget) {
          pages.add(itemsList.sublist(itemIndex));
          itemIndex = itemsList.length;
          break;
        }

        final interItems = <Map<String, dynamic>>[];
        var interUsed = 0;
        while (itemIndex < itemsList.length) {
          final h = itemHeightOf(itemsList[itemIndex]);
          if (interItems.isNotEmpty && (interUsed + h > interItemBudget)) {
            break;
          }
          interItems.add(itemsList[itemIndex]);
          interUsed += h;
          itemIndex++;
        }
        pages.add(interItems);
      }

      return pages;
    }

    final commands = _TsplBuffer();

    if (shouldPaginate) {
      final pages = paginateItems();
      for (var pageIdx = pages.length - 1; pageIdx >= 0; pageIdx--) {
        commands
          ..writeln('SIZE $safeWidth mm,$requestedHeightMm mm')
          ..writeln('GAP $safeGap mm,0 mm')
          ..writelnIf(autoDetectGap, 'GAPDETECT')
          ..writeln('DENSITY 8')
          ..writeln('DIRECTION ${direction == 1 ? 1 : 0}')
          ..writeln('REFERENCE 0,0')
          ..writeln('CLS');

        var currentY = topGapMargin;

        if (pageIdx == 0) {
          if (hasCustomBizName) {
            final bizText = _fit(_ascii(businessName.trim()), maxBodyChars);
            final layout = _widestTextLayout(
              bizText,
              usableW,
              maxHeight: (labelHeightDots * 0.14).clamp(10, 24).round(),
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

          final page1OrderNo =
              _fit(orderIdShort, (availableOrderChars - 8).clamp(3, 22));
          if (hasOrderNo && hasDate) {
            commands.writeln(
                'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"Sip #$page1OrderNo (1/${pages.length})"');
            commands.writeln(
                'TEXT $safeDateX,$currentY,"$bodyFont",0,1,1,"$dateText"');
            currentY += rowHeight;
          } else if (hasOrderNo) {
            commands.writeln(
                'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"Sip #$page1OrderNo (1/${pages.length})"');
            currentY += rowHeight;
          } else if (hasDate) {
            commands.writeln(
                'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"$timeStr (1/${pages.length})"');
            currentY += rowHeight;
          }

          if (showCustomerName) {
            final whoText = custClean.isNotEmpty
                ? 'Mus: ${_fit(custClean, (maxBodyChars - 5).clamp(4, 60))}'
                : 'Mus: Genel';
            commands.writeln(
                'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"$whoText"');
            currentY += rowHeight;

            if (phoneClean.isNotEmpty) {
              final phoneText =
                  'Tel: ${_fit(phoneClean, (maxBodyChars - 5).clamp(4, 30))}';
              commands.writeln(
                  'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"$phoneText"');
              currentY += rowHeight;
            }
          }
          if (previousDebt > 0.001) {
            commands.writeln(
              'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"Brc: TL ${previousDebt.toStringAsFixed(2)}"',
            );
            currentY += rowHeight;
          }

          commands.writeln('BAR $paddingX,$currentY,$barW,$barH');
          currentY += barH + sy(3);

          currentY = renderItems(pages[0], currentY, commands);

          commands.writeln('BAR $paddingX,$currentY,$barW,$barH');
        } else if (pageIdx < pages.length - 1) {
          final contOrderNo =
              _fit(orderIdShort, (availableOrderChars - 10).clamp(3, 20));
          if (hasOrderNo && hasDate) {
            commands.writeln(
                'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"Sip #$contOrderNo (${pageIdx + 1}/${pages.length})"');
            commands.writeln(
                'TEXT $safeDateX,$currentY,"$bodyFont",0,1,1,"$dateText"');
            currentY += rowHeight;
          } else if (hasOrderNo) {
            commands.writeln(
                'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"Sip #$contOrderNo (${pageIdx + 1}/${pages.length})"');
            currentY += rowHeight;
          } else if (hasDate) {
            commands.writeln(
                'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"$timeStr (${pageIdx + 1}/${pages.length})"');
            currentY += rowHeight;
          }

          commands.writeln('BAR $paddingX,$currentY,$barW,$barH');
          currentY += barH + sy(3);

          currentY = renderItems(pages[pageIdx], currentY, commands);

          commands.writeln('BAR $paddingX,$currentY,$barW,$barH');
        } else {
          final contOrderNo =
              _fit(orderIdShort, (availableOrderChars - 10).clamp(3, 20));
          if (hasOrderNo && hasDate) {
            commands.writeln(
                'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"Sip #$contOrderNo (${pages.length}/${pages.length})"');
            commands.writeln(
                'TEXT $safeDateX,$currentY,"$bodyFont",0,1,1,"$dateText"');
            currentY += rowHeight;
          } else if (hasOrderNo) {
            commands.writeln(
                'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"Sip #$contOrderNo (${pages.length}/${pages.length})"');
            currentY += rowHeight;
          } else if (hasDate) {
            commands.writeln(
                'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"$timeStr (${pages.length}/${pages.length})"');
            currentY += rowHeight;
          }

          commands.writeln('BAR $paddingX,$currentY,$barW,$barH');
          currentY += barH + sy(3);

          currentY = renderItems(pages[pageIdx], currentY, commands);

          commands.writeln('BAR $paddingX,$currentY,$barW,$barH');
          currentY += barH + sy(3);

          final paymentY = currentY;
          if (qrValue.isNotEmpty) {
            commands.writeln(
              'QRCODE $qrX,$paymentY,L,$qrCellWidth,A,0,"$qrValue"',
            );
          }

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

          final footerY = currentY + sy(2);
          if (showTotalAmount && totalAmount != null) {
            final totalStr = 'TOPLAM: TL ${totalAmount.toStringAsFixed(2)}';
            final safeAvailableWidth =
                (qrX - paddingX - 10).clamp(60, widthDots).round();
            final footerTextChars = ((safeAvailableWidth) ~/ 12).clamp(8, 30);
            final safeTotal = _fit(totalStr, footerTextChars);
            final totalLayout = _widestTextLayout(safeTotal, safeAvailableWidth,
                maxHeight: (isVeryWide ? sy(32) : sy(26)));
            commands.boldText(
              paddingX,
              footerY,
              totalLayout.font,
              totalLayout.xMultiplier,
              totalLayout.yMultiplier,
              safeTotal,
            );
          }
        }

        commands.writeln('PRINT ${copies.clamp(1, 20)},1');
      }
    } else {
      final safeHeight = (safeGap > 0 && paginateOnOverflow)
          ? requestedHeightMm
          : math.max(
              requestedHeightMm,
              (calculatedDots * 25.4 / safeDpi).ceil(),
            );
      final heightDots = (safeHeight * safeDpi / 25.4).round();

      commands
        ..writeln('SIZE $safeWidth mm,$safeHeight mm')
        ..writeln('GAP $safeGap mm,0 mm')
        ..writelnIf(autoDetectGap, 'GAPDETECT')
        ..writeln('DENSITY 8')
        ..writeln('DIRECTION ${direction == 1 ? 1 : 0}')
        ..writeln('REFERENCE 0,0')
        ..writeln('CLS');

      var currentY = topGapMargin;

      if (hasCustomBizName) {
        final bizText = _fit(_ascii(businessName.trim()), maxBodyChars);
        final layout = _widestTextLayout(
          bizText,
          usableW,
          maxHeight: (heightDots * 0.14).clamp(10, 24).round(),
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

      final safeOrderNo =
          _fit(orderIdShort, (availableOrderChars - 5).clamp(3, 25));
      if (hasOrderNo && hasDate) {
        commands.writeln(
            'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"Sip #$safeOrderNo"');
        commands.writeln(
            'TEXT $safeDateX,$currentY,"$bodyFont",0,1,1,"$dateText"');
        currentY += rowHeight;
      } else if (hasOrderNo) {
        commands.writeln(
            'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"Sip #$safeOrderNo"');
        currentY += rowHeight;
      } else if (hasDate) {
        commands.writeln(
            'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"$timeStr"');
        currentY += rowHeight;
      }

      // ── 3. Customer Info ──
      if (showCustomerName) {
        final whoText = custClean.isNotEmpty
            ? 'Mus: ${_fit(custClean, (maxBodyChars - 5).clamp(4, 60))}'
            : 'Mus: Genel';
        commands.writeln(
            'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"$whoText"');
        currentY += rowHeight;

        if (phoneClean.isNotEmpty) {
          final phoneText =
              'Tel: ${_fit(phoneClean, (maxBodyChars - 5).clamp(4, 30))}';
          commands.writeln(
              'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"$phoneText"');
          currentY += rowHeight;
        }
      }
      if (previousDebt > 0.001) {
        commands.writeln(
          'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"Brc: TL ${previousDebt.toStringAsFixed(2)}"',
        );
        currentY += rowHeight;
      }

      // ── 4. Separator Line 1 ──
      commands.writeln('BAR $paddingX,$currentY,$barW,$barH');
      currentY += barH + sy(3);

      // ── 5. Items Breakdown ──
      if (showItemsCount &&
          itemsCount != null &&
          (items == null || items.isEmpty)) {
        commands.writeln(
          'TEXT $paddingX,$currentY,"$bodyFont",0,1,1,"${_fit('- $itemsCount Parca Urun / Paket', maxBodyChars)}"',
        );
        currentY += rowHeight;
      }

      currentY = renderItems(itemsList, currentY, commands);

      // ── 6. Separator Line 2 ──
      commands.writeln('BAR $paddingX,$currentY,$barW,$barH');
      currentY += barH + sy(3);

      // ── 7. Payment Status & QR Code ──
      final paymentY = currentY;
      if (qrValue.isNotEmpty) {
        commands.writeln(
          'QRCODE $qrX,$paymentY,L,$qrCellWidth,A,0,"$qrValue"',
        );
      }

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

      // ── 8. Total Amount ──
      final footerY = currentY + sy(2);
      if (showTotalAmount && totalAmount != null) {
        final totalStr = 'TOPLAM: TL ${totalAmount.toStringAsFixed(2)}';
        final safeAvailableWidth =
            (qrX - paddingX - 10).clamp(60, widthDots).round();
        final footerTextChars = ((safeAvailableWidth) ~/ 8).clamp(8, 50);
        final safeTotal = _fit(totalStr, footerTextChars);
        final totalLayout = _widestTextLayout(safeTotal, safeAvailableWidth,
            maxHeight: (isVeryWide ? sy(32) : sy(26)));
        commands.boldText(
          paddingX,
          footerY,
          totalLayout.font,
          totalLayout.xMultiplier,
          totalLayout.yMultiplier,
          safeTotal,
        );
      }

      commands.writeln('PRINT ${copies.clamp(1, 20)},1');
    }

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

    final result = <String>[];
    for (final l in lines) {
      result.add(_fit(l, maxCharsPerLine));
    }
    return result.isEmpty ? [_fit(clean, maxCharsPerLine)] : result;
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

      final maxTargetW = (widthDots * 0.50).round().clamp(60, 220);
      final maxTargetH = maxHeight;
      final scale = math.min(
        maxTargetW / decoded.width,
        maxTargetH / decoded.height,
      );
      var targetWidth = (decoded.width * scale).round().clamp(16, maxTargetW);
      var targetHeight = (decoded.height * scale).round().clamp(8, maxTargetH);
      targetWidth = ((targetWidth + 7) ~/ 8) * 8; // Multiple of 8
      if (targetWidth < 8) targetWidth = 8;
      final widthBytes = targetWidth ~/ 8;

      final resized =
          img.copyResize(decoded, width: targetWidth, height: targetHeight);
      final centerX =
          ((widthDots - targetWidth) / 2).clamp(10, widthDots - targetWidth).round();

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
          rasterBytes.add(b);
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
