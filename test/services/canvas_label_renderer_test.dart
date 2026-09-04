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

  test('TsplCanvasLabelEngine clamps width to 384 dots (48 bytes) for <=54mm printheads', () async {
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
  });
}
