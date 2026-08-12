import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/barcode_standard.dart';

void main() {
  group('BarcodeStandard', () {
    test('uses UPC-A as the common identity for zero-prefixed EAN-13', () {
      expect(BarcodeStandard.normalize('0123456789012'), '123456789012');
      expect(BarcodeStandard.normalize('123456789012'), '123456789012');
      expect(
        BarcodeStandard.lookupCandidates('0123456789012'),
        ['123456789012', '0123456789012'],
      );
    });

    test('preserves other GTIN and internal barcode formats', () {
      expect(BarcodeStandard.normalize('8690000000001'), '8690000000001');
      expect(BarcodeStandard.normalize('00012345'), '00012345');
      expect(BarcodeStandard.normalize('URUN-001'), 'URUN-001');
    });
  });
}
