// lib/presentation/controllers/hazelnut_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/hazelnut_models.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_hazelnut_repository.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/providers/hazelnut_providers.dart';

class HazelnutController {
  final IHazelnutRepository _repo;
  final Ref _ref;

  HazelnutController(this._repo, this._ref);

  Future<List<WarehouseEntity>> getWarehouses() async {
    final warehouses = await _repo.getWarehouses();
    if (warehouses.isEmpty) {
      final defaultWh = WarehouseEntity(
        id: 'wh-main',
        name: 'Ana Depo (Silo 1)',
        location: 'Merkez',
        capacityKg: 50000.0,
        currentStockKg: 0.0,
        averageRendiment: 50.0,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _repo.saveWarehouse(defaultWh);
      _ref.invalidate(warehousesProvider);
      return [defaultWh];
    }
    return warehouses;
  }

  Future<CustomerHazelnutEscrowEntity> addEscrowBatch({
    required String customerId,
    required String warehouseId,
    String? receiptNo,
    required double grossKg,
    required int sackCount,
    required double tarePerSack,
    required double rendiment,
    String? notes,
  }) async {
    final escrow = await _repo.addEscrowBatch(
      customerId: customerId,
      warehouseId: warehouseId,
      receiptNo: receiptNo,
      grossKg: grossKg,
      sackCount: sackCount,
      tarePerSack: tarePerSack,
      rendiment: rendiment,
      notes: notes,
    );
    _ref.invalidate(customerEscrowsProvider(customerId));
    _ref.invalidate(warehousesProvider);
    _ref.invalidate(warehouseDetailProvider(warehouseId));
    _ref.invalidate(warehouseMovementsProvider(warehouseId));
    return escrow;
  }

  Future<HazelnutPriceCutEntity> cutEscrowPrice({
    required String escrowId,
    required String customerId,
    required double cutKg,
    required double basePrice50,
    required String settlementType,
    required String customerName,
    String? notes,
  }) async {
    final cutResult = await _repo.cutEscrowPrice(
      escrowId: escrowId,
      cutKg: cutKg,
      basePrice50: basePrice50,
      settlementType: settlementType,
      customerName: customerName,
      notes: notes,
    );
    _ref.invalidate(customerEscrowsProvider(customerId));
    _ref.invalidate(customerDetailProvider(customerId));
    _ref.invalidate(customerTransactionsProvider(customerId));
    _ref.invalidate(customerBalanceDetailsProvider(customerId));
    return cutResult;
  }

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
