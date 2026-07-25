// lib/infrastructure/services/crypto/signature_verifier_interface.dart
// Serenut Platform — Cryptographic Verification Abstraction Interface

import 'dart:io';

abstract class SignatureVerifier {
  /// Verify the digital signature of raw manifest JSON string using public key.
  Future<bool> verifyManifest({
    required String manifestContent,
    required String signature,
    String? publicKeyOverride,
  });

  /// Verify the SHA-256 integrity and digital signature of a downloaded artifact file.
  Future<bool> verifyArtifact({
    required File file,
    required String expectedSha256,
    required String signature,
    String? publicKeyOverride,
  });
}
