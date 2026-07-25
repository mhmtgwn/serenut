// test/unit/update_v2/canonical_json_test.dart
// Serenut Platform — Canonical JSON Serializer (RFC 8785) Tests

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/crypto/canonical_json.dart';

void main() {
  group('CanonicalJsonSerializer Tests', () {
    test('Alphabetically sorts map keys deterministically', () {
      final mapA = {'z': 1, 'b': 2, 'a': 3};
      final mapB = {'a': 3, 'z': 1, 'b': 2};

      final canonicalA = CanonicalJsonSerializer.encode(mapA);
      final canonicalB = CanonicalJsonSerializer.encode(mapB);

      expect(canonicalA, equals('{"a":3,"b":2,"z":1}'));
      expect(canonicalA, equals(canonicalB));
    });

    test('Recursively sorts nested objects and lists', () {
      final nested = {
        'rules': {'minRamMb': 2048, 'isMandatory': false},
        'artifacts': [
          {'type': 'installer', 'size': 100},
          {'type': 'updater', 'size': 50}
        ]
      };

      final canonical = CanonicalJsonSerializer.encode(nested);
      expect(
        canonical,
        equals('{"artifacts":[{"size":100,"type":"installer"},{"size":50,"type":"updater"}],"rules":{"isMandatory":false,"minRamMb":2048}}'),
      );
    });
  });
}
