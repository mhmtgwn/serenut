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
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serenutos/config/app_platform.dart';
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

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final downloadUrl =
        (json['downloadUrl'] ?? json['download_url']) as String?;
    return UpdateInfo(
      hasUpdate: (json['hasUpdate'] ?? json['has_update']) as bool? ??
          (downloadUrl != null && downloadUrl.isNotEmpty),
      isForceUpdate:
          (json['isForceUpdate'] ?? json['is_force_update']) as bool? ?? false,
      latestVersion:
          (json['latestVersion'] ?? json['latest_version']) as String? ?? '',
      minRequiredVersion: (json['minRequiredVersion'] ??
          json['min_required_version']) as String?,
      downloadUrl: downloadUrl,
      sha256Hash: (json['sha256Hash'] ?? json['sha256_hash']) as String?,
      signature: json['signature'] as String?,
      fileSizeBytes:
          _parseOptionalInt(json['fileSizeBytes'] ?? json['file_size_bytes']),
      releaseNotes: (json['releaseNotes'] ?? json['release_notes']) as String?,
      channel: json['channel'] as String? ?? 'stable',
    );
  }
}

int? _parseOptionalInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
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

class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() =>
      'Güncelleme indirmesi kullanıcı tarafından iptal edildi.';
}

class DownloadCancellationToken {
  bool _isCancelled = false;
  final Set<void Function()> _listeners = {};

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void throwIfCancelled() {
    if (_isCancelled) throw const DownloadCancelledException();
  }

  void _addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void _removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}

/// Possible outcomes of an OTA install attempt.
enum InstallResult {
  success,
  sha256Failed,
  permissionRequired,
  openFileFailed,
  platformUnsupported
}

/// Release Manager Service
///
/// Usage:
/// ```dart
/// final rm = ReleaseManagerService();
/// final info = await rm.checkForUpdates(
///   currentVersion: '1.0.0+1',
///   platform: AppPlatform.releaseKey,
///   deviceId: deviceId,
///   companyId: companyId,
///   jwtToken: token,
/// );
/// if (info.hasUpdate) { ... }
/// ```
class ReleaseManagerService {
  static const MethodChannel _androidUpdateChannel =
      MethodChannel('serenut/app_update');
  static const String _configuredRsaModulus = String.fromEnvironment(
    'RELEASE_RSA_MODULUS',
    defaultValue: '',
  );
  static const String _configuredRsaModuli = String.fromEnvironment(
    'RELEASE_RSA_MODULI',
    defaultValue: '',
  );

  final EnvironmentConfig _config;
  final http.Client _httpClient;
  final List<String> _rsaModuli;
  final String _rsaExponent;

  ReleaseManagerService({
    EnvironmentConfig? config,
    http.Client? httpClient,
    String? rsaModulus,
    List<String>? rsaModuli,
    String rsaExponent = '65537',
  })  : _config = config ?? EnvironmentConfig.current,
        _httpClient = httpClient ?? http.Client(),
        _rsaModuli = _resolveTrustedModuli(rsaModulus, rsaModuli),
        _rsaExponent = rsaExponent;

  static List<String> _resolveTrustedModuli(
    String? rsaModulus,
    List<String>? rsaModuli,
  ) {
    final configured = rsaModuli ??
        (rsaModulus != null
            ? <String>[rsaModulus]
            : _configuredRsaModuli.split(','));
    final result = configured
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (result.isEmpty && _configuredRsaModulus.trim().isNotEmpty) {
      return <String>[_configuredRsaModulus.trim()];
    }
    return result;
  }

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
        if (deviceId != null) 'device_activation_id': deviceId,
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
    DownloadCancellationToken? cancellationToken,
  }) async* {
    cancellationToken?.throwIfCancelled();
    final downloadPath = updateInfo.downloadUrl!;
    final totalBytes = updateInfo.fileSizeBytes;
    final ext = AppPlatform.updateFileExtension(platform);
    final filename = 'serenut-update-${updateInfo.latestVersion}$ext';

    final tempDir = await getTemporaryDirectory();
    final targetFile = File('${tempDir.path}/$filename');
    final tmpFile = File('${tempDir.path}/$filename.tmp');

    // If final file already downloaded and verified, skip
    if (await targetFile.exists()) {
      final existingHash = await _computeSha256(targetFile);
      if (updateInfo.sha256Hash != null &&
          existingHash == updateInfo.sha256Hash) {
        debugPrint(
            '[ReleaseManager] Cached file hash match, skipping download.');
        yield DownloadProgress(
            bytesDownloaded: totalBytes ?? 0,
            totalBytes: totalBytes,
            percentage: 1.0);
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
      final origin =
          '${uri.scheme}://${uri.host}${uri.hasPort ? ":${uri.port}" : ""}';
      fullUrl =
          '$origin$downloadPath${deviceId != null ? "?device_activation_id=$deviceId" : ""}';
    } else {
      fullUrl = '${_config.apiBaseUrl}${_config.releaseEndpoint}$downloadPath'
          '${deviceId != null ? "?device_activation_id=$deviceId" : ""}';
    }

    final request = http.Request('GET', Uri.parse(fullUrl));
    if (jwtToken != null) {
      request.headers['Authorization'] = 'Bearer $jwtToken';
    }

    if (existingLength > 0 &&
        totalBytes != null &&
        existingLength < totalBytes) {
      request.headers['Range'] = 'bytes=$existingLength-';
      debugPrint(
          '[ReleaseManager] Resuming OTA download from offset: $existingLength bytes');
    }

    final downloadClient = http.Client();
    void cancelRequest() => downloadClient.close();
    cancellationToken?._addListener(cancelRequest);
    IOSink? iosink;
    int downloaded = 0;

    try {
      final streamedResponse = await downloadClient
          .send(request)
          .timeout(const Duration(seconds: 30));
      cancellationToken?.throwIfCancelled();
      final isPartial = streamedResponse.statusCode == 206;

      if (streamedResponse.statusCode != 200 &&
          streamedResponse.statusCode != 206) {
        throw Exception(
            '[ReleaseManager] Download failed: ${streamedResponse.statusCode}');
      }

      final int startByte = isPartial ? existingLength : 0;
      if (!isPartial && existingLength > 0) {
        // Server did not support range or returned full payload, clear old tmp file
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }
      }

      iosink =
          tmpFile.openWrite(mode: isPartial ? FileMode.append : FileMode.write);
      downloaded = startByte;

      await for (final chunk in streamedResponse.stream) {
        cancellationToken?.throwIfCancelled();
        iosink.add(chunk);
        downloaded += chunk.length;
        final pct = (totalBytes != null && totalBytes > 0)
            ? downloaded / totalBytes
            : 0.0;
        yield DownloadProgress(
          bytesDownloaded: downloaded,
          totalBytes: totalBytes,
          percentage: pct.clamp(0.0, 1.0),
        );
      }
      cancellationToken?.throwIfCancelled();
      await iosink.flush();
      await iosink.close();
      iosink = null;
    } catch (error) {
      if (cancellationToken?.isCancelled ?? false) {
        throw const DownloadCancelledException();
      }
      rethrow;
    } finally {
      if (iosink != null) {
        await iosink.close();
      }
      cancellationToken?._removeListener(cancelRequest);
      downloadClient.close();
    }

    // Rename tmp file to final file
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await tmpFile.rename(targetFile.path);

    debugPrint(
        '[ReleaseManager] Download complete and merged: ${targetFile.path} ($downloaded bytes)');
  }

  /// Get the path to the downloaded update file.
  Future<File?> getDownloadedFile(String version, String platform) async {
    final ext = AppPlatform.updateFileExtension(platform);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/serenut-update-$version$ext');
    return await file.exists() ? file : null;
  }

  /// Verify SHA-256 hash and RSA digital signature of downloaded file.
  Future<bool> verifyDownload(
      File file, String expectedHash, String signature) async {
    // 1. Verify SHA-256 integrity
    final actualHash = await _computeSha256(file);
    final validHash = actualHash == expectedHash;
    debugPrint(
        '[ReleaseManager] SHA-256 verify: expected=$expectedHash actual=$actualHash match=$validHash');
    if (!validHash) return false;

    // 2. Production updates fail closed unless the detached RSA signature can
    // be verified with the public key embedded at build time.
    if (signature.trim().isEmpty || _rsaModuli.isEmpty) {
      debugPrint(
          '[ReleaseManager] Rejecting update: RSA key or signature is missing.');
      return false;
    }
    try {
      final signatureBytes = base64.decode(signature.trim());
      final payloadBytes = utf8.encode(actualHash); // Signed data is file hash

      final publicExponent = BigInt.parse(_rsaExponent);
      final rsaSignature = RSASignature(signatureBytes);
      for (var index = 0; index < _rsaModuli.length; index++) {
        final publicKey = RSAPublicKey(
          BigInt.parse(_rsaModuli[index]),
          publicExponent,
        );
        final verifier = RSASigner(SHA256Digest(), '0609608648016503040201');
        verifier.init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
        if (verifier.verifySignature(payloadBytes, rsaSignature)) {
          debugPrint(
              '[ReleaseManager] RSA signature verified by trusted key #$index');
          return true;
        }
      }
      debugPrint('[ReleaseManager] RSA signature did not match trusted keys.');
      return false;
    } catch (e) {
      debugPrint('[ReleaseManager] RSA signature verification failed: $e');
      return false;
    }
  }

  /// Open and install the downloaded APK / EXE.
  Future<InstallResult> installUpdate(File file, String platform) async {
    if (kIsWeb) return InstallResult.platformUnsupported;

    final path = file.path;

    if (Platform.isAndroid) {
      final canInstall = await _androidUpdateChannel
              .invokeMethod<bool>('canRequestPackageInstalls') ??
          false;
      if (!canInstall) {
        await _androidUpdateChannel.invokeMethod<void>(
          'openInstallPermissionSettings',
        );
        return InstallResult.permissionRequired;
      }
      final result = await OpenFilex.open(path,
          type: 'application/vnd.android.package-archive');
      return result.type == ResultType.done
          ? InstallResult.success
          : InstallResult.openFileFailed;
    } else if (Platform.isWindows) {
      try {
        debugPrint('[ReleaseManager] Launching Windows installer: $path');
        final currentExe = Platform.resolvedExecutable;
        final batchFile =
            File('${file.parent.path}\\serenut_update_runner.bat');
        final batchContent = '@echo off\r\n'
            'timeout /t 2 /nobreak >nul\r\n'
            'start /wait "" "$path" /SILENT /SP- /NOCANCEL\r\n'
            'if exist "%ProgramFiles%\\Serenut OS\\serenutos.exe" (\r\n'
            '    start "" "%ProgramFiles%\\Serenut OS\\serenutos.exe"\r\n'
            ') else if exist "$currentExe" (\r\n'
            '    start "" "$currentExe"\r\n'
            ')\r\n'
            'del "%~f0"\r\n';

        await batchFile.writeAsString(batchContent);

        await Process.start('cmd.exe', ['/c', batchFile.path],
            mode: ProcessStartMode.detached);

        Future.delayed(const Duration(milliseconds: 150), () {
          exit(0);
        });
        return InstallResult.success;
      } catch (e) {
        debugPrint(
            '[ReleaseManager] Process.start failed, falling back to OpenFilex: $e');
        final result = await OpenFilex.open(path);
        if (result.type == ResultType.done) {
          Future.delayed(const Duration(milliseconds: 600), () {
            exit(0);
          });
          return InstallResult.success;
        }
        return InstallResult.openFileFailed;
      }
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
            Uri.parse(
                '${_config.apiBaseUrl}${_config.releaseEndpoint}/report-version'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer $jwtToken',
            },
            body: jsonEncode({
              'device_activation_id': deviceId,
              'platform': platform,
              'current_version': currentVersion,
              'channel': _config.releaseChannel,
            }),
          )
          .timeout(const Duration(seconds: 8));

      debugPrint(
          '[ReleaseManager] Version reported: $currentVersion on $platform');
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
            Uri.parse(
                '${_config.apiBaseUrl}${_config.releaseEndpoint}/confirm-download'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
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
