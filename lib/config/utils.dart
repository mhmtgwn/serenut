// lib/config/utils.dart

import 'package:intl/intl.dart';

extension IdShortener on String {
  /// Converts long generated database IDs to unique, short, human-friendly display IDs.
  /// Example: 'sale-1782150318456' -> 'S-318456'
  /// Example: 'order-1782150318456' -> 'O-318456'
  String get toShortId {
    final lower = toLowerCase();
    if (RegExp(r'^sp-\d{6,}$').hasMatch(lower)) {
      return toUpperCase();
    } else if ((lower.startsWith('sale-') || lower.startsWith('sale_')) &&
        length >= 5) {
      final idx = indexOf(RegExp(r'[-_]'));
      final suffix = substring(idx + 1);
      return 'S-${suffix.substring(suffix.length > 6 ? suffix.length - 6 : 0).toUpperCase()}';
    } else if ((lower.startsWith('order-') ||
            lower.startsWith('order_') ||
            lower.startsWith('ord-') ||
            lower.startsWith('ord_')) &&
        length >= 4) {
      final idx = indexOf(RegExp(r'[-_]'));
      final suffix = substring(idx + 1);
      return 'O-${suffix.substring(suffix.length > 6 ? suffix.length - 6 : 0).toUpperCase()}';
    } else if ((lower.startsWith('trans-') || lower.startsWith('trans_')) &&
        length >= 6) {
      final idx = indexOf(RegExp(r'[-_]'));
      final suffix = substring(idx + 1);
      return 'T-${suffix.substring(suffix.length > 6 ? suffix.length - 6 : 0).toUpperCase()}';
    }
    // Fallback for UUIDs or other IDs
    return length > 8 ? substring(0, 8).toUpperCase() : toUpperCase();
  }
}

extension TurkishNormalization on String {
  /// Converts string to standard Turkish uppercase (e.g. i -> İ, ı -> I)
  String get toTurkishUpperCase {
    return replaceAll('i', 'İ')
        .replaceAll('ı', 'I')
        .toUpperCase()
        .trim();
  }

  String get normalizeTurkish {
    return replaceAll('İ', 'i')
        .replaceAll('I', 'i')
        .replaceAll('Ş', 's')
        .replaceAll('Ç', 'c')
        .replaceAll('Ğ', 'g')
        .replaceAll('Ü', 'u')
        .replaceAll('Ö', 'o')
        .toLowerCase()
        .replaceAll('\u0307', '')
        .replaceAll('ı', 'i')
        .replaceAll('ş', 's')
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .trim();
  }
}

/// Generates an SQLite expression that transliterates Turkish characters
/// and converts ASCII to lowercase, allowing case-insensitive and diacritic-insensitive
/// matching directly inside SQLite queries without schema migrations.
String sqliteTurkishFold(String column) {
  final safe = 'COALESCE($column, \'\')';
  return "LOWER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE($safe, 'İ', 'i'), 'I', 'i'), 'ı', 'i'), 'Ş', 's'), 'ş', 's'), 'Ç', 'c'), 'ç', 'c'), 'Ğ', 'g'), 'ğ', 'g'), 'Ü', 'u'), 'ü', 'u'), 'Ö', 'o'), 'ö', 'o'))";
}

extension NumberFormatting on num {
  /// Format money/currency to Turkish Lira: e.g. 29666552.5 -> "₺29.666.552,50"
  String toTurkishCurrency({bool symbol = true, int decimalDigits = 2}) {
    final fmt = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: symbol ? '₺' : '',
      decimalDigits: decimalDigits,
    );
    return fmt.format(this).trim();
  }

  /// Format quantity/stock removing floating point inaccuracies (.000000004 or .999999998)
  /// e.g. 13276.649999999998 -> "13.276,65"
  /// e.g. 11469.100000000004 -> "11.469,1"
  /// e.g. 10.0 -> "10"
  String toTurkishQuantity({int maxDigits = 3}) {
    final d = toDouble();
    if (d % 1 == 0) {
      return NumberFormat.decimalPattern('tr_TR').format(d.toInt());
    }
    // Strip IEEE 754 precision noise (e.g. 13276.649999999998 -> 13276.65)
    final fixed = d.toStringAsFixed(maxDigits);
    final trimmed = fixed.contains('.')
        ? fixed.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')
        : fixed;
    final cleanDouble = double.tryParse(trimmed) ?? d;
    if (cleanDouble % 1 == 0) {
      return NumberFormat.decimalPattern('tr_TR').format(cleanDouble.toInt());
    }
    return NumberFormat.decimalPattern('tr_TR').format(cleanDouble);
  }
}

