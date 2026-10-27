import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/scale_barcode_parser.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';

void main() {
  group('Scale Barcode & Customer Barcode Sales Flow Integration Test', () {
    test(
        'Simulate scanning 27-series scale barcode adds weighed item with exact price',
        () {
      final notifier = SalesFlowNotifier();

      // Product in database with PLU '00142' (Giresun Tombul Fındık, 320 TL / kg)
      final hazelnut = ProductEntity(
        id: '00142',
        name: 'Giresun Tombul Fındık',
        description: 'Doğal kavrulmuş fındık',
        price: 320.0, // 320 TL / kg
        quantity: 50000,
        category: 'Kuruyemiş',
        saleType: 'weighed',
        minimumWeightGrams: 20,
      );

      // Scanned barcode from scale: 27 + 00142 + 00450 + 5 (450 grams)
      const scannedBarcode = '2700142004505';
      final scaleResult = ScaleBarcodeParser.tryParse(scannedBarcode);

      expect(scaleResult, isNotNull);
      expect(scaleResult!.isValid, isTrue);
      expect(scaleResult.pluCandidates, contains(hazelnut.id));

      // Simulate the sales_page submit handler calling addMeasuredToCart
      notifier.addMeasuredToCart(hazelnut, scaleResult.weightGrams);

      // Verify cart quantities and total price
      // 450g of 320 TL/kg = 0.45 * 320 = 144.00 TL
      expect(notifier.state.cartQuantities[hazelnut.id], equals(450));
      expect(notifier.state.total, closeTo(144.00, 0.001));
    });

    test(
        'Simulate scanning 28-series scale barcode with stripped PLU candidate matches product',
        () {
      final notifier = SalesFlowNotifier();

      // In database, merchant registered product with stripped PLU '55'
      final driedFigs = ProductEntity(
        id: '55',
        name: 'Aydın Kuru İncir',
        description: 'Organik incir',
        price: 240.0, // 240 TL / kg
        quantity: 30000,
        category: 'Kuru Meyve',
        saleType: 'weighed',
        minimumWeightGrams: 50,
      );

      // Scanned barcode from scale: 28 + 00055 + 01250 + 2 (1250 grams)
      const scannedBarcode = '2800055012502';
      final scaleResult = ScaleBarcodeParser.tryParse(scannedBarcode);

      expect(scaleResult, isNotNull);
      expect(scaleResult!.isValid, isTrue);
      expect(scaleResult.pluCandidates, contains(driedFigs.id));

      notifier.addMeasuredToCart(driedFigs, scaleResult.weightGrams);

      // 1250g of 240 TL/kg = 1.25 * 240 = 300.00 TL
      expect(notifier.state.cartQuantities[driedFigs.id], equals(1250));
      expect(notifier.state.total, closeTo(300.00, 0.001));
    });

    test('Customer barcode scan sets selected customer in sales flow', () {
      final notifier = SalesFlowNotifier();

      final customer = CustomerEntity(
        id: 'CUST-00991',
        name: 'Ahmet Yılmaz',
        email: 'ahmet@example.com',
        phone: '05551234567',
        balance: -250.0,
        createdAt: DateTime.now(),
      );

      expect(notifier.state.selectedCustomer, isNull);

      notifier.selectCustomer(customer);

      expect(notifier.state.selectedCustomer, isNotNull);
      expect(notifier.state.selectedCustomer!.id, equals('CUST-00991'));
      expect(notifier.state.selectedCustomer!.name, equals('Ahmet Yılmaz'));
    });
  });
}
