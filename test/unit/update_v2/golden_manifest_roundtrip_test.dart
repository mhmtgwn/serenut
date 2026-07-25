// test/unit/update_v2/golden_manifest_roundtrip_test.dart
// Serenut Platform — Golden Manifest Roundtrip Serialization Tests (JSON -> DTO -> JSON -> DTO)

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/update_v2/release_manifest.dart';
import 'package:serenutos/infrastructure/services/crypto/canonical_json.dart';

void main() {
  group('Golden Manifest Roundtrip Tests', () {
    test('JSON -> DTO -> JSON -> DTO roundtrip equality', () async {
      final fixtureFile = File('test/fixtures/crypto/golden_manifest_v1.json');
      final rawContent = await fixtureFile.readAsString();
      final initialJson = jsonDecode(rawContent) as Map<String, dynamic>;

      // 1. First Pass: JSON -> DTO
      final manifestDto1 = ReleaseManifest.fromJson(initialJson);

      // 2. Second Pass: DTO -> Canonical JSON
      final reserializedCanonicalJsonStr = CanonicalJsonSerializer.encode(manifestDto1.toJson());

      // 3. Third Pass: Reserialized JSON -> DTO 2
      final reserializedMap = jsonDecode(reserializedCanonicalJsonStr) as Map<String, dynamic>;
      final manifestDto2 = ReleaseManifest.fromJson(reserializedMap);

      // 4. Verify exact equality across fields
      expect(manifestDto1.schemaVersion, equals(manifestDto2.schemaVersion));
      expect(manifestDto1.releaseId, equals(manifestDto2.releaseId));
      expect(manifestDto1.version, equals(manifestDto2.version));
      expect(manifestDto1.artifacts.length, equals(manifestDto2.artifacts.length));
      expect(manifestDto1.artifacts.first.sha256, equals(manifestDto2.artifacts.first.sha256));

      // 5. Canonical JSON representations must be byte-for-byte identical
      final canonicalStr1 = CanonicalJsonSerializer.encode(manifestDto1.toJson());
      final canonicalStr2 = CanonicalJsonSerializer.encode(manifestDto2.toJson());
      expect(canonicalStr1, equals(canonicalStr2));
    });
  });
}
