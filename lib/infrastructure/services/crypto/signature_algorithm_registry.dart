// lib/infrastructure/services/crypto/signature_algorithm_registry.dart
// Serenut Platform — Cryptographic Signature Algorithm Registry

import 'package:flutter/foundation.dart';
import 'package:serenutos/infrastructure/services/crypto/rsa_sha256_signature_verifier.dart';
import 'package:serenutos/infrastructure/services/crypto/signature_verifier_interface.dart';

class SignatureAlgorithmRegistry {
  final Map<String, SignatureVerifier> _verifiers = {};

  SignatureAlgorithmRegistry({
    SignatureVerifier? defaultRsaVerifier,
  }) {
    registerVerifier(
      'RSA-SHA256',
      defaultRsaVerifier ?? RsaSha256SignatureVerifier(),
    );
  }

  void registerVerifier(String algorithmName, SignatureVerifier verifier) {
    _verifiers[algorithmName.toUpperCase()] = verifier;
  }

  SignatureVerifier? getVerifier(String algorithmName) {
    final verifier = _verifiers[algorithmName.toUpperCase()];
    if (verifier == null) {
      debugPrint(
          '[SignatureAlgorithmRegistry] Unsupported algorithm: $algorithmName');
    }
    return verifier;
  }

  bool supports(String algorithmName) {
    return _verifiers.containsKey(algorithmName.toUpperCase());
  }

  List<String> get supportedAlgorithms => _verifiers.keys.toList();
}
