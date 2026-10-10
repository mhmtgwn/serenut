// lib/domain/utils/safe_money.dart
// Serenut OS — Finansal Kuruş & Güvenli Para İşleme Motoru (SafeMoney)
//
// Float (IEEE 754 double) virgül kayması hatalarını önler.
// Tüm iç hesaplamalar kuruş (integer cents) bazında yapılır.
// 1 TL = 100 Kuruş

class SafeMoney {
  SafeMoney._();

  /// TL tutarını tam sayı kuruşa (integer cents) çevirir.
  /// Örn: 12.34 -> 1234, 100.0 -> 10000
  static int toCents(double amount) {
    if (amount.isNaN || amount.isInfinite) return 0;
    return (amount * 100).round();
  }

  /// Kuruşu (integer cents) TL'ye çevirir.
  /// Örn: 1234 -> 12.34, 10000 -> 100.0
  static double fromCents(int cents) {
    return cents / 100.0;
  }

  /// İki para tutarını kuruş hassasiyetiyle toplar.
  static double add(double a, double b) {
    return fromCents(toCents(a) + toCents(b));
  }

  /// İki para tutarını kuruş hassasiyetiyle çıkarır (a - b).
  static double subtract(double a, double b) {
    return fromCents(toCents(a) - toCents(b));
  }

  /// Tutarı katsayıyla çarpar.
  static double multiply(double amount, double factor) {
    return fromCents((toCents(amount) * factor).round());
  }

  /// İki para tutarının kuruş bazında tam eşit olup olmadığını kontrol eder.
  static bool isEqual(double a, double b) {
    return toCents(a) == toCents(b);
  }

  /// Tutarın 0 kuruş olup olmadığını kontrol eder.
  static bool isZero(double amount) {
    return toCents(amount).abs() == 0;
  }

  /// a > b kontrolü (kuruş bazında).
  static bool isGreater(double a, double b) {
    return toCents(a) > toCents(b);
  }

  /// a < b kontrolü (kuruş bazında).
  static bool isLess(double a, double b) {
    return toCents(a) < toCents(b);
  }

  /// a >= b kontrolü (kuruş bazında).
  static bool isGreaterOrEqual(double a, double b) {
    return toCents(a) >= toCents(b);
  }

  /// a <= b kontrolü (kuruş bazında).
  static bool isLessOrEqual(double a, double b) {
    return toCents(a) <= toCents(b);
  }

  /// Tutarın pozitif (> 0 kuruş) olup olmadığını kontrol eder.
  static bool isPositive(double amount) {
    return toCents(amount) > 0;
  }

  /// Bir toplam tutarı taksitlere böler.
  ///
  /// [roundBaseToWholeUnits] true ise (varsayılan):
  /// - İlk taksitler tam TL (kuruşsuz, yuvarlak) olur.
  /// - Kalan tüm küsurat/artık kuruş son taksite eklenir.
  /// - Tüm taksitlerin toplamının kuruşu kuruşuna [totalAmount]'a eşit olduğunu garanti eder.
  static List<double> splitInstallments({
    required double totalAmount,
    required int count,
    bool roundBaseToWholeUnits = true,
  }) {
    if (count <= 0) return const [];
    if (count == 1) return [fromCents(toCents(totalAmount))];

    final totalCents = toCents(totalAmount);
    if (totalCents <= 0) {
      return List<double>.filled(count, 0.0);
    }

    final rawBaseCents = totalCents ~/ count;

    int baseCents;
    if (roundBaseToWholeUnits) {
      // Tam TL tabanı: 100 kuruşun katı (örn: 33.33 TL yerine 33.00 TL)
      final wholeLiraCents = rawBaseCents - (rawBaseCents % 100);
      // Eğer tutar çok küçükse en azından 1 kuruş tabanı ver
      baseCents = wholeLiraCents > 0 ? wholeLiraCents : rawBaseCents;
    } else {
      baseCents = rawBaseCents;
    }

    final result = <double>[];
    int distributedCents = 0;

    for (int i = 0; i < count - 1; i++) {
      result.add(fromCents(baseCents));
      distributedCents += baseCents;
    }

    // Son taksit: Toplamdan önceki taksitlerin kuruş toplamı çıkarılır (kalan kuruşlar son taksite bağlanır)
    final lastCents = totalCents - distributedCents;
    result.add(fromCents(lastCents));

    return result;
  }

  /// Kuruş duyarlılığında biçimlendirilmiş metin (örn: 1.250,50 ₺).
  static String format(double amount, {String symbol = '₺'}) {
    final cents = toCents(amount);
    final isNegative = cents < 0;
    final absCents = cents.abs();

    final liras = absCents ~/ 100;
    final kurus = absCents % 100;

    final kurusStr = kurus.toString().padLeft(2, '0');

    // Binlik ayraç (nokta)
    final lirasStr = liras.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );

    final sign = isNegative ? '-' : '';
    return '$sign$lirasStr,$kurusStr $symbol';
  }
}
