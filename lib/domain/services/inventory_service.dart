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
  final double saleQuantity;
  final double unitPrice;

  SaleItemInput({
    required this.productId,
    required this.quantity,
    double? saleQuantity,
    required this.unitPrice,
  }) : saleQuantity = saleQuantity ?? quantity.toDouble();

  Map<String, dynamic> toMap() => {
        'product_id': productId,
        'quantity': saleQuantity,
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
      final product = await _productRepository.findById(item.productId);
      final int effectiveQty = (product != null && product.isWeighed && item.quantity >= 100)
          ? item.saleQuantity.round()
          : item.quantity;
      final qtyToDeduct = effectiveQty > 0 ? effectiveQty : 1;

      await _productRepository.decreaseStock(item.productId, qtyToDeduct);

      final parsedProductId =
          int.tryParse(item.productId.replaceAll(RegExp(r'[^0-9]'), '')) ??
              item.productId.hashCode.abs();

      _eventPublisher.publish(StockChangedEvent(
        productId: parsedProductId,
        quantityChange: -qtyToDeduct,
        reason: 'sale',
      ));
    }
  }

  /// Increases product stock levels for the given items (returns/reversals) and publishes StockChangedEvents.
  Future<void> increaseStock(List<SaleItemInput> items) async {
    for (final item in items) {
      final product = await _productRepository.findById(item.productId);
      final int effectiveQty = (product != null && product.isWeighed && item.quantity >= 100)
          ? item.saleQuantity.round()
          : (item.quantity > 0 ? item.quantity : item.saleQuantity.round());
      final qtyToApply = effectiveQty > 0 ? effectiveQty : 1;

      await _productRepository.increaseStock(item.productId, qtyToApply);

      final parsedProductId =
          int.tryParse(item.productId.replaceAll(RegExp(r'[^0-9]'), '')) ??
              item.productId.hashCode.abs();

      _eventPublisher.publish(StockChangedEvent(
        productId: parsedProductId,
        quantityChange: qtyToApply,
        reason: 'refund',
      ));
    }
  }
}
