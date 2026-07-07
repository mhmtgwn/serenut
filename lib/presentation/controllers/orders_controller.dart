// lib/presentation/controllers/orders_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/domain/events/domain_event.dart';
import 'package:serenutos/providers/event_providers.dart';
import 'package:serenutos/providers/audit_provider.dart';

class OrdersController extends AsyncNotifier<List<OrderEntity>> {
  late IOrderRepository _repository;

  @override
  FutureOr<List<OrderEntity>> build() async {
    _repository = await ref.watch(orderRepositoryProvider.future);
    return _repository.findAll();
  }

  Future<void> addOrder(OrderEntity order) async {
    await future;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.create(order);
      
      // Calculate total amount from items
      double total = 0.0;
      for (final item in order.items) {
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        total += qty * price;
      }
      
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

      // Log to Audit Trail
      try {
        final auditService = await ref.read(auditServiceProvider.future);
        final customerRepo = await ref.read(customerRepositoryProvider.future);
        final customer = await customerRepo.findById(order.customerId);
        await auditService.logEvent(
          eventType: 'order_created',
          entityType: 'order',
          entityId: order.id,
          newValue: 'Tutar: ₺${total.toStringAsFixed(2)}, Müşteri: ${customer?.name ?? 'Bilinmeyen Müşteri'}',
          notes: 'Yeni sipariş oluşturuldu: ${order.id}',
        );
      } catch (_) {}

      return _repository.findAll();
    });
  }

  Future<void> updateOrder(OrderEntity order) async {
    await future;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.update(order);

      // Log to Audit Trail
      try {
        final auditService = await ref.read(auditServiceProvider.future);
        final customerRepo = await ref.read(customerRepositoryProvider.future);
        final customer = await customerRepo.findById(order.customerId);
        await auditService.logEvent(
          eventType: 'order_updated',
          entityType: 'order',
          entityId: order.id,
          newValue: 'Durum: ${order.status}, Müşteri: ${customer?.name ?? 'Bilinmeyen Müşteri'}',
          notes: 'Sipariş güncellendi: ${order.id}',
        );
      } catch (_) {}

      return _repository.findAll();
    });
  }

  Future<void> deleteOrder(String id) async {
    await future;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final order = await _repository.findById(id);
      await _repository.delete(id);

      // Log to Audit Trail
      try {
        final auditService = await ref.read(auditServiceProvider.future);
        await auditService.logDelete(
          'order',
          id,
          'Sipariş Silindi - ID: $id (Müşteri ID: ${order?.customerId ?? 'Bilinmeyen'})',
        );
      } catch (_) {}

      return _repository.findAll();
    });
  }

  Future<void> updateStatus(String id, String status) async {
    await future;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.updateStatus(id, status);
      
      try {
        final order = await _repository.findById(id);
        if (order != null) {
          final publisher = ref.read(eventPublisherProvider);
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
          } else if (status == 'cancelled') {
            publisher.publish(OrderCancelledEvent(
              orderId: 0,
              customerId: 0,
              orderIdStr: order.id,
              customerIdStr: order.customerId,
            ));
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

      return _repository.findAll();
    });
  }

  Future<void> refresh() async {
    await future;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      return _repository.findAll();
    });
  }
}

final ordersControllerProvider =
    AsyncNotifierProvider<OrdersController, List<OrderEntity>>(() {
  return OrdersController();
});
