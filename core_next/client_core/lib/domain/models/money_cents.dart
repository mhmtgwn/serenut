// core_next/client_core/lib/domain/models/money_cents.dart

/// Kuruş cinsinden değer nesnesi (Value Object).
/// 
/// 1 TL = 100 Kuruş.
/// Kayan noktalı sayı (double / float) kaynaklı 1 kuruşluk sapmaları ve
/// IEEE 754 ikili yuvarlama hatalarını kalıcı olarak önler.
class MoneyCents implements Comparable<MoneyCents> {
  final int value;

  const MoneyCents(this.value);

  /// 0 Kuruş sabiti
  static const MoneyCents zero = MoneyCents(0);

  /// TL ondalık değerinden kuruşa güvenli dönüştürür.
  /// Örn: fromLira(12.50) -> MoneyCents(1250)
  factory MoneyCents.fromLira(double lira) {
    return MoneyCents((lira * 100).round());
  }

  /// Kuruşu TL olarak döner.
  /// YALNIZCA ekranda veya raporda göstermek içindir; matematik işlemlerinde KULLANILMAZ.
  double toLira() => value / 100.0;

  /// Türkiye para formatına uygun formatlanmış metin: "12,50 ₺" veya "-1,50 ₺"
  String formatTL() {
    final isNegative = value < 0;
    final absVal = value.abs();
    final liraPart = absVal ~/ 100;
    final kurusPart = (absVal % 100).toString().padLeft(2, '0');
    return '${isNegative ? '-' : ''}$liraPart,$kurusPart ₺';
  }


  // ── Aritmetik Operatörler ──────────────────────────────────────────────────
  MoneyCents operator +(MoneyCents other) => MoneyCents(value + other.value);
  MoneyCents operator -(MoneyCents other) => MoneyCents(value - other.value);
  MoneyCents operator -() => MoneyCents(-value);

  /// Çarpma: miktar veya adet ile kuruşu çarpar.
  MoneyCents operator *(num multiplier) =>
      MoneyCents((value * multiplier).round());

  /// Yüzde hesabı: Örn: KDV veya İskonto hesaplarken kuruş hassasiyetinde yuvarlar.
  MoneyCents percentage(int percent) =>
      MoneyCents(((value * percent) / 100).round());

  // ── Karşılaştırma ve Eşitlik ───────────────────────────────────────────────
  bool operator >(MoneyCents other) => value > other.value;
  bool operator <(MoneyCents other) => value < other.value;
  bool operator >=(MoneyCents other) => value >= other.value;
  bool operator <=(MoneyCents other) => value <= other.value;

  bool get isPositive => value > 0;
  bool get isNegative => value < 0;
  bool get isZero => value == 0;

  @override
  int compareTo(MoneyCents other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MoneyCents && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '${value}c ($formatTL)';
}
