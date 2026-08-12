/// Application-wide barcode identity rules.
///
/// UPC-A contains 12 digits. The same symbol can be represented as EAN-13 by
/// prefixing it with a zero. Serenut stores that pair in its UPC-A (12 digit)
/// form so imports, scanners and manual entry all address one product.
abstract final class BarcodeStandard {
  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  static String normalize(String rawBarcode) {
    final barcode = rawBarcode.trim();
    if (barcode.length == 13 &&
        barcode.startsWith('0') &&
        _digitsOnly.hasMatch(barcode)) {
      return barcode.substring(1);
    }
    return barcode;
  }

  static String? equivalent(String rawBarcode) {
    final barcode = rawBarcode.trim();
    if (!_digitsOnly.hasMatch(barcode)) return null;
    if (barcode.length == 12) return '0$barcode';
    if (barcode.length == 13 && barcode.startsWith('0')) {
      return barcode.substring(1);
    }
    return null;
  }

  static List<String> lookupCandidates(String rawBarcode) {
    final raw = rawBarcode.trim();
    final normalized = normalize(raw);
    final candidates = <String>[normalized];
    if (raw.isNotEmpty && raw != normalized) candidates.add(raw);
    final alias = equivalent(normalized);
    if (alias != null && !candidates.contains(alias)) candidates.add(alias);
    return candidates;
  }
}
