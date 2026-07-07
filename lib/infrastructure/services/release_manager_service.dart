// lib/infrastructure/services/release_manager_service.dart
// Serenut Platform — Release Manager Service (Sprint 6)
// Background update checker, download manager, SHA-256 verifier, and OTA installer.
// Created: 04 Jul 2026

import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serenutos/config/environment.dart';

/// Represents the result of an update check from the server.
class UpdateInfo {
  final bool hasUpdate;
  final bool isForceUpdate;
  final String latestVersion;
  final String? minRequiredVersion;
  final String? downloadUrl;
  final String? sha256Hash;
  final int? fileSizeBytes;
  final String? releaseNotes;
  final String channel;

  const UpdateInfo({
    required this.hasUpdate,
    required this.isForceUpdate,
    required this.latestVersion,
    this.minRequiredVersion,
    this.downloadUrl,
    this.sha256Hash,
    this.fileSizeBytes,
    this.releaseNotes,
    required this.channel,
  });

  factory UpdateInfo.noUpdate(String currentVersion) => UpdateInfo(
        hasUpdate: false,
        isForceUpdate: false,
        latestVersion: currentVersion,
        channel: 'stable',
      );

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        hasUpdate: json['hasUpdate'] as bool? ?? false,
        isForceUpdate: json['isForceUpdate'] as bool? ?? false,
        latestVersion: json['latestVersion'] as String? ?? '',
        minRequiredVersion: json['minRequiredVersion'] as String?,
        downloadUrl: json['downloadUrl'] as String?,
        sha256Hash: json['sha256Hash'] as String?,
        fileSizeBytes: json['fileSizeBytes'] as int?,
        releaseNotes: json['releaseNotes'] as String?,
        channel: json['channel'] as String? ?? 'stable',
      );
}

/// Download progress event emitted to UI.
class DownloadProgress {
  final int bytesDownloaded;
  final int? totalBytes;
  final double percentage; // 0.0 - 1.0

  const DownloadProgress({
    required this.bytesDownloaded,
    this.totalBytes,
    required this.percentage,
  });
}

/// Possible outcomes of an OTA install attempt.
enum InstallResult { success, sha256Failed, openFileFailed, platformUnsupported }

/// Release Manager Service
///
/// Usage:
/// ```dart
/// final rm = ReleaseManagerService();
/// final info = await rm.checkForUpdates(
///   currentVersion: '1.0.0+1',
///   platform: Platform.isAndroid ? 'android' : 'windows',
///   deviceId: deviceId,
///   companyId: companyId,
///   jwtToken: token,
/// );
/// if (info.hasUpdate) { ... }
/// ```
class ReleaseManagerService {
  final EnvironmentConfig _config;
  final http.Client _httpClient;

  ReleaseManagerService({
    EnvironmentConfig? config,
    http.Client? httpClient,
  })  : _config = config ?? EnvironmentConfig.current,
        _httpClient = httpClient ?? http.Client();

  // ── PUBLIC API ──────────────────────────────────────────────────────────────

  /// Check for updates. Returns [UpdateInfo].
  /// This is safe to call from background — never throws, returns noUpdate on error.
  Future<UpdateInfo> checkForUpdates({
    required String currentVersion,
    required String platform,
    String? deviceId,
    String? companyId,
    String? jwtToken,
  }) async {
    try {
      final queryParams = {
        'current_version': currentVersion,
        'platform': platform,
        'channel': _config.releaseChannel,
        if (deviceId != null) 'device_id': deviceId,
        if (companyId != null) 'company_id': companyId,
      };

      final uri = Uri.parse(
        '${_config.apiBaseUrl}${_config.releaseEndpoint}/check',
      ).replace(queryParameters: queryParams);

      final headers = <String, String>{};
      if (jwtToken != null) {
        headers['Authorization'] = 'Bearer $jwtToken';
      }

      final response = await _httpClient.get(uri, headers: headers).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode != 200) {
        debugPrint('[ReleaseManager] Check failed: ${response.statusCode}');
        return UpdateInfo.noUpdate(currentVersion);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final info = UpdateInfo.fromJson(data);

      debugPrint(
        '[ReleaseManager] Check OK — hasUpdate:${info.hasUpdate} '
        'force:${info.isForceUpdate} latest:${info.latestVersion}',
      );

      return info;
    } catch (e) {
      debugPrint('[ReleaseManager] Check error: $e');
      return UpdateInfo.noUpdate(currentVersion);
    }
  }

  /// Download the update file. Streams [DownloadProgress] events.
  /// Returns the local [File] path on success.
  /// Throws on network or file errors.
  Stream<DownloadProgress> downloadUpdate({
    required UpdateInfo updateInfo,
    required String platform,
    String? jwtToken,
    String? deviceId,
  }) async* {
    final downloadPath = updateInfo.downloadUrl!;
    final totalBytes = updateInfo.fileSizeBytes;
    final ext = platform == 'android' ? '.apk' : '.exe';
    final filename = 'serenut-update-${updateInfo.latestVersion}$ext';

    final tempDir = await getTemporaryDirectory();
    final targetFile = File('${tempDir.path}/$filename');

    // If already downloaded and verified, skip
    if (await targetFile.exists()) {
      final existingHash = await _computeSha256(targetFile);
      if (updateInfo.sha256Hash != null && existingHash == updateInfo.sha256Hash) {
        debugPrint('[ReleaseManager] Cached file hash match, skipping download.');
        yield DownloadProgress(bytesDownloaded: totalBytes ?? 0, totalBytes: totalBytes, percentage: 1.0);
        return;
      }
      await targetFile.delete();
    }

    final fullUrl = '${_config.apiBaseUrl}${_config.releaseEndpoint}${downloadPath}'
        '${deviceId != null ? '?device_id=$deviceId' : ''}';

    final request = http.Request('GET', Uri.parse(fullUrl));
    if (jwtToken != null) {
      request.headers['Authorization'] = 'Bearer $jwtToken';
    }

    final streamedResponse = await _httpClient.send(request);
    if (streamedResponse.statusCode != 200) {
      throw Exception('[ReleaseManager] Download failed: ${streamedResponse.statusCode}');
    }

    final sink = targetFile.openWrite();
    int downloaded = 0;

    await for (final chunk in streamedResponse.stream) {
      sink.add(chunk);
      downloaded += chunk.length;
      final pct = (totalBytes != null && totalBytes > 0) ? downloaded / totalBytes : 0.0;
      yield DownloadProgress(
        bytesDownloaded: downloaded,
        totalBytes: totalBytes,
        percentage: pct.clamp(0.0, 1.0),
      );
    }

    await sink.close();
    debugPrint('[ReleaseManager] Download complete: ${targetFile.path} ($downloaded bytes)');
  }

  /// Get the path to the downloaded update file.
  Future<File?> getDownloadedFile(String version, String platform) async {
    final ext = platform == 'android' ? '.apk' : '.exe';
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/serenut-update-$version$ext');
    return await file.exists() ? file : null;
  }

  /// Verify SHA-256 hash of downloaded file.
  Future<bool> verifyDownload(File file, String expectedHash) async {
    final actualHash = await _computeSha256(file);
    final valid = actualHash == expectedHash;
    debugPrint('[ReleaseManager] SHA-256 verify: expected=$expectedHash actual=$actualHash match=$valid');
    return valid;
  }

  /// Open and install the downloaded APK / EXE.
  Future<InstallResult> installUpdate(File file, String platform) async {
    if (kIsWeb) return InstallResult.platformUnsupported;

    final path = file.path;

    if (Platform.isAndroid) {
      final result = await OpenFile.open(path, type: 'application/vnd.android.package-archive');
      return result.type == ResultType.done ? InstallResult.success : InstallResult.openFileFailed;
    } else if (Platform.isWindows) {
      final result = await Process.run('start', [path], runInShell: true);
      return result.exitCode == 0 ? InstallResult.success : InstallResult.openFileFailed;
    }

    return InstallResult.platformUnsupported;
  }

  /// Report current app version to server for device version monitoring.
  Future<void> reportVersion({
    required String currentVersion,
    required String platform,
    required String deviceId,
    required String jwtToken,
  }) async {
    try {
      await _httpClient
          .post(
            Uri.parse('${_config.apiBaseUrl}${_config.releaseEndpoint}/report-version'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $jwtToken',
            },
            body: jsonEncode({
              'device_id': deviceId,
              'platform': platform,
              'current_version': currentVersion,
              'channel': _config.releaseChannel,
            }),
          )
          .timeout(const Duration(seconds: 8));

      debugPrint('[ReleaseManager] Version reported: $currentVersion on $platform');
    } catch (e) {
      debugPrint('[ReleaseManager] Version report failed (non-critical): $e');
    }
  }

  /// Confirm download verification result to server (updates download_logs table).
  Future<void> confirmDownload({
    required String logId,
    required bool verified,
    required String jwtToken,
  }) async {
    try {
      await _httpClient
          .post(
            Uri.parse('${_config.apiBaseUrl}${_config.releaseEndpoint}/confirm-download'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $jwtToken',
            },
            body: jsonEncode({'log_id': logId, 'verified': verified}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[ReleaseManager] Confirm download failed: $e');
    }
  }

  void dispose() {
    _httpClient.close();
  }

  // ── PRIVATE ─────────────────────────────────────────────────────────────────

  Future<String> _computeSha256(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }
}
