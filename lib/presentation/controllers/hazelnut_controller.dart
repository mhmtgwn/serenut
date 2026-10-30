// lib/presentation/controllers/hazelnut_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/hazelnut_models.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_hazelnut_repository.dart';
import 'package:serenutos/providers/hazelnut_providers.dart';

class HazelnutController {
  final IHazelnutRepository _repo;
  final Ref _ref;

  HazelnutController(this._repo, this._ref);

  Future<void> saveWarehouse(WarehouseEntity warehouse) async {
    await _repo.saveWarehouse(warehouse);
    _ref.invalidate(warehouseDetailProvider(warehouse.id));
    _ref.invalidate(warehousesProvider);
  }

  Future<void> transferBetweenWarehouses({
    required String sourceWarehouseId,
    required String targetWarehouseId,
    required double quantityKg,
    String? description,
  }) async {
    await _repo.transferBetweenWarehouses(
      sourceWarehouseId: sourceWarehouseId,
      targetWarehouseId: targetWarehouseId,
      quantityKg: quantityKg,
      description: description,
    );
    _ref.invalidate(warehouseDetailProvider(sourceWarehouseId));
    _ref.invalidate(warehouseDetailProvider(targetWarehouseId));
    _ref.invalidate(warehouseMovementsProvider(sourceWarehouseId));
    _ref.invalidate(warehouseMovementsProvider(targetWarehouseId));
    _ref.invalidate(warehousesProvider);
  }

  Future<WarehouseHazelnutMovementEntity> dispatchFromWarehouse({
    required String warehouseId,
    required String movementType,
    required double quantityKg,
    String? description,
  }) async {
    final movement = await _repo.dispatchFromWarehouse(
      warehouseId: warehouseId,
      movementType: movementType,
      quantityKg: quantityKg,
      description: description,
    );
    _ref.invalidate(warehouseDetailProvider(warehouseId));
    _ref.invalidate(warehouseMovementsProvider(warehouseId));
    _ref.invalidate(warehousesProvider);
    return movement;
  }

  Future<void> deleteWarehouse(String warehouseId) async {
    await _repo.deleteWarehouse(warehouseId);
    _ref.invalidate(warehousesProvider);
    _ref.invalidate(warehouseDetailProvider(warehouseId));
  }
}

final hazelnutControllerProvider = Provider<HazelnutController>((ref) {
  final repo = ref.watch(hazelnutRepositoryProvider);
  return HazelnutController(repo, ref);
});
