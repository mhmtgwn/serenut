// lib/domain/services/inventory_service.dart
// Phase 2.4 — Envanter Yönetim Servisi
// Handles stock validation and movement orchestration
// Generated: 21 Jun 2026

import 'package:serenutos/domain/events/domain_event.dart';
import 'package:serenutos/domain/events/event_publisher.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

/// Value class for sale/inventory item input
class SaleItemInput {
  final String productId;
  final int quantity;
  final double unitPrice;

  SaleItemInput({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
  });

  Map<String, dynamic> toMap() => {
        'product_id': productId,
        'quantity': quantity,
        'unit_price': unitPrice,
      };
}

/// Custom Exceptions for inventory
class ProductNotFoundException implements Exception {
  final String message;
  ProductNotFoundException(this.message);

  @override
  String toString() => message;
}

class InsufficientStockException implements Exception {
  final String message;
  InsufficientStockException(this.message);

  @override
  String toString() => message;
}

class InventoryService {
  final IProductRepository _productRepository;
  final EventPublisher _eventPublisher;

  InventoryService({
    required IProductRepository productRepository,
    required EventPublisher eventPublisher,
  })  : _productRepository = productRepository,
        _eventPublisher = eventPublisher;

  Future<void> verifyStockAvailability(List<SaleItemInput> items) async {
    for (final item in items) {
      final product = await _productRepository.findById(item.productId);
      if (product == null) {
        throw ProductNotFoundException('Ürün bulunamadı: ${item.productId}');
      }
      // Business requirement: allow selling into negative stock levels
      // if (product.quantity < item.quantity) {
      //   throw InsufficientStockException(
      //     'Yetersiz stok: "${product.name}" için mevcut stok: ${product.quantity}, talep edilen: ${item.quantity}',
      //   );
      // }
    }
  }

  /// Decreases product stock levels for the given items and publishes StockChangedEvents.
  Future<void> decreaseStock(List<SaleItemInput> items) async {
    for (final item in items) {
      await _productRepository.decreaseStock(item.productId, item.quantity);

      // Try to parse product ID as int for DomainEvent compatibility
      int parsedProductId = 0;
      try {
        parsedProductId =
            int.parse(item.productId.replaceAll(RegExp(r'[^0-9]'), ''));
      } catch (_) {}

      _eventPublisher.publish(StockChangedEvent(
        productId: parsedProductId,
        quantityChange: -item.quantity,
        reason: 'sale',
      ));
    }
  }

  /// Increases product stock levels for the given items (returns/reversals) and publishes StockChangedEvents.
  Future<void> increaseStock(List<SaleItemInput> items) async {
    for (final item in items) {
      await _productRepository.increaseStock(item.productId, item.quantity);

      int parsedProductId = 0;
      try {
        parsedProductId =
            int.parse(item.productId.replaceAll(RegExp(r'[^0-9]'), ''));
      } catch (_) {}

      _eventPublisher.publish(StockChangedEvent(
        productId: parsedProductId,
        quantityChange: item.quantity,
        reason: 'refund',
      ));
    }
  }
}
