// lib/domain/models/money.dart
// Serenut OS — Finansal Para Değer Nesnesi (Money Value Object)
//
// IEEE 754 kayan noktalı sayı (double) sapmalarını önlemek için
// tüm parasal değerleri tam sayı kuruş (minor units) olarak saklar.
// Değişmezdir (immutable).

import 'package:flutter/foundation.dart';
import '../utils/safe_money.dart';

@immutable
class Money implements Comparable<Money> {
  /// Kuruş (minor unit) cinsinden tam sayı değer.
  /// Örn: 100 TL = 10000 kuruş, 12.34 TL = 1234 kuruş.
  final int cents;

  /// Para birimi (ISO 4217, varsayılan TRY).
  final String currency;

  const Money(this.cents, {this.currency = 'TRY'});

  /// Sıfır tutarlı para.
  const Money.zero({String currency = 'TRY'}) : this(0, currency: currency);

  /// Kuruş cinsinden oluşturur.
  factory Money.fromCents(int cents, {String currency = 'TRY'}) {
    return Money(cents, currency: currency);
  }

  /// TL (lira) ondalıklı değerinden tam sayı kuruşa yuvarlayarak oluşturur.
  factory Money.fromLira(double lira, {String currency = 'TRY'}) {
    return Money(SafeMoney.toCents(lira), currency: currency);
  }

  /// Dinamik girişten güvenle Money üretir (int, double, num, string).
  factory Money.from(dynamic value, {String currency = 'TRY'}) {
    if (value == null) return Money.zero(currency: currency);
    if (value is Money) return value;
    if (value is int) {
      // Eğer doğrudan kuruş olduğu belirtilmemişse veya tam sayı geldiyse
      // Lira kabul edip kuruşa çevir (örn: 10 -> 1000 kuruş)
      return Money.fromLira(value.toDouble(), currency: currency);
    }
    if (value is double) {
      return Money.fromLira(value, currency: currency);
    }
    if (value is String) {
      final clean = value.replaceAll('₺', '').replaceAll('TL', '').trim();
      final parsed = double.tryParse(clean.replaceAll(',', '.'));
      if (parsed != null) {
        return Money.fromLira(parsed, currency: currency);
      }
    }
    return Money.zero(currency: currency);
  }

  /// TL cinsinden ondalıklı değer (yalnızca UI gösterimi ve legacy köprüler için).
  double get inLira => SafeMoney.fromCents(cents);

  /// Sıfır mı?
  bool get isZero => cents == 0;

  /// Pozitif mi (> 0)?
  bool get isPositive => cents > 0;

  /// Negatif mi (< 0)?
  bool get isNegative => cents < 0;

  /// Mutlak değer
  Money abs() => Money(cents.abs(), currency: currency);

  // --- Operatörler ---

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(cents + other.cents, currency: currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(cents - other.cents, currency: currency);
  }

  Money operator -() {
    return Money(-cents, currency: currency);
  }

  Money operator *(num factor) {
    return Money((cents * factor).round(), currency: currency);
  }

  Money operator /(num divisor) {
    if (divisor == 0) throw ArgumentError('Bölen sıfır olamaz');
    return Money((cents / divisor).round(), currency: currency);
  }

  bool operator <(Money other) {
    _assertSameCurrency(other);
    return cents < other.cents;
  }

  bool operator <=(Money other) {
    _assertSameCurrency(other);
    return cents <= other.cents;
  }

  bool operator >(Money other) {
    _assertSameCurrency(other);
    return cents > other.cents;
  }

  bool operator >=(Money other) {
    _assertSameCurrency(other);
    return cents >= other.cents;
  }

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return cents.compareTo(other.cents);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Money && other.cents == cents && other.currency == currency;
  }

  @override
  int get hashCode => Object.hash(cents, currency);

  /// Taksitlere böler (kuruş kayıpsız).
  List<Money> split(int count, {bool roundBaseToWholeUnits = true}) {
    if (count <= 0) return const [];
    final liraParts = SafeMoney.splitInstallments(
      totalAmount: inLira,
      count: count,
      roundBaseToWholeUnits: roundBaseToWholeUnits,
    );
    return liraParts.map((p) => Money.fromLira(p, currency: currency)).toList();
  }

  /// Biçimlendirilmiş metin çıktısı (örn: 1.250,50 ₺).
  String format({String symbol = '₺'}) {
    return SafeMoney.format(inLira, symbol: symbol);
  }

  @override
  String toString() => format();

  /// JSON serialization (tam sayı kuruş olarak)
  int toJson() => cents;

  void _assertSameCurrency(Money other) {
    if (currency != other.currency) {
      throw ArgumentError(
        'Farklı para birimleri arasında işlem yapılamaz: $currency != ${other.currency}',
      );
    }
  }
}
