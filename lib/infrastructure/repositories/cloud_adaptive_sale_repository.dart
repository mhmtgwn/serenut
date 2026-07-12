// lib/infrastructure/repositories/cloud_adaptive_sale_repository.dart
// Serenut Platform — Cloud Adaptive Sale Repository
// Implements Repository Pattern, coordinating Local SQLite and Remote Data Source.
// Created: 04 Jul 2026

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/datasources/remote_data_sources.dart';

class CloudAdaptiveSaleRepository implements ISaleRepository {
  final ISaleRepository _localRepo;
  final SalesRemoteDataSource _remoteDS;

  CloudAdaptiveSaleRepository(this._localRepo, this._remoteDS);

  // ── Read operations (Delegated directly to Local Source) ───────────────────
  @override
  Future<List<SaleEntity>> findAll() => _localRepo.findAll();

  @override
  Future<SaleEntity?> findById(id) => _localRepo.findById(id);

  @override
  Future<int> count() => _localRepo.count();

  @override
  Future<bool> exists(id) => _localRepo.exists(id);

  @override
  Future<SaleEntity?> findByIdempotencyKey(String key) => _localRepo.findByIdempotencyKey(key);

  @override
  Future<List<SaleEntity>> getTodaySales() => _localRepo.getTodaySales();

  @override
  Future<List<SaleEntity>> getSalesByDateRange(DateTime from, DateTime to) => _localRepo.getSalesByDateRange(from, to);

  @override
  Future<List<SaleEntity>> getByCustomerId(String customerId) => _localRepo.getByCustomerId(customerId);

  @override
  Future<List<SaleEntity>> getByPaymentMethod(String method) => _localRepo.getByPaymentMethod(method);

  @override
  Future<double> getTodayRevenue() => _localRepo.getTodayRevenue();

  @override
  Future<double> getRevenueByDateRange(DateTime from, DateTime to) => _localRepo.getRevenueByDateRange(from, to);

  @override
  Future<int> getTotalItemsSold() => _localRepo.getTotalItemsSold();

  @override
  Future<List<SaleEntity>> findUnsynced() => _localRepo.findUnsynced();

  @override
  Future<List<SaleEntity>> findFiltered({
    String? searchQuery,
    int limit = 25,
    int offset = 0,
  }) => _localRepo.findFiltered(searchQuery: searchQuery, limit: limit, offset: offset);

  // ── Write operations (Offline first: write local, then sync remote in bg) ──
  @override
  Future<int> create(SaleEntity entity) async {
    final res = await _localRepo.create(entity);
    try {
      await _remoteDS.pushSale(entity);
    } catch (_) {}
    return res;
  }

  @override
  Future<int> update(SaleEntity entity) async {
    final res = await _localRepo.update(entity);
    try {
      await _remoteDS.pushSale(entity);
    } catch (_) {}
    return res;
  }

  @override
  Future<int> delete(id) async {
    final res = await _localRepo.delete(id);
    return res;
  }
}
