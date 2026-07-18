// lib/domain/services/version_checker.dart
import 'dart:io';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/config/environment.dart';

class VersionCheckResult {
  final String latestVersion;
  final String minRequiredVersion;
  final bool isForceUpdate;
  final String downloadUrl;
  final int schemaVersion;
  final String releaseNotes;
  final String? sha256Hash;
  final String? signature;
  final int? fileSizeBytes;

  VersionCheckResult({
    required this.latestVersion,
    required this.minRequiredVersion,
    required this.isForceUpdate,
    required this.downloadUrl,
    required this.schemaVersion,
    required this.releaseNotes,
    this.sha256Hash,
    this.signature,
    this.fileSizeBytes,
  });

  factory VersionCheckResult.fromJson(Map<String, dynamic> json) {
    String url = (json['download_url'] ?? json['downloadUrl']) as String? ?? '';
    if (url.isNotEmpty && !url.startsWith('http')) {
      final base = EnvironmentConfig.current.apiBaseUrl;
      final uri = Uri.parse(base);
      final hostUrl = '${uri.scheme}://${uri.host}${uri.hasPort ? ":${uri.port}" : ""}';
      url = '$hostUrl$url';
    }
    return VersionCheckResult(
      latestVersion:
          (json['latest_version'] ?? json['latestVersion']) as String? ??
              '1.0.0+1',
      minRequiredVersion: (json['min_required_version'] ??
              json['minRequiredVersion']) as String? ??
          '1.0.0+1',
      isForceUpdate:
          (json['is_force_update'] ?? json['isForceUpdate']) as bool? ?? false,
      downloadUrl: url,
      schemaVersion:
          (json['schema_version'] ?? json['schemaVersion']) as int? ?? 1,
      releaseNotes:
          (json['release_notes'] ?? json['releaseNotes']) as String? ?? '',
      sha256Hash: (json['sha256_hash'] ?? json['sha256Hash']) as String?,
      signature: json['signature'] as String?,
      fileSizeBytes: (json['file_size_bytes'] ?? json['fileSizeBytes']) as int?,
    );
  }
}

class VersionChecker {
  final ApiClient _apiClient;

  VersionChecker({
    ApiClient? apiClient,
  }) : _apiClient = apiClient ?? ApiClient();

  static const String currentVersion = '1.0.1+2'; // Current app version
  static const int currentSchemaVersion = 1;

  String get _platform => Platform.isAndroid ? 'android' : 'windows';

  /// Check version from backend and decide if a force update is required
  Future<bool> checkForceUpdateRequired() async {
    try {
      final response = await _apiClient.get(
          '/updates/check?platform=$_platform&current_version=$currentVersion');

      if (response.statusCode != 200) return false;

      final data = response.json;
      final result = VersionCheckResult.fromJson(data);

      if (result.isForceUpdate) return true;

      return isVersionOlder(currentVersion, result.minRequiredVersion);
    } catch (_) {
      return false; // Offline resiliency: fail open if version check fails to avoid blocking users
    }
  }

  /// Retrieves the detailed version check result from the backend
  Future<VersionCheckResult?> getVersionInfo() async {
    try {
      final response = await _apiClient.get(
          '/updates/check?platform=$_platform&current_version=$currentVersion');
      if (response.statusCode != 200) return null;
      return VersionCheckResult.fromJson(response.json);
    } catch (_) {
      return null;
    }
  }

  /// Check if the local database schema version matches the server schema version
  Future<bool> checkSchemaVersionMatch() async {
    try {
      final response = await _apiClient.get(
          '/updates/check?platform=$_platform&current_version=$currentVersion');

      if (response.statusCode != 200) return true;

      final data = response.json;
      final result = VersionCheckResult.fromJson(data);

      return result.schemaVersion == currentSchemaVersion;
    } catch (_) {
      return true; // Resilient: assume match if server check fails (offline fallback)
    }
  }

  /// Helper to compare semantic versions formatted as major.minor.patch+build
  static bool isVersionOlder(String current, String required) {
    try {
      final partsCurrent = current.split('+');
      final partsReq = required.split('+');

      final verCurrent = partsCurrent[0].split('.').map(int.parse).toList();
      final verReq = partsReq[0].split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        if (verCurrent[i] < verReq[i]) return true;
        if (verCurrent[i] > verReq[i]) return false;
      }

      if (partsCurrent.length > 1 && partsReq.length > 1) {
        final buildCurrent = int.parse(partsCurrent[1]);
        final buildReq = int.parse(partsReq[1]);
        return buildCurrent < buildReq;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
