// lib/domain/models/update_v2/release_manifest.dart
// Serenut Platform — Client Release Manifest DTO (schemaVersion = 1)

import 'package:flutter/foundation.dart';

class UnsupportedSchemaException implements Exception {
  final int receivedVersion;
  final int supportedVersion;

  UnsupportedSchemaException({
    required this.receivedVersion,
    required this.supportedVersion,
  });

  @override
  String toString() =>
      'UnsupportedSchemaException: Received schemaVersion $receivedVersion, but client only supports up to $supportedVersion.';
}

class InvalidManifestException implements Exception {
  final String message;
  InvalidManifestException(this.message);

  @override
  String toString() => 'InvalidManifestException: $message';
}

@immutable
class BuildMetadata {
  final String commitHash;
  final int buildNumber;
  final String buildDate;
  final String signatureAlgorithm;

  const BuildMetadata({
    required this.commitHash,
    required this.buildNumber,
    required this.buildDate,
    required this.signatureAlgorithm,
  });

  factory BuildMetadata.fromJson(Map<String, dynamic> json) {
    return BuildMetadata(
      commitHash: json['commitHash'] as String? ?? '',
      buildNumber: json['buildNumber'] as int? ?? 0,
      buildDate: json['buildDate'] as String? ?? '',
      signatureAlgorithm: json['signatureAlgorithm'] as String? ?? 'RSA-SHA256',
    );
  }

  Map<String, dynamic> toJson() => {
        'commitHash': commitHash,
        'buildNumber': buildNumber,
        'buildDate': buildDate,
        'signatureAlgorithm': signatureAlgorithm,
      };
}

@immutable
class ReleaseCompatibility {
  final String minClientVersion;
  final String minimumUpdaterVersion;
  final String requiredBootstrapper;
  final String? requiredPreVersion;
  final bool migrationRequired;
  final int targetSchemaVersion;

  const ReleaseCompatibility({
    required this.minClientVersion,
    required this.minimumUpdaterVersion,
    required this.requiredBootstrapper,
    this.requiredPreVersion,
    required this.migrationRequired,
    required this.targetSchemaVersion,
  });

  factory ReleaseCompatibility.fromJson(Map<String, dynamic> json) {
    return ReleaseCompatibility(
      minClientVersion: json['minClientVersion'] as String? ?? '1.0.0',
      minimumUpdaterVersion:
          json['minimumUpdaterVersion'] as String? ?? '1.0.0',
      requiredBootstrapper: json['requiredBootstrapper'] as String? ?? '1',
      requiredPreVersion: json['requiredPreVersion'] as String?,
      migrationRequired: json['migrationRequired'] as bool? ?? false,
      targetSchemaVersion: json['targetSchemaVersion'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'minClientVersion': minClientVersion,
        'minimumUpdaterVersion': minimumUpdaterVersion,
        'requiredBootstrapper': requiredBootstrapper,
        'requiredPreVersion': requiredPreVersion,
        'migrationRequired': migrationRequired,
        'targetSchemaVersion': targetSchemaVersion,
      };
}

@immutable
class ReleaseRules {
  final bool isMandatory;
  final bool allowRollback;
  final int minFreeDiskMb;
  final int minRamMb;
  final List<String> supportedArchitectures;

  const ReleaseRules({
    required this.isMandatory,
    required this.allowRollback,
    required this.minFreeDiskMb,
    required this.minRamMb,
    required this.supportedArchitectures,
  });

  factory ReleaseRules.fromJson(Map<String, dynamic> json) {
    final rawArch = json['supportedArchitectures'];
    final archList =
        rawArch is List ? rawArch.map((e) => e.toString()).toList() : ['x64'];
    return ReleaseRules(
      isMandatory: json['isMandatory'] as bool? ?? false,
      allowRollback: json['allowRollback'] as bool? ?? true,
      minFreeDiskMb: json['minFreeDiskMb'] as int? ?? 300,
      minRamMb: json['minRamMb'] as int? ?? 2048,
      supportedArchitectures: archList,
    );
  }

  Map<String, dynamic> toJson() => {
        'isMandatory': isMandatory,
        'allowRollback': allowRollback,
        'minFreeDiskMb': minFreeDiskMb,
        'minRamMb': minRamMb,
        'supportedArchitectures': supportedArchitectures,
      };
}

@immutable
class ReleaseArtifact {
  final String type;
  final String filename;
  final String downloadUrl;
  final int sizeBytes;
  final String sha256;
  final String signature;

  const ReleaseArtifact({
    required this.type,
    required this.filename,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.sha256,
    required this.signature,
  });

  factory ReleaseArtifact.fromJson(Map<String, dynamic> json) {
    final sha = (json['sha256'] as String? ?? '').trim();
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha)) {
      throw InvalidManifestException('Invalid SHA-256 format: $sha');
    }
    return ReleaseArtifact(
      type: json['type'] as String? ?? 'installer_windows',
      filename: json['filename'] as String? ?? '',
      downloadUrl: json['downloadUrl'] as String? ?? '',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      sha256: sha,
      signature: json['signature'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'filename': filename,
        'downloadUrl': downloadUrl,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        'signature': signature,
      };
}

@immutable
class ReleaseManifest {
  static const int currentSupportedSchemaVersion = 1;

  final int schemaVersion;
  final String manifestVersion;
  final String releaseId;
  final String version;
  final String channel;
  final String publishedAt;
  final BuildMetadata buildMetadata;
  final ReleaseCompatibility compatibility;
  final ReleaseRules rules;
  final List<ReleaseArtifact> artifacts;

  const ReleaseManifest({
    required this.schemaVersion,
    required this.manifestVersion,
    required this.releaseId,
    required this.version,
    required this.channel,
    required this.publishedAt,
    required this.buildMetadata,
    required this.compatibility,
    required this.rules,
    required this.artifacts,
  });

  factory ReleaseManifest.fromJson(Map<String, dynamic> json) {
    final schemaVer = json['schemaVersion'] as int?;
    if (schemaVer == null) {
      throw InvalidManifestException('Missing schemaVersion in manifest.');
    }
    if (schemaVer > currentSupportedSchemaVersion) {
      throw UnsupportedSchemaException(
        receivedVersion: schemaVer,
        supportedVersion: currentSupportedSchemaVersion,
      );
    }

    final rawArtifacts = json['artifacts'];
    if (rawArtifacts == null || rawArtifacts is! List || rawArtifacts.isEmpty) {
      throw InvalidManifestException(
          'Manifest must contain at least one artifact.');
    }

    return ReleaseManifest(
      schemaVersion: schemaVer,
      manifestVersion: json['manifestVersion'] as String? ?? '1.0',
      releaseId: json['releaseId'] as String? ?? '',
      version: json['version'] as String? ?? '',
      channel: json['channel'] as String? ?? 'stable',
      publishedAt: json['publishedAt'] as String? ?? '',
      buildMetadata: BuildMetadata.fromJson(
          json['buildMetadata'] as Map<String, dynamic>? ?? {}),
      compatibility: ReleaseCompatibility.fromJson(
          json['compatibility'] as Map<String, dynamic>? ?? {}),
      rules:
          ReleaseRules.fromJson(json['rules'] as Map<String, dynamic>? ?? {}),
      artifacts: rawArtifacts
          .map((e) => ReleaseArtifact.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'manifestVersion': manifestVersion,
        'releaseId': releaseId,
        'version': version,
        'channel': channel,
        'publishedAt': publishedAt,
        'buildMetadata': buildMetadata.toJson(),
        'compatibility': compatibility.toJson(),
        'rules': rules.toJson(),
        'artifacts': artifacts.map((e) => e.toJson()).toList(),
      };
}
