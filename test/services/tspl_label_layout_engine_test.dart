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
    expect(output, contains('BARCODE '));
    expect(output, endsWith('PRINT 2,1\r\n'));
    expect(output, isNot(contains('\x1dV')));
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
    expect(output, contains('"2",0,1,1'));
    expect(output, isNot(contains('BARCODE ')));
    expect(output, contains('"3",0,1,1,"TL 123.45"'));
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

    expect(output, contains('"4",0,1,1,"Kisa Urun"'));
    expect(output, contains('Kod: 1234567890'));
    expect(output, contains('"4",0,2,2,"299"'));
    expect(output, contains('"2",0,1,1,"95"'));
    expect(output, isNot(contains('TL 299.95')));
  });

  test('paket logosu TSPL ürün etiketine bitmap olarak eklenir', () {
    final logoBytes = File('assets/logo.png').readAsBytesSync();
    final output = latin1.decode(
      TsplLabelLayoutEngine.generateLabelBytes(
        productLabel(),
        logoBytes: logoBytes,
      ),
    );

    expect(output, contains('BITMAP '));
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
    expect(output, contains('"2",0,1,1,"TL 1234567.89"'));
    expect(
        output, isNot(contains('CokUzunTekParcaUrunAdiEtiketSiniriniAsamaz')));
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

    expect(output, contains('- 1 Parca Urun / Paket'));
    expect(output, contains('- 2x Ornek Urun'));
    expect(output, isNot(contains('•')));
    expect(output, endsWith('PRINT 1,1\r\n'));
  });
}
