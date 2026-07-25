// lib/infrastructure/services/update_v2/manifest_parser_service.dart
// Serenut Platform — Client Manifest Parser & Validator Service

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:serenutos/domain/models/update_v2/release_manifest.dart';
import 'package:serenutos/infrastructure/services/crypto/canonical_json.dart';
import 'package:serenutos/infrastructure/services/crypto/signature_algorithm_registry.dart';

class ManifestValidationResult {
  final bool isValid;
  final ReleaseManifest? manifest;
  final String? errorMessage;

  ManifestValidationResult({
    required this.isValid,
    this.manifest,
    this.errorMessage,
  });

  factory ManifestValidationResult.success(ReleaseManifest manifest) =>
      ManifestValidationResult(isValid: true, manifest: manifest);

  factory ManifestValidationResult.failure(String message) =>
      ManifestValidationResult(isValid: false, errorMessage: message);
}

class ManifestParserService {
  final SignatureAlgorithmRegistry _algorithmRegistry;

  ManifestParserService({
    SignatureAlgorithmRegistry? algorithmRegistry,
  }) : _algorithmRegistry = algorithmRegistry ?? SignatureAlgorithmRegistry();

  /// Parses raw manifest JSON content, applies canonical normalization, verifies RSA signature via algorithm registry, and evaluates schema compatibility.
  Future<ManifestValidationResult> parseAndVerify({
    required String rawManifestContent,
    required String signature,
    String? publicKeyOverride,
  }) async {
    if (rawManifestContent.trim().isEmpty) {
      return ManifestValidationResult.failure('Manifest content is empty.');
    }

    try {
      final decodedJson = jsonDecode(rawManifestContent);
      if (decodedJson is! Map<String, dynamic>) {
        return ManifestValidationResult.failure('Manifest root must be a JSON object.');
      }

      // 1. Parse into strongly-typed DTO (validates schemaVersion & SHA formats)
      final manifest = ReleaseManifest.fromJson(decodedJson);

      // 2. Resolve signature verifier from algorithm registry
      final algorithmName = manifest.buildMetadata.signatureAlgorithm;
      final verifier = _algorithmRegistry.getVerifier(algorithmName);
      if (verifier == null) {
        return ManifestValidationResult.failure(
            'Unsupported signature algorithm: $algorithmName');
      }

      // 3. Apply RFC 8785 Canonical JSON normalization prior to signature check
      final canonicalContent = CanonicalJsonSerializer.encode(decodedJson);

      // 4. Verify digital signature
      final isSignatureValid = await verifier.verifyManifest(
        manifestContent: canonicalContent,
        signature: signature,
        publicKeyOverride: publicKeyOverride,
      );

      if (!isSignatureValid) {
        return ManifestValidationResult.failure(
            'Digital signature verification failed for algorithm $algorithmName.');
      }

      return ManifestValidationResult.success(manifest);
    } on UnsupportedSchemaException catch (e) {
      return ManifestValidationResult.failure(e.toString());
    } on InvalidManifestException catch (e) {
      return ManifestValidationResult.failure(e.toString());
    } catch (e) {
      return ManifestValidationResult.failure('Unexpected manifest parse failure: $e');
    }
  }
}
