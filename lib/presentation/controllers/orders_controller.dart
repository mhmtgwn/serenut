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
  bool _isLoadingMore = false;
  String? _statusFilter;
  String? _searchQuery;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  bool _overdueOnly = false;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;

  @override
  FutureOr<List<OrderEntity>> build() async {
    _repository = await ref.watch(orderRepositoryProvider.future);
    _offset = 0;
    _hasMore = true;
    _isLoadingMore = false;
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
    _isLoadingMore = false;
    final result = await AsyncValue.guard(() => _repository.findFiltered(
          status: _statusFilter,
          searchQuery: _searchQuery,
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          overdueOnly: _overdueOnly,
          limit: _kPageSize,
          offset: 0,
        ));
    state = result;
    _offset = state.valueOrNull?.length ?? 0;
    _hasMore = (_offset == _kPageSize);
  }

  Future<void> applySearch(String? query) async {
    _searchQuery = (query == null || query.isEmpty) ? null : query;
    _offset = 0;
    _hasMore = true;
    _isLoadingMore = false;
    final result = await AsyncValue.guard(() => _repository.findFiltered(
          status: _statusFilter,
          searchQuery: _searchQuery,
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          overdueOnly: _overdueOnly,
          limit: _kPageSize,
          offset: 0,
        ));
    state = result;
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
    if (!_hasMore || _isLoadingMore) return;
    _isLoadingMore = true;
    try {
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
      if (next.isEmpty || next.length < _kPageSize) {
        _hasMore = false;
      }
      _offset += next.length;
      final existingIds = current.map((e) => e.id).toSet();
      final uniqueNext =
          next.where((e) => !existingIds.contains(e.id)).toList();
      if (uniqueNext.isEmpty) {
        _hasMore = false;
      } else {
        state = AsyncValue.data([...current, ...uniqueNext]);
      }
    } catch (e, stack) {
      _hasMore = false;
      TelemetryService().logError(
        e,
        stack,
        context: 'OrdersController.loadNextPage',
        level: LogLevel.error,
      );
    } finally {
      _isLoadingMore = false;
    }
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
    _isLoadingMore = false;
    final result = await AsyncValue.guard(() => _repository.findFiltered(
          status: _statusFilter,
          searchQuery: _searchQuery,
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          overdueOnly: _overdueOnly,
          limit: _kPageSize,
          offset: 0,
        ));
    state = result;
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
            'Tutar: ₺${total.toStringAsFixed(2)}, Müşteri: ${order.customerId.isEmpty ? 'Genel Müşteri' : (customer?.name ?? 'Bilinmeyen Müşteri')}',
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
            'Durum: ${order.status}, Müşteri: ${order.customerId.isEmpty ? 'Genel Müşteri' : (customer?.name ?? 'Bilinmeyen Müşteri')}',
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
    if (order == null) return;
    if (order.status.toLowerCase() == 'delivered') {
      throw StateError('Teslim edilmiş siparişler silinemez.');
    }

    // Sipariş henüz iptal edilmemişse depoya stokları iade et
    if (order.status.toLowerCase() != 'cancelled') {
      try {
        final inventory = await ref.read(inventoryServiceProvider.future);
        await inventory.increaseStock(_inventoryItems(order.items));
      } catch (e, st) {
        TelemetryService().logError(e, st,
            context: 'orders_controller:deleteOrder:stockRestore', level: LogLevel.warning);
      }
    }

    await _repository.delete(id);

    // Optimistically update state so the deleted order vanishes immediately
    if (state.hasValue) {
      state = AsyncValue.data(
        state.requireValue.where((o) => o.id != id).toList(),
      );
    }

    // Log to Audit Trail
    try {
      final auditService = await ref.read(auditServiceProvider.future);
      await auditService.logDelete(
        'order',
        id,
        'Sipariş Silindi - ID: $id (Müşteri ID: ${order.customerId})',
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

    if (state.hasValue) {
      state = AsyncValue.data(
        state.requireValue
            .map((o) => o.id == id ? o.copyWith(status: status) : o)
            .toList(),
      );
    }

    unawaited(ref.read(syncProvider.notifier).triggerSync());
    await refresh();
  }

  /// Toplu sipariş silme (teslim edilenler hariç).
  Future<int> bulkDeleteOrders(Iterable<String> ids,
      {String? approvedByUserId, String? approvedByUserName}) async {
    await future;
    final idSet = ids.toSet();
    if (idSet.isEmpty) return 0;

    int deletedCount = 0;
    final deletedIds = <String>{};
    final auditService = await ref.read(auditServiceProvider.future);

    for (final id in idSet) {
      final order = await _repository.findById(id);
      if (order == null) continue;
      // TESLİM EDİLMİŞ SİPARİŞLER SİLİNEMEZ (KORUMA KURALI)
      if (order.status.toLowerCase() == 'delivered') continue;

      // Sipariş henüz iptal edilmemişse depoya stokları iade et
      if (order.status.toLowerCase() != 'cancelled') {
        try {
          final inventory = await ref.read(inventoryServiceProvider.future);
          await inventory.increaseStock(_inventoryItems(order.items));
        } catch (_) {}
      }

      await _repository.delete(id);
      deletedCount++;
      deletedIds.add(id);

      try {
        await auditService.logDelete(
          'order',
          id,
          'Toplu Sipariş Silindi - ID: $id (Müşteri ID: ${order.customerId})',
          approvedByUserId: approvedByUserId,
          approvedByUserName: approvedByUserName,
        );
      } catch (e, st) {
        TelemetryService().logError(e, st,
            context: 'orders_controller:bulkDelete', level: LogLevel.warning);
      }
    }

    if (deletedCount > 0) {
      if (state.hasValue) {
        state = AsyncValue.data(
          state.requireValue.where((o) => !deletedIds.contains(o.id)).toList(),
        );
      }
      unawaited(ref.read(syncProvider.notifier).triggerSync());
      await refresh();
    }

    return deletedCount;
  }

  /// Toplu sipariş iptali (teslim edilenler hariç).
  Future<int> bulkCancelOrders(Iterable<String> ids) async {
    await future;
    final idSet = ids.toSet();
    if (idSet.isEmpty) return 0;

    int cancelledCount = 0;
    final cancellationService =
        await ref.read(orderCancellationServiceProvider.future);
    final publisher = ref.read(eventPublisherProvider);
    final auditService = await ref.read(auditServiceProvider.future);
    final affectedCustomerIds = <String>{};

    for (final id in idSet) {
      final order = await _repository.findById(id);
      if (order == null) continue;
      // TESLİM EDİLMİŞ VEYA ZATEN İPTAL OLANLAR ATLANIR
      final currentStatus = order.status.toLowerCase();
      if (currentStatus == 'delivered' || currentStatus == 'cancelled') {
        continue;
      }

      await cancellationService.cancel(id: order.id);
      cancelledCount++;
      affectedCustomerIds.add(order.customerId);

      publisher.publish(OrderCancelledEvent(
        orderId: 0,
        customerId: 0,
        orderIdStr: order.orderNumber,
        customerIdStr: order.customerId,
      ));

      try {
        await auditService.logEvent(
          eventType: 'order_cancelled',
          entityType: 'order',
          entityId: id,
          newValue: 'cancelled',
          notes: 'Toplu Sipariş İptal Edildi - ID: $id',
        );
      } catch (e, st) {
        TelemetryService().logError(e, st,
            context: 'orders_controller:bulkCancel', level: LogLevel.warning);
      }
    }

    if (cancelledCount > 0) {
      ref.invalidate(customersControllerProvider);
      for (final custId in affectedCustomerIds) {
        ref.invalidate(customerTransactionsProvider(custId));
        ref.invalidate(customerBalanceDetailsProvider(custId));
      }
      unawaited(ref.read(syncProvider.notifier).triggerSync());
      await refresh();
    }

    return cancelledCount;
  }

  /// Toplu sipariş durumu güncelleme (teslim hariç).
  Future<int> bulkUpdateStatus(Iterable<String> ids, String newStatus) async {
    await future;
    final targetStatus = newStatus.toLowerCase();
    // TESLİM DURUMU TOPLU İŞLEMLERE KAPALIDIR
    if (targetStatus == 'delivered') {
      throw ArgumentError(
          'Teslim işlemi toplu olarak yapılamaz; satış ve ödeme adımları gerektirir.');
    }

    if (targetStatus == 'cancelled') {
      return bulkCancelOrders(ids);
    }

    final idSet = ids.toSet();
    if (idSet.isEmpty) return 0;

    int updatedCount = 0;
    final publisher = ref.read(eventPublisherProvider);
    final auditService = await ref.read(auditServiceProvider.future);

    for (final id in idSet) {
      final order = await _repository.findById(id);
      if (order == null) continue;
      // TESLİM EDİLMİŞ SİPARİŞLERİN DURUMU TOPLUCA DEĞİŞTİRİLEMEZ
      if (order.status.toLowerCase() == 'delivered') continue;
      if (order.status.toLowerCase() == targetStatus) continue;

      await _repository.updateStatus(id, targetStatus);
      updatedCount++;

      if (targetStatus == 'preparing') {
        publisher.publish(OrderPreparingEvent(
          orderId: 0,
          customerId: 0,
          orderIdStr: order.orderNumber,
          customerIdStr: order.customerId,
        ));
      } else if (targetStatus == 'ready') {
        publisher.publish(OrderReadyEvent(
          orderId: 0,
          customerId: 0,
          orderIdStr: order.orderNumber,
          customerIdStr: order.customerId,
        ));
      }

      try {
        await auditService.logEvent(
          eventType: 'order_status_updated',
          entityType: 'order',
          entityId: id,
          newValue: targetStatus,
          notes: 'Toplu Sipariş Durumu Güncellendi: $id -> $targetStatus',
        );
      } catch (e, st) {
        TelemetryService().logError(e, st,
            context: 'orders_controller:bulkUpdateStatus',
            level: LogLevel.warning);
      }
    }

    if (updatedCount > 0) {
      unawaited(ref.read(syncProvider.notifier).triggerSync());
      await refresh();
    }

    return updatedCount;
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
