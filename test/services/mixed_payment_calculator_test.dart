import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/mixed_payment_calculator.dart';

void main() {
  group('MixedPaymentCalculator', () {
    test('treats excess tendered cash as change', () {
      final result = MixedPaymentCalculator.calculate(
        total: 100,
        cashTendered: 100,
        card: 30,
        debt: 0,
      );

      expect(result.isValid, isTrue);
      expect(result.cashApplied, 70);
      expect(result.paidAmount, 100);
      expect(result.change, 30);
    });

    test('keeps debt out of paid amount', () {
      final result = MixedPaymentCalculator.calculate(
        total: 100,
        cashTendered: 50,
        card: 20,
        debt: 30,
      );

      expect(result.isValid, isTrue);
      expect(result.paidAmount, 70);
      expect(result.allocatedTotal, 100);
      expect(result.change, 0);
    });

    test('rejects card and debt above the sale total', () {
      final result = MixedPaymentCalculator.calculate(
        total: 100,
        cashTendered: 0,
        card: 80,
        debt: 30,
      );

      expect(result.isValid, isFalse);
    });

    test('reports missing cash as remaining', () {
      final result = MixedPaymentCalculator.calculate(
        total: 100,
        cashTendered: 40,
        card: 30,
        debt: 0,
      );

      expect(result.isValid, isFalse);
      expect(result.remaining, 30);
    });
  });
}
