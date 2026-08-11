import 'package:serenutos/infrastructure/network/api_client.dart';
import 'cloud_catalog_service_stub.dart'
    if (dart.library.io) 'cloud_catalog_service_io.dart' as implementation;

class CloudCatalogMetadata {
  final String name;
  final int sizeBytes;
  final int productCount;
  final String? sha256;

  const CloudCatalogMetadata({
    required this.name,
    required this.sizeBytes,
    required this.productCount,
    this.sha256,
  });

  factory CloudCatalogMetadata.fromJson(Map<String, dynamic> json) {
    return CloudCatalogMetadata(
      name: json['name']?.toString() ?? 'Serenut Hazır Ürün Kataloğu',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      productCount: (json['productCount'] as num?)?.toInt() ?? 0,
      sha256: json['sha256']?.toString(),
    );
  }
}

class CloudCatalogDownload {
  final String path;
  final int sizeBytes;
  final CloudCatalogMetadata metadata;

  const CloudCatalogDownload({
    required this.path,
    required this.sizeBytes,
    required this.metadata,
  });
}

abstract class CloudCatalogService {
  Future<CloudCatalogMetadata> fetchMetadata();

  Future<CloudCatalogDownload> download({
    required void Function(double progress, String status) onProgress,
  });

  Future<void> cleanup(String path);
}

CloudCatalogService createCloudCatalogService(ApiClient apiClient) =>
    implementation.createCloudCatalogService(apiClient);
