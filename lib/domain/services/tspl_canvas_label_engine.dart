import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

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
  }) async {
    final safeDpi = dpi < 100 ? 203 : dpi;
    final safeWidth = widthMm.clamp(20, 120);
    final requestedHeightMm = heightMm.clamp(15, 150);

    final widthDots = (safeWidth * safeDpi / 25.4).round();
    final heightDots = (requestedHeightMm * safeDpi / 25.4).round();

    final paddingX = (widthDots * 0.045).clamp(16.0, 32.0);
    final usableW = widthDots - (2 * paddingX);
    final topMargin = (heightDots * 0.04).clamp(10.0, 20.0);
    final bottomMargin = (heightDots * 0.08).clamp(24.0, 40.0);
    final maxSafePageY = heightDots - bottomMargin;

    final isWide = safeWidth >= 75;
    final titleFontSize = isWide ? 17.0 : 13.0;
    final bodyFontSize = isWide ? 13.5 : 10.5;
    final detailFontSize = isWide ? 12.0 : 9.5;

    final dateStr = (showDate && timestamp != null)
        ? '${timestamp.day.toString().padLeft(2, '0')}.${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}'
        : '';

    final hasCustomBizName = showBusinessName &&
        businessName != null &&
        businessName.trim().isNotEmpty &&
        !businessName.trim().toUpperCase().contains('SERENUT');

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
      final name = (item['product_name'] ?? item['name'] ?? 'Ürün').toString().trim();
      final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final qtyStr = qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(1);
      final unitPrice = (item['unit_price'] as num? ?? item['unitPrice'] as num?)?.toDouble();
      final lineTotal = item['total'] != null
          ? (item['total'] as num).toDouble()
          : item['line_total'] != null
              ? (item['line_total'] as num).toDouble()
              : unitPrice == null
                  ? null
                  : unitPrice * qty;
      final rightTotal = lineTotal == null ? '' : '${lineTotal.toStringAsFixed(2)} TL';

      final namePainter = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            color: Colors.black,
            fontSize: bodyFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: usableW);

      final String detailText;
      if (unitPrice != null && rightTotal.isNotEmpty) {
        detailText = '  ${qtyStr}x ${unitPrice.toStringAsFixed(2)} TL = $rightTotal';
      } else if (rightTotal.isNotEmpty) {
        detailText = '  $qtyStr adet = $rightTotal';
      } else {
        detailText = '  $qtyStr adet';
      }

      final detailPainter = TextPainter(
        text: TextSpan(
          text: detailText,
          style: TextStyle(
            color: Colors.black,
            fontSize: detailFontSize,
            fontWeight: FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: usableW);

      final totalH = namePainter.height + detailPainter.height + 4.0;
      return _MeasuredItem(item, namePainter, detailPainter, totalH);
    }

    final measuredItems = itemsList.map(measureItem).toList();

    // Measure Header Heights
    double measurePage1HeaderHeight() {
      var h = topMargin;
      if (hasCustomBizName) h += titleFontSize + 6.0;
      if (showOrderNo || showDate) h += bodyFontSize + 6.0;
      if (showCustomerName) {
        h += bodyFontSize + 4.0;
        if (customerPhone != null && customerPhone.trim().isNotEmpty) {
          h += bodyFontSize + 4.0;
        }
      }
      if (previousDebt > 0.001) h += bodyFontSize + 4.0;
      h += 6.0; // Divider bar
      return h;
    }

    final page1HeaderH = measurePage1HeaderHeight();
    final subsequentHeaderH = topMargin + bodyFontSize + 10.0;
    final closingFooterH = (bodyFontSize * 2) + 24.0; // Odm, Toplam, lines

    // Multi-page distribution
    final pages = <List<_MeasuredItem>>[];
    if (!paginateOnOverflow || (itemsList.length <= 3 && (page1HeaderH + measuredItems.fold<double>(0, (s, i) => s + i.totalHeight) + closingFooterH <= maxSafePageY))) {
      pages.add(measuredItems);
    } else {
      var itemIdx = 0;
      final page1Budget = maxSafePageY - page1HeaderH - 8.0;
      final page1Items = <_MeasuredItem>[];
      var page1Used = 0.0;
      while (itemIdx < measuredItems.length) {
        final item = measuredItems[itemIdx];
        if (page1Items.isNotEmpty && (page1Used + item.totalHeight > page1Budget)) {
          break;
        }
        page1Items.add(item);
        page1Used += item.totalHeight;
        itemIdx++;
      }
      if (itemIdx == measuredItems.length && page1Items.length > 1) {
        page1Items.removeLast();
        itemIdx--;
      }
      pages.add(page1Items);

      final subClosingBudget = maxSafePageY - subsequentHeaderH - closingFooterH;
      final subInterBudget = maxSafePageY - subsequentHeaderH - 8.0;

      while (itemIdx < measuredItems.length) {
        var remainingH = 0.0;
        for (var i = itemIdx; i < measuredItems.length; i++) {
          remainingH += measuredItems[i].totalHeight;
        }
        if (remainingH <= subClosingBudget) {
          pages.add(measuredItems.sublist(itemIdx));
          break;
        }

        final inter = <_MeasuredItem>[];
        var interUsed = 0.0;
        while (itemIdx < measuredItems.length) {
          final it = measuredItems[itemIdx];
          if (inter.isNotEmpty && (interUsed + it.totalHeight > subInterBudget)) {
            break;
          }
          inter.add(it);
          interUsed += it.totalHeight;
          itemIdx++;
        }
        pages.add(inter);
      }
    }

    // Render each page with Canvas and encode to 1-bit TSPL BITMAP
    final outputBytes = <int>[];
    final totalPagesCount = pages.length;

    for (var pageIdx = totalPagesCount - 1; pageIdx >= 0; pageIdx--) {
      final pageItems = pages[pageIdx];
      final isFirstPage = pageIdx == 0;
      final isLastPage = pageIdx == totalPagesCount - 1;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, widthDots.toDouble(), heightDots.toDouble()),
      );

      // Background
      canvas.drawRect(
        Rect.fromLTWH(0, 0, widthDots.toDouble(), heightDots.toDouble()),
        Paint()..color = Colors.white,
      );

      final linePaint = Paint()
        ..color = Colors.black
        ..strokeWidth = isWide ? 2.0 : 1.5;

      var currentY = topMargin;

      if (isFirstPage) {
        // Business Name
        if (hasCustomBizName) {
          final bizPainter = TextPainter(
            text: TextSpan(
              text: businessName.trim(),
              style: TextStyle(
                color: Colors.black,
                fontSize: titleFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: usableW);
          bizPainter.paint(
            canvas,
            Offset(((widthDots - bizPainter.width) / 2).clamp(paddingX, widthDots - paddingX), currentY),
          );
          currentY += bizPainter.height + 4.0;
        }

        // Order No & Date
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
          )..layout(maxWidth: usableW * 0.65);
          orderPainter.paint(canvas, Offset(paddingX, currentY));

          if (dateStr.isNotEmpty) {
            final datePainter = TextPainter(
              text: TextSpan(
                text: dateStr,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: bodyFontSize * 0.95,
                  fontWeight: FontWeight.normal,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: usableW * 0.45);
            datePainter.paint(canvas, Offset(widthDots - paddingX - datePainter.width, currentY));
          }
          currentY += math.max(orderPainter.height, bodyFontSize) + 4.0;
        }

        // Customer & Phone
        if (showCustomerName) {
          final custStr = customerName.trim().isNotEmpty ? 'Müş: ${customerName.trim()}' : 'Müş: Genel';
          final custPainter = TextPainter(
            text: TextSpan(
              text: custStr,
              style: TextStyle(
                color: Colors.black,
                fontSize: bodyFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: usableW);
          custPainter.paint(canvas, Offset(paddingX, currentY));
          currentY += custPainter.height + 2.0;

          if (customerPhone != null && customerPhone.trim().isNotEmpty) {
            final phonePainter = TextPainter(
              text: TextSpan(
                text: 'Tel: ${customerPhone.trim()}',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: bodyFontSize * 0.95,
                  fontWeight: FontWeight.normal,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: usableW);
            phonePainter.paint(canvas, Offset(paddingX, currentY));
            currentY += phonePainter.height + 2.0;
          }
        }

        if (previousDebt > 0.001) {
          final debtPainter = TextPainter(
            text: TextSpan(
              text: 'Geçmiş Borç: ${previousDebt.toStringAsFixed(2)} TL',
              style: TextStyle(
                color: Colors.black,
                fontSize: bodyFontSize * 0.95,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: usableW);
          debtPainter.paint(canvas, Offset(paddingX, currentY));
          currentY += debtPainter.height + 2.0;
        }

        // Divider
        canvas.drawLine(Offset(paddingX, currentY + 2), Offset(widthDots - paddingX, currentY + 2), linePaint);
        currentY += 6.0;
      } else {
        // Subsequent Pages Header
        final contTitle = 'Sip #$orderIdShort (${pageIdx + 1}/$totalPagesCount) - Devam';
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
        )..layout(maxWidth: usableW * 0.65);
        contPainter.paint(canvas, Offset(paddingX, currentY));

        if (dateStr.isNotEmpty) {
          final datePainter = TextPainter(
            text: TextSpan(
              text: dateStr,
              style: TextStyle(
                color: Colors.black,
                fontSize: bodyFontSize * 0.9,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: usableW * 0.35);
          datePainter.paint(canvas, Offset(widthDots - paddingX - datePainter.width, currentY));
        }
        currentY += math.max(contPainter.height, bodyFontSize) + 4.0;
        canvas.drawLine(Offset(paddingX, currentY + 2), Offset(widthDots - paddingX, currentY + 2), linePaint);
        currentY += 6.0;
      }

      // Draw Items
      for (final it in pageItems) {
        it.namePainter.paint(canvas, Offset(paddingX, currentY));
        currentY += it.namePainter.height;
        it.detailPainter.paint(canvas, Offset(paddingX, currentY));
        currentY += it.detailPainter.height + 4.0;
      }

      // Divider after items
      canvas.drawLine(Offset(paddingX, currentY + 2), Offset(widthDots - paddingX, currentY + 2), linePaint);
      currentY += 6.0;

      if (isLastPage) {
        // Payment status
        final payPainter = TextPainter(
          text: TextSpan(
            text: 'Ödeme: $paymentStatus',
            style: TextStyle(
              color: Colors.black,
              fontSize: bodyFontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: usableW * 0.60);
        payPainter.paint(canvas, Offset(paddingX, currentY));

        // Total Amount (Bold, right aligned)
        if (showTotalAmount && totalAmount != null) {
          final totPainter = TextPainter(
            text: TextSpan(
              text: 'TOPLAM: ${totalAmount.toStringAsFixed(2)} TL',
              style: TextStyle(
                color: Colors.black,
                fontSize: titleFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: usableW);
          totPainter.paint(canvas, Offset(widthDots - paddingX - totPainter.width, currentY - 2.0));
        }
      } else {
        // Continuation banner
        final contBanner = TextPainter(
          text: TextSpan(
            text: '>> DEVAMI ${(pageIdx + 2)}. ETIKETTE >>',
            style: TextStyle(
              color: Colors.black,
              fontSize: detailFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: usableW);
        contBanner.paint(
          canvas,
          Offset(((widthDots - contBanner.width) / 2).clamp(paddingX, widthDots - paddingX), currentY + 2),
        );
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(widthDots, heightDots);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (byteData != null) {
        final widthBytes = (widthDots + 7) ~/ 8;
        final rasterBytes = Uint8List(widthBytes * heightDots);
        var rasterIdx = 0;
        final pixels = byteData.buffer.asUint32List();

        for (var y = 0; y < heightDots; y++) {
          for (var byteCol = 0; byteCol < widthBytes; byteCol++) {
            var b = 0;
            for (var bit = 0; bit < 8; bit++) {
              final px = byteCol * 8 + bit;
              if (px < widthDots) {
                final pixel = pixels[y * widthDots + px];
                final r = pixel & 0xFF;
                final g = (pixel >> 8) & 0xFF;
                final bChannel = (pixel >> 16) & 0xFF;
                final lum = (r * 77 + g * 150 + bChannel * 29) >> 8;
                if (lum < 160) {
                  b |= (0x80 >> bit);
                }
              }
            }
            rasterBytes[rasterIdx++] = b;
          }
        }

        final tsplHeader =
            'SIZE $safeWidth mm,$requestedHeightMm mm\r\n'
            'GAP $gapMm mm,0 mm\r\n'
            '${autoDetectGap ? "GAPDETECT\r\n" : ""}'
            'DENSITY 8\r\n'
            'DIRECTION ${direction == 1 ? 1 : 0}\r\n'
            'REFERENCE 0,0\r\n'
            'CLS\r\n'
            'BITMAP 0,0,$widthBytes,$heightDots,0,';

        outputBytes
          ..addAll(latin1.encode(tsplHeader))
          ..addAll(rasterBytes)
          ..addAll(latin1.encode('\r\nPRINT ${copies.clamp(1, 20)},1\r\n'));
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

  _MeasuredItem(this.item, this.namePainter, this.detailPainter, this.totalHeight);
}
