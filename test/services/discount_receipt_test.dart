import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/printing/printing_renderers.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';

void main() {
  group('Aşama 2: İndirim (İskonto) Sistemi Testleri', () {
    test('SaleEntity calculates remaining amount and preserves discountAmount', () {
      final sale = SaleEntity(
        id: 'sale-test-123',
        customerId: 'cust-1',
        totalAmount: 2920.0,
        paidAmount: 2000.0,
        discountAmount: 150.0,
        paymentMethod: 'cash',
        status: 'completed',
        createdAt: DateTime(2026, 9, 7, 14, 30),
        items: [
          {
            'product_id': 'p1',
            'product_name': 'Kaju Fıstığı',
            'quantity': 2.0,
            'unit_price': 1535.0,
          }
        ],
      );

      expect(sale.discountAmount, 150.0);
      expect(sale.totalAmount, 2920.0);
      expect(sale.remainingAmount, 920.0);

      final map = sale.toMap();
      expect(map['discount_amount'], 150.0);
      expect(map['total_amount'], 2920.0);

      final fromMapSale = SaleEntity.fromMap(map);
      expect(fromMapSale.discountAmount, 150.0);
      expect(fromMapSale.totalAmount, 2920.0);
    });

    test('OrderEntity calculates subtotalAmount and totalAmount with discount', () {
      final order = OrderEntity(
        id: 'ord-test-456',
        orderNumber: 'SP-000123',
        customerId: 'cust-2',
        status: 'created',
        createdAt: DateTime(2026, 9, 7, 14, 30),
        discountAmount: 250.0,
        items: [
          {
            'product_id': 'p1',
            'product_name': 'Antep Fıstığı',
            'quantity': 3.0,
            'unit_price': 1000.0,
          }
        ],
      );

      // Subtotal = 3 * 1000 = 3000
      expect(order.subtotalAmount, 3000.0);
      // Net Total = 3000 - 250 = 2750
      expect(order.totalAmount, 2750.0);
      expect(order.discountAmount, 250.0);

      final map = order.toMap();
      expect(map['discount_amount'], 250.0);

      final fromMapOrder = OrderEntity.fromMap(map);
      expect(fromMapOrder.discountAmount, 250.0);
    });

    test('SalesFlowNotifier applies discount and calculates subtotal and net total', () {
      final notifier = SalesFlowNotifier();
      final product = ProductEntity(
        id: 'p-test',
        name: 'Fındık İçi',
        description: '',
        price: 500.0,
        quantity: 10,
        category: 'Kuruyemiş',
      );

      notifier.addToCart(product);
      notifier.addToCart(product); // 2 adet * 500 = 1000 TL

      expect(notifier.state.subtotal, 1000.0);
      expect(notifier.state.total, 1000.0);
      expect(notifier.state.paidAmount, 1000.0);

      // Apply 100 TL discount
      notifier.setDiscount(100.0);
      expect(notifier.state.discountAmount, 100.0);
      expect(notifier.state.subtotal, 1000.0);
      expect(notifier.state.total, 900.0);
      expect(notifier.state.paidAmount, 900.0); // cash/card auto updates paid

      // Reset / Clear cart resets discount
      notifier.clearCart();
      expect(notifier.state.discountAmount, 0.0);
      expect(notifier.state.total, 0.0);
    });

    test('EscPosReceiptRenderer prints Ara Toplam and Indirim rows on receipt', () async {
      final renderer = EscPosReceiptRenderer();
      final rendered = await renderer.render(PrintJobRecord(
        id: 'job-1',
        kind: PrintDocumentKind.receipt,
        payloadJson: jsonEncode({
          'document': {
            'subtotal': 3070.0,
            'discount': 150.0,
            'total': 2920.0,
            'paid': 2920.0,
            'remaining': 0.0,
            'number': 'SAT-999',
            'date': '2026-09-07T14:30:00',
            'payment': 'Nakit',
            'cashier': 'Kasiyer 1',
            'customerName': 'Ahmet Yılmaz',
            'customerPhone': '05551234567',
            'customerBalance': 200.0,
            'barcode': 'SAT-999',
          },
          'items': [
            {
              'name': 'Fıstık Ezmesi',
              'quantity': 2.0,
              'unitPrice': 1535.0,
              'total': 3070.0,
            }
          ],
        }),
        copies: 1,
        designProfileId: 'design',
        designSnapshotJson: jsonEncode({'paperWidthMm': 80}),
        deviceId: 'pos80',
        transportSnapshotJson: '{}',
        capabilitySnapshotJson: jsonEncode({'paperWidthMm': 80, 'printableWidthDots': 576}),
        rendererVersion: 'escpos-v1',
        state: PrintJobState.rendering,
        attemptCount: 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ));

      final text = latin1.decode(rendered.bytes, allowInvalid: true);
      expect(text.contains('Ara Toplam:'), isTrue);
      expect(text.contains('3070.00'), isTrue);
      expect(text.contains('150.00'), isTrue);
      expect(text.contains('GENEL TOPLAM'), isTrue);
      expect(text.contains('2920.00'), isTrue);
      expect(text.contains('===='), isFalse);
    });

    test('TsplOrderLabelRenderer renders order label with discount without error', () async {
      final renderer = TsplOrderLabelRenderer();
      final rendered = await renderer.render(PrintJobRecord(
        id: 'job-label-1',
        kind: PrintDocumentKind.orderLabel,
        payloadJson: jsonEncode({
          'orderNo': '0-919747',
          'customerName': 'Ismail BOZKURT',
          'customerPhone': '0532 999 88 77',
          'customerNo': '919747',
          'previousDebt': 0.0,
          'productName': 'Findik Paketi',
          'quantity': 1.0,
          'totalAmount': 2920.0,
          'discountAmount': 150.0,
          'items': [
            {'product_name': 'Kir Kavur 1Kg Pk.', 'quantity': 12, 'unit_price': 70.0},
            {'product_name': 'Ezme Kabuklu', 'quantity': 12, 'unit_price': 130.0},
          ],
          'paymentStatus': 'Nakit',
          'itemsCount': 2,
          'labelWidthMm': 80,
          'labelHeightMm': 60,
          'labelGapMm': 2,
          'labelDpi': 203,
          'autoDetectGap': false,
          'qrData': 'order|0-919747|2920.0',
        }),
        copies: 1,
        designProfileId: 'design',
        designSnapshotJson: jsonEncode({'widthMm': 80, 'heightMm': 60, 'useCanvas': true}),
        deviceId: 'tspl-printer',
        transportSnapshotJson: '{}',
        capabilitySnapshotJson: jsonEncode({'labelWidthMm': 80, 'labelHeightMm': 60, 'dpi': 203}),
        rendererVersion: 'tspl-order-v1',
        state: PrintJobState.rendering,
        attemptCount: 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ));

      expect(rendered.bytes.isNotEmpty, isTrue);
      expect(rendered.mimeType, 'application/vnd.tspl');
      final tsplStr = latin1.decode(rendered.bytes, allowInvalid: true);
      expect(tsplStr.contains('SIZE 80 mm,60 mm'), isTrue);
      expect(tsplStr.contains('BITMAP'), isTrue);
    });
  });
}
