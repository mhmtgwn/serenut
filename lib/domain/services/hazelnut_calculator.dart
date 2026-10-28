// lib/domain/services/hazelnut_calculator.dart

/// Fındık Emanet ve Randıman Hesaplama Motoru
class HazelnutCalculator {
  /// Randıman bazlı birim fiyat hesabı.
  /// Karadeniz fındık piyasası standardı: 50 randıman baz fiyattır.
  /// Formül: birim_fiyat = 50_randıman_fiyatı * (randıman / 50.0)
  static double calculateEffectiveUnitPrice({
    required double basePrice50,
    required double rendiment,
  }) {
    if (basePrice50 <= 0 || rendiment <= 0) return 0.0;
    final price = basePrice50 * (rendiment / 50.0);
    return double.parse(price.toStringAsFixed(2));
  }

  /// Brüt kg, çuval adedi ve dara ile net kg hesabı.
  /// [tarePerSack] varsayılan olarak 1.0 kg (standart jüt çuval darası).
  static double calculateNetKg({
    required double grossKg,
    int sackCount = 0,
    double tarePerSack = 1.0,
    double manualTareKg = 0.0,
  }) {
    if (grossKg <= 0) return 0.0;
    final effectiveTare = manualTareKg > 0 ? manualTareKg : (sackCount * tarePerSack);
    final net = grossKg - effectiveTare;
    return net > 0 ? double.parse(net.toStringAsFixed(2)) : 0.0;
  }

  /// Toplam tutar hesabı: kesilen kg * efektif birim fiyat
  static double calculateTotalAmount({
    required double cutKg,
    required double effectiveUnitPrice,
  }) {
    if (cutKg <= 0 || effectiveUnitPrice <= 0) return 0.0;
    return double.parse((cutKg * effectiveUnitPrice).toStringAsFixed(2));
  }

  /// Depo için ağırlıklı ortalama randıman hesabı (Yeni mal girişinde).
  /// Formül: ((Mevcut Stok * Mevcut Randıman) + (Giren Kg * Giren Randıman)) / (Mevcut Stok + Giren Kg)
  static double calculateWeightedAverageRendiment({
    required double currentStockKg,
    required double currentAverageRendiment,
    required double incomingKg,
    required double incomingRendiment,
  }) {
    if (incomingKg <= 0) return currentAverageRendiment;
    if (currentStockKg <= 0) {
      return double.parse(incomingRendiment.toStringAsFixed(2));
    }
    final totalKg = currentStockKg + incomingKg;
    final weighted = ((currentStockKg * currentAverageRendiment) + (incomingKg * incomingRendiment)) / totalKg;
    return double.parse(weighted.toStringAsFixed(2));
  }
}

