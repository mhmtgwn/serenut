// lib/infrastructure/services/update_v2/manifest_cache_service.dart
// Serenut Platform — Local Manifest Cache Service (Offline Resiliency)

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:serenutos/domain/models/update_v2/release_manifest.dart';

class CachedManifestEntry {
  final ReleaseManifest manifest;
  final String rawManifestContent;
  final String signature;
  final String cachedAt;

  CachedManifestEntry({
    required this.manifest,
    required this.rawManifestContent,
    required this.signature,
    required this.cachedAt,
  });

  Map<String, dynamic> toJson() => {
        'manifest': manifest.toJson(),
        'rawManifestContent': rawManifestContent,
        'signature': signature,
        'cachedAt': cachedAt,
      };

  factory CachedManifestEntry.fromJson(Map<String, dynamic> json) {
    return CachedManifestEntry(
      manifest:
          ReleaseManifest.fromJson(json['manifest'] as Map<String, dynamic>),
      rawManifestContent: json['rawManifestContent'] as String? ?? '',
      signature: json['signature'] as String? ?? '',
      cachedAt: json['cachedAt'] as String? ?? '',
    );
  }
}

class ManifestCacheService {
  static const String _cacheFileName = 'manifest_cache.json';

  Future<File> _getCacheFile() async {
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/cache')
      ..createSync(recursive: true);
    return File('${cacheDir.path}/$_cacheFileName');
  }

  /// Persists a verified manifest and signature to local cache file.
  Future<bool> saveToCache({
    required ReleaseManifest manifest,
    required String rawManifestContent,
    required String signature,
  }) async {
    try {
      final file = await _getCacheFile();
      final entry = CachedManifestEntry(
        manifest: manifest,
        rawManifestContent: rawManifestContent,
        signature: signature,
        cachedAt: DateTime.now().toIso8601String(),
      );
      await file.writeAsString(jsonEncode(entry.toJson()), flush: true);
      debugPrint(
          '[ManifestCacheService] Manifest cached successfully for release ${manifest.releaseId}');
      return true;
    } catch (e) {
      debugPrint('[ManifestCacheService] Cache save failed: $e');
      return false;
    }
  }

  /// Retrieves the cached manifest entry if present on disk.
  Future<CachedManifestEntry?> getCachedEntry() async {
    try {
      final file = await _getCacheFile();
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;

      final json = jsonDecode(content) as Map<String, dynamic>;
      return CachedManifestEntry.fromJson(json);
    } catch (e) {
      debugPrint('[ManifestCacheService] Cache read failed: $e');
      return null;
    }
  }

  /// Clears the local manifest cache.
  Future<void> clearCache() async {
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[ManifestCacheService] Cache clear failed: $e');
    }
  }
}
