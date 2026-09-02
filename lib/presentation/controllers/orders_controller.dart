// lib/presentation/controllers/orders_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/domain/events/domain_event.dart';
import 'package:serenutos/providers/event_providers.dart';
import 'package:serenutos/providers/audit_provider.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
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
  DateTime? _dateFrom;
  DateTime? _dateTo;
  bool _overdueOnly = false;

  bool get hasMore => _hasMore;

  @override
  FutureOr<List<OrderEntity>> build() async {
    _repository = await ref.watch(orderRepositoryProvider.future);
    _offset = 0;
    _hasMore = true;
    final firstPage = await _repository.findFiltered(
      status: _statusFilter,
      searchQuery: _searchQuery,
      dateFrom: _dateFrom,
      dateTo: _dateTo,
      overdueOnly: _overdueOnly,
      limit: _kPageSize,
      offset: 0,
    );
    _offset = firstPage.length;
    _hasMore = firstPage.length == _kPageSize;
    return firstPage;
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
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          overdueOnly: _overdueOnly,
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
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          overdueOnly: _overdueOnly,
          limit: _kPageSize,
          offset: 0,
        ));
    _offset = state.valueOrNull?.length ?? 0;
    _hasMore = (_offset == _kPageSize);
  }

  Future<void> applyAdvancedFilter({
    DateTime? dateFrom,
    DateTime? dateTo,
    bool overdueOnly = false,
  }) async {
    _dateFrom = dateFrom;
    _dateTo = dateTo;
    _overdueOnly = overdueOnly;
    await refresh();
  }

  // ── Pagination ──────────────────────────────────────────────────────────────

  Future<void> loadNextPage() async {
    if (!_hasMore) return;
    final current = state.valueOrNull ?? [];
    final next = await _repository.findFiltered(
      status: _statusFilter,
      searchQuery: _searchQuery,
      dateFrom: _dateFrom,
      dateTo: _dateTo,
      overdueOnly: _overdueOnly,
      limit: _kPageSize,
      offset: _offset,
    );
    if (next.length < _kPageSize) _hasMore = false;
    _offset += next.length;
    state = AsyncValue.data([...current, ...next]);
  }

  // ── Status counts (for sidebar badges) ────────────────────────────────────

  Future<Map<String, int>> getStatusCounts() async {
    return _repository.getStatusCounts(
      searchQuery: _searchQuery,
      dateFrom: _dateFrom,
      dateTo: _dateTo,
      overdueOnly: _overdueOnly,
    );
  }

  // ── Refresh ────────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    _offset = 0;
    _hasMore = true;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.findFiltered(
          status: _statusFilter,
          searchQuery: _searchQuery,
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          overdueOnly: _overdueOnly,
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

    final persistedOrder = await _repository.findById(order.id);
    if (persistedOrder == null || persistedOrder.orderNumber.isEmpty) {
      throw StateError('Oluşturulan siparişin benzersiz numarası alınamadı.');
    }

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
        orderIdStr: persistedOrder.orderNumber,
        customerIdStr: order.customerId,
      ));
    } catch (e, st) {
      TelemetryService().logError(e, st,
          context: 'orders_controller', level: LogLevel.warning);
    }

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
    } catch (e, st) {
      TelemetryService().logError(e, st,
          context: 'orders_controller', level: LogLevel.warning);
    }

    unawaited(ref.read(syncProvider.notifier).triggerSync());
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
    } catch (e, st) {
      TelemetryService().logError(e, st,
          context: 'orders_controller', level: LogLevel.warning);
    }

    unawaited(ref.read(syncProvider.notifier).triggerSync());
    await refresh();
  }

  List<SaleItemInput> _inventoryItems(List<Map<String, dynamic>> items) {
    return items
        .map((item) {
          final productId =
              (item['product_id'] ?? item['productId']).toString();
          final rawQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
          final intQty =
              rawQty >= 1.0 ? rawQty.round() : (rawQty > 0.0 ? 1 : 0);
          final price = ((item['unit_price'] ??
                      item['unitPrice'] ??
                      item['price']) as num?)
                  ?.toDouble() ??
              0.0;
          return SaleItemInput(
            productId: productId,
            quantity: intQty,
            saleQuantity: rawQty,
            unitPrice: price,
          );
        })
        .where((item) => item.productId.isNotEmpty && item.saleQuantity > 0)
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
    } catch (e, st) {
      TelemetryService().logError(e, st,
          context: 'orders_controller', level: LogLevel.warning);
    }

    unawaited(ref.read(syncProvider.notifier).triggerSync());
    await refresh();
  }

  Future<void> updateStatus(String id, String status) async {
    await future;
    final order = await _repository.findById(id);
    if (order == null) throw StateError('Sipariş bulunamadı: $id');
    final publisher = ref.read(eventPublisherProvider);

    if (status == 'cancelled') {
      final cancellationService =
          await ref.read(orderCancellationServiceProvider.future);

      await cancellationService.cancel(
        id: order.id,
      );

      publisher.publish(OrderCancelledEvent(
        orderId: 0,
        customerId: 0,
        orderIdStr: order.orderNumber,
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
          orderIdStr: order.orderNumber,
          customerIdStr: order.customerId,
        ));
      } else if (status == 'preparing') {
        publisher.publish(OrderPreparingEvent(
          orderId: 0,
          customerId: 0,
          orderIdStr: order.orderNumber,
          customerIdStr: order.customerId,
        ));
      } else if (status == 'ready') {
        publisher.publish(OrderReadyEvent(
          orderId: 0,
          customerId: 0,
          orderIdStr: order.orderNumber,
          customerIdStr: order.customerId,
        ));
      }
    }

    // Audit failure must not hide or roll back a successful status mutation.
    try {
      final auditService = await ref.read(auditServiceProvider.future);
      await auditService.logEvent(
        eventType: 'order_status_updated',
        entityType: 'order',
        entityId: id,
        newValue: status,
        notes: 'Sipariş durumu güncellendi: $id -> $status',
      );
    } catch (e, st) {
      TelemetryService().logError(e, st,
          context: 'orders_controller', level: LogLevel.warning);
    }

    unawaited(ref.read(syncProvider.notifier).triggerSync());
    await refresh();
  }

  Future<void> refundOrder({
    required String orderId,
    required String refundMethod,
    required String reason,
    List<SaleItemInput>? itemsToRefund,
  }) async {
    await future;
    final order = await _repository.findById(orderId);
    if (order == null) throw StateError('Sipariş bulunamadı: $orderId');

    final inventory = await ref.read(inventoryServiceProvider.future);
    final paymentService = await ref.read(paymentServiceProvider.future);

    // 1. İade edilecek ürünleri ve toplam tutarı belirle
    final restoredItems = <SaleItemInput>[];
    double totalRefundAmount = 0.0;

    if (itemsToRefund != null && itemsToRefund.isNotEmpty) {
      restoredItems.addAll(itemsToRefund);
      for (final item in itemsToRefund) {
        final qty = item.saleQuantity;
        totalRefundAmount += qty * item.unitPrice;
      }
    } else {
      // Siparişteki tüm kalemlerin tam iadesi
      for (final item in order.items) {
        final productId =
            item['product_id'] as String? ?? item['productId'] as String?;
        final double rawQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final price = (item['unit_price'] as num?)?.toDouble() ??
            (item['unitPrice'] as num?)?.toDouble() ??
            0.0;
        if (productId != null && rawQty > 0) {
          final int intQty =
              rawQty < 1 ? (rawQty * 1000).round() : rawQty.round();
          restoredItems.add(SaleItemInput(
            productId: productId,
            quantity: intQty,
            saleQuantity: rawQty,
            unitPrice: price,
          ));
          totalRefundAmount += rawQty * price;
        }
      }
    }

    // 2. Stokları depoya geri yükle
    if (restoredItems.isNotEmpty) {
      await inventory.increaseStock(restoredItems);
    }

    // 3. Deftere iade kaydı işle (müşteri bakiyesini güncelle veya nakit çıkışı yap)
    await paymentService.processRefund(
      saleId: order.id,
      customerId: order.customerId,
      refundTotal: totalRefundAmount,
      refundMethod: refundMethod,
    );

    // 4. Sipariş notuna ve durumuna iade bilgisini işle
    final returnNote =
        'İade Alındı: ₺${totalRefundAmount.toStringAsFixed(2)} ($refundMethod) - $reason';
    final updatedNotes = order.notes != null && order.notes!.isNotEmpty
        ? '${order.notes}\n$returnNote'
        : returnNote;

    await _repository.update(order.copyWith(
      status: 'cancelled',
      notes: updatedNotes,
    ));

    // 5. Denetim kütüğüne (Audit Trail) işle
    try {
      final auditService = await ref.read(auditServiceProvider.future);
      await auditService.logEvent(
        eventType: 'items_returned',
        entityType: 'order',
        entityId: order.id,
        newValue: '₺${totalRefundAmount.toStringAsFixed(2)}',
        notes:
            'Sipariş İadesi Yapıldı (${order.orderNumber.isNotEmpty ? order.orderNumber : order.id}) - Yöntem: $refundMethod, Gerekçe: $reason',
      );
    } catch (e, st) {
      TelemetryService().logError(e, st,
          context: 'orders_controller', level: LogLevel.warning);
    }

    // İlgili tüm sağlayıcıları yenile
    ref.invalidate(customersControllerProvider);
    ref.invalidate(customerTransactionsProvider(order.customerId));
    ref.invalidate(customerBalanceDetailsProvider(order.customerId));
    ref.invalidate(productsControllerProvider);
    unawaited(ref.read(syncProvider.notifier).triggerSync());
    await refresh();
  }
}

final ordersControllerProvider =
    AsyncNotifierProvider<OrdersController, List<OrderEntity>>(() {
  return OrdersController();
});
