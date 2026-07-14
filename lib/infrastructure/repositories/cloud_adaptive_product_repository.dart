// lib/infrastructure/repositories/cloud_adaptive_product_repository.dart
// Serenut Platform — Cloud Adaptive Product Repository
// Implements Repository Pattern, orchestrating Local SQLite and Remote Data Source.
// Created: 04 Jul 2026

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/datasources/remote_data_sources.dart';

class CloudAdaptiveProductRepository implements IProductRepository {
  final IProductRepository _localRepo;
  final ProductRemoteDataSource _remoteDS;

  CloudAdaptiveProductRepository(this._localRepo, this._remoteDS);

  // ── Read operations (Delegated directly to Local Source) ───────────────────
  @override
  Future<List<ProductEntity>> findAll() => _localRepo.findAll();

  @override
  Future<ProductEntity?> findById(id) => _localRepo.findById(id);

  @override
  Future<int> count() => _localRepo.count();

  @override
  Future<bool> exists(id) => _localRepo.exists(id);

  @override
  Future<List<ProductEntity>> searchByName(String query) =>
      _localRepo.searchByName(query);

  @override
  Future<List<ProductEntity>> getByCategory(String category) =>
      _localRepo.getByCategory(category);

  @override
  Future<Map<String, List<ProductEntity>>> getGroupedByCategory() =>
      _localRepo.getGroupedByCategory();

  @override
  Future<List<ProductEntity>> getLowStockProducts(int threshold) =>
      _localRepo.getLowStockProducts(threshold);

  @override
  Future<List<String>> getCategories() => _localRepo.getCategories();

  @override
  Future<List<ProductEntity>> findFiltered(
          {String? searchQuery, String? category, int? limit, int? offset}) =>
      _localRepo.findFiltered(
          searchQuery: searchQuery,
          category: category,
          limit: limit,
          offset: offset);

  // ── Write operations (Offline first: write local, then sync remote in bg) ──
  @override
  Future<int> create(ProductEntity entity) async {
    final res = await _localRepo.create(entity);
    try {
      await _remoteDS.pushProduct(entity);
    } catch (_) {
      // Fail silently to preserve offline-first functionality.
      // In production, the offline sync queue handles retries.
    }
    return res;
  }

  @override
  Future<int> update(ProductEntity entity, {String? oldId}) async {
    final res = await _localRepo.update(entity, oldId: oldId);
    try {
      await _remoteDS.pushProduct(entity);
    } catch (_) {}
    return res;
  }

  @override
  Future<int> delete(id) async {
    final res = await _localRepo.delete(id);
    // Soft delete: local updates modified_at.
    // In production sync, this is marked for remote deletion/deactivation.
    return res;
  }

  @override
  Future<void> decreaseStock(String productId, int quantity) async {
    await _localRepo.decreaseStock(productId, quantity);
    final product = await _localRepo.findById(productId);
    if (product != null) {
      try {
        await _remoteDS.pushProduct(product);
      } catch (_) {}
    }
  }

  @override
  Future<void> increaseStock(String productId, int quantity) async {
    await _localRepo.increaseStock(productId, quantity);
    final product = await _localRepo.findById(productId);
    if (product != null) {
      try {
        await _remoteDS.pushProduct(product);
      } catch (_) {}
    }
  }
}
