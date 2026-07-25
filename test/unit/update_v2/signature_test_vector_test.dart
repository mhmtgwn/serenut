// test/unit/update_v2/signature_test_vector_test.dart
// Serenut Platform — Cryptographic Signature Test Vectors & Parser Tests

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/update_v2/manifest_parser_service.dart';

void main() {
  group('Signature Test Vectors & Fixture Tests', () {
    late ManifestParserService parserService;

    setUp(() {
      parserService = ManifestParserService();
    });

    test('Rejects invalid signature test vector fixture', () async {
      final goldenJson = await File('test/fixtures/crypto/golden_manifest_v1.json').readAsString();
      final invalidSig = await File('test/fixtures/crypto/golden_manifest_v1_invalid.sig').readAsString();

      final result = await parserService.parseAndVerify(
        rawManifestContent: goldenJson,
        signature: invalidSig,
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Digital signature verification failed'));
    });

    test('Rejects tampered manifest content test vector fixture', () async {
      final tamperedJson = await File('test/fixtures/crypto/golden_manifest_v1_tampered.json').readAsString();
      final goldenSig = await File('test/fixtures/crypto/golden_manifest_v1.sig').readAsString();

      final result = await parserService.parseAndVerify(
        rawManifestContent: tamperedJson,
        signature: goldenSig,
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Digital signature verification failed'));
    });
  });
}
