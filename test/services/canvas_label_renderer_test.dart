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

    // Verify background polarity: In TSPL 1=white (unburned), 0=black (burned).
    // The majority of bytes must be 0xFF (white background), NOT 0x00 (pitch black).
    const bitmapPrefix = 'BITMAP 0,0,48,240,0,';
    final bitmapIndex = output.indexOf(bitmapPrefix);
    expect(bitmapIndex, isNonNegative);
    final rasterStart = bitmapIndex + bitmapPrefix.length;
    final rasterData = bytes.sublist(rasterStart, rasterStart + (48 * 240));
    final whiteBytes = rasterData.where((b) => b == 0xFF).length;
    const totalBytes = 48 * 240;
    // White background must account for >70% of the label bytes
    expect(whiteBytes / totalBytes, greaterThan(0.70));
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
    // On 30mm label, 4 items must be split into 2 separate label prints so item 4 doesn't bleed into gap
    final printCount = RegExp(r'PRINT 1,1').allMatches(output).length;
    final bitmapCount = RegExp(r'BITMAP 0,0,48,').allMatches(output).length;
    expect(printCount, equals(2));
    expect(bitmapCount, equals(2));
  });
}
