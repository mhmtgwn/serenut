// lib/infrastructure/repositories/cloud_adaptive_customer_repository.dart
// Serenut Platform — Cloud Adaptive Customer Repository
// Implements Repository Pattern, coordinating Local SQLite and Remote Data Source.
// Created: 04 Jul 2026

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/datasources/remote_data_sources.dart';

class CloudAdaptiveCustomerRepository implements ICustomerRepository {
  final ICustomerRepository _localRepo;
  final CustomerRemoteDataSource _remoteDS;

  CloudAdaptiveCustomerRepository(this._localRepo, this._remoteDS);

  // ── Read operations (Delegated directly to Local Source) ───────────────────
  @override
  Future<List<CustomerEntity>> findAll() => _localRepo.findAll();

  @override
  Future<CustomerEntity?> findById(id) => _localRepo.findById(id);

  @override
  Future<int> count() => _localRepo.count();

  @override
  Future<bool> exists(id) => _localRepo.exists(id);

  @override
  Future<List<CustomerEntity>> search(String query) => _localRepo.search(query);

  @override
  Future<List<CustomerEntity>> getDebtors() => _localRepo.getDebtors();

  @override
  Future<List<CustomerEntity>> getWithCredit() => _localRepo.getWithCredit();

  @override
  Future<double> getBalance(String customerId) =>
      _localRepo.getBalance(customerId);

  @override
  Future<double> getTotalDebt(String customerId) =>
      _localRepo.getTotalDebt(customerId);

  @override
  Future<double> getTotalPaid(String customerId) =>
      _localRepo.getTotalPaid(customerId);

  @override
  Future<List<CustomerEntity>> findFiltered(
          {String? searchQuery, int? limit, int? offset}) =>
      _localRepo.findFiltered(
          searchQuery: searchQuery, limit: limit, offset: offset);

  // ── Write operations (Offline first: write local, then sync remote in bg) ──
  @override
  Future<int> create(CustomerEntity entity) async {
    final res = await _localRepo.create(entity);
    try {
      await _remoteDS.pushCustomer(entity);
    } catch (_) {}
    return res;
  }

  @override
  Future<int> update(CustomerEntity entity) async {
    final res = await _localRepo.update(entity);
    try {
      await _remoteDS.pushCustomer(entity);
    } catch (_) {}
    return res;
  }

  @override
  Future<int> delete(id) async {
    final res = await _localRepo.delete(id);
    return res;
  }

  @override
  Future<void> updateBalance(String customerId, double amount) async {
    await _localRepo.updateBalance(customerId, amount);
    final customer = await _localRepo.findById(customerId);
    if (customer != null) {
      try {
        await _remoteDS.pushCustomer(customer);
      } catch (_) {}
    }
  }
}
