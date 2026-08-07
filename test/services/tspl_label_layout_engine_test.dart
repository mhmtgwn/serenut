import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/label_model.dart';
import 'package:serenutos/domain/services/tspl_label_layout_engine.dart';

void main() {
  LabelModel productLabel({String? barcode}) => LabelModel(
        productName: 'Uzun Ürün Adı ve Çeşidi',
        brand: 'Örnek Marka',
        unit: 'adet',
        shelfCode: 'A-12',
        businessName: 'Şaman Market',
        weight: 1,
        price: 123.45,
        barcode: barcode ?? '869000000001',
        qrData: 'product-test',
        timestamp: DateTime(2026, 7, 30),
      );

  test('50x30 mm TSPL etiketi fiziksel boyut ve aralıkla sınırlar', () {
    final output = latin1.decode(
      TsplLabelLayoutEngine.generateLabelBytes(
        productLabel(),
        widthMm: 50,
        heightMm: 30,
        gapMm: 2,
        dpi: 203,
        copies: 2,
      ),
    );

    expect(output, startsWith('SIZE 50 mm,30 mm\r\nGAP 2 mm,0 mm\r\n'));
    expect(output, contains('CLS\r\n'));
    expect(output, contains(',0,0,1,2,"869000000001"'));
    expect(output, endsWith('PRINT 2,1\r\n'));
    expect(output, isNot(contains('\x1dV')));
  });

  test('gap otomatik algılama yazıcının kendi ölçümüne bırakılır', () {
    final output = latin1.decode(TsplLabelLayoutEngine.generateLabelBytes(
      productLabel(),
      autoDetectGap: true,
    ));

    expect(
      output,
      startsWith(
        'SIZE 50 mm,30 mm\r\nGAP 2 mm,0 mm\r\nGAPDETECT\r\n',
      ),
    );
  });

  test('300 DPI ve farklı rulo ölçüsü komutlara doğru yansır', () {
    final output = latin1.decode(
      TsplLabelLayoutEngine.generateLabelBytes(
        productLabel(),
        widthMm: 60,
        heightMm: 40,
        gapMm: 3,
        dpi: 300,
      ),
    );

    expect(output, startsWith('SIZE 60 mm,40 mm\r\nGAP 3 mm,0 mm\r\n'));
    expect(output, endsWith('PRINT 1,1\r\n'));
  });

  test('Türkçe ve uzun metin yazıcı güvenli biçime çevrilir', () {
    final output = latin1.decode(
      TsplLabelLayoutEngine.generateLabelBytes(
        productLabel(barcode: '8690 geçersiz çok uzun barkod değeri 123456789'),
      ),
    );

    expect(output, contains('Uzun Urun Adi'));
    expect(output, contains('Cesidi'));
    expect(output, contains('"3",0,1,2'));
    expect(output, isNot(contains('BARCODE ')));
    expect(output, contains('"4",0,1,1,"TL 123.45"'));
    expect(output, isNot(contains('Ü')));
    expect(output, isNot(contains('geçersiz')));
  });

  test('ürün etiketi referans hiyerarşisinde büyük ad ve bölünmüş fiyat üretir',
      () {
    final output = latin1.decode(
      TsplLabelLayoutEngine.generateLabelBytes(
        LabelModel(
          productName: 'Kisa Urun',
          businessName: 'Serenut OS',
          weight: 1,
          price: 299.95,
          barcode: '1234567890',
          qrData: 'product-test',
          timestamp: DateTime(2026, 7, 30),
        ),
        widthMm: 50,
        heightMm: 30,
        showBrand: false,
        showVat: false,
      ),
    );

    expect(output, contains('"2",0,3,3,"Kisa Urun"'));
    expect(output, isNot(contains('Kod:')));
    expect(output, contains('"3",0,2,2,"299,95"'));
    expect(output, contains('"2",0,1,1,"TL"'));
    expect(output, isNot(contains('TL 299.95')));
  });

  test('paket logosu TSPL ürün etiketine bitmap olarak eklenir', () {
    final logoBytes = File('assets/logo.png').readAsBytesSync();
    final bytes = TsplLabelLayoutEngine.generateLabelBytes(
      productLabel(),
      logoBytes: logoBytes,
    );
    final output = latin1.decode(bytes);

    expect(output, contains('BITMAP '));
    expect(output, isNot(matches(RegExp(r'BITMAP[^\r\n]+,[0-9A-F]{100,}'))));
    expect(output, isNot(contains('TEXT 128,6,"2",0,1,1,"Saman Market"')));
  });

  test('uzun kimlik ve büyük fiyat ürün etiketinin sağından taşmaz', () {
    final output = latin1.decode(
      TsplLabelLayoutEngine.generateLabelBytes(
        LabelModel(
          productName: 'CokUzunTekParcaUrunAdiEtiketSiniriniAsamaz',
          businessName: 'Serenut OS',
          weight: 1,
          price: 1234567.89,
          barcode: '550e8400-e29b-41d4-a716-446655440000',
          qrData: 'product-test',
          timestamp: DateTime(2026, 7, 30),
        ),
        widthMm: 50,
        heightMm: 30,
      ),
    );

    expect(output, isNot(contains('BARCODE ')));
    expect(output, contains('"4",0,1,1,"TL 1234567.89"'));
    expect(
        output, isNot(contains('CokUzunTekParcaUrunAdiEtiketSiniriniAsamaz')));
  });

  test('30 mm ürün etiketindeki tüm metinler sağ sınırın içinde kalır', () {
    final output = latin1.decode(
      TsplLabelLayoutEngine.generateLabelBytes(
        LabelModel(
          productName: 'Cok Uzun Tek Parca Urun Adi',
          businessName: 'Serenut OS',
          weight: 1,
          price: 299.95,
          barcode: '1234567890',
          qrData: 'product-narrow',
          timestamp: DateTime(2026, 8, 4),
        ),
        widthMm: 30,
        heightMm: 30,
        showBrand: false,
        showVat: false,
      ),
    );

    const widthDots = 240;
    final textPattern =
        RegExp(r'TEXT (\d+),\d+,"([1-4])",0,(\d+),(\d+),"([^"]*)"');
    const charWidths = {'1': 8, '2': 12, '3': 16, '4': 24};
    for (final match in textPattern.allMatches(output)) {
      final x = int.parse(match.group(1)!);
      final font = match.group(2)!;
      final xMultiplier = int.parse(match.group(3)!);
      final text = match.group(5)!;
      final rightEdge = x + text.length * charWidths[font]! * xMultiplier;
      expect(rightEdge, lessThanOrEqualTo(widthDots),
          reason: 'Metin sağdan taşıyor: $text ($rightEdge > $widthDots)');
    }
    expect(output, isNot(contains('Kod:')));
  });

  test('sipariş etiketi yalnızca Latin-1 uyumlu TSPL üretir', () {
    final bytes = TsplLabelLayoutEngine.generateOrderLabelBytes(
      orderIdShort: 'order-123',
      customerName: 'Şaman Müşteri',
      productName: 'Çeşitli Ürün',
      quantity: 2,
      items: const [
        {
          'product_name': 'Örnek Ürün',
          'quantity': 2.0,
        },
      ],
      itemsCount: 1,
      totalAmount: 20,
      businessName: 'Şaman Market',
    );
    final output = latin1.decode(bytes);

    expect(output, isNot(contains('Parca Urun / Paket')));
    expect(output, contains('QRCODE '));
    expect(output, isNot(contains('BARCODE ')));
    expect(output, contains('- 2x Ornek Urun'));
    expect(output, contains('DIRECTION 0'));
    expect(output, isNot(contains('•')));
    expect(output, endsWith('PRINT 1,1\r\n'));
  });

  test('sipariş etiketi gapsız medyada tüm ürünler için dinamik uzar', () {
    final output = latin1.decode(
      TsplLabelLayoutEngine.generateOrderLabelBytes(
        orderIdShort: 'ORD-2026-42',
        customerName: 'Test Musteri',
        productName: '4 Urun',
        quantity: 1,
        timestamp: DateTime(2026, 8, 6, 15, 45),
        items: const [
          {'product_name': 'Elma', 'quantity': 2.0, 'unit_price': 12.5},
          {'product_name': 'Armut', 'quantity': 1.0, 'unit_price': 20.0},
          {'product_name': 'Muz', 'quantity': 3.0, 'unit_price': 10.0},
          {'product_name': 'Erik', 'quantity': 1.0, 'unit_price': 5.0},
        ],
        itemsCount: 4,
        totalAmount: 80,
        widthMm: 58,
        heightMm: 30,
        gapMm: 0,
        logoBytes: File('assets/logo.png').readAsBytesSync(),
      ),
    );

    final order =
        RegExp(r'TEXT \d+,(\d+),"1",0,1,1,"SIPARIS').firstMatch(output);
    final date =
        RegExp(r'TEXT \d+,(\d+),"1",0,1,1,"06\.08 15:45"').firstMatch(output);
    expect(order, isNotNull);
    expect(date, isNotNull);
    expect(
        int.parse(date!.group(1)!), greaterThan(int.parse(order!.group(1)!)));
    expect(output, contains('- 2x Elma TL25.00'));
    expect(output, contains('- 1x Armut TL20.00'));
    expect(output, contains('- 3x Muz TL30.00'));
    expect(output, contains('- 1x Erik TL5.00'));
    expect(output, isNot(contains(' +1')));
    expect(output, contains('GAP 0 mm,0 mm'));
    expect(output, isNot(contains('GAPDETECT')));
    final size = RegExp(r'SIZE 58 mm,(\d+) mm').firstMatch(output);
    expect(size, isNotNull);
    expect(int.parse(size!.group(1)!), greaterThan(30));
  });

  test('sipariş etiketinde 10+ ürün kesilmeden yazdırılır ve kağıt boyu dinamik uzar', () {
    final items = List.generate(
      12,
      (i) => {
        'product_name': 'Ürün $i',
        'quantity': (i + 1).toDouble(),
        'unit_price': 10.0 * (i + 1),
      },
    );
    final output = latin1.decode(
      TsplLabelLayoutEngine.generateOrderLabelBytes(
        orderIdShort: 'ORD-MANY-12',
        customerName: 'Ahmet Yilmaz',
        productName: '12 Urun',
        quantity: 1,
        items: items,
        itemsCount: 12,
        totalAmount: 1500,
        widthMm: 58,
        heightMm: 30,
      ),
    );

    for (var i = 0; i < 12; i++) {
      expect(output, contains('Urun $i'));
    }
    expect(output, contains('TOPLAM: TL 1500.00'));
    final sizeMatch = RegExp(r'SIZE 58 mm,(\d+) mm').firstMatch(output);
    expect(sizeMatch, isNotNull);
    expect(int.parse(sizeMatch!.group(1)!), greaterThan(50));
  });
}
