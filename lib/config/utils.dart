// lib/config/utils.dart

extension IdShortener on String {
  /// Converts long generated database IDs to unique, short, human-friendly display IDs.
  /// Example: 'sale-1782150318456' -> 'S-318456'
  /// Example: 'order-1782150318456' -> 'O-318456'
  String get toShortId {
    final lower = toLowerCase();
    if ((lower.startsWith('sale-') || lower.startsWith('sale_')) &&
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
