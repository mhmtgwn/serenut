// test/domain/safe_money_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/utils/safe_money.dart';

void main() {
  group('SafeMoney — Kuruş Hassasiyeti', () {
    test('toCents ve fromCents doğru dönüştürür', () {
      expect(SafeMoney.toCents(100.0), 10000);
      expect(SafeMoney.toCents(12.34), 1234);
      expect(SafeMoney.toCents(0.01), 1);
      expect(SafeMoney.toCents(0.0), 0);

      expect(SafeMoney.fromCents(10000), 100.0);
      expect(SafeMoney.fromCents(1234), 12.34);
      expect(SafeMoney.fromCents(1), 0.01);
    });

    test('add ve subtract float kaymasını engeller', () {
      // Standart float'ta 0.1 + 0.2 = 0.30000000000000004
      expect(0.1 + 0.2 != 0.3, isTrue); // Standart dart float hatası
      // SafeMoney ile:
      expect(SafeMoney.add(0.1, 0.2), 0.3);
      expect(SafeMoney.subtract(100.0, 33.33), 66.67);
      expect(SafeMoney.subtract(50.0, 50.0), 0.0);
    });

    test('isZero ve isEqual tam kuruş duyarlılığında çalışır', () {
      expect(SafeMoney.isZero(0.0001), isTrue);
      expect(SafeMoney.isZero(0.004), isTrue); // Yarım kuruş altı (0 kuruş)
      expect(SafeMoney.isZero(0.006), isFalse); // Yarım kuruş üstü (1 kuruş)
      expect(SafeMoney.isZero(0.01), isFalse);

      expect(SafeMoney.isEqual(100.001, 100.0), isTrue);
      expect(SafeMoney.isEqual(100.01, 100.0), isFalse);
    });

    test('splitInstallments — 100 TL 3 taksite yuvarlak bölünür ve artık son taksite eklenir', () {
      // 100 TL / 3 taksit
      // Yuvarlak taban: 33.00 TL
      // 1. Taksit: 33.00 TL
      // 2. Taksit: 33.00 TL
      // 3. Taksit: 34.00 TL (100 - 66)
      final installments = SafeMoney.splitInstallments(totalAmount: 100.0, count: 3);
      expect(installments.length, 3);
      expect(installments[0], 33.0);
      expect(installments[1], 33.0);
      expect(installments[2], 34.0);

      // Toplamın kuruşu kuruşuna tam 100.0 TL olduğunu doğrula
      final total = installments.fold(0.0, (acc, val) => SafeMoney.add(acc, val));
      expect(total, 100.0);
    });

    test('splitInstallments — 1000 TL 3 taksit', () {
      // 1000 TL / 3 taksit
      // Taban: 333.00 TL
      // 1. Taksit: 333.00 TL
      // 2. Taksit: 333.00 TL
      // 3. Taksit: 334.00 TL
      final installments = SafeMoney.splitInstallments(totalAmount: 1000.0, count: 3);
      expect(installments[0], 333.0);
      expect(installments[1], 333.0);
      expect(installments[2], 334.0);

      final total = installments.fold(0.0, (acc, val) => SafeMoney.add(acc, val));
      expect(total, 1000.0);
    });

    test('splitInstallments — Küsuratlı borç (örn 1250.75 TL 3 taksit)', () {
      // 1250.75 TL / 3 = 416.916...
      // Taban yuvarlak: 416.00 TL
      // 1. Taksit: 416.00 TL
      // 2. Taksit: 416.00 TL
      // 3. Taksit: 418.75 TL (1250.75 - 832.00)
      final installments = SafeMoney.splitInstallments(totalAmount: 1250.75, count: 3);
      expect(installments[0], 416.0);
      expect(installments[1], 416.0);
      expect(installments[2], 418.75);

      final total = installments.fold(0.0, (acc, val) => SafeMoney.add(acc, val));
      expect(total, 1250.75);
    });

    test('format — Türk Lirası formatlama', () {
      expect(SafeMoney.format(1250.50), '1.250,50 ₺');
      expect(SafeMoney.format(100.0), '100,00 ₺');
      expect(SafeMoney.format(0.0), '0,00 ₺');
      expect(SafeMoney.format(-50.25), '-50,25 ₺');
    });
  });
}
