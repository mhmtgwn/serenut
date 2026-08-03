import 'dart:convert';

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
    expect(output, contains('ve Cesidi'));
    expect(output, contains('"2",0,2,2'));
    expect(output, contains('"128"'));
    expect(output, contains('TL"'));
    expect(output, isNot(contains('Ü')));
    expect(output, isNot(contains('geçersiz')));
  });
}
