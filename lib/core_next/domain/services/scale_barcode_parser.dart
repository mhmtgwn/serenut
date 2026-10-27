/// Domain service that parses in-store weighed scale barcodes (EAN-13).
///
/// In retail stores, markets, and nut shops, electronic label-printing scales
/// (e.g. Bizerba, Dibal, CAS, TEM, DIGI) print EAN-13 barcodes with embedded
/// product PLU and measured weight or pre-calculated total price.
///
/// Standard format (GS1 prefix 27, 28, 29):
/// - 2 digits: Prefix ('27' for weight/price, '28' or '29' for store internal weight/price)
/// - 5 digits: Product PLU code (e.g. '00142')
/// - 5 digits: Net weight in grams (e.g. '00450' -> 450 grams) OR price in kuruş (e.g. '04550' -> 45.50 TL)
/// - 1 digit:  EAN-13 Modulo-10 check digit
library;

/// Represents whether the 5-digit scale barcode payload contains weight or price.
enum ScaleBarcodeType {
  /// Payload digits represent net weight in grams (e.g. '00450' -> 450 grams).
  weightEmbedded,

  /// Payload digits represent pre-calculated total price in kuruş (e.g. '04550' -> 45.50 TL = 4550 kuruş).
  priceEmbedded,
}

class ScaleBarcodeResult {
  final bool isScaleBarcode;
  final String rawBarcode;
  final String prefix;
  final String plu;
  final int weightGrams;
  final int priceCents;
  final ScaleBarcodeType barcodeType;
  final List<String> pluCandidates;
  final bool isChecksumValid;

  const ScaleBarcodeResult({
    required this.isScaleBarcode,
    required this.rawBarcode,
    this.prefix = '',
    this.plu = '',
    this.weightGrams = 0,
    this.priceCents = 0,
    this.barcodeType = ScaleBarcodeType.weightEmbedded,
    this.pluCandidates = const [],
    this.isChecksumValid = false,
  });

  static const invalid = ScaleBarcodeResult(
    isScaleBarcode: false,
    rawBarcode: '',
  );

  bool get isValid =>
      isScaleBarcode &&
      isChecksumValid &&
      (barcodeType == ScaleBarcodeType.weightEmbedded
          ? weightGrams > 0
          : priceCents > 0);

  /// Calculates the effective net weight in grams.
  /// If [barcodeType] is [ScaleBarcodeType.priceEmbedded], weight is derived from unit price:
  /// `((priceCents * 1000) + (unitPriceCentsPerKg ~/ 2)) ~/ unitPriceCentsPerKg`.
  int calculateEffectiveWeightGrams(int unitPriceCentsPerKg) {
    if (barcodeType == ScaleBarcodeType.weightEmbedded) {
      return weightGrams;
    }
    if (unitPriceCentsPerKg <= 0) return 0;
    return ((priceCents * 1000) + (unitPriceCentsPerKg ~/ 2)) ~/
        unitPriceCentsPerKg;
  }

  /// Calculates the effective total sales price in kuruş (MoneyCents).
  /// If [barcodeType] is [ScaleBarcodeType.weightEmbedded], price is calculated as:
  /// `((unitPriceCentsPerKg * weightGrams) + 500) ~/ 1000`.
  int calculateEffectiveTotalCents(int unitPriceCentsPerKg) {
    if (barcodeType == ScaleBarcodeType.priceEmbedded) {
      return priceCents;
    }
    return ((unitPriceCentsPerKg * weightGrams) + 500) ~/ 1000;
  }
}

abstract final class ScaleBarcodeParser {
  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  /// Supported scale prefixes in Turkish retail and GS1 in-store standards.
  static const Set<String> supportedPrefixes = {'27', '28', '29'};

  /// Calculates the standard EAN-13 check digit for the first 12 digits.
  static int calculateEan13CheckDigit(String twelveDigits) {
    if (twelveDigits.length != 12 || !_digitsOnly.hasMatch(twelveDigits)) {
      return -1;
    }
    int oddSum = 0;
    int evenSum = 0;
    for (int i = 0; i < 12; i++) {
      final digit = twelveDigits.codeUnitAt(i) - 48; // '0' is ASCII 48
      if (i % 2 == 0) {
        oddSum += digit;
      } else {
        evenSum += digit;
      }
    }
    final total = oddSum + (evenSum * 3);
    return (10 - (total % 10)) % 10;
  }

  /// Verifies whether the full 13-digit EAN-13 barcode has a valid checksum.
  static bool verifyEan13Checksum(String thirteenDigits) {
    if (thirteenDigits.length != 13 || !_digitsOnly.hasMatch(thirteenDigits)) {
      return false;
    }
    final expectedCheckDigit =
        calculateEan13CheckDigit(thirteenDigits.substring(0, 12));
    final actualCheckDigit = thirteenDigits.codeUnitAt(12) - 48;
    return expectedCheckDigit == actualCheckDigit;
  }

  /// Checks if a barcode starts with a scale prefix and has 13 numeric digits.
  static bool isScaleBarcodeCandidate(String rawBarcode) {
    final barcode = rawBarcode.trim();
    if (barcode.length != 13 || !_digitsOnly.hasMatch(barcode)) {
      return false;
    }
    final prefix = barcode.substring(0, 2);
    return supportedPrefixes.contains(prefix);
  }

  /// Parses an EAN-13 scale barcode into PLU and net weight or price.
  ///
  /// By default, parses as [ScaleBarcodeType.weightEmbedded] (100% backward compatible).
  /// If [pricePrefixes] is provided and contains the barcode prefix, or if [defaultType] is
  /// [ScaleBarcodeType.priceEmbedded], the 5-digit payload is parsed as price in kuruş.
  static ScaleBarcodeResult? tryParse(
    String rawBarcode, {
    ScaleBarcodeType defaultType = ScaleBarcodeType.weightEmbedded,
    Set<String>? pricePrefixes,
    Set<String>? weightPrefixes,
  }) {
    final barcode = rawBarcode.trim();
    if (!isScaleBarcodeCandidate(barcode)) {
      return null;
    }

    final prefix = barcode.substring(0, 2);
    final isChecksumValid = verifyEan13Checksum(barcode);
    if (!isChecksumValid) {
      return ScaleBarcodeResult(
        isScaleBarcode: true,
        rawBarcode: barcode,
        prefix: prefix,
        isChecksumValid: false,
      );
    }

    final rawPlu = barcode.substring(2, 7); // 5 digits
    final rawValue = barcode.substring(7, 12); // 5 digits
    final parsedNumericValue = int.tryParse(rawValue) ?? 0;

    // Resolve barcode type
    ScaleBarcodeType resolvedType = defaultType;
    if (pricePrefixes != null && pricePrefixes.contains(prefix)) {
      resolvedType = ScaleBarcodeType.priceEmbedded;
    } else if (weightPrefixes != null && weightPrefixes.contains(prefix)) {
      resolvedType = ScaleBarcodeType.weightEmbedded;
    }

    final weightGrams =
        resolvedType == ScaleBarcodeType.weightEmbedded ? parsedNumericValue : 0;
    final priceCents =
        resolvedType == ScaleBarcodeType.priceEmbedded ? parsedNumericValue : 0;

    // Generate lookup candidates for matching in products table:
    // 1. Raw 5-digit PLU (e.g. '00142')
    // 2. Trimmed integer PLU (e.g. '142')
    // 3. Prefix + PLU (e.g. '2700142')
    final candidates = <String>[rawPlu];
    final intPlu = int.tryParse(rawPlu);
    if (intPlu != null) {
      final stripped = intPlu.toString();
      if (!candidates.contains(stripped)) {
        candidates.add(stripped);
      }
    }
    final prefixPlu = '$prefix$rawPlu';
    if (!candidates.contains(prefixPlu)) {
      candidates.add(prefixPlu);
    }

    return ScaleBarcodeResult(
      isScaleBarcode: true,
      rawBarcode: barcode,
      prefix: prefix,
      plu: rawPlu,
      weightGrams: weightGrams,
      priceCents: priceCents,
      barcodeType: resolvedType,
      pluCandidates: candidates,
      isChecksumValid: true,
    );
  }
}
