import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/printing/label_dimension_models.dart';
import 'package:serenutos/domain/services/tspl_canvas_label_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DynamicLabelSizeEngine - Measurement & Decision', () {
    test('40x30 media with small content stays on 1 page', () {
      const media = MediaProfile(widthMm: 40, heightMm: 30, gapMm: 2, dpi: 203);
      final contentSize = DynamicLabelSizeEngine.measureOrderContent(
        mediaProfile: media,
        orderIdShort: '101',
        customerName: 'Ali',
        productName: 'Su',
        quantity: 1.0,
      );

      final target = DynamicLabelSizeEngine.determineTargetSize(
        contentSize: contentSize,
        mediaProfile: media,
      );

      expect(target.widthMm, equals(40.0));
      expect(target.heightMm, equals(30.0));
      expect(target.pagesCount, equals(1));
      expect(target.isMultiPage, isFalse);
      expect(target.mode, equals(MediaMode.gap));
    });

    test('50x30 media with small content fits 1 page', () {
      const media = MediaProfile(widthMm: 50, heightMm: 30, gapMm: 2, dpi: 203);
      final contentSize = DynamicLabelSizeEngine.measureOrderContent(
        mediaProfile: media,
        orderIdShort: '202',
        customerName: 'Ayşe',
        productName: 'Kahve',
        quantity: 1.0,
      );

      final target = DynamicLabelSizeEngine.determineTargetSize(
        contentSize: contentSize,
        mediaProfile: media,
      );

      expect(target.widthMm, equals(50.0));
      expect(target.heightMm, equals(30.0));
      expect(target.pagesCount, equals(1));
      expect(target.isMultiPage, isFalse);
    });

    test('80x40 media with 2 small items fits in 1 single 80x40 page', () {
      const media = MediaProfile(widthMm: 80, heightMm: 40, gapMm: 2, dpi: 203);
      final items = [
        {'product_name': 'Danone Puding', 'quantity': 2.0, 'unit_price': 35.0},
        {'product_name': 'Yulaf Bar', 'quantity': 1.0, 'unit_price': 22.5},
      ];

      final contentSize = DynamicLabelSizeEngine.measureOrderContent(
        mediaProfile: media,
        orderIdShort: '303',
        customerName: 'Ahmet',
        productName: '2 Ürün',
        items: items,
        totalAmount: 92.5,
      );

      final target = DynamicLabelSizeEngine.determineTargetSize(
        contentSize: contentSize,
        mediaProfile: media,
      );

      expect(target.widthMm, equals(80.0));
      expect(target.heightMm, equals(40.0));
      expect(target.pagesCount, equals(1));
      expect(target.isMultiPage, isFalse);
    });

    test('80x40 media with 8 items requires pagination', () {
      const media = MediaProfile(widthMm: 80, heightMm: 40, gapMm: 2, dpi: 203);
      final items = List.generate(
        8,
        (i) => {
          'product_name': 'Ürün Kalemi No $i',
          'quantity': 1.0,
          'unit_price': 50.0,
        },
      );

      final contentSize = DynamicLabelSizeEngine.measureOrderContent(
        mediaProfile: media,
        orderIdShort: '404',
        customerName: 'Mehmet',
        productName: '8 Ürün',
        items: items,
        totalAmount: 400.0,
      );

      final target = DynamicLabelSizeEngine.determineTargetSize(
        contentSize: contentSize,
        mediaProfile: media,
      );

      expect(target.widthMm, equals(80.0));
      expect(target.heightMm, equals(40.0));
      expect(target.isMultiPage, isTrue);
      expect(target.pagesCount, greaterThanOrEqualTo(2));
    });

    test('80x80 media keeps 6 items on single 80x80 page without artificial split', () {
      const media = MediaProfile(widthMm: 80, heightMm: 80, gapMm: 2, dpi: 203);
      final items = List.generate(
        6,
        (i) => {
          'product_name': 'Geniş Sipariş Ürünü $i',
          'quantity': 1.0,
          'unit_price': 40.0,
        },
      );

      final contentSize = DynamicLabelSizeEngine.measureOrderContent(
        mediaProfile: media,
        orderIdShort: '505',
        customerName: 'Can',
        productName: '6 Ürün',
        items: items,
        totalAmount: 240.0,
      );

      final target = DynamicLabelSizeEngine.determineTargetSize(
        contentSize: contentSize,
        mediaProfile: media,
      );

      expect(target.widthMm, equals(80.0));
      expect(target.heightMm, equals(80.0));
      expect(target.pagesCount, equals(1));
      expect(target.isMultiPage, isFalse);
    });

    test('100x80 media keeps large content on single 100x80 page', () {
      const media = MediaProfile(widthMm: 100, heightMm: 80, gapMm: 2, dpi: 203);
      final items = List.generate(
        5,
        (i) => {
          'product_name': 'Paketli Toptan Ürün Kalemi $i',
          'quantity': 3.0,
          'unit_price': 120.0,
        },
      );

      final contentSize = DynamicLabelSizeEngine.measureOrderContent(
        mediaProfile: media,
        orderIdShort: '606',
        customerName: 'Toptan Müşteri',
        productName: '5 Ürün',
        items: items,
        totalAmount: 1800.0,
      );

      final target = DynamicLabelSizeEngine.determineTargetSize(
        contentSize: contentSize,
        mediaProfile: media,
      );

      expect(target.widthMm, equals(100.0));
      expect(target.heightMm, equals(80.0));
      expect(target.pagesCount, equals(1));
    });

    test('Continuous media (gapMm=0) expands height dynamically without pagination', () {
      const media = MediaProfile(widthMm: 80, heightMm: 40, gapMm: 0, dpi: 203);
      final items = List.generate(
        10,
        (i) => {
          'product_name': 'Sürekli Rulo Ürünü $i',
          'quantity': 1.0,
          'unit_price': 25.0,
        },
      );

      final contentSize = DynamicLabelSizeEngine.measureOrderContent(
        mediaProfile: media,
        orderIdShort: '707',
        customerName: 'Sürekli Müşteri',
        productName: '10 Ürün',
        items: items,
        totalAmount: 250.0,
      );

      final target = DynamicLabelSizeEngine.determineTargetSize(
        contentSize: contentSize,
        mediaProfile: media,
      );

      expect(target.widthMm, equals(80.0));
      expect(target.heightMm, greaterThan(40.0)); // Dynamically expanded!
      expect(target.pagesCount, equals(1)); // Always 1 continuous page
      expect(target.isMultiPage, isFalse);
      expect(target.mode, equals(MediaMode.continuous));
    });

    test('Continuous media sizes height cleanly for different content lengths', () {
      const media = MediaProfile(widthMm: 80, heightMm: 40, gapMm: 0, dpi: 203);

      // Short
      final shortContent = DynamicLabelSizeEngine.measureOrderContent(
        mediaProfile: media,
        orderIdShort: '801',
        customerName: 'Kısa',
        productName: '1 Ürün',
        quantity: 1,
      );
      final shortTarget = DynamicLabelSizeEngine.determineTargetSize(
        contentSize: shortContent,
        mediaProfile: media,
      );
      expect(shortTarget.heightMm, lessThanOrEqualTo(45.0));

      // Long
      final longItems = List.generate(
        15,
        (i) => {'product_name': 'Uzun Kalem $i', 'quantity': 1.0, 'unit_price': 10.0},
      );
      final longContent = DynamicLabelSizeEngine.measureOrderContent(
        mediaProfile: media,
        orderIdShort: '802',
        customerName: 'Uzun',
        productName: '15 Ürün',
        items: longItems,
      );
      final longTarget = DynamicLabelSizeEngine.determineTargetSize(
        contentSize: longContent,
        mediaProfile: media,
      );
      expect(longTarget.heightMm, greaterThan(70.0));
      expect(longTarget.pagesCount, equals(1));
    });

    test('Width boundary check: throws PrintLayoutException when content strictly exceeds narrow head bounds', () {
      const media = MediaProfile(widthMm: 50, heightMm: 30, gapMm: 2, dpi: 203);
      const invalidContent = ContentSize(
        widthMm: 75.0,
        heightMm: 25.0,
        totalHeightDots: 200,
        maxLineWidthDots: 600,
      );

      expect(
        () => DynamicLabelSizeEngine.determineTargetSize(
          contentSize: invalidContent,
          mediaProfile: media,
        ),
        throwsA(isA<PrintLayoutException>()),
      );
    });

    test('DPI scaling: 300 DPI scales dots accurately relative to mm', () {
      const media203 = MediaProfile(widthMm: 50, heightMm: 30, dpi: 203);
      const media300 = MediaProfile(widthMm: 50, heightMm: 30, dpi: 300);

      expect(media203.dotsPerMm, closeTo(7.99, 0.05));
      expect(media300.dotsPerMm, closeTo(11.81, 0.05));

      // 50mm on <=54mm clamped to 48mm: 384 dots @ 203 DPI, 567 dots @ 300 DPI
      expect(media203.maxPhysicalDots, equals(384));
      expect(media300.maxPhysicalDots, equals(567));
    });
  });

  group('TsplCanvasLabelEngine - Continuous & TargetPageSize Integration', () {
    test('Continuous media generates single TSPL label with dynamic height and GAP 0', () async {
      final items = List.generate(
        8,
        (i) => {
          'product_name': 'Sürekli Kağıt Ürünü $i',
          'quantity': 1.0,
          'unit_price': 15.0,
        },
      );

      const media = MediaProfile(widthMm: 80, heightMm: 40, gapMm: 0, dpi: 203);
      final contentSize = DynamicLabelSizeEngine.measureOrderContent(
        mediaProfile: media,
        orderIdShort: '9001',
        customerName: 'Ali Veli',
        productName: '8 Ürün',
        items: items,
        totalAmount: 120.0,
      );
      final target = DynamicLabelSizeEngine.determineTargetSize(
        contentSize: contentSize,
        mediaProfile: media,
      );

      final bytes = await TsplCanvasLabelEngine.generateOrderLabelBytes(
        orderIdShort: '9001',
        customerName: 'Ali Veli',
        productName: '8 Ürün',
        items: items,
        totalAmount: 120.0,
        widthMm: 80,
        heightMm: 40,
        gapMm: 0,
        targetPageSize: target,
      );

      final output = latin1.decode(bytes, allowInvalid: true);
      final printMatches = RegExp(r'PRINT 1,1').allMatches(output);

      // Exactly 1 seamless print command
      expect(printMatches.length, equals(1));
      expect(output, contains('GAP 0 mm,0 mm'));

      // Dynamic height reflected in SIZE command (greater than 40 mm)
      final sizeMatch = RegExp(r'SIZE 80 mm,(\d+) mm').firstMatch(output);
      expect(sizeMatch, isNotNull);
      final parsedH = int.parse(sizeMatch!.group(1)!);
      expect(parsedH, greaterThan(40));

      // No continuation banners
      expect(output, isNot(contains('DEVAMI')));
      // Contains QR code on the single page
      expect(output, contains('QRCODE '));
    });
  });
}
