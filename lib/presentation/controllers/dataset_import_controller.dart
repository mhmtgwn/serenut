import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/import_strategy.dart';
import 'package:serenutos/domain/services/dataset_import_service.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/providers/dataset_import_provider.dart';
import 'package:serenutos/providers/repository_providers.dart';

final datasetImportControllerProvider = Provider<DatasetImportController>((ref) {
  return DatasetImportController(ref);
});

class DatasetImportController {
  final Ref _ref;

  DatasetImportController(this._ref);

  Future<Uint8List> exportToZip(void Function(double progress) onProgress) async {
    final service = await _ref.read(datasetImportServiceProvider.future);
    return await service.exportToZip(onProgress);
  }

  Future<Map<String, int>> importFromZip(
    Uint8List bytes,
    void Function(double progress, String status) onProgress, [
    ImportStrategy strategy = const ImportStrategy(),
    Map<String, String> columnMapping = const {},
    bool isCloud = false,
  ]) async {
    final service = await _ref.read(datasetImportServiceProvider.future);
    final result = await service.importFromZip(
      bytes,
      onProgress,
      strategy,
      columnMapping,
      isCloud,
    );
    invalidateProductCaches();
    return result;
  }

  Future<Map<String, int>> importFromFile(
    String filePath,
    void Function(double progress, String status) onProgress, [
    ImportStrategy strategy = const ImportStrategy(),
    bool isCloud = false,
  ]) async {
    final service = await _ref.read(datasetImportServiceProvider.future);
    final result = await service.importFromFile(
      filePath,
      onProgress,
      strategy,
      isCloud,
    );
    invalidateProductCaches();
    return result;
  }

  Future<ParsedCatalogData> analyzeZip(
    Uint8List bytes,
    void Function(double progress, String status) onProgress,
  ) async {
    final service = await _ref.read(datasetImportServiceProvider.future);
    return await service.analyzeZip(bytes, onProgress);
  }

  Future<ParsedCatalogData> analyzeFile(
    String filePath,
    void Function(double progress, String status) onProgress,
  ) async {
    final service = await _ref.read(datasetImportServiceProvider.future);
    return await service.analyzeFile(filePath, onProgress);
  }

  void invalidateProductCaches() {
    try {
      _ref.read(productSearchQueryProvider.notifier).state = '';
      _ref.read(productCategoryFilterProvider.notifier).state = null;
    } catch (_) {
      // Ignored if provider not active
    }
    _ref.invalidate(productRepositoryProvider);
    _ref.invalidate(productsControllerProvider);
    _ref.invalidate(salesProductsControllerProvider);
    _ref.invalidate(ordersProductsControllerProvider);
    _ref.invalidate(productInventorySummaryProvider);
    _ref.invalidate(allProductsProvider);
  }
}

