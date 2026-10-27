import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/scale_barcode_parser.dart';

void main() {
  group('ScaleBarcodeParser Tests', () {
    test('Correctly calculates and validates EAN-13 check digit', () {
      // 270014200450 -> check digit must be 5
      final checkDigit =
          ScaleBarcodeParser.calculateEan13CheckDigit('270014200450');
      expect(checkDigit, equals(5));

      expect(
          ScaleBarcodeParser.verifyEan13Checksum('2700142004505'), isTrue);
      expect(
          ScaleBarcodeParser.verifyEan13Checksum('2700142004509'), isFalse);
    });

    test('Parses valid 27 series weight barcode with 450 grams (default backward compatible)', () {
      const barcode = '2700142004505';
      final result = ScaleBarcodeParser.tryParse(barcode);

      expect(result, isNotNull);
      expect(result!.isScaleBarcode, isTrue);
      expect(result.barcodeType, equals(ScaleBarcodeType.weightEmbedded));
      expect(result.isChecksumValid, isTrue);
      expect(result.isValid, isTrue);
      expect(result.prefix, equals('27'));
      expect(result.plu, equals('00142'));
      expect(result.weightGrams, equals(450));
      expect(result.priceCents, equals(0));
      expect(result.pluCandidates,
          containsAllInOrder(['00142', '142', '2700142']));

      // Effective weight and price calculations with unit price 400 TL/kg (40.000 kuruş)
      // 450g * 40.000 / 1000 = 18.000 kuruş (180.00 TL)
      expect(result.calculateEffectiveWeightGrams(40000), equals(450));
      expect(result.calculateEffectiveTotalCents(40000), equals(18000));
    });

    test('Parses valid 28 series scale barcode with 1250 grams', () {
      // 280005501250 -> check digit is 2
      const barcode = '2800055012502';
      final result = ScaleBarcodeParser.tryParse(barcode);

      expect(result, isNotNull);
      expect(result!.isScaleBarcode, isTrue);
      expect(result.isChecksumValid, isTrue);
      expect(result.isValid, isTrue);
      expect(result.prefix, equals('28'));
      expect(result.plu, equals('00055'));
      expect(result.weightGrams, equals(1250));
      expect(result.pluCandidates,
          containsAllInOrder(['00055', '55', '2800055']));
    });

    test('Parses price-embedded scale barcode (45.50 TL = 4550 kuruş)', () {
      // 280014204550 -> check digit is 5
      const barcode = '2800142045505';
      final result = ScaleBarcodeParser.tryParse(
        barcode,
        defaultType: ScaleBarcodeType.priceEmbedded,
      );

      expect(result, isNotNull);
      expect(result!.isScaleBarcode, isTrue);
      expect(result.barcodeType, equals(ScaleBarcodeType.priceEmbedded));
      expect(result.isValid, isTrue);
      expect(result.prefix, equals('28'));
      expect(result.plu, equals('00142'));
      expect(result.priceCents, equals(4550)); // 45.50 TL
      expect(result.weightGrams, equals(0));

      // With product unit price: 100 TL/kg (10.000 kuruş/kg)
      // 4550 kuruş / 10000 kuruş/kg * 1000 = 455 grams
      expect(result.calculateEffectiveWeightGrams(10000), equals(455));
      expect(result.calculateEffectiveTotalCents(10000), equals(4550));
    });

    test('Parses price-embedded scale barcode using prefix configuration', () {
      // 27 prefix configured as price-embedded
      // 270014200450 -> check digit 5, payload 00450 -> 4.50 TL = 450 kuruş
      const barcode = '2700142004505';
      final result = ScaleBarcodeParser.tryParse(
        barcode,
        pricePrefixes: {'27'},
      );

      expect(result, isNotNull);
      expect(result!.barcodeType, equals(ScaleBarcodeType.priceEmbedded));
      expect(result.priceCents, equals(450));
      expect(result.weightGrams, equals(0));
    });

    test('Rejects barcode when check digit is corrupted/invalid', () {
      const corruptedBarcode = '2700142004508'; // Expected 5, received 8
      final result = ScaleBarcodeParser.tryParse(corruptedBarcode);

      expect(result, isNotNull);
      expect(result!.isScaleBarcode, isTrue);
      expect(result.isChecksumValid, isFalse);
      expect(result.isValid, isFalse);
    });

    test('Ignores regular commercial barcodes (e.g. 869... Turkish packaged items)',
        () {
      const standardBarcode = '8690504033221';
      final isCandidate =
          ScaleBarcodeParser.isScaleBarcodeCandidate(standardBarcode);
      expect(isCandidate, isFalse);

      final result = ScaleBarcodeParser.tryParse(standardBarcode);
      expect(result, isNull);
    });

    test('Rejects invalid input (non-numeric, short length, null/empty)', () {
      expect(ScaleBarcodeParser.tryParse(''), isNull);
      expect(ScaleBarcodeParser.tryParse('2700142'), isNull);
      expect(ScaleBarcodeParser.tryParse('270014200450A'), isNull);
      expect(ScaleBarcodeParser.tryParse('ABCDEFGHIJKLM'), isNull);
    });
  });
}
