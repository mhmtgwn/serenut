import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:serenutos/domain/models/label_model.dart';
import 'package:serenutos/domain/printing/label_dimension_models.dart';

/// Next-Generation TSPL Label Renderer powered by Flutter's Canvas & TextPainter.
///
/// Eliminates character width and pixel height guessing entirely by measuring
/// and rendering with Flutter's actual typography engine directly to 1-bit
/// monochrome raster bitmaps.
class TsplCanvasLabelEngine {
  static String? _resolvedFontFamily;
  static bool _fontInitialized = false;

  static String? get resolvedFontFamily => _resolvedFontFamily;

  /// Ensures a robust, high-legibility system font (Arial on Windows, Roboto on Android)
  /// is registered via FontLoader for TextPainter rendering, preventing tofu / black squares.
  static Future<String?> ensureFontLoaded() async {
    if (_fontInitialized) return _resolvedFontFamily;
    _fontInitialized = true;
    try {
      if (Platform.isWindows) {
        final fontFile = File('C:/Windows/Fonts/arial.ttf');
        if (fontFile.existsSync()) {
          final fontData = await fontFile.readAsBytes();
          final fontLoader = FontLoader('SerenutLabelFont');
          fontLoader.addFont(Future.value(ByteData.view(fontData.buffer)));
          await fontLoader.load();
          _resolvedFontFamily = 'SerenutLabelFont';
          return _resolvedFontFamily;
        }
      } else if (Platform.isAndroid) {
        final fontFile = File('/system/fonts/Roboto-Regular.ttf');
        if (fontFile.existsSync()) {
          final fontData = await fontFile.readAsBytes();
          final fontLoader = FontLoader('SerenutLabelFont');
          fontLoader.addFont(Future.value(ByteData.view(fontData.buffer)));
          await fontLoader.load();
          _resolvedFontFamily = 'SerenutLabelFont';
          return _resolvedFontFamily;
        }
      }
    } catch (e) {
      debugPrint('[TsplCanvasLabelEngine] Font loader warning: $e');
    }
    return null;
  }

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
    double? discountAmount,
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
    String? fontFamily,
  }) async {
    final effectiveFontFamily = fontFamily ?? await ensureFontLoaded();

    TextStyle ts({
      required double fontSize,
      FontWeight fontWeight = FontWeight.normal,
      FontStyle fontStyle = FontStyle.normal,
      Color color = Colors.black,
    }) {
      return TextStyle(
        fontFamily: effectiveFontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        color: color,
      );
    }

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

    // Safe margins: 4.5mm left on narrow labels (<=54mm), 5.0mm on wide labels (>=70mm)
    // Safe margins: 4.0mm left on narrow labels (<=54mm), 5.0mm on wide labels (>=70mm)
    // to ensure lines, text, and QR code never get cut off by physical printer margins.
    final marginMm = safeWidth <= 54 ? 4.0 : 5.0;
    final paddingLeft = (marginMm * safeDpi / 25.4).roundToDouble();
    final paddingRight =
        ((safeWidth <= 54 ? 5.5 : 3.5) * safeDpi / 25.4).roundToDouble();
    const safetyDots = 2.0;
    final safeRightX = (widthDots - paddingRight - safetyDots).roundToDouble();
    final usableW = (safeRightX - paddingLeft).clamp(60.0, 1000.0);
    final topMargin = ((requestedHeightMm <= 30 ? 1.0 : 2.5) * safeDpi / 25.4).roundToDouble();
    // 2.5mm bottom clearance on 30mm labels to completely avoid bleeding into gap
    final bottomMargin = (requestedHeightMm <= 30 ? 2.5 : 2.0) * safeDpi / 25.4;
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
        (isWide ? (isTall ? 32.0 : 26.0) : 23.0) * fontScale;
    final bodyFontSize =
        (isWide ? (isTall ? 26.0 : 21.0) : 18.0) * fontScale;
    final detailFontSize =
        (isWide ? (isTall ? 22.0 : 18.0) : 15.0) * fontScale;

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

      final String detailText;
      if (unitPrice != null && lineTotal != null) {
        if (qty == 1.0) {
          detailText = '1 Adet  ${lineTotal.toStringAsFixed(2)} TL';
        } else {
          detailText =
              '$qtyStr x ${unitPrice.toStringAsFixed(2)} = ${lineTotal.toStringAsFixed(2)} TL';
        }
      } else if (lineTotal != null) {
        detailText = '$qtyStr x ${lineTotal.toStringAsFixed(2)} TL';
      } else if (rightTotal.isNotEmpty) {
        detailText = '$qtyStr x $rightTotal';
      } else {
        detailText = '$qtyStr x';
      }

      final detailPainter = TextPainter(
        text: TextSpan(
          text: detailText,
          style: ts(
            fontSize: detailFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: isWide ? 1 : 2,
      )..layout(maxWidth: isWide ? (usableW * 0.65) : usableW);

      final double nameMaxW;
      if (isWide) {
        nameMaxW = (usableW - detailPainter.width - 12.0).clamp(60.0, usableW);
      } else {
        nameMaxW = usableW;
      }

      final namePainter = TextPainter(
        text: TextSpan(
          text: name,
          style: ts(
            fontSize: bodyFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: nameMaxW);

      final canBeSideBySide = isWide;
      final double totalH;
      if (canBeSideBySide) {
        totalH = math.max(namePainter.height, detailPainter.height) +
            (isTall ? 5.0 : (isWide ? 2.5 : 3.5));
      } else {
        totalH = namePainter.height + detailPainter.height + 2.5;
      }
      return _MeasuredItem(
        item,
        namePainter,
        detailPainter,
        totalH,
        isSingleLine: canBeSideBySide,
      );
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
            style: ts(
              fontSize: bodyFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: orderMaxW);
        h += math.max(orderPainter.height, bodyFontSize) + 2.0;
      }
      if (showCustomerName) {
        final cleanCust = customerName.trim();
        final isRawId = cleanCust.startsWith('cust-') ||
            RegExp(r'^[0-9a-fA-F-]{20,}$').hasMatch(cleanCust);
        final displayCust = (cleanCust.isNotEmpty && !isRawId)
            ? cleanCust
            : 'Genel Müşteri';
        final custStr = 'Müş: $displayCust';
        if (isWide && customerPhone != null && customerPhone.trim().isNotEmpty) {
          final custPainter = TextPainter(
            text: TextSpan(
              text: custStr,
              style: ts(
                fontSize: bodyFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: usableW * 0.58);

          final phonePainter = TextPainter(
            text: TextSpan(
              text: 'Tel: ${customerPhone.trim()}',
              style: ts(
                fontSize: detailFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: usableW * 0.40);

          h += math.max(custPainter.height, phonePainter.height) + 2.0;
        } else {
          final custPainter = TextPainter(
            text: TextSpan(
              text: custStr,
              style: ts(
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
                style: ts(
                  fontSize: detailFontSize,
                  fontWeight: FontWeight.normal,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: usableW);
            h += phonePainter.height + 1.0;
          }
        }
      }
      if (previousDebt > 0.001) {
        final debtPainter = TextPainter(
          text: TextSpan(
            text: 'Geçmiş Borç: ${previousDebt.toStringAsFixed(2)} TL',
            style: ts(
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
      final contTitle = dateStr.isNotEmpty
          ? 'Sip #$orderIdShort (9/9)'
          : 'Sip #$orderIdShort (9/9) - Devam';
      final contPainter = TextPainter(
        text: TextSpan(
          text: contTitle,
          style: ts(
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
        qrActualSizeDots + (isWide ? (requestedHeightMm <= 40 ? 6.0 : 16.0) : 4.0),
        (isWide ? (requestedHeightMm <= 40 ? 8.0 : 14.0) : 10.0) * dotsPerMm);

    // Guaranteed margins to prevent right or bottom overflow on physical label:
    final qrRightMarginDots = (safeWidth <= 54 ? 7.0 : 2.5) * dotsPerMm;
    final qrBottomMarginDots =
        (requestedHeightMm <= 30 ? 3.0 : (requestedHeightMm <= 40 ? 1.5 : 2.0)) * dotsPerMm;

    final footerTotalFontSize = (hasQr && !isWide)
        ? (titleFontSize * 0.70).clamp(14.0, 16.5)
        : titleFontSize;

    // Accurate closing footer height measurement using exact TextPainter layouts
    double measureClosingFooterHeight() {
      var leftTextH = 0.0;
      final footerTextW = hasQr
          ? (safeRightX - paddingLeft - qrBoxDots - 8.0).clamp(60.0, usableW)
          : usableW;
      if (note != null && note.trim().isNotEmpty) {
        final notePainter = TextPainter(
          text: TextSpan(
            text: 'Not: ${note.trim()}',
            style: ts(
              fontSize: detailFontSize,
              fontStyle: FontStyle.italic,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 2,
        )..layout(maxWidth: footerTextW);
        leftTextH += notePainter.height + 1.5;
      }
      if (isWide && showItemsCount && itemsCount != null) {
        final totalQty = itemsList.fold<double>(
            0, (s, i) => s + ((i['quantity'] as num?)?.toDouble() ?? 1.0));
        final payPainter = TextPainter(
          text: TextSpan(
            text:
                'Ödeme: $paymentStatus  •  $itemsCount Çeşit (${totalQty.toStringAsFixed(0)} Ad.)',
            style: ts(
              fontSize: bodyFontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: footerTextW);
        leftTextH += payPainter.height + 1.5;
      } else {
        if (showItemsCount && itemsCount != null) {
          final itemsPainter = TextPainter(
            text: TextSpan(
              text:
                  'Çeşit: $itemsCount | Toplam: ${itemsList.fold<double>(0, (s, i) => s + ((i['quantity'] as num?)?.toDouble() ?? 1.0)).toStringAsFixed(0)} Ad.',
              style: ts(
                fontSize: detailFontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: footerTextW);
          leftTextH += itemsPainter.height + 1.5;
        }

        final payPainter = TextPainter(
          text: TextSpan(
            text: 'Ödeme: $paymentStatus',
            style: ts(
              fontSize: bodyFontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: footerTextW);
        leftTextH += payPainter.height + 1.5;
      }

      if (showTotalAmount && totalAmount != null) {
        final hasDiscount = discountAmount != null && discountAmount > 0.009;
        final totalText = hasDiscount
            ? 'TOPLAM: ${totalAmount.toStringAsFixed(2)} TL (İnd: -${discountAmount.toStringAsFixed(2)} TL)'
            : 'TOPLAM: ${totalAmount.toStringAsFixed(2)} TL';
        final totPainter = TextPainter(
          text: TextSpan(
            text: totalText,
            style: ts(
              fontSize: footerTotalFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: footerTextW);
        leftTextH += totPainter.height + 1.5;
      }

      final bodyH = hasQr ? math.max(leftTextH, qrBoxDots) : leftTextH;
      return bodyH + (isTall ? 3.0 : 1.0);
    }

    final closingFooterH = measureClosingFooterHeight();
    const contFooterH = 0.0;

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
              style: ts(
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
                style: ts(
                  fontSize: bodyFontSize * 0.88,
                  fontWeight: FontWeight.w500,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: usableW * 0.40);
            final preferredGap = isWide ? 24.0 : 16.0;
            final naturalDateX = paddingLeft + orderPainter.width + preferredGap;
            final maxDateX = safeRightX - datePainter.width;
            final dateX = isWide
                ? maxDateX
                : (naturalDateX <= maxDateX
                    ? naturalDateX
                    : maxDateX.clamp(paddingLeft, maxDateX));
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
          final cleanCust = customerName.trim();
          final isRawId = cleanCust.startsWith('cust-') ||
              RegExp(r'^[0-9a-fA-F-]{20,}$').hasMatch(cleanCust);
          final displayCust = (cleanCust.isNotEmpty && !isRawId)
              ? cleanCust
              : 'Genel Müşteri';
          final custStr = 'Müş: $displayCust';
          if (isWide && customerPhone != null && customerPhone.trim().isNotEmpty) {
            final custPainter = TextPainter(
              text: TextSpan(
                text: custStr,
                style: ts(
                  fontSize: bodyFontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: usableW * 0.58);
            custPainter.paint(canvas, Offset(paddingLeft, currentY));

            pageBoxes.add(ElementBoundingBox(
              elementName: 'CustomerName',
              left: paddingLeft,
              top: currentY,
              width: custPainter.width,
              height: custPainter.height,
            ));

            final phonePainter = TextPainter(
              text: TextSpan(
                text: 'Tel: ${customerPhone.trim()}',
                style: ts(
                  fontSize: detailFontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: usableW * 0.40);
            final phoneX = safeRightX - phonePainter.width;
            phonePainter.paint(canvas, Offset(phoneX, currentY));

            pageBoxes.add(ElementBoundingBox(
              elementName: 'CustomerPhone',
              left: phoneX,
              top: currentY,
              width: phonePainter.width,
              height: phonePainter.height,
            ));
            currentY += math.max(custPainter.height, phonePainter.height) + 2.0;
          } else {
            final custPainter = TextPainter(
              text: TextSpan(
                text: custStr,
                style: ts(
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
                  style: ts(
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
        }

        if (previousDebt > 0.001) {
          final debtPainter = TextPainter(
            text: TextSpan(
              text: 'Geçmiş Borç: ${previousDebt.toStringAsFixed(2)} TL',
              style: ts(
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
        final contTitle = dateStr.isNotEmpty
            ? 'Sip #$orderIdShort (${pageIdx + 1}/$totalPagesCount)'
            : 'Sip #$orderIdShort (${pageIdx + 1}/$totalPagesCount) - Devam';
        final contPainter = TextPainter(
          text: TextSpan(
            text: contTitle,
            style: ts(
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
              style: ts(
                fontSize: bodyFontSize * 0.88,
                fontWeight: FontWeight.w500,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: usableW * 0.40);
          final preferredGap = isWide ? 20.0 : 14.0;
          final naturalDateX = paddingLeft + contPainter.width + preferredGap;
          final maxDateX = safeRightX - datePainter.width;
          final dateX = isWide
              ? maxDateX
              : (naturalDateX <= maxDateX
                  ? naturalDateX
                  : maxDateX.clamp(paddingLeft, maxDateX));
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
        if (it.isSingleLine) {
          final itemH = math.max(it.namePainter.height, it.detailPainter.height);
          it.namePainter.paint(canvas, Offset(paddingLeft, currentY));
          pageBoxes.add(ElementBoundingBox(
            elementName: 'ItemName_${pageIdx + 1}_$itemIdx',
            left: paddingLeft,
            top: currentY,
            width: it.namePainter.width,
            height: it.namePainter.height,
          ));

          final detailX =
              (safeRightX - it.detailPainter.width).clamp(paddingLeft, safeRightX);
          it.detailPainter.paint(canvas, Offset(detailX, currentY));
          pageBoxes.add(ElementBoundingBox(
            elementName: 'ItemDetail_${pageIdx + 1}_$itemIdx',
            left: detailX,
            top: currentY,
            width: it.detailPainter.width,
            height: it.detailPainter.height,
          ));
          currentY += itemH + (isTall ? 5.0 : (isWide ? 2.5 : 3.5));
        } else {
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
                style: ts(
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
              style: ts(
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

        if (isWide && showItemsCount && itemsCount != null) {
          final totalQty = itemsList.fold<double>(
              0, (s, i) => s + ((i['quantity'] as num?)?.toDouble() ?? 1.0));
          final payPainter = TextPainter(
            text: TextSpan(
              text:
                  'Ödeme: $paymentStatus  •  $itemsCount Çeşit (${totalQty.toStringAsFixed(0)} Ad.)',
              style: ts(
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
        } else {
          // Summary item count (if enabled)
          if (showItemsCount && itemsCount != null) {
            final itemsPainter = TextPainter(
              text: TextSpan(
                text:
                    'Çeşit: $itemsCount | Toplam: ${itemsList.fold<double>(0, (s, i) => s + ((i['quantity'] as num?)?.toDouble() ?? 1.0)).toStringAsFixed(0)} Ad.',
                style: ts(
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

          // Payment status
          final payPainter = TextPainter(
            text: TextSpan(
              text: 'Ödeme: $paymentStatus',
              style: ts(
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
        }

        if (showTotalAmount && totalAmount != null) {
          final hasDiscount = discountAmount != null && discountAmount > 0.009;
          final totalText = hasDiscount
              ? 'TOPLAM: ${totalAmount.toStringAsFixed(2)} TL (İnd: -${discountAmount.toStringAsFixed(2)} TL)'
              : 'TOPLAM: ${totalAmount.toStringAsFixed(2)} TL';
          final totPainter = TextPainter(
            text: TextSpan(
              text: totalText,
              style: ts(
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

  /// Generates single-page TSPL shelf label bytes using Flutter Canvas.
  ///
  /// Matches the exact reference design:
  /// - Top Header: Centered Logo / Serenut OS Lockup
  /// - Middle: Huge high-contrast bold product name
  /// - Divider: Full-width clean horizontal line
  /// - Bottom-Left: 'Kod: ...' text + Code 128 barcode bars
  /// - Bottom-Right: Turkish Lira currency symbol + large bold integer price + superscript cents
  static Future<List<int>> generateShelfLabelBytes({
    required LabelModel model,
    int widthMm = 80,
    int heightMm = 40,
    int gapMm = 2,
    bool autoDetectGap = false,
    int dpi = 203,
    int direction = 0,
    int copies = 1,
    int? printableWidthDots,
    bool showBusinessName = true,
    bool showBrand = false,
    bool showBarcode = true,
    bool showPrice = true,
    String fontSize = 'Orta',
    String? logoPath,
    Uint8List? logoBytes,
    String? fontFamily,
  }) async {
    final effectiveFontFamily = fontFamily ?? await ensureFontLoaded();

    TextStyle ts({
      required double fontSize,
      FontWeight fontWeight = FontWeight.normal,
      FontStyle fontStyle = FontStyle.normal,
      Color color = Colors.black,
    }) {
      return TextStyle(
        fontFamily: effectiveFontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        color: color,
      );
    }

    final safeDpi = dpi < 100 ? 203 : dpi;
    final safeWidth = widthMm.clamp(20, 150);
    final safeHeight = heightMm.clamp(15, 120);

    final mediaWidthDots = (safeWidth * safeDpi / 25.4).round();
    final maxNarrowDots = (48.0 * safeDpi / 25.4).round();
    final maxPhysicalDots = safeWidth <= 54
        ? math.min(mediaWidthDots, maxNarrowDots)
        : mediaWidthDots;
    final effectivePrintableDots = printableWidthDots != null &&
            printableWidthDots > 100
        ? math.min(maxPhysicalDots, printableWidthDots)
        : maxPhysicalDots;
    final widthBytes = (effectivePrintableDots + 7) ~/ 8;
    final labelWidthDots = widthBytes * 8;
    final labelHeightDots = (safeHeight * safeDpi / 25.4).round();

    // Margins (in dots)
    final marginMm = safeWidth <= 54 ? 3.0 : 4.0;
    final leftMargin = (marginMm * safeDpi / 25.4).round();
    final rightMargin = labelWidthDots - leftMargin;
    final usableWidth = rightMargin - leftMargin;
    final topMargin = (1.5 * safeDpi / 25.4).round();
    final bottomMargin = labelHeightDots - (2.5 * safeDpi / 25.4).round();

    // Load logo image if available
    ui.Image? logoImage;
    if (showBusinessName) {
      Uint8List? effectiveLogoBytes = logoBytes;
      if (effectiveLogoBytes == null && logoPath != null) {
        try {
          final file = File(logoPath);
          if (file.existsSync()) {
            effectiveLogoBytes = file.readAsBytesSync();
          }
        } catch (_) {}
      }
      if (effectiveLogoBytes == null) {
        // Check default Serenut OS branding lockup
        try {
          final defaultLockup =
              File('assets/branding/lockups/serenut-os-color-128h.png');
          if (defaultLockup.existsSync()) {
            effectiveLogoBytes = defaultLockup.readAsBytesSync();
          }
        } catch (_) {}
      }
      if (effectiveLogoBytes != null && effectiveLogoBytes.isNotEmpty) {
        try {
          final codec = await ui.instantiateImageCodec(effectiveLogoBytes);
          final frame = await codec.getNextFrame();
          logoImage = frame.image;
        } catch (_) {}
      }
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(
        0,
        0,
        labelWidthDots.toDouble(),
        labelHeightDots.toDouble(),
      ),
    );

    // Fill label background with pure white
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        0,
        labelWidthDots.toDouble(),
        labelHeightDots.toDouble(),
      ),
      Paint()..color = Colors.white,
    );

    // ── 1. Top Header: Centered Logo / Business Name ───────────────────────
    final headerHeight = (labelHeightDots * 0.23).clamp(42.0, 76.0);
    var currentY = topMargin.toDouble();

    if (showBusinessName) {
      if (logoImage != null) {
        // If this is the standard Serenut OS lockup (400x128 with transparent padding),
        // crop the transparent margin (19, 19, 368, 90) so the logo content fills the header.
        final isStandardLockup =
            logoImage.width == 400 && logoImage.height == 128;
        final srcRect = isStandardLockup
            ? const Rect.fromLTWH(19, 19, 368, 90)
            : Rect.fromLTWH(
                0, 0, logoImage.width.toDouble(), logoImage.height.toDouble());
        final aspect = srcRect.width / srcRect.height;
        final targetH = headerHeight;
        final targetW = math.min(targetH * aspect, usableWidth * 0.72);
        final actualH = targetW / aspect;
        final logoX = (labelWidthDots - targetW) / 2;
        final logoY = currentY + (headerHeight - actualH) / 2;
        canvas.drawImageRect(
          logoImage,
          srcRect,
          Rect.fromLTWH(logoX, logoY, targetW, actualH),
          Paint(),
        );
      } else {
        final businessText = model.businessName?.trim().isNotEmpty == true
            ? model.businessName!.trim()
            : 'Serenut OS';
        final headerPainter = TextPainter(
          text: TextSpan(
            text: businessText,
            style: ts(
              fontSize: headerHeight * 0.75,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final textX = (labelWidthDots - headerPainter.width) / 2;
        headerPainter.paint(canvas, Offset(textX, currentY));
      }
    }

    final headerBottom = currentY + headerHeight + 2.0;

    // ── 2. Bottom Section Geometry Calculations (Anchored from Bottom Up) ───
    // Unit Price (e.g. "Birim Fiyatı: 299,95 TL / Adet")
    final unitFontSize = (labelHeightDots * 0.050).clamp(10.0, 15.0);
    final unitPriceVal = model.unitPrice ?? model.price;
    final unitStr = model.unit.toLowerCase().trim();
    final unitDisplay = (unitStr == 'adet' || unitStr.isEmpty)
        ? 'Ad.'
        : (unitStr == 'kg' ? 'kg' : unitStr);
    final unitPriceText =
        'Birim Fiyatı: ${unitPriceVal.toStringAsFixed(2)} TL / $unitDisplay';
    final unitPainter = TextPainter(
      text: TextSpan(
        text: unitPriceText,
        style: ts(
          fontSize: unitFontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: usableWidth * 0.48);

    // Actual unit baseline is firmly anchored to bottom margin
    final actualUnitY = bottomMargin - unitPainter.height;

    // Barcode: vertically shortened, compact, and sits tightly above unit price
    final barcodeHeight = (labelHeightDots * 0.115).clamp(24.0, 36.0);
    final barcodeY = actualUnitY - 2.5 - barcodeHeight;

    // Code & Shelf text sits tightly above the barcode
    final codeStr = (model.barcode?.isNotEmpty == true
            ? model.barcode
            : model.shelfCode) ??
        '';
    final shelfText = model.shelfCode?.trim().isNotEmpty == true
        ? '   Raf: ${model.shelfCode!.trim()}'
        : '';
    final codeLabel = 'Kod: $codeStr$shelfText';
    final codePainter = TextPainter(
      text: TextSpan(
        text: codeLabel,
        style: ts(
          fontSize: (labelHeightDots * 0.058).clamp(11.0, 17.0),
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: usableWidth * 0.48);
    final codeY = barcodeY - 2.0 - codePainter.height;

    // Price layout (Right side) - Format with thousand separator (e.g. 11.599 or 299)
    final wholePart = model.price.floor();
    final centsPart = ((model.price - wholePart) * 100).round();
    final wholeStrRaw = wholePart.toString();
    final wholeStrBuffer = StringBuffer();
    for (var i = 0; i < wholeStrRaw.length; i++) {
      if (i > 0 && (wholeStrRaw.length - i) % 3 == 0) {
        wholeStrBuffer.write('.');
      }
      wholeStrBuffer.write(wholeStrRaw[i]);
    }
    final wholeStr = wholeStrBuffer.toString();
    final centsStr = centsPart.toString().padLeft(2, '0');

    final maxPriceWidth = usableWidth * 0.49;
    double wholeFontSize = (labelHeightDots * 0.235).clamp(30.0, 70.0);
    double centsFontSize = (wholeFontSize * 0.44).clamp(15.0, 32.0);
    double symbolFontSize = (wholeFontSize * 0.48).clamp(16.0, 34.0);
    double symbolGap = (wholeFontSize * 0.08).clamp(3.0, 7.0);
    double centsGap = (wholeFontSize * 0.05).clamp(2.0, 4.0);

    var wholePainter = TextPainter(
      text: TextSpan(
        text: wholeStr,
        style: ts(fontSize: wholeFontSize, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    var centsPainter = TextPainter(
      text: TextSpan(
        text: centsStr,
        style: ts(fontSize: centsFontSize, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    var symbolPainter = TextPainter(
      text: TextSpan(
        text: '₺',
        style: ts(fontSize: symbolFontSize, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    var totalPriceWidth = symbolPainter.width +
        symbolGap +
        wholePainter.width +
        centsGap +
        centsPainter.width;

    // Auto-shrink price font size for large prices like 11.599 so it never clips
    while (totalPriceWidth > maxPriceWidth && wholeFontSize > 20.0) {
      wholeFontSize -= 1.0;
      centsFontSize = (wholeFontSize * 0.44).clamp(15.0, 32.0);
      symbolFontSize = (wholeFontSize * 0.48).clamp(16.0, 34.0);
      symbolGap = (wholeFontSize * 0.08).clamp(3.0, 7.0);
      centsGap = (wholeFontSize * 0.05).clamp(2.0, 4.0);

      wholePainter = TextPainter(
        text: TextSpan(
          text: wholeStr,
          style: ts(fontSize: wholeFontSize, fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      centsPainter = TextPainter(
        text: TextSpan(
          text: centsStr,
          style: ts(fontSize: centsFontSize, fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      symbolPainter = TextPainter(
        text: TextSpan(
          text: '₺',
          style: ts(fontSize: symbolFontSize, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      totalPriceWidth = symbolPainter.width +
          symbolGap +
          wholePainter.width +
          centsGap +
          centsPainter.width;
    }

    final priceStartX = rightMargin - totalPriceWidth;
    final wholeY = actualUnitY - wholePainter.height * 0.82;
    final centsY = wholeY;
    final symbolY =
        wholeY + (wholePainter.height - symbolPainter.height) * 0.65;
    final wholeNumberStartX = priceStartX + symbolPainter.width + symbolGap;

    // Vergi bilgisi: Birim fiyatı ile dikeyde hizalı, fiyat rakamının başlangıcından başlar
    final vatPainter = TextPainter(
      text: TextSpan(
        text: 'KDV Dahildir',
        style: ts(
          fontSize: (labelHeightDots * 0.046).clamp(9.5, 14.0),
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final vatY = actualUnitY + (unitPainter.height - vatPainter.height);
    final vatX = wholeNumberStartX;

    // Regulatory Micro Info Bar (Menşei • F.D.T)
    // Menşei ile Kod arasındaki satır boşluğu, Kod ile Barkod arasındaki boşlukla (2.0) tam olarak eşitlendi
    final fdtDate =
        '${model.timestamp.day.toString().padLeft(2, '0')}.${model.timestamp.month.toString().padLeft(2, '0')}.${model.timestamp.year}';
    final originText = model.origin.isNotEmpty ? model.origin : 'TÜRKİYE';
    final microText = 'Menşei: $originText  •  F.D.T: $fdtDate';
    final microPainter = TextPainter(
      text: TextSpan(
        text: microText,
        style: ts(
          fontSize: (labelHeightDots * 0.044).clamp(9.0, 13.0),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: usableWidth.toDouble());

    // Menşei satırı, Kod satırının tam 2.0 px üstüne yerleştirilir (Kod-Barkod arasıyla birebir aynı)
    final microY = codeY - 2.0 - microPainter.height;

    // Clean Horizontal Divider Line: directly above micro bar and above price
    final dividerY = math.min(microY - 2.5, showPrice ? wholeY - 3.0 : microY - 2.5);

    // ── 3. Product Name (Responsive, Big & Bold, Centered, Max 2 Lines) ────
    final nameZoneTop = headerBottom;
    final availableNameHeight = dividerY - 3.0 - nameZoneTop;

    double productNameFontSize = (labelHeightDots * 0.165).clamp(26.0, 54.0);
    var namePainter = TextPainter(
      text: TextSpan(
        text: model.productName,
        style: ts(
          fontSize: productNameFontSize,
          fontWeight: FontWeight.w900,
        ),
      ),
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '...',
      textDirection: TextDirection.ltr,
    )..layout(
        minWidth: usableWidth.toDouble(),
        maxWidth: usableWidth.toDouble(),
      );

    // If it wraps to 2 lines, scale to a bold, prominent 2-line target size
    if (namePainter.computeLineMetrics().length > 1) {
      productNameFontSize = (labelHeightDots * 0.125).clamp(22.0, 40.0);
      namePainter = TextPainter(
        text: TextSpan(
          text: model.productName,
          style: ts(
            fontSize: productNameFontSize,
            fontWeight: FontWeight.w900,
          ),
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        ellipsis: '...',
        textDirection: TextDirection.ltr,
      )..layout(
          minWidth: usableWidth.toDouble(),
          maxWidth: usableWidth.toDouble(),
        );
    }

    // Step down font size if it exceeds the reserved headroom
    while (namePainter.height > availableNameHeight && productNameFontSize > 13.0) {
      productNameFontSize -= 1.0;
      namePainter = TextPainter(
        text: TextSpan(
          text: model.productName,
          style: ts(
            fontSize: productNameFontSize,
            fontWeight: FontWeight.w900,
          ),
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        ellipsis: '...',
        textDirection: TextDirection.ltr,
      )..layout(
          minWidth: usableWidth.toDouble(),
          maxWidth: usableWidth.toDouble(),
        );
    }

    // Paint Product Name centered vertically within its generous upper zone
    final nameY = nameZoneTop + (availableNameHeight - namePainter.height) / 2;
    namePainter.paint(canvas, Offset(leftMargin.toDouble(), nameY));

    // ── 4. Paint Horizontal Divider Line & Regulatory Info ─────────────────
    canvas.drawLine(
      Offset(leftMargin.toDouble(), dividerY),
      Offset(rightMargin.toDouble(), dividerY),
      Paint()
        ..color = Colors.black
        ..strokeWidth = 1.8,
    );
    microPainter.paint(canvas, Offset(leftMargin.toDouble(), microY));

    // ── 5. Paint Code, Barcode, Unit Price ──────────────────────────────────
    codePainter.paint(canvas, Offset(leftMargin.toDouble(), codeY));

    if (showBarcode && codeStr.isNotEmpty) {
      final barcodeWidth = (usableWidth * 0.44).clamp(140.0, 300.0);
      try {
        final bc = Barcode.code128();
        final elements = bc.make(
          codeStr,
          width: barcodeWidth,
          height: barcodeHeight,
        );
        final barPaint = Paint()
          ..color = Colors.black
          ..style = PaintingStyle.fill;
        for (final elem in elements) {
          if (elem is BarcodeBar && elem.black) {
            canvas.drawRect(
              Rect.fromLTWH(
                leftMargin + elem.left,
                barcodeY,
                elem.width,
                barcodeHeight,
              ),
              barPaint,
            );
          }
        }
      } catch (_) {}
    }

    unitPainter.paint(canvas, Offset(leftMargin.toDouble(), actualUnitY));

    // ── 6. Paint Price & VAT (Right side) ───────────────────────────────────
    if (showPrice) {
      symbolPainter.paint(canvas, Offset(priceStartX, symbolY));
      wholePainter.paint(
        canvas,
        Offset(wholeNumberStartX, wholeY),
      );
      centsPainter.paint(
        canvas,
        Offset(
          wholeNumberStartX + wholePainter.width + centsGap,
          centsY,
        ),
      );
      vatPainter.paint(canvas, Offset(vatX, vatY));
    }

    // ── 5. Rasterize to 1-Bit TSPL Monochrome Bitmap ──────────────────────
    final picture = recorder.endRecording();
    final img = await picture.toImage(labelWidthDots, labelHeightDots);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (byteData == null) {
      throw StateError('Canvas rasterization failed for shelf label');
    }

    final rasterBytes = Uint8List(widthBytes * labelHeightDots);
    var rasterIdx = 0;
    final pixels = byteData.buffer.asUint32List();

    for (var y = 0; y < labelHeightDots; y++) {
      for (var byteCol = 0; byteCol < widthBytes; byteCol++) {
        var b = 0xFF; // TSPL: 1 = white, 0 = black
        for (var bit = 0; bit < 8; bit++) {
          final px = byteCol * 8 + bit;
          if (px < labelWidthDots) {
            final pixel = pixels[y * labelWidthDots + px];
            final a = (pixel >> 24) & 0xFF;
            final r = pixel & 0xFF;
            final g = (pixel >> 8) & 0xFF;
            final bChannel = (pixel >> 16) & 0xFF;
            final lum = (r * 77 + g * 150 + bChannel * 29) >> 8;
            if (a > 50 && lum < 200) {
              b &= ~(0x80 >> bit);
            }
          }
        }
        rasterBytes[rasterIdx++] = b;
      }
    }

    final isContinuous = gapMm <= 0;
    final tsplHeader = 'SIZE $safeWidth mm,$safeHeight mm\r\n'
        'GAP ${isContinuous ? 0 : gapMm} mm,0 mm\r\n'
        'DENSITY 8\r\n'
        'DIRECTION ${direction == 1 ? 1 : 0}\r\n'
        'REFERENCE 0,0\r\n'
        'CLS\r\n'
        'BITMAP 0,0,$widthBytes,$labelHeightDots,0,';

    final outputBytes = <int>[
      ...latin1.encode(tsplHeader),
      ...rasterBytes,
      ...const [13, 10],
      ...latin1.encode('PRINT ${copies.clamp(1, 20)},1\r\n'),
    ];

    return outputBytes;
  }
}

class _MeasuredItem {
  final Map<String, dynamic> item;
  final TextPainter namePainter;
  final TextPainter detailPainter;
  final double totalHeight;
  final bool isSingleLine;

  _MeasuredItem(
    this.item,
    this.namePainter,
    this.detailPainter,
    this.totalHeight, {
    this.isSingleLine = false,
  });
}
