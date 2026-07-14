// lib/domain/services/update_client.dart
// Serenut Platform — Update Client Service
// Implements Manifest checking, SHA256 integrity validation, and mock download/migration routines.
// Created: 04 Jul 2026

import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

class UpdateManifest {
  final String latestVersion;
  final String minRequiredVersion;
  final bool isForceUpdate;
  final String downloadUrl;
  final String sha256;
  final String releaseNotes;

  const UpdateManifest({
    required this.latestVersion,
    required this.minRequiredVersion,
    required this.isForceUpdate,
    required this.downloadUrl,
    required this.sha256,
    required this.releaseNotes,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    return UpdateManifest(
      latestVersion: json['latestVersion'] as String? ?? '1.0.0+1',
      minRequiredVersion: json['minRequiredVersion'] as String? ?? '1.0.0+1',
      isForceUpdate: json['isForceUpdate'] as bool? ?? false,
      downloadUrl: json['downloadUrl'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      releaseNotes: json['releaseNotes'] as String? ?? '',
    );
  }
}

class UpdateClient {
  final ApiClient _apiClient;

  UpdateClient(this._apiClient);

  /// Fetch the latest update manifest from the update endpoint.
  Future<UpdateManifest?> checkForUpdates() async {
    try {
      final response = await _apiClient.get('/version/check');
      if (response.statusCode != 200) return null;
      return UpdateManifest.fromJson(response.json);
    } catch (_) {
      return null;
    }
  }

  /// Downloads the update package.
  /// For Phase 1 (no real VPS), this writes a mock package file to mock download.
  Future<File> downloadUpdate(String url, String destinationPath) async {
    final file = File(destinationPath);
    // Write fake binary update payload
    await file.writeAsString('SERENUT_UPDATE_BINARY_PAYLOAD_MOCK_2026');
    return file;
  }

  /// Calculates the SHA256 of the downloaded file and compares it to expected hash.
  Future<bool> verifyChecksum(String filePath, String expectedSha256) async {
    final file = File(filePath);
    if (!await file.exists()) return false;

    final bytes = await file.readAsBytes();
    final hash = sha256.convert(bytes).toString();
    return hash.toLowerCase() == expectedSha256.toLowerCase();
  }

  /// Prepares the system for schema migration and mock restarts.
  Future<bool> triggerUpdateAndRestart(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return false;

    // Simulate trigger action (e.g. system flag update or platform trigger)
    return true;
  }
}
