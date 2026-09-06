import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/tspl_canvas_label_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Flutter Canvas renders 1-bit monochrome bitmap for TSPL', () async {
    const width = 400; // 50 mm @ 203 dpi
    const height = 240; // 30 mm @ 203 dpi

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    // White background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.white,
    );

    // Draw text with TextPainter
    final tp = TextPainter(
      text: const TextSpan(
        text: 'Sip #1042 - Ahmet Yilmaz',
        style: TextStyle(
          color: Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 360);

    tp.paint(canvas, const Offset(20, 20));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

    expect(byteData, isNotNull);
    expect(byteData!.lengthInBytes, width * height * 4);
    expect(image.width, width);
    expect(image.height, height);
  });

  test('TsplCanvasLabelEngine generates valid TSPL bitmap commands with pagination', () async {
    final items = List.generate(
      6,
      (i) => {
        'product_name': 'Kaliteli Fındık Ürünü $i',
        'quantity': 2.0,
        'unit_price': 85.0,
      },
    );

    final bytes = await TsplCanvasLabelEngine.generateOrderLabelBytes(
      orderIdShort: '1042',
      customerName: 'Ahmet Yılmaz',
      customerPhone: '0532 123 45 67',
      productName: '6 Ürün',
      quantity: 1,
      items: items,
      totalAmount: 1020.0,
      widthMm: 80,
      heightMm: 40,
      gapMm: 2,
    );

    final output = latin1.decode(bytes, allowInvalid: true);
    expect(output, contains('SIZE 80 mm,40 mm'));
    expect(output, contains('GAP 2 mm,0 mm'));
    expect(output, contains('BITMAP 0,0,'));
    expect(output, contains('PRINT 1,1'));
  });

  test('TsplCanvasLabelEngine clamps width to 384 dots (48 bytes) for <=54mm printheads and inverts polarity for TSPL', () async {
    final bytes = await TsplCanvasLabelEngine.generateOrderLabelBytes(
      orderIdShort: '2001',
      customerName: 'Mehmet Demir',
      productName: 'Fındık',
      quantity: 1,
      totalAmount: 150.0,
      widthMm: 50,
      heightMm: 30,
      gapMm: 2,
    );

    final output = latin1.decode(bytes, allowInvalid: true);
    expect(output, contains('SIZE 50 mm,30 mm'));
    // 384 dots / 8 = 48 bytes. Must be BITMAP 0,0,48,240,0, NOT 50 bytes!
    expect(output, contains('BITMAP 0,0,48,'));
    expect(output, contains('PRINT 1,1'));

    // Verify background polarity: In TSPL BITMAP mode 0: 1=white (unburned), 0=black (burned).
    // The majority of bytes must be 0xFF (white background), NOT 0x00 (pitch black).
    const bitmapPrefix = 'BITMAP 0,0,48,240,0,';
    final bitmapIndex = output.indexOf(bitmapPrefix);
    expect(bitmapIndex, isNonNegative);
    final rasterStart = bitmapIndex + bitmapPrefix.length;
    final rasterData = bytes.sublist(rasterStart, rasterStart + (48 * 240));
    final whiteBytes = rasterData.where((b) => b == 0xFF).length;
    const totalBytes = 48 * 240;
    // White background (0xFF) must account for >65% of the label bytes
    expect(whiteBytes / totalBytes, greaterThan(0.65));
  });

  test('TsplCanvasLabelEngine positions QR code safely inside 50x30mm bounds without clipping', () async {
    final bytes = await TsplCanvasLabelEngine.generateOrderLabelBytes(
      orderIdShort: '2001',
      customerName: 'Mehmet Demir',
      productName: 'Fındık',
      quantity: 1,
      totalAmount: 150.0,
      widthMm: 50,
      heightMm: 30,
      gapMm: 2,
      qrData: 'order|2001',
    );

    final output = latin1.decode(bytes, allowInvalid: true);
    expect(output, contains('QRCODE '));
    final match = RegExp(r'QRCODE\s+(\d+),(\d+),').firstMatch(output);
    expect(match, isNotNull);
    final qrX = int.parse(match!.group(1)!);
    final qrY = int.parse(match.group(2)!);
    // On 50mm (384 dots width), QR X must be <= 300 to leave safe clearance before 384
    expect(qrX, lessThanOrEqualTo(300));
    // On 30mm (240 dots height), QR Y must be <= 160 to leave safe clearance before 240
    expect(qrY, lessThanOrEqualTo(160));
  });

  test('TsplCanvasLabelEngine splits 4 items across multiple pages on 30mm label to prevent gap overflow', () async {
    final items = [
      {'product_name': 'Findik Ezmesi 350g', 'quantity': 1.0, 'unit_price': 120.0},
      {'product_name': 'Kavrulmus Findik 500g', 'quantity': 2.0, 'unit_price': 250.0},
      {'product_name': 'Cig Findik 1kg', 'quantity': 1.0, 'unit_price': 300.0},
      {'product_name': 'Findik Unu 250g', 'quantity': 3.0, 'unit_price': 90.0},
    ];

    final bytes = await TsplCanvasLabelEngine.generateOrderLabelBytes(
      orderIdShort: '4004',
      customerName: 'Ahmet Kaya',
      customerPhone: '0544 333 22 11',
      productName: '4 Urun',
      quantity: 1,
      items: items,
      totalAmount: 1190.0,
      widthMm: 50,
      heightMm: 30,
      gapMm: 2,
    );

    final output = latin1.decode(bytes, allowInvalid: true);
    // On 30mm label, 4 items must be split across pages so no item bleeds into gap
    final printCount = RegExp(r'PRINT 1,1').allMatches(output).length;
    final bitmapCount = RegExp(r'BITMAP 0,0,48,').allMatches(output).length;
    expect(printCount, inInclusiveRange(2, 3));
    expect(bitmapCount, inInclusiveRange(2, 3));
  });

  test('TsplCanvasLabelEngine emits QRCODE on final page and prints in forward order', () async {
    final items = List.generate(
      14,
      (i) => {
        'product_name': 'Paket Ürün No $i',
        'quantity': 1.0,
        'unit_price': 50.0,
      },
    );

    final bytes = await TsplCanvasLabelEngine.generateOrderLabelBytes(
      orderIdShort: 'SP-109',
      customerName: 'Mustafa Bey',
      customerPhone: '0538 000 11 22',
      productName: '14 Ürün',
      quantity: 1,
      items: items,
      totalAmount: 700.0,
      widthMm: 80,
      heightMm: 40,
      gapMm: 2,
      qrData: 'order|SP-109|700.0',
    );

    final output = latin1.decode(bytes, allowInvalid: true);
    // Must contain TSPL QRCODE command
    expect(output, contains('QRCODE '));
    expect(output, contains('"order|SP-109|700.0"'));

    // Check forward page order: multiple pages generated, QRCODE emitted only on the final page
    final firstBitmap = output.indexOf('BITMAP 0,0,');
    final secondBitmap = output.indexOf('BITMAP 0,0,', firstBitmap + 1);
    expect(firstBitmap, isNonNegative);
    expect(secondBitmap, isNonNegative);

    final qrIndex = output.indexOf('QRCODE ');
    expect(qrIndex, greaterThan(secondBitmap));
  });

  test('TsplCanvasLabelEngine keeps 2 items on single 80x40mm page without artificial split', () async {
    final items = [
      {'product_name': 'Danone Çikolatalı Puding 375g', 'quantity': 2.0, 'unit_price': 35.0},
      {'product_name': 'Eti Lifalif Yulaf Bar 105g', 'quantity': 1.0, 'unit_price': 22.5},
    ];

    final bytes = await TsplCanvasLabelEngine.generateOrderLabelBytes(
      orderIdShort: 'SP-200',
      customerName: 'Ahmet Yılmaz',
      productName: '2 Ürün',
      items: items,
      totalAmount: 92.5,
      widthMm: 80,
      heightMm: 40,
      gapMm: 2,
    );

    final output = latin1.decode(bytes, allowInvalid: true);
    final printCount = RegExp(r'PRINT 1,1').allMatches(output).length;
    // Exactly 1 page on 80x40 mm!
    expect(printCount, equals(1));
    expect(output, contains('QRCODE '));
  });

  test('overflow keeps every continuation page at the selected 80x80mm media size',
      () async {
    final items = List.generate(
      36,
      (index) => {
        'product_name': 'Uzun açıklamalı sipariş ürünü numara $index',
        'quantity': 1.0,
        'unit_price': 10.0,
      },
    );

    final bytes = await TsplCanvasLabelEngine.generateOrderLabelBytes(
      orderIdShort: 'ORD-8080',
      customerName: 'Ölçü Test Müşteri',
      productName: '36 Ürün',
      items: items,
      totalAmount: 360,
      widthMm: 80,
      heightMm: 80,
      gapMm: 3,
    );

    final output = latin1.decode(bytes, allowInvalid: true);
    final pageCount = RegExp(r'PRINT 1,1').allMatches(output).length;
    final sizeCount = RegExp(r'SIZE 80 mm,80 mm').allMatches(output).length;
    expect(pageCount, greaterThan(1));
    expect(sizeCount, pageCount);
    expect(RegExp(r'GAP 3 mm,0 mm').allMatches(output).length, pageCount);
  });

  test('TsplCanvasLabelEngine ensures QR code has at least 40 dots safe clearance on right edge of 50mm label', () async {
    final bytes = await TsplCanvasLabelEngine.generateOrderLabelBytes(
      orderIdShort: 'ORD-9999',
      customerName: 'Test Müşteri',
      productName: 'Fındık 500g',
      quantity: 1,
      totalAmount: 200.0,
      widthMm: 50,
      heightMm: 30,
      gapMm: 2,
      printableWidthDots: 400, // Even if 400 dots requested from settings
    );

    final output = latin1.decode(bytes, allowInvalid: true);
    expect(output, contains('BITMAP 0,0,48,')); // Clamped to 384 dots (48 bytes)
    final match = RegExp(r'QRCODE\s+(\d+),(\d+),').firstMatch(output);
    expect(match, isNotNull);
    final qrX = int.parse(match!.group(1)!);
    // At cell width 2 and 29 modules (58 dots), QR ending edge (qrX + 58) must be <= 344
    expect(qrX, lessThanOrEqualTo(270));
    expect(qrX + 58, lessThanOrEqualTo(344));
  });

  test('TsplCanvasLabelEngine splits 2 items across 2 pages when closing footer causes overflow', () async {
    final items = [
      {'product_name': 'Findik Ezmesi 350g', 'quantity': 1.0, 'unit_price': 120.0},
      {'product_name': 'Kavrulmus Findik 500g', 'quantity': 2.0, 'unit_price': 250.0},
    ];

    final bytes = await TsplCanvasLabelEngine.generateOrderLabelBytes(
      orderIdShort: '4002',
      customerName: 'Ahmet Kaya',
      customerPhone: '0544 333 22 11',
      productName: '2 Urun',
      quantity: 1,
      items: items,
      totalAmount: 620.0,
      widthMm: 50,
      heightMm: 30,
      gapMm: 2,
    );

    final output = latin1.decode(bytes, allowInvalid: true);
    final printMatches = RegExp(r'PRINT 1,1').allMatches(output);
    expect(printMatches.length, equals(2));

    final bitmapMatches = RegExp(r'BITMAP 0,0,48,240,0,').allMatches(output);
    expect(bitmapMatches.length, equals(2));

    // Page 1 is continuation (no QR code), Page 2 has the closing footer with QRCODE
    final p1Section = output.substring(0, printMatches.first.end);
    final p2Section = output.substring(printMatches.first.end);
    expect(p1Section, isNot(contains('QRCODE')));
    expect(p2Section, contains('QRCODE'));
  });
}


