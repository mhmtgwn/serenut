import 'package:serenutos/infrastructure/network/api_client.dart';
import 'cloud_catalog_service.dart';

CloudCatalogService createCloudCatalogService(ApiClient apiClient) =>
    _UnsupportedCloudCatalogService();

class _UnsupportedCloudCatalogService implements CloudCatalogService {
  Never _unsupported() => throw UnsupportedError(
        'Bulut kataloğu içe aktarma bu platformda desteklenmiyor.',
      );

  @override
  Future<CloudCatalogMetadata> fetchMetadata() async => _unsupported();

  @override
  Future<CloudCatalogDownload> download({
    required void Function(double progress, String status) onProgress,
  }) async =>
      _unsupported();

  @override
  Future<void> cleanup(String path) async {}
}
