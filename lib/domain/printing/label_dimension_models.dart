import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Operating mode of the thermal label media.
enum MediaMode {
  /// Die-cut labels with a physical gap or notch between labels.
  gap,

  /// Continuous roll of thermal paper (no gap, cut-to-length).
  continuous,
}

/// Represents a 2D bounding box in printer dots for an individual rendered element.
class ElementBoundingBox {
  /// Identifying name of the rendered element (e.g. 'ProductName', 'QR', 'FooterTotal').
  final String elementName;

  /// Left coordinate in printer dots.
  final double left;

  /// Top coordinate in printer dots.
  final double top;

  /// Width in printer dots.
  final double width;

  /// Height in printer dots.
  final double height;

  const ElementBoundingBox({
    required this.elementName,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double get right => left + width;
  double get bottom => top + height;

  Rect toRect() => Rect.fromLTWH(left, top, width, height);

  /// Checks if this element exceeds the defined usable boundaries.
  bool exceedsBounds({
    required double usableLeft,
    required double usableTop,
    required double usableRight,
    required double usableBottom,
    double safetyDots = 0.0,
  }) {
    return left < (usableLeft - 0.01) ||
        top < (usableTop - 0.01) ||
        right > (usableRight - safetyDots + 0.01) ||
        bottom > (usableBottom - safetyDots + 0.01);
  }

  /// Formats a detailed debug message when an overflow is detected.
  String formatOverflow({
    required double usableLeft,
    required double usableTop,
    required double usableRight,
    required double usableBottom,
  }) {
    final overflowX = math.max(0.0, right - usableRight);
    final overflowY = math.max(0.0, bottom - usableBottom);
    final underflowX = math.max(0.0, usableLeft - left);
    final underflowY = math.max(0.0, usableTop - top);
    return 'OVERFLOW DETECTED: [$elementName]\n'
        '  Left:   ${left.toStringAsFixed(1)} (usableLeft: ${usableLeft.toStringAsFixed(1)})\n'
        '  Top:    ${top.toStringAsFixed(1)} (usableTop: ${usableTop.toStringAsFixed(1)})\n'
        '  Right:  ${right.toStringAsFixed(1)} (usableRight: ${usableRight.toStringAsFixed(1)})\n'
        '  Bottom: ${bottom.toStringAsFixed(1)} (usableBottom: ${usableBottom.toStringAsFixed(1)})\n'
        '  OverflowX: ${overflowX > 0 ? "+${overflowX.toStringAsFixed(1)}" : (underflowX > 0 ? "-${underflowX.toStringAsFixed(1)}" : "0.0")}\n'
        '  OverflowY: ${overflowY > 0 ? "+${overflowY.toStringAsFixed(1)}" : (underflowY > 0 ? "-${underflowY.toStringAsFixed(1)}" : "0.0")}';
  }

  @override
  String toString() =>
      '$elementName(L:${left.toStringAsFixed(1)}, T:${top.toStringAsFixed(1)}, R:${right.toStringAsFixed(1)}, B:${bottom.toStringAsFixed(1)})';
}

/// Represents the usable printable area inside the canvas, after margins and safety allowances.
class UsablePrintArea {
  final double usableLeft;
  final double usableTop;
  final double usableRight;
  final double usableBottom;
  final double safetyDots;

  const UsablePrintArea({
    required this.usableLeft,
    required this.usableTop,
    required this.usableRight,
    required this.usableBottom,
    this.safetyDots = 2.0,
  });

  double get usableWidth =>
      math.max(0.0, (usableRight - safetyDots) - usableLeft);
  double get usableHeight =>
      math.max(0.0, (usableBottom - safetyDots) - usableTop);

  bool containsBox(ElementBoundingBox box) {
    return !box.exceedsBounds(
      usableLeft: usableLeft,
      usableTop: usableTop,
      usableRight: usableRight,
      usableBottom: usableBottom,
      safetyDots: safetyDots,
    );
  }
}

/// Comprehensive layout validation report verifying bounds and bounding box of a label page.
class LayoutValidationReport {
  final bool isValid;
  final List<ElementBoundingBox> elements;
  final List<String> overflowErrors;
  final Rect contentBoundingBox;

  const LayoutValidationReport({
    required this.isValid,
    required this.elements,
    required this.overflowErrors,
    required this.contentBoundingBox,
  });

  @override
  String toString() =>
      'LayoutValidationReport(valid: $isValid, elements: ${elements.length}, errors: ${overflowErrors.length})';
}

/// Represents the measured bounding-box dimensions of the label content.
class ContentSize {
  /// Total content width in millimeters.
  final double widthMm;

  /// Total content height in millimeters needed to render all content seamlessly.
  final double heightMm;

  /// Total content height in printer dots.
  final double totalHeightDots;

  /// Maximum line width in printer dots.
  final double maxLineWidthDots;

  /// Real content bounding box in dots.
  final Rect? contentBoundingBox;

  /// Individual element bounding boxes.
  final List<ElementBoundingBox> elementBoxes;

  const ContentSize({
    required this.widthMm,
    required this.heightMm,
    required this.totalHeightDots,
    required this.maxLineWidthDots,
    this.contentBoundingBox,
    this.elementBoxes = const [],
  });

  @override
  String toString() =>
      'ContentSize(${widthMm.toStringAsFixed(1)}×${heightMm.toStringAsFixed(1)} mm, dots: ${maxLineWidthDots.toInt()}×${totalHeightDots.toInt()})';
}

/// Represents the physical media profile installed in or supported by the target printer.
class MediaProfile {
  /// Physical roll width in millimeters.
  final double widthMm;

  /// Physical label height in millimeters for die-cut labels (or default reference height for continuous).
  final double heightMm;

  /// Inter-label gap height in millimeters. If <= 0, media is considered continuous.
  final double gapMm;

  /// Printer resolution in DPI (typically 203 or 300).
  final int dpi;

  /// Maximum printable dots reported by hardware (e.g. 384 dots for standard 2-inch printhead).
  final int? printableWidthDots;

  /// Operating mode (gap vs continuous).
  final MediaMode mode;

  const MediaProfile({
    required this.widthMm,
    required this.heightMm,
    this.gapMm = 2.0,
    this.dpi = 203,
    this.printableWidthDots,
    MediaMode? mode,
  }) : mode = mode ?? (gapMm <= 0 ? MediaMode.continuous : MediaMode.gap);

  double get dotsPerMm => (dpi < 100 ? 203 : dpi) / 25.4;

  /// Returns the maximum physical dots that the printhead can burn across [widthMm].
  int get maxPhysicalDots {
    final mediaDots = (widthMm * dotsPerMm).round();
    final maxNarrowDots = (48.0 * dotsPerMm).round(); // 384 dots @ 203 DPI
    return widthMm <= 54 ? math.min(mediaDots, maxNarrowDots) : mediaDots;
  }

  /// Returns the effective printable dots taking into account physical head width and user configuration.
  int get effectivePrintableDots {
    final maxDots = maxPhysicalDots;
    if (printableWidthDots != null && printableWidthDots! > 100) {
      return math.min(maxDots, printableWidthDots!);
    }
    return maxDots;
  }

  /// The printable width in millimeters.
  double get printableWidthMm => effectivePrintableDots / dotsPerMm;

  @override
  String toString() =>
      'MediaProfile(${widthMm.toInt()}×${heightMm.toInt()} mm, gap: ${gapMm}mm, dpi: $dpi, mode: ${mode.name})';
}

/// Represents the determined target physical page size and pagination decision.
class TargetPageSize {
  /// Final output width in millimeters for TSPL `SIZE` command.
  final double widthMm;

  /// Final output height in millimeters for TSPL `SIZE` command.
  final double heightMm;

  /// Total number of physical labels that will be printed.
  final int pagesCount;

  /// Whether the content requires pagination across multiple labels.
  final bool isMultiPage;

  /// Operating mode of the target page.
  final MediaMode mode;

  const TargetPageSize({
    required this.widthMm,
    required this.heightMm,
    this.pagesCount = 1,
    this.isMultiPage = false,
    required this.mode,
  });

  @override
  String toString() =>
      'TargetPageSize(${widthMm.toStringAsFixed(1)}×${heightMm.toStringAsFixed(1)} mm, pages: $pagesCount, mode: ${mode.name})';
}

/// Controlled exception thrown when content exceeds printable physical limits.
class PrintLayoutException implements Exception {
  final String code;
  final String message;

  const PrintLayoutException({
    required this.code,
    required this.message,
  });

  @override
  String toString() => 'PrintLayoutException($code): $message';
}

/// Dynamic Label Size Engine: Decides target physical dimensions and pagination
/// based on measured content bounding box and installed media capabilities.
class DynamicLabelSizeEngine {
  /// Measures the complete bounding box required for an order label under the given [mediaProfile].
  static ContentSize measureOrderContent({
    required MediaProfile mediaProfile,
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
    String fontSize = 'Orta',
    bool showCustomerName = true,
    bool showOrderNo = true,
    bool showDate = true,
    bool showTotalAmount = true,
    bool showItemsCount = true,
    bool showQrCode = true,
    String? qrData,
    String? fontFamily,
  }) {
    TextStyle ts({
      required double fontSize,
      FontWeight fontWeight = FontWeight.normal,
      FontStyle fontStyle = FontStyle.normal,
      Color color = Colors.black,
    }) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        color: color,
      );
    }

    final dotsPerMm = mediaProfile.dotsPerMm;
    final effectiveDots = mediaProfile.effectivePrintableDots;

    // Margins: 4.0mm left on narrow labels (<=54mm), 5.0mm on wide labels (>=70mm)
    // to prevent clipping from mechanical paper guide offsets.
    final marginMm = mediaProfile.widthMm <= 54 ? 4.0 : 5.0;
    final paddingLeft = (marginMm * dotsPerMm).roundToDouble();
    final paddingRight =
        ((mediaProfile.widthMm <= 54 ? 5.5 : 3.5) * dotsPerMm).roundToDouble();
    const safetyDots = 2.0;
    final safeRightX =
        (effectiveDots - paddingRight - safetyDots).roundToDouble();
    final usableW = (safeRightX - paddingLeft).clamp(60.0, 1000.0);
    final topMargin =
        ((mediaProfile.heightMm <= 30 ? 1.0 : 2.5) * dotsPerMm).roundToDouble();
    final bottomMargin =
        (mediaProfile.heightMm <= 30 ? 2.5 : 2.0) * dotsPerMm;

    final usableArea = UsablePrintArea(
      usableLeft: paddingLeft,
      usableTop: topMargin,
      usableRight: safeRightX,
      usableBottom:
          (mediaProfile.heightMm * dotsPerMm) - bottomMargin - safetyDots,
      safetyDots: 0.0,
    );

    // Typography
    final fontScale = switch (fontSize) {
      'Küçük' => 0.88,
      'Büyük' => 1.15,
      _ => 1.0,
    };
    final isWide = mediaProfile.widthMm >= 70;
    final isTall = mediaProfile.heightMm > 40;
    final bodyFontSize =
        (isWide ? (isTall ? 26.0 : 21.0) : 18.0) * fontScale;
    final detailFontSize =
        (isWide ? (isTall ? 22.0 : 18.0) : 15.0) * fontScale;
    final footerTotalFontSize =
        (isWide ? (isTall ? 28.0 : 24.0) : 19.0) * fontScale;

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

    final boxes = <ElementBoundingBox>[];
    var currentY = topMargin;

    // 1. Measure & record Header
    if (showOrderNo || showDate) {
      final leftOrder = showOrderNo ? 'Sip #$orderIdShort' : '';
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

      boxes.add(ElementBoundingBox(
        elementName: 'OrderNo',
        left: paddingLeft,
        top: currentY,
        width: orderPainter.width,
        height: orderPainter.height,
      ));

      if (showDate && timestamp != null) {
        final dateStr =
            '${timestamp.day.toString().padLeft(2, '0')}.${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
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

        boxes.add(ElementBoundingBox(
          elementName: 'Date',
          left: dateX,
          top: currentY,
          width: datePainter.width,
          height: datePainter.height,
        ));
      }
      currentY += math.max(orderPainter.height, bodyFontSize) + 2.0;
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

        boxes.add(ElementBoundingBox(
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

        boxes.add(ElementBoundingBox(
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

        boxes.add(ElementBoundingBox(
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

          boxes.add(ElementBoundingBox(
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

      boxes.add(ElementBoundingBox(
        elementName: 'PreviousDebt',
        left: paddingLeft,
        top: currentY,
        width: debtPainter.width,
        height: debtPainter.height,
      ));
      currentY += debtPainter.height + 1.0;
    }

    // Header divider
    currentY += 2.0;
    boxes.add(ElementBoundingBox(
      elementName: 'HeaderDivider',
      left: paddingLeft,
      top: currentY,
      width: safeRightX - paddingLeft,
      height: isWide ? 2.0 : 1.2,
    ));
    currentY += 2.5;

    // 2. Measure & record items
    var maxItemLineWidth = 0.0;
    var itemIndex = 0;
    for (final item in itemsList) {
      itemIndex++;
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

      if (canBeSideBySide) {
        final itemH = math.max(namePainter.height, detailPainter.height);
        boxes.add(ElementBoundingBox(
          elementName: 'ItemName_$itemIndex',
          left: paddingLeft,
          top: currentY,
          width: namePainter.width,
          height: namePainter.height,
        ));

        final detailX =
            (safeRightX - detailPainter.width).clamp(paddingLeft, safeRightX);
        boxes.add(ElementBoundingBox(
          elementName: 'ItemDetail_$itemIndex',
          left: detailX,
          top: currentY,
          width: detailPainter.width,
          height: detailPainter.height,
        ));
        currentY += itemH + (isTall ? 5.0 : (isWide ? 2.5 : 3.5));

        maxItemLineWidth = math.max(
          maxItemLineWidth,
          namePainter.width + detailPainter.width + 12.0,
        );
      } else {
        boxes.add(ElementBoundingBox(
          elementName: 'ItemName_$itemIndex',
          left: paddingLeft,
          top: currentY,
          width: namePainter.width,
          height: namePainter.height,
        ));
        currentY += namePainter.height + 0.5;

        boxes.add(ElementBoundingBox(
          elementName: 'ItemDetail_$itemIndex',
          left: paddingLeft,
          top: currentY,
          width: detailPainter.width,
          height: detailPainter.height,
        ));
        currentY += detailPainter.height + 2.0;

        maxItemLineWidth = math.max(
          maxItemLineWidth,
          math.max(namePainter.width, detailPainter.width),
        );
      }
    }

    // Items divider
    currentY += 1.5;
    boxes.add(ElementBoundingBox(
      elementName: 'ItemsDivider',
      left: paddingLeft,
      top: currentY,
      width: safeRightX - paddingLeft,
      height: isWide ? 2.0 : 1.2,
    ));
    currentY += 2.5;

    // 3. QR sizing
    final cleanQrData = (qrData != null && qrData.trim().isNotEmpty)
        ? qrData.trim()
        : 'order|$orderIdShort';
    final hasQr = showQrCode && cleanQrData.isNotEmpty;
    final qrCellWidth = (isWide && mediaProfile.heightMm > 40)
        ? (mediaProfile.dpi >= 300 ? 4 : 3)
        : (mediaProfile.dpi >= 300 ? 3 : 2);
    final qrModules = cleanQrData.length > 25 ? 35 : 29;
    final qrActualSizeDots = (qrModules * qrCellWidth).toDouble();
    final qrRightMarginDots = (mediaProfile.widthMm <= 54 ? 7.0 : 2.5) * dotsPerMm;

    // 4. Measure & record Closing Footer
    final maxSafeQrX =
        (effectiveDots - qrActualSizeDots - qrRightMarginDots).round();
    final pageQrX = maxSafeQrX.clamp(
        paddingLeft.round(), (safeRightX - qrActualSizeDots).round());
    final textMaxW = hasQr
        ? (pageQrX - paddingLeft - 8.0).clamp(60.0, usableW)
        : usableW;

    final footerStartY = currentY;

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

      boxes.add(ElementBoundingBox(
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
      final combinedText =
          'Ödeme: $paymentStatus  •  $itemsCount Çeşit (${totalQty.toStringAsFixed(0)} Ad.)';
      final payPainter = TextPainter(
        text: TextSpan(
          text: combinedText,
          style: ts(
            fontSize: bodyFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: textMaxW);

      boxes.add(ElementBoundingBox(
        elementName: 'FooterPayment',
        left: paddingLeft,
        top: currentY,
        width: payPainter.width,
        height: payPainter.height,
      ));
      currentY += payPainter.height + 1.5;
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
        )..layout(maxWidth: textMaxW);

        boxes.add(ElementBoundingBox(
          elementName: 'FooterItemsCount',
          left: paddingLeft,
          top: currentY,
          width: itemsPainter.width,
          height: itemsPainter.height,
        ));
        currentY += itemsPainter.height + 1.5;
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
      )..layout(maxWidth: textMaxW);

      boxes.add(ElementBoundingBox(
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

      boxes.add(ElementBoundingBox(
        elementName: 'FooterTotal',
        left: paddingLeft,
        top: currentY,
        width: totPainter.width,
        height: totPainter.height,
      ));
      currentY += totPainter.height + 1.5;
    }

    if (hasQr) {
      final qrTotalH = qrActualSizeDots + (isWide ? 14.0 : 0.0);
      boxes.add(ElementBoundingBox(
        elementName: 'QRCode',
        left: pageQrX.toDouble(),
        top: footerStartY,
        width: qrActualSizeDots,
        height: qrActualSizeDots,
      ));
      if (isWide) {
        boxes.add(ElementBoundingBox(
          elementName: 'QRCaption',
          left: pageQrX.toDouble(),
          top: footerStartY + qrActualSizeDots + 1.0,
          width: qrActualSizeDots,
          height: 12.0,
        ));
      }
      currentY = math.max(currentY, footerStartY + qrTotalH);
    }

    // Compute combined content bounding box
    var minL = double.infinity;
    var minT = double.infinity;
    var maxR = 0.0;
    var maxB = 0.0;
    for (final box in boxes) {
      minL = math.min(minL, box.left);
      minT = math.min(minT, box.top);
      maxR = math.max(maxR, box.right);
      maxB = math.max(maxB, box.bottom);
    }
    final contentBoundingBox = boxes.isEmpty
        ? Rect.zero
        : Rect.fromLTRB(minL, minT, maxR, maxB);

    // Pre-pagination width warning check
    if (contentBoundingBox.right > usableArea.usableRight) {
      developer.log(
        'WIDTH OVERFLOW DETECTED during measurement: content right ${contentBoundingBox.right.toStringAsFixed(1)} > usableRight ${usableArea.usableRight.toStringAsFixed(1)}',
        name: 'DynamicLabelEngine',
      );
    }

    final totalHeightDots = math.max(currentY, maxB);
    final contentHeightMm = totalHeightDots / dotsPerMm;
    final maxLineWidthDots = paddingLeft + maxItemLineWidth + paddingRight;
    final contentWidthMm = maxLineWidthDots / dotsPerMm;

    return ContentSize(
      widthMm: contentWidthMm,
      heightMm: contentHeightMm,
      totalHeightDots: totalHeightDots,
      maxLineWidthDots: maxLineWidthDots,
      contentBoundingBox: contentBoundingBox,
      elementBoxes: boxes,
    );
  }

  /// Validates that all rendered element bounding boxes and the overall content bounding box
  /// fit strictly within the [usableArea] without any right or bottom overflow.
  static LayoutValidationReport validatePageLayout({
    required int pageIndex,
    required List<ElementBoundingBox> boxes,
    required UsablePrintArea usableArea,
  }) {
    final errors = <String>[];
    var minL = double.infinity;
    var minT = double.infinity;
    var maxR = 0.0;
    var maxB = 0.0;

    for (final box in boxes) {
      minL = math.min(minL, box.left);
      minT = math.min(minT, box.top);
      maxR = math.max(maxR, box.right);
      maxB = math.max(maxB, box.bottom);

      if (!usableArea.containsBox(box)) {
        final err = box.formatOverflow(
          usableLeft: usableArea.usableLeft,
          usableTop: usableArea.usableTop,
          usableRight: usableArea.usableRight,
          usableBottom: usableArea.usableBottom,
        );
        errors.add(err);
        debugPrint('=== OVERFLOW DETECTED (Page ${pageIndex + 1}) ===\n$err');
      }
    }

    final combinedRect = boxes.isEmpty
        ? Rect.zero
        : Rect.fromLTRB(minL, minT, maxR, maxB);

    return LayoutValidationReport(
      isValid: errors.isEmpty,
      elements: boxes,
      overflowErrors: errors,
      contentBoundingBox: combinedRect,
    );
  }

  /// Determines the [TargetPageSize] considering content dimensions and [mediaProfile].
  static TargetPageSize determineTargetSize({
    required ContentSize contentSize,
    required MediaProfile mediaProfile,
  }) {
    // 1. Physical Width Boundary Enforcement
    if (mediaProfile.widthMm <= 0) {
      throw const PrintLayoutException(
        code: 'invalid_media_width',
        message: 'Media width must be greater than 0 mm.',
      );
    }

    final printableWidthMm = mediaProfile.printableWidthMm;
    if (contentSize.widthMm > printableWidthMm + 1.0) {
      // If content strictly exceeds physical head bounds and cannot reflow
      if (mediaProfile.widthMm <= 54 && contentSize.widthMm > 54.0) {
        throw PrintLayoutException(
          code: 'content_exceeds_printable_width',
          message:
              'Content width (${contentSize.widthMm.toStringAsFixed(1)}mm) exceeds printable media width (${printableWidthMm.toStringAsFixed(1)}mm).',
        );
      }
    }

    // 2. Continuous Media (GAP <= 0)
    if (mediaProfile.mode == MediaMode.continuous || mediaProfile.gapMm <= 0) {
      // Dynamic height: expand height to fit content seamlessly, bounded by min 15mm and max 300mm
      final neededHeightMm = (contentSize.heightMm + 2.0).clamp(15.0, 300.0);
      final dynamicHeightMm = (neededHeightMm * 10).ceilToDouble() / 10.0;
      return TargetPageSize(
        widthMm: mediaProfile.widthMm,
        heightMm: dynamicHeightMm,
        pagesCount: 1,
        isMultiPage: false,
        mode: MediaMode.continuous,
      );
    }

    // 3. Die-Cut Gap Media (GAP > 0)
    final targetHeightMm = mediaProfile.heightMm;
    final dotsPerMm = mediaProfile.dotsPerMm;
    final bottomMargin = (targetHeightMm <= 30 ? 2.5 : 1.5) * dotsPerMm;
    final totalMediaDots = (targetHeightMm * dotsPerMm).round();
    final maxSafePageY = totalMediaDots - bottomMargin;
    final safeHeightLimit = totalMediaDots - (bottomMargin * 0.5);

    if (contentSize.totalHeightDots <= safeHeightLimit) {
      return TargetPageSize(
        widthMm: mediaProfile.widthMm,
        heightMm: targetHeightMm,
        pagesCount: 1,
        isMultiPage: false,
        mode: MediaMode.gap,
      );
    }

    // Content overflows fixed media height -> Multi-page pagination required
    final estimatedPages =
        (contentSize.totalHeightDots / (maxSafePageY * 0.75)).ceil().clamp(2, 20);

    return TargetPageSize(
      widthMm: mediaProfile.widthMm,
      heightMm: targetHeightMm,
      pagesCount: estimatedPages,
      isMultiPage: true,
      mode: MediaMode.gap,
    );
  }
}
