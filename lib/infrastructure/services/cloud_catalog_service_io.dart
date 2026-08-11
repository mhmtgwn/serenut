import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'cloud_catalog_service.dart';

CloudCatalogService createCloudCatalogService(ApiClient apiClient) =>
    _IoCloudCatalogService(apiClient);

class _IoCloudCatalogService implements CloudCatalogService {
  final ApiClient _apiClient;

  _IoCloudCatalogService(this._apiClient);

  @override
  Future<CloudCatalogMetadata> fetchMetadata() async {
    final response = await _apiClient.get('/catalogs/ready');
    if (!response.isSuccess) {
      throw Exception(
          'Hazır katalog bilgisi alınamadı (${response.statusCode}).');
    }
    final json = response.json;
    if (json is! Map<String, dynamic> || json['available'] != true) {
      throw Exception('Hazır katalog şu anda kullanılamıyor.');
    }
    return CloudCatalogMetadata.fromJson(json);
  }

  @override
  Future<CloudCatalogDownload> download({
    required void Function(double progress, String status) onProgress,
  }) async {
    final metadata = await fetchMetadata();
    final base = EnvironmentConfig.current.apiBaseUrl;
    final uri = Uri.parse('$base/catalogs/ready/download');
    final request = http.Request('GET', uri)
      ..headers['Accept'] = 'application/zip';
    final token = _apiClient.jwtToken;
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final client = http.Client();
    File? target;
    IOSink? sink;
    try {
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Katalog indirilemedi (${response.statusCode}).');
      }
      final expected = response.contentLength ?? metadata.sizeBytes;
      final directory = await getTemporaryDirectory();
      target = File(
        '${directory.path}${Platform.pathSeparator}serenut-hazir-katalog-${DateTime.now().millisecondsSinceEpoch}.zip',
      );
      sink = target.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final progress = expected > 0 ? received / expected : 0.0;
        onProgress(
          progress.clamp(0.0, 1.0),
          '${_formatBytes(received)} / ${_formatBytes(expected)} indirildi',
        );
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (expected > 0 && received != expected) {
        throw Exception('Katalog eksik indirildi. Lütfen yeniden deneyin.');
      }
      if (metadata.sha256 != null && metadata.sha256!.isNotEmpty) {
        onProgress(1, 'İndirilen katalog doğrulanıyor...');
        final digest = await sha256.bind(target.openRead()).first;
        if (digest.toString().toLowerCase() != metadata.sha256!.toLowerCase()) {
          throw Exception('Katalog doğrulaması başarısız oldu. Lütfen yeniden deneyin.');
        }
      }
      onProgress(1, 'İndirme tamamlandı, katalog çözümleniyor...');
      return CloudCatalogDownload(
        path: target.path,
        sizeBytes: received,
        metadata: metadata,
      );
    } catch (_) {
      await sink?.close();
      if (target != null && await target.exists()) await target.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  @override
  Future<void> cleanup(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}
