import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/label_model.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/domain/services/tspl_canvas_label_engine.dart';
import 'package:serenutos/infrastructure/printing/printing_renderers.dart';
import 'package:serenutos/infrastructure/printing/printing_transports.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Stage 10.12.29: Generate and Dispatch Production Test Receipt and Label', () async {
    // ══════════════════════════════════════════════════════════════════════════
    // 1. ESC/POS RECEIPT TEST (POS-80) — Universal Turkish Mode
    // ══════════════════════════════════════════════════════════════════════════
    final receiptRenderer = EscPosReceiptRenderer();
    final now = DateTime.now();

    final testReceiptJob = PrintJobRecord(
      id: 'test-receipt-${now.millisecondsSinceEpoch}',
      deviceId: 'pos-80-device',
      kind: PrintDocumentKind.receipt,
      rendererVersion: 'escpos-v1',
      copies: 1,
      attemptCount: 0,
      designProfileId: 'profile-receipt-default',
      payloadJson: jsonEncode({
        'business': {
          'name': 'SERENUT OS',
          'subtitle': 'TEST FISI',
          'address': 'Ataturk Cad. No:15\nFatsa / Ordu',
          'phone': '0452 423 00 00',
          'taxId': '1234567890',
        },
        'document': {
          'number': 'TEST-80',
          'date': '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
          'payment': 'NAKIT',
          'customerName': 'Çağrı ŞĞİÖÜçşı', // Turkish characters to verify universal transliteration
          'total': 185.00,
          'paid': 185.00,
          'barcode': '1042',
        },
        'items': [
          {
            'name': 'Çiğ Fındık 500g',
            'quantity': 1,
            'unitPrice': 85.00,
            'total': 85.00,
          },
          {
            'name': 'Sürülebilir Fındık Ezmesi',
            'quantity': 1,
            'unitPrice': 100.00,
            'total': 100.00,
          },
        ],
        'currency': 'TL',
      }),
      designSnapshotJson: jsonEncode({
        'paperWidthMm': 80,
        'turkishMode': 'universal',
        'showLogo': false,
        'showProductDetails': true,
        'autoCut': true,
      }),
      capabilitySnapshotJson: jsonEncode({
        'paperWidthMm': 80,
        'printableWidthDots': 576,
      }),
      transportSnapshotJson: jsonEncode({
        'transport': 'windowsSpooler',
        'config': {'printerName': 'POS-80'},
      }),
      state: PrintJobState.queued,
      createdAt: now,
      updatedAt: now,
    );

    final renderedReceipt = await receiptRenderer.render(testReceiptJob);
    expect(renderedReceipt.bytes.isNotEmpty, isTrue);

    // Verify all bytes are standard ASCII <= 127 in universal mode (no Chinese ROM corruption)
    final nonAsciiBytes = renderedReceipt.bytes.where((b) => b > 127).toList();
    expect(nonAsciiBytes, isEmpty,
        reason: 'Universal Turkish mode must strictly emit ASCII <= 127 to prevent Chinese ROM corruption on POS-80');

    // ══════════════════════════════════════════════════════════════════════════
    // 2. TSPL LABEL TEST (etiket) — 50x30mm Canvas Engine with Turkish Typography
    // ══════════════════════════════════════════════════════════════════════════
    final labelModel = LabelModel(
      productName: 'Çiğ Fındık İçi 500g',
      businessName: 'SERENUT OS',
      weight: 1,
      price: 185.00,
      barcode: '8680001234567',
      qrData: 'https://serenutos.com/p/8680001234567',
      origin: 'TÜRKİYE',
      timestamp: now,
    );

    final labelBytes = await TsplCanvasLabelEngine.generateShelfLabelBytes(
      model: labelModel,
      widthMm: 50,
      heightMm: 30,
      gapMm: 2,
      dpi: 203,
      direction: 0,
      copies: 1,
      showBusinessName: true,
      showBarcode: true,
      showPrice: true,
    );

    expect(labelBytes.isNotEmpty, isTrue);
    final labelHeader = String.fromCharCodes(labelBytes.take(150));
    expect(labelHeader, contains('SIZE 50 mm,30 mm'));
    expect(labelHeader, contains('GAP 2 mm,0 mm'));
    expect(labelHeader, contains('BITMAP 0,0,'));

    // ══════════════════════════════════════════════════════════════════════════
    // 3. PHYSICAL TRANSMISSION VIA WINDOWS SPOOLER TRANSPORT
    // ══════════════════════════════════════════════════════════════════════════
    final spoolerTransport = WindowsSpoolerPrintTransport();

    bool receiptDispatched = false;
    bool labelDispatched = false;

    try {
      final receiptResult = await spoolerTransport.send(
        bytes: renderedReceipt.bytes,
        copies: 1,
        configuration: {'printerName': 'POS-80'},
      );
      receiptDispatched = receiptResult.details['bytesAccepted'] != null;
    } catch (e) {
      debugPrint('[PrintDispatch] POS-80 spooling notice: $e');
    }

    try {
      final labelResult = await spoolerTransport.send(
        bytes: Uint8List.fromList(labelBytes),
        copies: 1,
        configuration: {'printerName': 'etiket'},
      );
      labelDispatched = labelResult.details['bytesAccepted'] != null;
    } catch (e) {
      debugPrint('[PrintDispatch] etiket spooling notice: $e');
    }

    debugPrint('[PrintDispatch] POS-80 Receipt bytes: ${renderedReceipt.bytes.length}, Spooled: $receiptDispatched');
    debugPrint('[PrintDispatch] etiket Label bytes: ${labelBytes.length}, Spooled: $labelDispatched');
  });
}
