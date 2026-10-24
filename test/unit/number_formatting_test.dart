import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/config/utils.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

void main() {
  group('NumberFormatting Extension & ProductEntity formattedQuantity Tests', () {
    test('Eliminates IEEE-754 precision noise from quantities (user screenshot scenarios)', () {
      // Image 1, Card 1: 13276.649999999998 -> "13.276,65"
      final val1 = 13276.649999999998;
      expect(val1.toTurkishQuantity(), '13.276,65');

      // Image 1, Card 2: 11469.100000000004 -> "11.469,1"
      final val2 = 11469.100000000004;
      expect(val2.toTurkishQuantity(), '11.469,1');

      // ProductEntity integration
      final product1 = ProductEntity(
        id: 'prod-1',
        name: 'Kır Kavur 0.5 Pk.',
        description: '',
        price: 80.0,
        quantity: 13276.649999999998,
        category: 'Hizmetler',
      );
      expect(product1.formattedQuantity, '13.276,65');
      expect(product1.category.toTurkishUpperCase, 'HİZMETLER');

      final product2 = ProductEntity(
        id: 'prod-2',
        name: 'Kır Kavur 1Kg Pk.',
        description: '',
        price: 70.0,
        quantity: 11469.100000000004,
        category: 'Hizmetler',
      );
      expect(product2.formattedQuantity, '11.469,1');
    });

    test('Formats whole numbers cleanly without decimal points', () {
      expect(0.toTurkishQuantity(), '0');
      expect(10.toTurkishQuantity(), '10');
      expect(100.0.toTurkishQuantity(), '100');
      expect(1500.toTurkishQuantity(), '1.500');
      expect(25000.toTurkishQuantity(), '25.000');
    });

    test('Formats valid fractions cleanly', () {
      expect(0.5.toTurkishQuantity(), '0,5');
      expect(0.25.toTurkishQuantity(), '0,25');
      expect(1.75.toTurkishQuantity(), '1,75');
      expect(2.1.toTurkishQuantity(), '2,1');
    });

    test('Formats currency with Turkish thousand and decimal separators (user screenshot scenario 2)', () {
      // Image 2: 29666552.50 -> "₺29.666.552,50"
      final totalStockValue = 29666552.50;
      expect(totalStockValue.toTurkishCurrency(), '₺29.666.552,50');

      expect(0.0.toTurkishCurrency(), '₺0,00');
      expect(80.0.toTurkishCurrency(), '₺80,00');
      expect(1250.75.toTurkishCurrency(), '₺1.250,75');
      expect(1250.75.toTurkishCurrency(symbol: false), '1.250,75');
    });
  });
}
