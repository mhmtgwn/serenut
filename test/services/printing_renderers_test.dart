import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/label_model.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/infrastructure/printing/printing_renderers.dart';

PrintJobRecord job({
  required PrintDocumentKind kind,
  required String rendererVersion,
  required Map<String, Object?> payload,
  required Map<String, Object?> design,
  required Map<String, Object?> capabilities,
}) {
  final now = DateTime.utc(2026);
  return PrintJobRecord(
    id: 'job',
    kind: kind,
    payloadJson: jsonEncode(payload),
    copies: 1,
    designProfileId: 'design',
    designSnapshotJson: jsonEncode(design),
    deviceId: 'device',
    transportSnapshotJson: '{}',
    capabilitySnapshotJson: jsonEncode(capabilities),
    rendererVersion: rendererVersion,
    state: PrintJobState.rendering,
    attemptCount: 1,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('58 mm receipt width comes only from physical capability snapshot',
      () async {
    final rendered = await EscPosReceiptRenderer().render(job(
      kind: PrintDocumentKind.receipt,
      rendererVersion: 'escpos-v1',
      payload: {
        'business': {'name': 'Serenut OS'},
        'document': {'number': '1', 'total': 299.95},
        'items': [
          {'name': 'Uzun ürün adı', 'quantity': 1, 'unitPrice': 299.95},
        ],
        'currency': 'TL',
      },
      design: {
        'paperWidthMm': 80,
        'showLogo': false,
        'showProductDetails': true,
        'autoCut': true,
      },
      capabilities: {'paperWidthMm': 58, 'printableWidthDots': 384},
    ));
    final text = String.fromCharCodes(rendered.bytes);
    expect(text, contains('=' * 32));
    expect(text, isNot(contains('=' * 48)));
    expect(text, contains('[ SIPARIS FISI ]'));
    expect(text, contains('GENEL TOPLAM'));
    expect(text, contains('AD.'));
    expect(rendered.bytes.sublist(rendered.bytes.length - 4),
        [0x1D, 0x56, 0x41, 0x08]);
  });

  test('80 mm receipt renders columnar products, breakdown, and Nutopia layout',
      () async {
    final rendered = await EscPosReceiptRenderer().render(job(
      kind: PrintDocumentKind.receipt,
      rendererVersion: 'escpos-v1',
      payload: {
        'business': {
          'name': 'Nutopia',
          'subtitle': 'FINDIK DEGIRMENI',
          'address': 'Ataturk Cad. No:15\nFatsa / Ordu',
          'phone': '0452 423 00 00',
          'taxId': '1234567890',
          'email': 'www.nutopia.com.tr',
        },
        'document': {
          'number': '1042',
          'date': '04.09.2026 14:35',
          'payment': 'Kredi Karti (Pos)',
          'customerName': 'Ahmet Yilmaz',
          'total': 535.00,
          'barcode': '1042',
        },
        'items': [
          {
            'name': 'Surulebilir Findik Ezmesi 350g',
            'quantity': 2,
            'unitPrice': 120.00,
            'total': 240.00,
          },
          {
            'name': 'Kavrulmus Ic Findik 500g',
            'quantity': 1,
            'unitPrice': 210.00,
            'total': 210.00,
          },
        ],
        'currency': 'TL',
      },
      design: {
        'paperWidthMm': 80,
        'showLogo': false,
        'showProductDetails': true,
        'autoCut': true,
      },
      capabilities: {'paperWidthMm': 80, 'printableWidthDots': 576},
    ));
    final text = String.fromCharCodes(rendered.bytes);
    expect(text, contains('=' * 48));
    expect(text, contains('[ SIPARIS FISI ]'));
    expect(text, contains('FINDIK DEGIRMENI'));
    expect(text, contains('Siparis No: #1042'));
    expect(text, contains('Tarih: 04.09.2026'));
    expect(text, contains('Musteri: Ahmet Yilmaz'));
    expect(text, contains('Saat: 14:35'));
    expect(text, contains('AD. URUN ADI'));
    expect(text, contains('BIRIM'));
    expect(text, contains('TUTAR'));
    expect(text, contains('GENEL TOPLAM'));
    expect(text, contains('535.00 TL'));
    expect(text, contains('* 1042 - 2026 - NUTOPIA *'));
    expect(text, contains('www.nutopia.com.tr'));
  });

  test('product label uses device media dimensions and emits one TSPL copy',
      () async {
    final label = LabelModel(
      productName: 'Ürününüzün adı',
      weight: 1,
      price: 299.95,
      barcode: '1234567890',
      qrData: 'product|1',
      timestamp: DateTime.utc(2026),
      businessName: 'Serenut OS',
    );
    final rendered = await TsplProductLabelRenderer().render(job(
      kind: PrintDocumentKind.productLabel,
      rendererVersion: 'tspl-product-v1',
      payload: {
        'labels': [label.toMap()]
      },
      design: {
        'showBusinessName': true,
        'showBarcode': true,
        'showPrice': true,
      },
      capabilities: {
        'mediaWidthMm': 50,
        'mediaHeightMm': 30,
        'gapMm': 2,
        'dpi': 203,
      },
    ));
    final output = latin1.decode(rendered.bytes);
    expect(output, startsWith('SIZE 50 mm,30 mm\r\nGAP 2 mm,0 mm\r\n'));
    expect(output, contains('PRINT 1,1'));
    expect(output, isNot(contains('Kod:')));
  });

  test('order renderer creates one aggregate order label', () async {
    final rendered = await TsplOrderLabelRenderer().render(job(
      kind: PrintDocumentKind.orderLabel,
      rendererVersion: 'tspl-order-v1',
      payload: {
        'orderNo': 'ORD-1',
        'customerName': 'Müşteri',
        'customerPhone': '0555 111 22 33',
        'previousDebt': 245.50,
        'paymentStatus': 'Kısmi ödendi',
        'productName': '2 Ürün / Paket',
        'quantity': 1,
        'itemsCount': 2,
        'totalAmount': 120,
        'businessName': 'Serenut OS',
        'items': [
          {'product_name': 'A', 'quantity': 1},
          {'product_name': 'B', 'quantity': 1},
        ],
      },
      design: const {},
      capabilities: {
        'mediaWidthMm': 50,
        'mediaHeightMm': 30,
        'gapMm': 2,
        'dpi': 203,
      },
    ));
    final output = latin1.decode(rendered.bytes);
    expect(RegExp(r'PRINT 1,1').allMatches(output), hasLength(1));
    expect(output, contains('DIRECTION 0'));
    expect(output, contains('Tel: 0555 111 22 33'));
    expect(output, contains('Brc: TL 245.50'));
    expect(output, contains('TOPLAM: TL 120.00'));
    expect(output, contains('Odm: Kismi odendi'));
  });
}
