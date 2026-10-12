// test/domain/money_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/money.dart';

void main() {
  group('Money Value Object', () {
    test('Temel oluşturma ve kuruş-lira dönüşümleri', () {
      final m1 = Money.fromLira(100.50);
      expect(m1.cents, 10050);
      expect(m1.inLira, 100.50);
      expect(m1.currency, 'TRY');

      final m2 = Money.fromCents(250);
      expect(m2.cents, 250);
      expect(m2.inLira, 2.50);

      const zero = Money.zero();
      expect(zero.isZero, isTrue);
      expect(zero.cents, 0);
    });

    test('Float kayması olmadan toplama ve çıkarma', () {
      // 0.1 + 0.2 float'ta 0.30000000000000004 olur
      final a = Money.fromLira(0.10);
      final b = Money.fromLira(0.20);
      final sum = a + b;
      expect(sum.cents, 30);
      expect(sum.inLira, 0.30);

      final diff = sum - a;
      expect(diff, b);
      expect(diff.cents, 20);
    });

    test('Çarpma ve bölme', () {
      final m = Money.fromLira(10.00);
      final multiplied = m * 1.5;
      expect(multiplied.cents, 1500);
      expect(multiplied.inLira, 15.00);

      final divided = m / 3;
      expect(divided.cents, 333); // 3.33 TL
      expect(divided.inLira, 3.33);
    });

    test('Karşılaştırma operatörleri ve eşitlik', () {
      final m1 = Money.fromLira(50.0);
      final m2 = Money.fromLira(50.0);
      final m3 = Money.fromLira(75.0);

      expect(m1 == m2, isTrue);
      expect(m1.hashCode == m2.hashCode, isTrue);
      expect(m1 < m3, isTrue);
      expect(m3 > m1, isTrue);
      expect(m1 <= m2, isTrue);
      expect(m1 >= m2, isTrue);
      expect([m3, m1]..sort(), [m1, m3]);
    });

    test('Negatif ve mutlak değer', () {
      final m = Money.fromLira(45.0);
      final neg = -m;
      expect(neg.cents, -4500);
      expect(neg.isNegative, isTrue);
      expect(neg.abs(), m);
    });

    test('split — Taksitlere kuruş kayıpsız bölme', () {
      final m = Money.fromLira(100.0);
      final parts = m.split(3);
      expect(parts.length, 3);
      expect(parts[0].inLira, 33.0);
      expect(parts[1].inLira, 33.0);
      expect(parts[2].inLira, 34.0);

      final total = parts.reduce((acc, p) => acc + p);
      expect(total, m);
    });

    test('Biçimlendirme', () {
      expect(Money.fromLira(1250.50).format(), '1.250,50 ₺');
      expect(Money.fromLira(0).format(), '0,00 ₺');
      expect(Money.fromLira(-25.75).format(), '-25,75 ₺');
    });

    test('Farklı para birimlerinde hata fırlatır', () {
      final tryMoney = Money.fromLira(10, currency: 'TRY');
      final usdMoney = Money.fromLira(10, currency: 'USD');

      expect(() => tryMoney + usdMoney, throwsArgumentError);
      expect(() => tryMoney - usdMoney, throwsArgumentError);
      expect(() => tryMoney < usdMoney, throwsArgumentError);
    });
  });
}
