// lib/infrastructure/services/release_manager_service.dart
// Serenut Platform — Release Manager Service (Sprint 6)
// Background update checker, download manager, SHA-256 verifier, and OTA installer.
// Created: 04 Jul 2026

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:pointycastle/export.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
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
  final String? signature;
  final String? releaseNotes;
  final String channel;

  const UpdateInfo({
    required this.hasUpdate,
    required this.isForceUpdate,
    required this.latestVersion,
    this.minRequiredVersion,
    this.downloadUrl,
    this.sha256Hash,
    this.signature,
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
        signature: json['signature'] as String?,
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
  static const String _rsaModulusHex = '24411462201226996438841939549021454888733195236274468065775741224235870828599975687442961469702706222823140813618470146034318791144081164140895510392862259766582087914988353091642332590862692172508245336721761478288563513793312713764686147506940136020087563505042690937627842320486248227124477581576031460706918080381582170251418495030474651546222624978118721452561800320320246965787168638531779352900516824205685716199734459208444432818729619600489270457687453750695905613821629449668637610680017348238336982462564377297468305133351943448287065558841371731196118193920355175788560618289960848258703300389635524278281';
  static const String _rsaExponentHex = '65537';

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
    final tmpFile = File('${tempDir.path}/$filename.tmp');

    // If final file already downloaded and verified, skip
    if (await targetFile.exists()) {
      final existingHash = await _computeSha256(targetFile);
      if (updateInfo.sha256Hash != null && existingHash == updateInfo.sha256Hash) {
        debugPrint('[ReleaseManager] Cached file hash match, skipping download.');
        yield DownloadProgress(bytesDownloaded: totalBytes ?? 0, totalBytes: totalBytes, percentage: 1.0);
        return;
      }
      await targetFile.delete();
    }

    int existingLength = 0;
    if (await tmpFile.exists()) {
      existingLength = await tmpFile.length();
    }

    final String fullUrl;
    if (downloadPath.startsWith('http')) {
      fullUrl = downloadPath;
    } else if (downloadPath.startsWith('/api')) {
      final uri = Uri.parse(_config.apiBaseUrl);
      final origin = '${uri.scheme}://${uri.host}${uri.hasPort ? ":${uri.port}" : ""}';
      fullUrl = '$origin$downloadPath${deviceId != null ? "?device_id=$deviceId" : ""}';
    } else {
      fullUrl = '${_config.apiBaseUrl}${_config.releaseEndpoint}$downloadPath'
          '${deviceId != null ? "?device_id=$deviceId" : ""}';
    }

    final request = http.Request('GET', Uri.parse(fullUrl));
    if (jwtToken != null) {
      request.headers['Authorization'] = 'Bearer $jwtToken';
    }

    if (existingLength > 0 && totalBytes != null && existingLength < totalBytes) {
      request.headers['Range'] = 'bytes=$existingLength-';
      debugPrint('[ReleaseManager] Resuming OTA download from offset: $existingLength bytes');
    }

    final streamedResponse = await _httpClient.send(request);
    final isPartial = streamedResponse.statusCode == 206;

    if (streamedResponse.statusCode != 200 && streamedResponse.statusCode != 206) {
      throw Exception('[ReleaseManager] Download failed: ${streamedResponse.statusCode}');
    }

    final int startByte = isPartial ? existingLength : 0;
    if (!isPartial && existingLength > 0) {
      // Server did not support range or returned full payload, clear old tmp file
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
    }

    final iosink = tmpFile.openWrite(mode: isPartial ? FileMode.append : FileMode.write);
    int downloaded = startByte;

    await for (final chunk in streamedResponse.stream) {
      iosink.add(chunk);
      downloaded += chunk.length;
      final pct = (totalBytes != null && totalBytes > 0) ? downloaded / totalBytes : 0.0;
      yield DownloadProgress(
        bytesDownloaded: downloaded,
        totalBytes: totalBytes,
        percentage: pct.clamp(0.0, 1.0),
      );
    }

    await iosink.close();
    
    // Rename tmp file to final file
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await tmpFile.rename(targetFile.path);

    debugPrint('[ReleaseManager] Download complete and merged: ${targetFile.path} ($downloaded bytes)');
  }

  /// Get the path to the downloaded update file.
  Future<File?> getDownloadedFile(String version, String platform) async {
    final ext = platform == 'android' ? '.apk' : '.exe';
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/serenut-update-$version$ext');
    return await file.exists() ? file : null;
  }

  /// Verify SHA-256 hash and RSA digital signature of downloaded file.
  Future<bool> verifyDownload(File file, String expectedHash, String signature) async {
    // 1. Verify SHA-256 integrity
    final actualHash = await _computeSha256(file);
    final validHash = actualHash == expectedHash;
    debugPrint('[ReleaseManager] SHA-256 verify: expected=$expectedHash actual=$actualHash match=$validHash');
    if (!validHash) return false;

    // 2. Verify RSA Digital Signature
    if (signature.isEmpty) {
      debugPrint('[ReleaseManager] RSA Signature missing! Rejecting update package.');
      return false;
    }

    try {
      final signatureBytes = base64.decode(signature.trim());
      final payloadBytes = utf8.encode(actualHash); // The signed data is the file hash

      final modulus = BigInt.parse(_rsaModulusHex);
      final publicExponent = BigInt.parse(_rsaExponentHex);
      
      final publicKey = RSAPublicKey(modulus, publicExponent);
      final verifier = RSASigner(SHA256Digest(), '0609608648016503040201');
      verifier.init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
      
      final rsaSignature = RSASignature(signatureBytes);
      final verified = verifier.verifySignature(payloadBytes, rsaSignature);
      debugPrint('[ReleaseManager] RSA signature verify match=$verified');
      return verified;
    } catch (e) {
      debugPrint('[ReleaseManager] RSA signature verification failed with error: $e');
      return false;
    }
  }

  /// Open and install the downloaded APK / EXE.
  Future<InstallResult> installUpdate(File file, String platform) async {
    if (kIsWeb) return InstallResult.platformUnsupported;

    final path = file.path;

    if (Platform.isAndroid) {
      final result = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
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
    // Stream-based hashing prevents loading large APKs into memory (OOM safety)
    final stream = file.openRead();
    final hash = await sha256.bind(stream).first;
    return hash.toString();
  }
}
