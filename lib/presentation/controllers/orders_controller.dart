// lib/presentation/controllers/orders_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/domain/events/domain_event.dart';
import 'package:serenutos/providers/event_providers.dart';
import 'package:serenutos/providers/audit_provider.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/domain/services/math_engine.dart';
import 'package:serenutos/domain/services/inventory_service.dart';
import 'package:serenutos/providers/database_provider.dart';
import 'package:serenutos/providers/sync_provider.dart';

// ─── Pagination constants ─────────────────────────────────────────────────────
const _kPageSize = 25;

class OrdersController extends AsyncNotifier<List<OrderEntity>> {
  late IOrderRepository _repository;

  // Pagination state
  int _offset = 0;
  bool _hasMore = true;
  String? _statusFilter;
  String? _searchQuery;

  bool get hasMore => _hasMore;

  @override
  FutureOr<List<OrderEntity>> build() async {
    _repository = await ref.watch(orderRepositoryProvider.future);
    _offset = 0;
    _hasMore = true;
    return _repository.findFiltered(
      status: _statusFilter,
      searchQuery: _searchQuery,
      limit: _kPageSize,
      offset: 0,
    );
  }

  // ── Filtering & Search ──────────────────────────────────────────────────────

  Future<void> applyFilter(String? status) async {
    _statusFilter = (status == 'all' || status == null) ? null : status;
    _offset = 0;
    _hasMore = true;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.findFiltered(
          status: _statusFilter,
          searchQuery: _searchQuery,
          limit: _kPageSize,
          offset: 0,
        ));
    _offset = state.valueOrNull?.length ?? 0;
    _hasMore = (_offset == _kPageSize);
  }

  Future<void> applySearch(String? query) async {
    _searchQuery = (query == null || query.isEmpty) ? null : query;
    _offset = 0;
    _hasMore = true;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.findFiltered(
          status: _statusFilter,
          searchQuery: _searchQuery,
          limit: _kPageSize,
          offset: 0,
        ));
    _offset = state.valueOrNull?.length ?? 0;
    _hasMore = (_offset == _kPageSize);
  }

  // ── Pagination ──────────────────────────────────────────────────────────────

  Future<void> loadNextPage() async {
    if (!_hasMore) return;
    final current = state.valueOrNull ?? [];
    final next = await _repository.findFiltered(
      status: _statusFilter,
      searchQuery: _searchQuery,
      limit: _kPageSize,
      offset: _offset,
    );
    if (next.length < _kPageSize) _hasMore = false;
    _offset += next.length;
    state = AsyncValue.data([...current, ...next]);
  }

  // ── Status counts (for sidebar badges) ────────────────────────────────────

  Future<Map<String, int>> getStatusCounts() async {
    return _repository.getStatusCounts(searchQuery: _searchQuery);
  }

  // ── Refresh ────────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    _offset = 0;
    _hasMore = true;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.findFiltered(
          status: _statusFilter,
          searchQuery: _searchQuery,
          limit: _kPageSize,
          offset: 0,
        ));
    _offset = state.valueOrNull?.length ?? 0;
    _hasMore = (_offset == _kPageSize);
  }

  // ── CRUD mutations (unchanged, call refresh after) ─────────────────────────

  Future<void> addOrder(OrderEntity order) async {
    await future;
    final inventory = await ref.read(inventoryServiceProvider.future);
    final gateway = ref.read(dbGatewayProvider);
    await gateway.transaction(() async {
      await inventory.verifyStockAvailability(_inventoryItems(order.items));
      await _repository.create(order);
      await inventory.decreaseStock(_inventoryItems(order.items));
    });

    // Calculate total amount from items
    final total = MathEngine.calculateMappedItemsTotal(order.items);

    // Publish OrderCreatedEvent
    try {
      final publisher = ref.read(eventPublisherProvider);
      publisher.publish(OrderCreatedEvent(
        orderId: 0,
        customerId: 0,
        totalAmount: total,
        expectedDeliveryDate: order.expectedDeliveryDate ?? DateTime.now(),
        orderIdStr: order.id,
        customerIdStr: order.customerId,
      ));
    } catch (_) {}

    unawaited(ref.read(syncProvider.notifier).triggerSync());

    // Log to Audit Trail
    try {
      final auditService = await ref.read(auditServiceProvider.future);
      final customerRepo = await ref.read(customerRepositoryProvider.future);
      final customer = await customerRepo.findById(order.customerId);
      await auditService.logEvent(
        eventType: 'order_created',
        entityType: 'order',
        entityId: order.id,
        newValue:
            'Tutar: ₺${total.toStringAsFixed(2)}, Müşteri: ${customer?.name ?? 'Bilinmeyen Müşteri'}',
        notes: 'Yeni sipariş oluşturuldu: ${order.id}',
      );
    } catch (_) {}

    await refresh();
  }

  Future<void> updateOrder(OrderEntity order) async {
    await future;
    final previous = await _repository.findById(order.id);
    if (previous == null) {
      throw StateError('Düzenlenecek sipariş bulunamadı: ${order.id}');
    }
    final inventory = await ref.read(inventoryServiceProvider.future);
    final gateway = ref.read(dbGatewayProvider);
    await gateway.transaction(() async {
      await inventory.increaseStock(_inventoryItems(previous.items));
      await inventory.verifyStockAvailability(_inventoryItems(order.items));
      await _repository.update(order);
      await inventory.decreaseStock(_inventoryItems(order.items));
    });

    // Log to Audit Trail
    try {
      final auditService = await ref.read(auditServiceProvider.future);
      final customerRepo = await ref.read(customerRepositoryProvider.future);
      final customer = await customerRepo.findById(order.customerId);
      await auditService.logEvent(
        eventType: 'order_updated',
        entityType: 'order',
        entityId: order.id,
        newValue:
            'Durum: ${order.status}, Müşteri: ${customer?.name ?? 'Bilinmeyen Müşteri'}',
        notes: 'Sipariş güncellendi: ${order.id}',
      );
    } catch (_) {}

    await refresh();
  }

  List<SaleItemInput> _inventoryItems(List<Map<String, dynamic>> items) {
    return items
        .map((item) {
          final productId =
              (item['product_id'] ?? item['productId']).toString();
          final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
          final price = ((item['unit_price'] ??
                      item['unitPrice'] ??
                      item['price']) as num?)
                  ?.toDouble() ??
              0.0;
          return SaleItemInput(
            productId: productId,
            quantity: quantity,
            unitPrice: price,
          );
        })
        .where((item) => item.productId.isNotEmpty && item.quantity > 0)
        .toList();
  }

  Future<void> deleteOrder(String id,
      {String? approvedByUserId, String? approvedByUserName}) async {
    await future;
    final order = await _repository.findById(id);
    await _repository.delete(id);

    // Log to Audit Trail
    try {
      final auditService = await ref.read(auditServiceProvider.future);
      await auditService.logDelete(
        'order',
        id,
        'Sipariş Silindi - ID: $id (Müşteri ID: ${order?.customerId ?? 'Bilinmeyen'})',
        approvedByUserId: approvedByUserId,
        approvedByUserName: approvedByUserName,
      );
    } catch (_) {}

    await refresh();
  }

  Future<void> updateStatus(String id, String status) async {
    await future;

    try {
      final order = await _repository.findById(id);
      if (order != null) {
        final publisher = ref.read(eventPublisherProvider);

        if (status == 'cancelled') {
          final cancellationService =
              await ref.read(orderCancellationServiceProvider.future);

          await cancellationService.cancel(
            id: order.id,
            isOrder: true,
          );

          publisher.publish(OrderCancelledEvent(
            orderId: 0,
            customerId: 0,
            orderIdStr: order.id,
            customerIdStr: order.customerId,
          ));

          // Invalidate balance/transaction providers to refresh UI state immediately
          ref.invalidate(customersControllerProvider);
          ref.invalidate(customerTransactionsProvider(order.customerId));
          ref.invalidate(customerBalanceDetailsProvider(order.customerId));
        } else {
          await _repository.updateStatus(id, status);

          if (status == 'delivered') {
            publisher.publish(OrderDeliveredEvent(
              orderId: 0,
              customerId: 0,
              orderIdStr: order.id,
              customerIdStr: order.customerId,
            ));
          } else if (status == 'preparing') {
            publisher.publish(OrderPreparingEvent(
              orderId: 0,
              customerId: 0,
              orderIdStr: order.id,
              customerIdStr: order.customerId,
            ));
          } else if (status == 'ready') {
            publisher.publish(OrderReadyEvent(
              orderId: 0,
              customerId: 0,
              orderIdStr: order.id,
              customerIdStr: order.customerId,
            ));
          }
        }

        // Log status update to audit trail
        final auditService = await ref.read(auditServiceProvider.future);
        await auditService.logEvent(
          eventType: 'order_status_updated',
          entityType: 'order',
          entityId: id,
          newValue: status,
          notes: 'Sipariş durumu güncellendi: $id -> $status',
        );
      }
    } catch (_) {}

    await refresh();
  }
}

final ordersControllerProvider =
    AsyncNotifierProvider<OrdersController, List<OrderEntity>>(() {
  return OrdersController();
});
