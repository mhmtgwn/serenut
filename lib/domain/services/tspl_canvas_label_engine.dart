import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:serenutos/domain/printing/label_dimension_models.dart';

/// Next-Generation TSPL Label Renderer powered by Flutter's Canvas & TextPainter.
///
/// Eliminates character width and pixel height guessing entirely by measuring
/// and rendering with Flutter's actual typography engine directly to 1-bit
/// monochrome raster bitmaps.
class TsplCanvasLabelEngine {
  /// Generates multi-page or single-page TSPL order label bytes using Flutter Canvas.
  static Future<List<int>> generateOrderLabelBytes({
    required String orderIdShort,
    required String customerName,
    String? customerPhone,
    String? customerNo,
    double previousDebt = 0.0,
    String paymentStatus = 'Bilinmiyor',
    required String productName,
    double quantity = 1.0,
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
    int direction = 0,
    int copies = 1,
    int? printableWidthDots,
    bool showBusinessName = true,
    bool showCustomerName = true,
    bool showOrderNo = true,
    bool showDate = true,
    bool showTotalAmount = true,
    bool showItemsCount = true,
    String fontSize = 'Orta',
    bool paginateOnOverflow = true,
    String? businessName,
    Uint8List? logoBytes,
    String? qrData,
    bool showQrCode = true,
    TargetPageSize? targetPageSize,
  }) async {
    final isContinuous =
        gapMm <= 0 || (targetPageSize?.mode == MediaMode.continuous);
    final effectiveWidthMm = targetPageSize != null
        ? targetPageSize.widthMm.round()
        : widthMm;
    final effectiveInitialHeightMm = targetPageSize != null
        ? targetPageSize.heightMm.round()
        : heightMm;

    final safeDpi = dpi < 100 ? 203 : dpi;
    final safeWidth = effectiveWidthMm.clamp(20, 150);
    final requestedHeightMm = effectiveInitialHeightMm.clamp(15, 300);

    final mediaWidthDots = (safeWidth * safeDpi / 25.4).round();
    // Standard 2-inch printhead width is 48mm (384 dots @ 203 DPI, 576 dots @ 300 DPI).
    final maxNarrowDots = (48.0 * safeDpi / 25.4).round();
    final maxPhysicalDots = safeWidth <= 54
        ? math.min(mediaWidthDots, maxNarrowDots)
        : mediaWidthDots;
    final effectivePrintableDots = printableWidthDots != null &&
            printableWidthDots > 100
        ? math.min(maxPhysicalDots, printableWidthDots)
        : maxPhysicalDots;
    final widthBytes = (effectivePrintableDots + 7) ~/ 8;
    final widthDots = widthBytes * 8;
    final heightDots = (requestedHeightMm * safeDpi / 25.4).round();

    // Safe margins: 4.0mm left, 5.5mm right on narrow labels (<=54mm) to ensure lines
    // and QR code never reach the physical edge or bleed off-label.
    final marginMm = safeWidth <= 54 ? 4.0 : 2.0;
    final paddingLeft = (marginMm * safeDpi / 25.4).roundToDouble();
    final paddingRight =
        ((safeWidth <= 54 ? 5.5 : 2.0) * safeDpi / 25.4).roundToDouble();
    const safetyDots = 2.0;
    final safeRightX = (widthDots - paddingRight - safetyDots).roundToDouble();
    final usableW = (safeRightX - paddingLeft).clamp(60.0, 1000.0);
    final topMargin = (1.0 * safeDpi / 25.4).roundToDouble();
    // 2.5mm bottom clearance on 30mm labels to completely avoid bleeding into gap
    final bottomMargin = (requestedHeightMm <= 30 ? 2.5 : 1.5) * safeDpi / 25.4;
    final maxSafePageY = heightDots - bottomMargin - safetyDots;

    final fontScale = switch (fontSize) {
      'Küçük' => 0.88,
      'Büyük' => 1.15,
      _ => 1.0,
    };
    final isWide = safeWidth >= 70;
    final isTall = requestedHeightMm > 40;
    // Larger, highly legible typography tailored to both width and height:
    final titleFontSize =
        (isWide ? (isTall ? 30.0 : 25.0) : 23.0) * fontScale;
    final bodyFontSize =
        (isWide ? (isTall ? 24.0 : 19.0) : 18.0) * fontScale;
    final detailFontSize =
        (isWide ? (isTall ? 20.0 : 16.0) : 15.0) * fontScale;

    final dateStr = (showDate && timestamp != null)
        ? '${timestamp.day.toString().padLeft(2, '0')}.${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}'
        : '';

    final List<Map<String, dynamic>> itemsList;
    if (items != null && items.isNotEmpty) {
      itemsList = items;
    } else {
      itemsList = [
        {
          'product_name': productName.trim(),
          'quantity': quantity,
          if (totalAmount != null) 'total': totalAmount,
        }
      ];
    }

    // Measure Item Layout and Height using TextPainter
    _MeasuredItem measureItem(Map<String, dynamic> item) {
      final name =
          (item['product_name'] ?? item['name'] ?? 'Ürün').toString().trim();
      final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final qtyStr =
          qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(1);
      final unitPrice =
          (item['unit_price'] as num? ?? item['unitPrice'] as num?)?.toDouble();
      final lineTotal = item['total'] != null
          ? (item['total'] as num).toDouble()
          : item['line_total'] != null
              ? (item['line_total'] as num).toDouble()
              : unitPrice == null
                  ? null
                  : unitPrice * qty;
      final rightTotal =
          lineTotal == null ? '' : '${lineTotal.toStringAsFixed(2)} TL';

      final namePainter = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            color: Colors.black,
            fontSize: bodyFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: usableW);

      final String detailText;
      if (unitPrice != null && rightTotal.isNotEmpty) {
        detailText =
            '$qtyStr ad. x ${unitPrice.toStringAsFixed(2)} TL = $rightTotal';
      } else if (rightTotal.isNotEmpty) {
        detailText = '$qtyStr adet = $rightTotal';
      } else {
        detailText = '$qtyStr adet';
      }

      final detailPainter = TextPainter(
        text: TextSpan(
          text: detailText,
          style: TextStyle(
            color: Colors.black,
            fontSize: detailFontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: usableW);

      final totalH = namePainter.height + detailPainter.height + 2.5;
      return _MeasuredItem(item, namePainter, detailPainter, totalH);
    }

    final measuredItems = itemsList.map(measureItem).toList();

    // Measure Header Heights with exact TextPainters matching painting
    double measurePage1HeaderHeight() {
      var h = topMargin;
      if (showOrderNo || showDate) {
        final leftOrder = showOrderNo ? 'Sip #$orderIdShort' : '';
        final orderMaxW = dateStr.isNotEmpty ? usableW * 0.55 : usableW;
        final orderPainter = TextPainter(
          text: TextSpan(
            text: leftOrder,
            style: TextStyle(
              color: Colors.black,
              fontSize: bodyFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: orderMaxW);
        h += math.max(orderPainter.height, bodyFontSize) + 2.0;
      }
      if (showCustomerName) {
        final custStr = customerName.trim().isNotEmpty
            ? 'Müş: ${customerName.trim()}'
            : 'Müş: Genel';
        final custPainter = TextPainter(
          text: TextSpan(
            text: custStr,
            style: TextStyle(
              color: Colors.black,
              fontSize: bodyFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: usableW);
        h += custPainter.height + 1.0;

        if (customerPhone != null && customerPhone.trim().isNotEmpty) {
          final phonePainter = TextPainter(
            text: TextSpan(
              text: 'Tel: ${customerPhone.trim()}',
              style: TextStyle(
                color: Colors.black,
                fontSize: detailFontSize,
                fontWeight: FontWeight.normal,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: usableW);
          h += phonePainter.height + 1.0;
        }
      }
      if (previousDebt > 0.001) {
        final debtPainter = TextPainter(
          text: TextSpan(
            text: 'Geçmiş Borç: ${previousDebt.toStringAsFixed(2)} TL',
            style: TextStyle(
              color: Colors.black,
              fontSize: detailFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: usableW);
        h += debtPainter.height + 1.0;
      }
      h += 4.5; // Divider bar
      return h;
    }

    final page1HeaderH = measurePage1HeaderHeight();
    final subsequentHeaderH = () {
      var h = topMargin;
      final contMaxW = dateStr.isNotEmpty ? usableW * 0.55 : usableW;
      final contPainter = TextPainter(
        text: TextSpan(
          text: 'Sip #$orderIdShort (9/9) - Devam',
          style: TextStyle(
            color: Colors.black,
            fontSize: bodyFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: contMaxW);
      h += math.max(contPainter.height, bodyFontSize) + 2.0;
      h += 2.5; // Divider
      return h;
    }();

    // Sizing for QR code on the closing footer (scaled proportionally to DPI)
    final dotsPerMm = safeDpi / 25.4;
    final cleanQrData = (qrData != null && qrData.trim().isNotEmpty)
        ? qrData.trim()
        : 'order|$orderIdShort';
    final hasQr = showQrCode && cleanQrData.isNotEmpty;

    // Sizing for QR code on the closing footer (scaled proportionally to DPI and label height)
    final qrCellWidth = (isWide && requestedHeightMm > 40)
        ? (safeDpi >= 300 ? 4 : 3)
        : (safeDpi >= 300 ? 3 : 2);
    // Level-M QR code generates 21-25 modules (Version 1-2) + 8 modules quiet zone for short keys
    final qrModules = cleanQrData.length > 25 ? 35 : 29;
    final qrActualSizeDots = (qrModules * qrCellWidth).toDouble();
    // Layout reservation on canvas to ensure breathing room and avoid collision (plus caption if wide):
    final qrBoxDots = math.max(
        qrActualSizeDots + (isWide ? 16.0 : 4.0),
        (isWide ? (requestedHeightMm <= 40 ? 10.0 : 14.0) : 10.0) * dotsPerMm);

    // Guaranteed margins to prevent right or bottom overflow on physical label:
    final qrRightMarginDots = (safeWidth <= 54 ? 7.0 : 2.5) * dotsPerMm;
    final qrBottomMarginDots =
        (requestedHeightMm <= 30 ? 3.0 : 2.0) * dotsPerMm;

    final footerTotalFontSize = (hasQr && !isWide)
        ? (titleFontSize * 0.85).clamp(16.0, 20.0)
        : titleFontSize;

    // Accurate closing footer height measurement using exact TextPainter layouts
    double measureClosingFooterHeight() {
      var h = 4.0; // Divider before footer
      final footerTextW = hasQr
          ? (usableW - qrBoxDots - 8.0).clamp(60.0, usableW)
          : usableW;
      if (note != null && note.trim().isNotEmpty) {
        final notePainter = TextPainter(
          text: TextSpan(
            text: 'Not: ${note.trim()}',
            style: TextStyle(
              fontSize: detailFontSize,
              fontStyle: FontStyle.italic,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 2,
        )..layout(maxWidth: footerTextW);
        h += notePainter.height + 1.5;
      }
      var textH = 0.0;
      if (showItemsCount && itemsCount != null) {
        final itemsPainter = TextPainter(
          text: TextSpan(
            text:
                'Çeşit: $itemsCount | Toplam: ${itemsList.fold<double>(0, (s, i) => s + ((i['quantity'] as num?)?.toDouble() ?? 1.0)).toStringAsFixed(0)} Ad.',
            style: TextStyle(
              color: Colors.black,
              fontSize: detailFontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: footerTextW);
        textH += itemsPainter.height + 1.5;
      }

      final payPainter = TextPainter(
        text: TextSpan(
          text: 'Ödeme: $paymentStatus',
          style: TextStyle(
            color: Colors.black,
            fontSize: bodyFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: footerTextW);
      textH += payPainter.height + 1.5;

      if (showTotalAmount && totalAmount != null) {
        final totPainter = TextPainter(
          text: TextSpan(
            text: 'TOPLAM: ${totalAmount.toStringAsFixed(2)} TL',
            style: TextStyle(
              color: Colors.black,
              fontSize: footerTotalFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: footerTextW);
        textH += totPainter.height + 1.5;
      }

      if (hasQr) {
        h += math.max(textH, qrBoxDots);
      } else {
        h += textH;
      }
      return h + 4.0;
    }

    final closingFooterH = measureClosingFooterHeight();
    final contFooterH = () {
      final contBanner = TextPainter(
        text: TextSpan(
          text: '>> DEVAMI 9. ETİKETTE >>',
          style: TextStyle(
            color: Colors.black,
            fontSize: detailFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: usableW);
      return contBanner.height + 16.0;
    }();

    // ── Mathematically exact, lossless multi-page distribution ──
    final pages = <List<_MeasuredItem>>[];
    final allItemsTotalH =
        measuredItems.fold<double>(0, (s, i) => s + i.totalHeight);
    final totalContentHeightDots = page1HeaderH + allItemsTotalH + closingFooterH;

    final int pageHeightDots;
    final int labelHeightMm;
    final bool canFitSinglePage;

    if (isContinuous) {
      final neededDots = totalContentHeightDots + bottomMargin + 4.0;
      final neededMm = (neededDots * 25.4 / safeDpi).clamp(15.0, 300.0);
      labelHeightMm = neededMm.ceil();
      pageHeightDots = (labelHeightMm * safeDpi / 25.4).round();
      canFitSinglePage = true;
    } else {
      labelHeightMm = requestedHeightMm;
      pageHeightDots = heightDots;
      canFitSinglePage = (totalContentHeightDots <= maxSafePageY);
    }

    if (!paginateOnOverflow || canFitSinglePage) {
      pages.add(measuredItems);
    } else {
      var itemIdx = 0;
      // Page 1 budget
      final page1Budget = maxSafePageY - page1HeaderH - contFooterH;
      final page1Items = <_MeasuredItem>[];
      var page1Used = 0.0;
      while (itemIdx < measuredItems.length) {
        final item = measuredItems[itemIdx];
        if (page1Items.isNotEmpty &&
            (page1Used + item.totalHeight > page1Budget)) {
          break;
        }
        page1Items.add(item);
        page1Used += item.totalHeight;
        itemIdx++;
      }

      // If page 1 consumed all items because contFooterH is smaller than closingFooterH,
      // but they cannot fit together with the full closing footer, at least one item must move to page 2.
      if (itemIdx == measuredItems.length) {
        if (page1Items.length > 1) {
          final last = page1Items.removeLast();
          page1Used -= last.totalHeight;
          itemIdx--;
          pages.add(page1Items);
        } else {
          // Even a single item cannot fit together with the full closing footer.
          // Page 1 gets the item + continuation banner, Page 2 gets the closing footer.
          pages.add(page1Items);
          pages.add(<_MeasuredItem>[]);
          itemIdx = measuredItems.length;
        }
      } else {
        pages.add(page1Items);
      }

      // Subsequent pages budget
      final subClosingBudget =
          maxSafePageY - subsequentHeaderH - closingFooterH;
      final subInterBudget = maxSafePageY - subsequentHeaderH - contFooterH;

      while (itemIdx < measuredItems.length) {
        var remainingH = 0.0;
        for (var i = itemIdx; i < measuredItems.length; i++) {
          remainingH += measuredItems[i].totalHeight;
        }
        // If remaining items fit comfortably on the final page together with closing footer:
        if (remainingH <= subClosingBudget) {
          pages.add(measuredItems.sublist(itemIdx));
          break;
        }

        // Otherwise pack as many items as fit before the continuation banner
        final inter = <_MeasuredItem>[];
        var interUsed = 0.0;
        while (itemIdx < measuredItems.length) {
          final it = measuredItems[itemIdx];
          if (inter.isNotEmpty &&
              (interUsed + it.totalHeight > subInterBudget)) {
            break;
          }
          inter.add(it);
          interUsed += it.totalHeight;
          itemIdx++;
        }
        if (itemIdx == measuredItems.length) {
          if (inter.length > 1) {
            final last = inter.removeLast();
            interUsed -= last.totalHeight;
            itemIdx--;
            pages.add(inter);
          } else {
            pages.add(inter);
            pages.add(<_MeasuredItem>[]);
            break;
          }
        } else {
          pages.add(inter);
        }
      }
    }

    // Render each page in FORWARD order (1/N prints first, then 2/N, etc.)
    final outputBytes = <int>[];
    final totalPagesCount = pages.length;

    for (var pageIdx = 0; pageIdx < totalPagesCount; pageIdx++) {
      final pageItems = pages[pageIdx];
      final isFirstPage = pageIdx == 0;
      final isLastPage = pageIdx == totalPagesCount - 1;
      int pageQrX = 0;
      int pageQrY = 0;

      final usableArea = UsablePrintArea(
        usableLeft: paddingLeft,
        usableTop: topMargin,
        usableRight: safeRightX,
        usableBottom: isContinuous
            ? (pageHeightDots - bottomMargin - safetyDots).roundToDouble()
            : maxSafePageY,
        safetyDots: 0.0,
      );
      final pageBoxes = <ElementBoundingBox>[];

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, widthDots.toDouble(), pageHeightDots.toDouble()),
      );

      // Background
      canvas.drawRect(
        Rect.fromLTWH(0, 0, widthDots.toDouble(), pageHeightDots.toDouble()),
        Paint()..color = Colors.white,
      );

      final linePaint = Paint()
        ..color = Colors.black
        ..strokeWidth = isWide ? 2.0 : 1.2;

      var currentY = topMargin;

      if (isFirstPage) {
        // Order No & Date (placed with natural, balanced spacing rather than pushed to extreme edges)
        final pageSuffix = totalPagesCount > 1 ? ' (1/$totalPagesCount)' : '';
        if (showOrderNo || showDate) {
          final leftOrder = showOrderNo ? 'Sip #$orderIdShort$pageSuffix' : '';
          final orderPainter = TextPainter(
            text: TextSpan(
              text: leftOrder,
              style: TextStyle(
                color: Colors.black,
                fontSize: bodyFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: usableW * 0.55);
          orderPainter.paint(canvas, Offset(paddingLeft, currentY));

          pageBoxes.add(ElementBoundingBox(
            elementName: 'OrderNo',
            left: paddingLeft,
            top: currentY,
            width: orderPainter.width,
            height: orderPainter.height,
          ));

          if (dateStr.isNotEmpty) {
            final datePainter = TextPainter(
              text: TextSpan(
                text: dateStr,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: bodyFontSize * 0.88,
                  fontWeight: FontWeight.w500,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: usableW * 0.40);
            final preferredGap = isWide ? 24.0 : 16.0;
            final naturalDateX = paddingLeft + orderPainter.width + preferredGap;
            final maxDateX = safeRightX - datePainter.width;
            final dateX = naturalDateX <= maxDateX
                ? naturalDateX
                : maxDateX.clamp(paddingLeft, maxDateX);
            datePainter.paint(canvas, Offset(dateX, currentY));

            pageBoxes.add(ElementBoundingBox(
              elementName: 'Date',
              left: dateX,
              top: currentY,
              width: datePainter.width,
              height: datePainter.height,
            ));
          }
          currentY += math.max(orderPainter.height, bodyFontSize) + 2.0;
        }

        // Customer & Phone
        if (showCustomerName) {
          final custStr = customerName.trim().isNotEmpty
              ? 'Müş: ${customerName.trim()}'
              : 'Müş: Genel';
          final custPainter = TextPainter(
            text: TextSpan(
              text: custStr,
              style: TextStyle(
                color: Colors.black,
                fontSize: bodyFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: usableW);
          custPainter.paint(canvas, Offset(paddingLeft, currentY));

          pageBoxes.add(ElementBoundingBox(
            elementName: 'CustomerName',
            left: paddingLeft,
            top: currentY,
            width: custPainter.width,
            height: custPainter.height,
          ));
          currentY += custPainter.height + 1.0;

          if (customerPhone != null && customerPhone.trim().isNotEmpty) {
            final phonePainter = TextPainter(
              text: TextSpan(
                text: 'Tel: ${customerPhone.trim()}',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: detailFontSize,
                  fontWeight: FontWeight.normal,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: usableW);
            phonePainter.paint(canvas, Offset(paddingLeft, currentY));

            pageBoxes.add(ElementBoundingBox(
              elementName: 'CustomerPhone',
              left: paddingLeft,
              top: currentY,
              width: phonePainter.width,
              height: phonePainter.height,
            ));
            currentY += phonePainter.height + 1.0;
          }
        }

        if (previousDebt > 0.001) {
          final debtPainter = TextPainter(
            text: TextSpan(
              text: 'Geçmiş Borç: ${previousDebt.toStringAsFixed(2)} TL',
              style: TextStyle(
                color: Colors.black,
                fontSize: detailFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: usableW);
          debtPainter.paint(canvas, Offset(paddingLeft, currentY));

          pageBoxes.add(ElementBoundingBox(
            elementName: 'PreviousDebt',
            left: paddingLeft,
            top: currentY,
            width: debtPainter.width,
            height: debtPainter.height,
          ));
          currentY += debtPainter.height + 1.0;
        }

        // Divider
        currentY += 2.0;
        canvas.drawLine(Offset(paddingLeft, currentY),
            Offset(safeRightX, currentY), linePaint);
        pageBoxes.add(ElementBoundingBox(
          elementName: 'HeaderDivider',
          left: paddingLeft,
          top: currentY,
          width: safeRightX - paddingLeft,
          height: isWide ? 2.0 : 1.2,
        ));
        currentY += 2.5;
      } else {
        // Subsequent Pages Header
        final contTitle =
            'Sip #$orderIdShort (${pageIdx + 1}/$totalPagesCount) - Devam';
        final contPainter = TextPainter(
          text: TextSpan(
            text: contTitle,
            style: TextStyle(
              color: Colors.black,
              fontSize: bodyFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: dateStr.isNotEmpty ? usableW * 0.55 : usableW);
        contPainter.paint(canvas, Offset(paddingLeft, currentY));

        pageBoxes.add(ElementBoundingBox(
          elementName: 'ContinuationHeader',
          left: paddingLeft,
          top: currentY,
          width: contPainter.width,
          height: contPainter.height,
        ));

        if (dateStr.isNotEmpty) {
          final datePainter = TextPainter(
            text: TextSpan(
              text: dateStr,
              style: TextStyle(
                color: Colors.black,
                fontSize: bodyFontSize * 0.88,
                fontWeight: FontWeight.w500,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: usableW * 0.40);
          final preferredGap = isWide ? 20.0 : 14.0;
          final naturalDateX = paddingLeft + contPainter.width + preferredGap;
          final maxDateX = safeRightX - datePainter.width;
          final dateX = naturalDateX <= maxDateX
              ? naturalDateX
              : maxDateX.clamp(paddingLeft, maxDateX);
          datePainter.paint(canvas, Offset(dateX, currentY));

          pageBoxes.add(ElementBoundingBox(
            elementName: 'Date',
            left: dateX,
            top: currentY,
            width: datePainter.width,
            height: datePainter.height,
          ));
        }
        currentY += math.max(contPainter.height, bodyFontSize) + 2.0;
        canvas.drawLine(Offset(paddingLeft, currentY),
            Offset(safeRightX, currentY), linePaint);
        pageBoxes.add(ElementBoundingBox(
          elementName: 'HeaderDivider',
          left: paddingLeft,
          top: currentY,
          width: safeRightX - paddingLeft,
          height: isWide ? 2.0 : 1.2,
        ));
        currentY += 2.5;
      }

      // Draw Items with tight vertical leading
      var itemIdx = 0;
      for (final it in pageItems) {
        itemIdx++;
        it.namePainter.paint(canvas, Offset(paddingLeft, currentY));
        pageBoxes.add(ElementBoundingBox(
          elementName: 'ItemName_${pageIdx + 1}_$itemIdx',
          left: paddingLeft,
          top: currentY,
          width: it.namePainter.width,
          height: it.namePainter.height,
        ));
        currentY += it.namePainter.height + 0.5;

        it.detailPainter.paint(canvas, Offset(paddingLeft, currentY));
        pageBoxes.add(ElementBoundingBox(
          elementName: 'ItemDetail_${pageIdx + 1}_$itemIdx',
          left: paddingLeft,
          top: currentY,
          width: it.detailPainter.width,
          height: it.detailPainter.height,
        ));
        currentY += it.detailPainter.height + 2.0;
      }

      // Divider after items
      currentY += 1.5;
      canvas.drawLine(Offset(paddingLeft, currentY),
          Offset(safeRightX, currentY), linePaint);
      pageBoxes.add(ElementBoundingBox(
        elementName: 'ItemsDivider',
        left: paddingLeft,
        top: currentY,
        width: safeRightX - paddingLeft,
        height: isWide ? 2.0 : 1.2,
      ));
      currentY += 2.5;

      if (isLastPage) {
        if (hasQr) {
          // Position QR safely inside the right border with generous clearance
          final maxSafeQrX =
              (widthDots - qrActualSizeDots - qrRightMarginDots).round();
          pageQrX = maxSafeQrX.clamp(paddingLeft.round(), (safeRightX - qrActualSizeDots).round());

          // Position QR safely above the bottom border
          final maxSafeQrY =
              (pageHeightDots - qrActualSizeDots - qrBottomMarginDots).round();
          pageQrY = currentY.round().clamp(topMargin.round(), maxSafeQrY);

          pageBoxes.add(ElementBoundingBox(
            elementName: 'QRCode',
            left: pageQrX.toDouble(),
            top: pageQrY.toDouble(),
            width: qrActualSizeDots,
            height: qrActualSizeDots,
          ));

          // Paint a small "SİPARİŞİ AÇ" caption under the QR area on canvas for wide labels
          if (isWide) {
            final qrLabelPainter = TextPainter(
              text: TextSpan(
                text: 'SİPARİŞİ AÇ',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: (detailFontSize * 0.72).clamp(8.0, 11.0),
                  fontWeight: FontWeight.bold,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: qrBoxDots + 20.0);
            final labelX = (pageQrX + (qrActualSizeDots - qrLabelPainter.width) / 2)
                .clamp(paddingLeft, safeRightX - qrLabelPainter.width);
            final labelY =
                (pageQrY + qrActualSizeDots + 1.0).clamp(0.0, pageHeightDots - 11.0);
            if (labelY + qrLabelPainter.height <= pageHeightDots - 2.0) {
              qrLabelPainter.paint(canvas, Offset(labelX, labelY));
              pageBoxes.add(ElementBoundingBox(
                elementName: 'QRCaption',
                left: labelX,
                top: labelY,
                width: qrLabelPainter.width,
                height: qrLabelPainter.height,
              ));
            }
          }
        }

        final textMaxW = hasQr
            ? (pageQrX - paddingLeft - 8.0).clamp(60.0, usableW)
            : usableW;

        // Order Note
        if (note != null && note.trim().isNotEmpty) {
          final notePainter = TextPainter(
            text: TextSpan(
              text: 'Not: ${note.trim()}',
              style: TextStyle(
                color: Colors.black,
                fontSize: detailFontSize,
                fontStyle: FontStyle.italic,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 2,
          )..layout(maxWidth: textMaxW);
          notePainter.paint(canvas, Offset(paddingLeft, currentY));

          pageBoxes.add(ElementBoundingBox(
            elementName: 'FooterNote',
            left: paddingLeft,
            top: currentY,
            width: notePainter.width,
            height: notePainter.height,
          ));
          currentY += notePainter.height + 1.5;
        }

        // Summary item count (if enabled)
        if (showItemsCount && itemsCount != null) {
          final itemsPainter = TextPainter(
            text: TextSpan(
              text:
                  'Çeşit: $itemsCount | Toplam: ${itemsList.fold<double>(0, (s, i) => s + ((i['quantity'] as num?)?.toDouble() ?? 1.0)).toStringAsFixed(0)} Ad.',
              style: TextStyle(
                color: Colors.black,
                fontSize: detailFontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: textMaxW);
          itemsPainter.paint(canvas, Offset(paddingLeft, currentY));

          pageBoxes.add(ElementBoundingBox(
            elementName: 'FooterItemsCount',
            left: paddingLeft,
            top: currentY,
            width: itemsPainter.width,
            height: itemsPainter.height,
          ));
          currentY += itemsPainter.height + 1.5;
        }

        // Payment status & Total Amount
        final payPainter = TextPainter(
          text: TextSpan(
            text: 'Ödeme: $paymentStatus',
            style: TextStyle(
              color: Colors.black,
              fontSize: bodyFontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: textMaxW);
        payPainter.paint(canvas, Offset(paddingLeft, currentY));

        pageBoxes.add(ElementBoundingBox(
          elementName: 'FooterPayment',
          left: paddingLeft,
          top: currentY,
          width: payPainter.width,
          height: payPainter.height,
        ));
        currentY += payPainter.height + 1.5;

        if (showTotalAmount && totalAmount != null) {
          final totPainter = TextPainter(
            text: TextSpan(
              text: 'TOPLAM: ${totalAmount.toStringAsFixed(2)} TL',
              style: TextStyle(
                color: Colors.black,
                fontSize: footerTotalFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: textMaxW);
          totPainter.paint(canvas, Offset(paddingLeft, currentY));

          pageBoxes.add(ElementBoundingBox(
            elementName: 'FooterTotal',
            left: paddingLeft,
            top: currentY,
            width: totPainter.width,
            height: totPainter.height,
          ));
          currentY += totPainter.height + 1.5;
        }
      } else {
        // Continuation banner
        final contBanner = TextPainter(
          text: TextSpan(
            text: '>> DEVAMI ${(pageIdx + 2)}. ETİKETTE >>',
            style: TextStyle(
              color: Colors.black,
              fontSize: detailFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: usableW);
        final bannerX = ((widthDots - contBanner.width) / 2)
            .clamp(paddingLeft, safeRightX - contBanner.width);
        contBanner.paint(canvas, Offset(bannerX, currentY + 2));

        pageBoxes.add(ElementBoundingBox(
          elementName: 'ContinuationBanner',
          left: bannerX,
          top: currentY + 2,
          width: contBanner.width,
          height: contBanner.height,
        ));
      }

      // Validate bounding boxes against UsablePrintArea
      DynamicLabelSizeEngine.validatePageLayout(
        pageIndex: pageIdx,
        boxes: pageBoxes,
        usableArea: usableArea,
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(widthDots, pageHeightDots);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (byteData != null) {
        final widthBytes = (widthDots + 7) ~/ 8;
        final rasterBytes = Uint8List(widthBytes * pageHeightDots);
        var rasterIdx = 0;
        final pixels = byteData.buffer.asUint32List();

        for (var y = 0; y < pageHeightDots; y++) {
          for (var byteCol = 0; byteCol < widthBytes; byteCol++) {
            var b =
                0xFF; // In TSPL BITMAP (mode 0): 1 = white paper (unburned), 0 = black dot (burned)
            for (var bit = 0; bit < 8; bit++) {
              final px = byteCol * 8 + bit;
              if (px < widthDots) {
                final pixel = pixels[y * widthDots + px];
                final r = pixel & 0xFF;
                final g = (pixel >> 8) & 0xFF;
                final bChannel = (pixel >> 16) & 0xFF;
                final lum = (r * 77 + g * 150 + bChannel * 29) >> 8;
                if (lum < 160) {
                  // Dark pixel (text, graphics): clear bit to 0
                  b &= ~(0x80 >> bit);
                }
              }
            }
            rasterBytes[rasterIdx++] = b;
          }
        }

        final currentGapMm = isContinuous ? 0 : gapMm;
        final tsplHeader = 'SIZE $safeWidth mm,$labelHeightMm mm\r\n'
            'GAP $currentGapMm mm,0 mm\r\n'
            // A gap scan is a calibration operation. On an overflowing order
            // it may run at most once, before the first physical label; doing
            // it again for every continuation label makes the printer feed
            // unpredictably and breaks page alignment.
            '${autoDetectGap && pageIdx == 0 ? "GAPDETECT\r\n" : ""}'
            'DENSITY 8\r\n'
            'DIRECTION ${direction == 1 ? 1 : 0}\r\n'
            'REFERENCE 0,0\r\n'
            'CLS\r\n'
            'BITMAP 0,0,$widthBytes,$pageHeightDots,0,';

        outputBytes
          ..addAll(latin1.encode(tsplHeader))
          ..addAll(rasterBytes)
          ..addAll(
              const [13, 10]); // CRLF termination after binary raster block

        if (isLastPage && hasQr) {
          final cleanQr = cleanQrData
              .replaceAll('"', "'")
              .replaceAll('\r', '')
              .replaceAll('\n', '');
          final qrCmd =
              'QRCODE $pageQrX,$pageQrY,M,$qrCellWidth,A,0,"$cleanQr"\r\n';
          outputBytes.addAll(latin1.encode(qrCmd));
        }

        outputBytes.addAll(latin1.encode('PRINT ${copies.clamp(1, 20)},1\r\n'));
      }
    }

    return outputBytes;
  }
}

class _MeasuredItem {
  final Map<String, dynamic> item;
  final TextPainter namePainter;
  final TextPainter detailPainter;
  final double totalHeight;

  _MeasuredItem(
      this.item, this.namePainter, this.detailPainter, this.totalHeight);
}
