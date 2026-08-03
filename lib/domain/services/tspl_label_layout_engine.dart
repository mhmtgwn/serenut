import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
    int widthMm = 58,
    int heightMm = 30,
    int gapMm = 2,
    int dpi = 203,
    int copies = 1,
    bool showLogo = true,
    bool showBusinessName = true,
    bool showBrand = true,
    bool showBarcode = true,
    bool showPrice = true,
    bool showVat = true,
    String? logoPath,
  }) {
    final safeWidth = widthMm > 0 ? widthMm : 58;
    final safeHeight = 30.0; // Hardcoded to 30mm as requested
    final safeDpi = dpi == 300 ? 300 : 203;

    final widthDots = (safeWidth * safeDpi / 25.4).round();
    final heightDots = (safeHeight * safeDpi / 25.4).round();

    int sx(num value) => (value * widthDots / 464).round();
    int sy(num value) => (value * heightDots / 240).round();

    final fontScale = (safeWidth / 58.0).clamp(0.8, 2.0);
    final fMult = (fontScale).round().clamp(1, 2);

    final barcode = _barcode(model.barcode ?? '');

    final resultBuffer = BytesBuilder();

    // Perfect physical paper margin balance (boxX1=4 dots, boxX2=384 dots)
    final boxX1 = 4;
    final boxY1 = 4;
    final boxX2 = 384; 
    final boxY2 = 202;

    final commands = StringBuffer()
      ..writeln('SIZE $safeWidth mm,$safeHeight mm')
      ..writeln('GAP 0,0') // Gapless (continuous)
      ..writeln('DENSITY 8')
      ..writeln('DIRECTION 0')
      ..writeln('REFERENCE 0,0')
      ..writeln('CLS')
      ..writeln('BOX $boxX1,$boxY1,$boxX2,$boxY2,3');

    int currentY = boxY1 + 4;
    final minX = boxX1 + 8;

    // ROW 1: Logo ONLY (Centered horizontally inside the frame, Firm name is NEVER printed)
    _TsplLogoData? logoData;
    if (showLogo && logoPath != null && logoPath.trim().isNotEmpty) {
      logoData = _prepareTsplLogoData(
        logoPath: logoPath,
        labelWidthDots: widthDots,
        labelHeightDots: heightDots,
      );
    }

    final hasLogo = logoData != null;
    final logoX = hasLogo
        ? (boxX1 + ((boxX2 - boxX1 - logoData!.widthDots) / 2)).round().clamp(minX, boxX2 - logoData.widthDots)
        : minX;
    final logoY = currentY;

    if (hasLogo) {
      currentY += logoData!.heightDots + sy(4);
    }

    // ROW 2: Product Name (Full 58mm width, Bold overprinting)
    final nameClean = _ascii(model.productName.trim());
    
    // Helper to simulate BOLD text in TSPL by printing twice with a slight 1-dot horizontal offset
    // Centered logic for Product Name
    void printBoldNameCenter(int y, String font, int mult, String text) {
      int fontWidth = font == "2" ? 12 : (font == "4" ? 24 : 16);
      int textW = text.length * fontWidth * mult; 
      int frameW = boxX2 - boxX1;
      int x = boxX1 + ((frameW - textW) / 2).round();
      x = x.clamp(minX, boxX2);
      
      commands.writeln('TEXT $x,$y,"$font",0,$mult,$mult,"$text"');
      commands.writeln('TEXT ${x + 1},$y,"$font",0,$mult,$mult,"$text"'); // 1-dot offset
    }

    int nameMult = fMult * 2; // 2x scale for Font 2 (results in 24x40 size, perfectly between previous two sizes)
    if (nameClean.length <= 15) {
      // Fit in one line with Font 2 at 2x scale
      printBoldNameCenter(currentY, "2", nameMult, nameClean);
      currentY += sy(32 * fMult); // Tight spacing
    } else {
      // Wrap and use Font 2 at 2x scale
      final lines = _wrapProductName(nameClean, 15);
      for (final line in lines) {
        printBoldNameCenter(currentY, "2", nameMult, line);
        currentY += sy(32 * fMult); 
      }
    }

    // SHARED ROW: Barcode (Left) and Price (Right)
    final barcodeHeight = sy(48 * fMult).clamp(32, 60);
    int lowerBound = currentY + sy(4 * fMult);
    final upperBound = boxY2 - barcodeHeight;
    if (lowerBound > upperBound) lowerBound = upperBound;

    final sharedY = (upperBound - 6).clamp(lowerBound, upperBound);

    // 1. BARCODE (Left Aligned on Shared Y)
    if (barcode.isNotEmpty) {
      final barcodeW = (barcode.length + 4) * 11 * 1; 
      final maxRight = (boxX2 - barcodeW).clamp(boxX1, boxX2);
      final rawX = minX;
      final barcodeX = rawX.clamp(boxX1, maxRight);

      commands.writeln(
        'BARCODE $barcodeX,$sharedY,"128",$barcodeHeight,0,0,1,1,"$barcode"',
      );
    }
    
    // 2. PRICE (Right Aligned on Shared Y)
    final priceVal = model.price > 0 ? model.price : 249.90;
    final priceFormatted = "${priceVal.toStringAsFixed(2)}TL"; // No space before TL
    const priceScaleX = 2;
    const priceScaleY = 2;
    
    int estimatedDots = 0;
    for (int i = 0; i < priceFormatted.length; i++) {
      if (priceFormatted[i] == '.' || priceFormatted[i] == ',') {
        estimatedDots += 12;
      } else if (priceFormatted[i] == 'T' || priceFormatted[i] == 'L') {
        estimatedDots += 20; 
      } else {
        estimatedDots += 24;
      }
    }
    
    final maxPriceRight = boxX2 - 24; 
    final priceX = (maxPriceRight - estimatedDots).clamp(minX, maxPriceRight);

    commands.writeln('TEXT $priceX,$sharedY,"4",0,$priceScaleX,$priceScaleY,"$priceFormatted"');
    commands.writeln('TEXT ${priceX + 1},$sharedY,"4",0,$priceScaleX,$priceScaleY,"$priceFormatted"');

    // Convert text commands first
    resultBuffer.add(latin1.encode(commands.toString().replaceAll('\n', '\r\n')));
    commands.clear();

    // Embed binary logo BITMAP safely after text commands if present
    if (hasLogo && logoData != null) {
      final logoBytes = _buildLogoBitmapBytes(logoData, logoX: logoX, logoY: logoY);
      resultBuffer.add(logoBytes);
    }

    // Print command at the very end
    final printCmd = 'PRINT ${copies.clamp(1, 20)},1\r\n';
    resultBuffer.add(latin1.encode(printCmd));
    
    // Add 2mm manual feed at the end for gapless tearing (16 dots = 2mm at 203dpi)
    resultBuffer.add(latin1.encode('FEED 16\r\n'));

    return resultBuffer.toBytes();
  }

  /// Generates TSPL commands specifically for Order Package / Kitchen / Item labels.
  ///
  /// Does NOT print logos, shelf prices, or store tags.
  /// Focuses purely on Order ID, Customer ("kimin"), Product & Quantity ("ürünler"), and Order Barcode.
  static List<int> generateOrderLabelBytes({
    required String orderIdShort,
    required String customerName,
    required List<Map<String, dynamic>> items,
    String? orderNotes,
    DateTime? timestamp,
    int widthMm = 50,
    int heightMm = 30,
    int gapMm = 2,
    int dpi = 203,
    int copies = 1,
    String? customerPhone,
    double? totalAmount,
  }) {
    final safeDpi = dpi == 300 ? 300 : 203;
    final widthDots = (widthMm * safeDpi / 25.4).round();

    final timeStr = timestamp != null
        ? '${timestamp.day.toString().padLeft(2, '0')}.${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}'
        : '';
    final custClean = _ascii(customerName.trim());
    final noteClean = orderNotes != null && orderNotes.trim().isNotEmpty
        ? _ascii(orderNotes.trim())
        : null;

    final boxX1 = 4;
    final boxY1 = 4;
    final boxX2 = widthDots - 16; 
    
    final startX = boxX1 + 8;
    int currentY = boxY1 + 12;

    final bodyCmds = StringBuffer();

    // 1. Header: Sipariş No & Tarih (No logo)
    bodyCmds.writeln('TEXT $startX,$currentY,"2",0,1,1,"SIPARIS #$orderIdShort"');
    if (timeStr.isNotEmpty) {
      bodyCmds.writeln('TEXT ${boxX2 - 130},$currentY,"1",0,1,1,"$timeStr"');
    }
    currentY += 24;

    // 2. Customer Info ("Kimin")
    final whoText = custClean.isNotEmpty ? 'Musteri: $custClean' : 'Musteri: Genel';
    bodyCmds.writeln('TEXT $startX,$currentY,"2",0,1,1,"$whoText"');
    currentY += 24;
    if (customerPhone != null && customerPhone.isNotEmpty) {
      final phoneClean = _ascii(customerPhone);
      bodyCmds.writeln('TEXT $startX,$currentY,"2",0,1,1,"Tel: $phoneClean"');
      currentY += 24;
    }

    // 3. Separator Line
    bodyCmds.writeln('BAR $startX,$currentY,${boxX2 - startX - 8},2');
    currentY += 12;

    // 4. Products & Quantities
    for (final item in items) {
      final name = item['product_name']?.toString().trim().isNotEmpty == true
          ? item['product_name'].toString()
          : item['product_id']?.toString() ?? 'Ürün';
      final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
      
      final qtyStr = qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(1);
      final prodClean = _ascii(name.trim());
      final itemTitle = '$qtyStr x $prodClean';

      if (itemTitle.length <= 18) {
        bodyCmds.writeln('TEXT $startX,$currentY,"3",0,1,1,"$itemTitle"');
        currentY += 32;
      } else {
        final lines = _wrapProductName(itemTitle, 24);
        for (final line in lines) {
          bodyCmds.writeln('TEXT $startX,$currentY,"2",0,1,1,"$line"');
          currentY += 24;
        }
      }
      
      final itemNote = item['note']?.toString();
      if (itemNote != null && itemNote.trim().isNotEmpty) {
        final itemNoteLines = _wrapProductName("  Not: ${_ascii(itemNote.trim())}", 30);
        for (final nLine in itemNoteLines) {
           bodyCmds.writeln('TEXT $startX,$currentY,"1",0,1,1,"$nLine"');
           currentY += 20;
        }
      }
    }

    if (totalAmount != null && totalAmount > 0) {
      bodyCmds.writeln('TEXT $startX,$currentY,"2",0,1,1,"Toplam: ${totalAmount.toStringAsFixed(2)} TL"');
      currentY += 24;
    }

    if (noteClean != null) {
      final noteLines = _wrapProductName("Siparis Notu: $noteClean", 30);
      for (final nLine in noteLines) {
        bodyCmds.writeln('TEXT $startX,$currentY,"1",0,1,1,"$nLine"');
        currentY += 20;
      }
    }

    // 5. Order QR Code / Footer at Bottom Left
    currentY += 16;
    final barcodeY = currentY;
    final cleanBarcode = _barcode(orderIdShort);
    if (cleanBarcode.isNotEmpty) {
      bodyCmds.writeln(
        'QRCODE $startX,$barcodeY,M,4,A,0,"$cleanBarcode"',
      );
      bodyCmds.writeln('TEXT ${boxX2 - 120},${barcodeY + 30},"2",0,1,1,"#$orderIdShort"');
      currentY += 180; // Massive safety buffer for QR Code to prevent height clipping
    }

    final boxY2 = currentY + 16;
    final heightDots = boxY2 + 32; // Extra Tear gap padding
    final safeHeight = (heightDots * 25.4 / safeDpi).ceil(); // Use integer mm to prevent TSPL decimal parsing issues

    final headCmds = StringBuffer()
      ..writeln('SIZE $widthMm mm,$safeHeight mm')
      ..writeln('GAP 0,0') // Gapless (continuous)
      ..writeln('DENSITY 8')
      ..writeln('DIRECTION 0')
      ..writeln('REFERENCE 0,0')
      ..writeln('CLS')
      ..writeln('BOX $boxX1,$boxY1,$boxX2,$boxY2,3');

    final finalString = headCmds.toString() + bodyCmds.toString() + 'PRINT ${copies.clamp(1, 20)},1\nFEED 16\n';
    return latin1.encode(finalString.replaceAll('\n', '\r\n'));
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
    return value.split('').map((char) => replacements[char] ?? char).join().replaceAll(',', '');
  }

  static _TsplLogoData? _prepareTsplLogoData({
    required String logoPath,
    required int labelWidthDots,
    required int labelHeightDots,
  }) {
    final trimmed = logoPath.trim();
    if (trimmed.isEmpty) return null;

    Uint8List? rawBytes;
    try {
      if (trimmed.startsWith('data:image/')) {
        final comma = trimmed.indexOf(',');
        if (comma != -1) {
          rawBytes = base64Decode(trimmed.substring(comma + 1));
        }
      } else if (File(trimmed).existsSync()) {
        rawBytes = File(trimmed).readAsBytesSync();
      }
    } catch (_) {
      return null;
    }

    if (rawBytes == null || rawBytes.isEmpty) return null;

    try {
      final image = img.decodeImage(rawBytes);
      if (image == null) return null;

      final maxW = (labelWidthDots * 0.30).round().clamp(24, 120);
      final maxH = (labelHeightDots * 0.14).round().clamp(12, 40);

      var targetW = maxW;
      var targetH = (image.height * targetW / image.width).round();
      if (targetH > maxH) {
        targetH = maxH;
        targetW = (image.width * targetH / image.height).round();
      }

      final resized = img.copyResize(image, width: targetW, height: targetH);
      final widthBytes = (resized.width + 7) ~/ 8;
      final heightDots = resized.height;

      final bitmapData = Uint8List(widthBytes * heightDots);

      for (int y = 0; y < heightDots; y++) {
        for (int xByte = 0; xByte < widthBytes; xByte++) {
          int byteVal = 0;
          for (int bit = 0; bit < 8; bit++) {
            final x = xByte * 8 + bit;
            if (x < resized.width) {
              final pixel = resized.getPixel(x, y);
              final isTransparent = pixel.a < 128;
              final luma = isTransparent ? 255 : img.getLuminance(pixel);
              // TSPL BITMAP: 1 = white paper, 0 = black thermal ink
              if (luma >= 128) {
                byteVal |= (0x80 >> bit);
              }
            } else {
              byteVal |= (0x80 >> bit);
            }
          }
          bitmapData[y * widthBytes + xByte] = byteVal;
        }
      }

      return _TsplLogoData(
        bitmapData: bitmapData,
        widthBytes: widthBytes,
        heightDots: heightDots,
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List _buildLogoBitmapBytes(
    _TsplLogoData logoData, {
    required int logoX,
    required int logoY,
  }) {
    final header = 'BITMAP $logoX,$logoY,${logoData.widthBytes},${logoData.heightDots},0,';
    final builder = BytesBuilder();
    builder.add(latin1.encode(header));
    builder.add(logoData.bitmapData);
    builder.add(latin1.encode('\r\n'));
    return builder.toBytes();
  }
}

class _TsplLogoData {
  final Uint8List bitmapData;
  final int widthBytes;
  final int heightDots;
  int get widthDots => widthBytes * 8;

  _TsplLogoData({
    required this.bitmapData,
    required this.widthBytes,
    required this.heightDots,
  });
}
