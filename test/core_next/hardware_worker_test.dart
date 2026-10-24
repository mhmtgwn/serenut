// test/core_next/hardware_worker_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_commands.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/esc_pos_builder.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/tspl_builder.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';

void main() {
  group('ESC/POS Receipt Builder Tests', () {
    late EscPosBuilder builder;

    setUp(() {
      builder = EscPosBuilder();
    });

    test('Fiş baytları ESC/POS başlatma ve kağıt kesme komutlarını içermelidir', () {
      final cmd = PrintReceiptCommand(
        correlationId: 'test-1',
        receiptNo: '20261012-001',
        title: 'Örnek Süpermarket',
        items: [
          const ReceiptLineItem(
            name: 'Köy Ekmeği',
            quantity: 2,
            unitPriceCents: 1500, // 15 TL
            totalCents: 3000, // 30 TL
          ),
        ],
        subtotalCents: 3000,
        totalCents: 3000,
        paidCents: 3000,
        paymentType: 'NAKİT',
        timestamp: DateTime(2026, 10, 12, 14, 30),
        cutPaper: true,
        openCashDrawer: true,
      );

      final bytes = builder.buildReceipt(cmd);
      expect(bytes.isNotEmpty, true);

      // ESC @ (Init) baytları başta olmalı: 0x1B, 0x40
      expect(bytes[0], 0x1B);
      expect(bytes[1], 0x40);

      // String'e dönüştürüldüğünde başlık ve toplamlar bulunmalı
      final asLatin = latin1.decode(bytes);
      expect(asLatin.contains('Ornek Supermarket'), true); // Türkçe normalizasyonu
      expect(asLatin.contains('Koy Ekmegi'), true);
      expect(asLatin.contains('30,00 TL'), true);
    });
  });

  group('TSPL Barcode Label Builder Tests', () {
    late TsplBuilder builder;

    setUp(() {
      builder = TsplBuilder();
    });

    test('TSPL komutları milimetrik boyut ve EAN13 barkod formatına uygun olmalıdır', () {
      const cmd = PrintLabelCommand(
        correlationId: 'label-1',
        productName: 'Çiçek Balı 850g',
        barcode: '8690504123456',
        priceCents: 24500, // 245,00 TL
        widthMm: 50,
        heightMm: 30,
        copies: 2,
      );

      final bytes = builder.buildLabel(cmd);
      final script = latin1.decode(bytes);

      expect(script.contains('SIZE 50 mm, 30 mm'), true);
      expect(script.contains('CLS'), true);
      expect(script.contains('Cicek Bali 850g'), true);
      expect(script.contains('245,00 TL'), true);
      expect(script.contains('BARCODE 20,110,"EAN13"'), true);
      expect(script.contains('PRINT 2'), true);
    });
  });

  group('HardwareWorker Isolate Tests', () {
    test('HardwareWorker izole Isolate başlatabilmeli ve dispose edilebilmelidir', () async {
      final worker = HardwareWorker();
      await worker.initialize();

      // UI thread'ini asla bloklamadan komut gönderimi
      expect(
        () => worker.printReceipt(
          PrintReceiptCommand(
            correlationId: 'async-1',
            receiptNo: '001',
            title: 'Test',
            items: [],
            subtotalCents: 0,
            totalCents: 0,
            paidCents: 0,
            paymentType: 'NAKİT',
            timestamp: DateTime.now(),
            targetAddress: '127.0.0.1',
            port: 9999, // Dinlemeyen port
          ),
        ),
        returnsNormally,
      );

      await worker.dispose();
    });
  });
}
