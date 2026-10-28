// lib/providers/hazelnut_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/hazelnut_models.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_hazelnut_repository.dart';
import 'package:serenutos/providers/database_provider.dart';

final hazelnutRepositoryProvider = Provider<IHazelnutRepository>((ref) {
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteHazelnutRepository(gateway);
});

final warehousesProvider = FutureProvider.autoDispose<List<WarehouseEntity>>((ref) async {
  final repo = ref.watch(hazelnutRepositoryProvider);
  return repo.getWarehouses();
});

final warehouseDetailProvider = FutureProvider.autoDispose.family<WarehouseEntity?, String>((ref, warehouseId) async {
  final repo = ref.watch(hazelnutRepositoryProvider);
  return repo.getWarehouseById(warehouseId);
});

final warehouseMovementsProvider = FutureProvider.autoDispose.family<List<WarehouseHazelnutMovementEntity>, String>((ref, warehouseId) async {
  final repo = ref.watch(hazelnutRepositoryProvider);
  return repo.getWarehouseMovements(warehouseId);
});

final customerEscrowsProvider = FutureProvider.autoDispose.family<List<CustomerHazelnutEscrowEntity>, String>((ref, customerId) async {
  final repo = ref.watch(hazelnutRepositoryProvider);
  return repo.getCustomerEscrows(customerId);
});

final allActiveEscrowsProvider = FutureProvider.autoDispose<List<CustomerHazelnutEscrowEntity>>((ref) async {
  final repo = ref.watch(hazelnutRepositoryProvider);
  return repo.getAllActiveEscrows();
});

