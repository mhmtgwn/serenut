// lib/infrastructure/services/crypto/rsa_sha256_signature_verifier.dart
// Serenut Platform — Concrete RSA-256 Signature Verifier

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:serenutos/infrastructure/services/crypto/signature_verifier_interface.dart';

class RsaSha256SignatureVerifier implements SignatureVerifier {
  final String _defaultModulus;
  final String _defaultExponent;

  RsaSha256SignatureVerifier({
    String? defaultModulus,
    String defaultExponent = '65537',
  })  : _defaultModulus = defaultModulus ??
            const String.fromEnvironment(
              'RELEASE_RSA_MODULUS',
              defaultValue:
                  '3449922726363179470659921245535684630300492654532437255746697311487433705207620078360146175262200564212115072203518845406307821291129638222378043187972392850846345912390979905834639566931161576390748445853906124348180328313940380498709980101038109866401225599162893747922802147146484478281479689082845721560118661652738870231333196772660376302669775603708425321811689618483090921029022185338799084539601318498833413093166619325530412311590045095602271949379471747671953247049882796917925074523654788034370681289729842293780163918242300732821377646830456838938160865451919938731524572438106832295148308047338821987614234483300149373860496107379048578169216363255928721871306398682703900462599272862074986934347810178783333570007477846744604243602688690279216651127156176586214166889283255763206243281734412184907286562680369307272497027670281380880448568050544802260513300233457790014608227005280587155207280202638502277137201',
            ),
        _defaultExponent = defaultExponent;

  @override
  Future<bool> verifyManifest({
    required String manifestContent,
    required String signature,
    String? publicKeyOverride,
  }) async {
    if (signature.trim().isEmpty) {
      debugPrint('[SignatureVerifier] Rejecting empty manifest signature.');
      return false;
    }

    final modulusStr = publicKeyOverride ?? _defaultModulus;
    if (modulusStr.isEmpty) {
      debugPrint(
          '[SignatureVerifier] Rejecting manifest verify due to unconfigured RSA public key.');
      return false;
    }

    try {
      final payloadBytes = utf8.encode(manifestContent.trim());
      final signatureBytes = base64.decode(signature.trim());

      final modulus = BigInt.parse(modulusStr);
      final publicExponent = BigInt.parse(_defaultExponent);

      final publicKey = RSAPublicKey(modulus, publicExponent);
      final verifier = RSASigner(SHA256Digest(), '0609608648016503040201');
      verifier.init(false, PublicKeyParameter<RSAPublicKey>(publicKey));

      final rsaSignature = RSASignature(signatureBytes);
      final valid = verifier.verifySignature(payloadBytes, rsaSignature);
      debugPrint('[SignatureVerifier] Manifest RSA signature valid=$valid');
      return valid;
    } catch (e) {
      debugPrint('[SignatureVerifier] Manifest RSA verification exception: $e');
      return false;
    }
  }

  @override
  Future<bool> verifyArtifact({
    required File file,
    required String expectedSha256,
    required String signature,
    String? publicKeyOverride,
  }) async {
    if (!await file.exists()) {
      debugPrint(
          '[SignatureVerifier] Artifact file does not exist: ${file.path}');
      return false;
    }

    // 1. Stream-based SHA-256 verification (prevents memory loading OOM)
    final stream = file.openRead();
    final computedHashDigest = await sha256.bind(stream).first;
    final actualHash = computedHashDigest.toString().toLowerCase();
    final expectedHash = expectedSha256.trim().toLowerCase();

    final shaMatches = actualHash == expectedHash;
    debugPrint(
        '[SignatureVerifier] Artifact SHA-256 match=$shaMatches (expected=$expectedHash actual=$actualHash)');
    if (!shaMatches) return false;

    // 2. RSA Digital Signature verification on the computed SHA-256 hash string
    final modulusStr = publicKeyOverride ?? _defaultModulus;
    if (signature.trim().isEmpty || modulusStr.isEmpty) {
      debugPrint(
          '[SignatureVerifier] Rejecting artifact verify due to empty signature or missing RSA key.');
      return false;
    }

    try {
      final payloadBytes = utf8.encode(actualHash);
      final signatureBytes = base64.decode(signature.trim());

      final modulus = BigInt.parse(modulusStr);
      final publicExponent = BigInt.parse(_defaultExponent);

      final publicKey = RSAPublicKey(modulus, publicExponent);
      final verifier = RSASigner(SHA256Digest(), '0609608648016503040201');
      verifier.init(false, PublicKeyParameter<RSAPublicKey>(publicKey));

      final rsaSignature = RSASignature(signatureBytes);
      final valid = verifier.verifySignature(payloadBytes, rsaSignature);
      debugPrint('[SignatureVerifier] Artifact RSA signature valid=$valid');
      return valid;
    } catch (e) {
      debugPrint('[SignatureVerifier] Artifact RSA verification exception: $e');
      return false;
    }
  }
}
