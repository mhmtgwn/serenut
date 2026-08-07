// lib/domain/models/update_v2/bootstrapper_manifest.dart
// Serenut Platform — Bootstrapper Handshake Manifest DTO (schemaVersion = 1)

import 'package:flutter/foundation.dart';
import 'package:serenutos/domain/models/update_v2/release_manifest.dart';

@immutable
class BootstrapperManifest {
  static const int currentSupportedSchemaVersion = 1;

  final int schemaVersion;
  final String correlationId;
  final int appPid;
  final String targetVersion;
  final String installerPath;
  final String targetDir;
  final String backupDir;
  final String postLaunchExe;

  const BootstrapperManifest({
    required this.schemaVersion,
    required this.correlationId,
    required this.appPid,
    required this.targetVersion,
    required this.installerPath,
    required this.targetDir,
    required this.backupDir,
    required this.postLaunchExe,
  });

  factory BootstrapperManifest.fromJson(Map<String, dynamic> json) {
    final schemaVer = json['schemaVersion'] as int?;
    if (schemaVer == null) {
      throw InvalidManifestException(
          'Missing schemaVersion in bootstrapper manifest.');
    }
    if (schemaVer > currentSupportedSchemaVersion) {
      throw UnsupportedSchemaException(
        receivedVersion: schemaVer,
        supportedVersion: currentSupportedSchemaVersion,
      );
    }

    return BootstrapperManifest(
      schemaVersion: schemaVer,
      correlationId: json['correlationId'] as String? ?? '',
      appPid: json['appPid'] as int? ?? 0,
      targetVersion: json['targetVersion'] as String? ?? '',
      installerPath: json['installerPath'] as String? ?? '',
      targetDir: json['targetDir'] as String? ?? '',
      backupDir: json['backupDir'] as String? ?? '',
      postLaunchExe: json['postLaunchExe'] as String? ?? 'serenutos.exe',
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'correlationId': correlationId,
        'appPid': appPid,
        'targetVersion': targetVersion,
        'installerPath': installerPath,
        'targetDir': targetDir,
        'backupDir': backupDir,
        'postLaunchExe': postLaunchExe,
      };
}
