import 'dart:async';
import 'package:uuid/uuid.dart';
// Complies with Clean Architecture dependency inversion rules
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/events/event_publisher.dart';
import 'package:serenutos/domain/events/domain_event.dart';
import 'package:serenutos/domain/services/inventory_service.dart';
import 'package:serenutos/domain/services/payment_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/domain/services/security_gate.dart';

export 'package:serenutos/domain/services/inventory_service.dart' show SaleItemInput, ProductNotFoundException, InsufficientStockException;

import 'package:serenutos/domain/services/data_integrity_service.dart';

class SalesService {
  final ISaleRepository _saleRepository;
  final InventoryService _inventoryService;
  final PaymentService _paymentService;
  final EventPublisher _eventPublisher;
  final IDbTransactionRunner _transactionRunner;
  final SecurityGate _securityGate;
  final DataIntegrityService? _dataIntegrityService;

  /// Standard constructor using IDbTransactionRunner for clean architectural separation
  SalesService({
    required ISaleRepository saleRepository,
    required InventoryService inventoryService,
    required PaymentService paymentService,
    required EventPublisher eventPublisher,
    required IDbTransactionRunner transactionRunner,
    required SecurityGate securityGate,
    DataIntegrityService? dataIntegrityService,
  })  : _saleRepository = saleRepository,
        _inventoryService = inventoryService,
        _paymentService = paymentService,
        _eventPublisher = eventPublisher,
        _transactionRunner = transactionRunner,
        _securityGate = securityGate,
        _dataIntegrityService = dataIntegrityService;

  /// Named alias — kept for backward compat with salesServiceProvider call sites
  factory SalesService.noDb({
    required ISaleRepository saleRepository,
    required InventoryService inventoryService,
    required PaymentService paymentService,
    required EventPublisher eventPublisher,
    required SecurityGate securityGate,
    IDbTransactionRunner? transactionRunner,
    DataIntegrityService? dataIntegrityService,
  }) =>
      SalesService(
        saleRepository:   saleRepository,
        inventoryService: inventoryService,
        paymentService:   paymentService,
        eventPublisher:   eventPublisher,
        transactionRunner: transactionRunner ?? _DummyTransactionRunner(),
        securityGate: securityGate,
        dataIntegrityService: dataIntegrityService,
      );

  void _checkSecurityGate() {
    _securityGate.ensureAccess();
    _securityGate.ensureDbIntegrity();
  }

  /// Create a new sale (atomic orchestration with event publishing)
  Future<SaleEntity> createSale({
    required String customerId,
    required List<SaleItemInput> items,
    required String paymentMethod,
    double? paidAmount,
    String? idempotencyKey,
    String? createdBy,
  }) async {
    _checkSecurityGate();
    final stopwatch = Stopwatch()..start();
    // Validate
    if (items.isEmpty) {
      throw SaleEmptyException('Sale must contain at least one item');
    }

    // Idempotency check:
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      final existingSale = await _saleRepository.findByIdempotencyKey(idempotencyKey);
      if (existingSale != null) {
        return existingSale;
      }
    }

    // Calculate totals
    double totalAmount = 0;
    for (final item in items) {
      totalAmount += item.quantity * item.unitPrice;
    }

    final double finalPaidAmount = paidAmount ?? totalAmount;

    // Create sale entity with idempotent Uuid v4
    const uuid = Uuid();
    final sale = SaleEntity(
      id: 'sale-${uuid.v4()}',
      customerId: customerId,
      totalAmount: totalAmount,
      paidAmount: finalPaidAmount,
      paymentMethod: paymentMethod,
      status: 'pending',
      createdAt: DateTime.now(),
      items: items.map((i) => i.toMap()).toList(),
      idempotencyKey: idempotencyKey,
      createdBy: createdBy,
    );

    if (kIsWeb) {
      try {
        await _inventoryService.verifyStockAvailability(items);

        final processingSale = SaleEntity(
          id: sale.id,
          customerId: sale.customerId,
          totalAmount: sale.totalAmount,
          paidAmount: sale.paidAmount,
          paymentMethod: sale.paymentMethod,
          status: 'processing',
          createdAt: sale.createdAt,
          items: sale.items,
          idempotencyKey: sale.idempotencyKey,
          isSynced: sale.isSynced,
        );
        await _saleRepository.create(processingSale);

        await _paymentService.processSalePayment(
          saleId: sale.id,
          customerId: customerId,
          totalAmount: totalAmount,
          paidAmount: finalPaidAmount,
          paymentMethod: paymentMethod,
        );
        await _inventoryService.decreaseStock(items);

        final completedSale = SaleEntity(
          id: sale.id,
          customerId: sale.customerId,
          totalAmount: sale.totalAmount,
          paidAmount: sale.paidAmount,
          paymentMethod: sale.paymentMethod,
          status: 'completed',
          createdAt: sale.createdAt,
          items: sale.items,
          idempotencyKey: sale.idempotencyKey,
          isSynced: sale.isSynced,
        );
        await _saleRepository.update(completedSale);

        int parsedSaleId = 0;
        try {
          parsedSaleId = sale.id.hashCode.abs();
        } catch (_) {}

        _eventPublisher.publish(SaleCreatedEvent(
          saleId: parsedSaleId,
          customerId: 0,
          totalAmount: totalAmount,
          saleIdStr: sale.id,
          customerIdStr: customerId,
          paidAmount: finalPaidAmount,
          paymentMethod: paymentMethod,
          occurredAt: DateTime.now(),
        ));

        final elapsed = stopwatch.elapsedMilliseconds;
        await TelemetryService().logEvent('sale_checkout', {
          'sale_id': sale.id,
          'items_count': items.length,
          'total_amount': totalAmount,
          'time_ms': elapsed,
          'status': 'success',
        });
        return completedSale;
      } catch (e) {
        _eventPublisher.publish(SaleFailedEvent(
          customerId: customerId.hashCode,
          reason: e.toString(),
          occurredAt: DateTime.now(),
        ));
        final elapsed = stopwatch.elapsedMilliseconds;
        await TelemetryService().logEvent('sale_checkout', {
          'items_count': items.length,
          'total_amount': totalAmount,
          'time_ms': elapsed,
          'status': 'failed',
          'error': e.toString(),
        });
        rethrow;
      }
    }

    try {
      return await _transactionRunner.transaction(() async {
        await _inventoryService.verifyStockAvailability(items);

        // Update to processing status
        final processingSale = SaleEntity(
          id: sale.id,
          customerId: sale.customerId,
          totalAmount: sale.totalAmount,
          paidAmount: sale.paidAmount,
          paymentMethod: sale.paymentMethod,
          status: 'processing',
          createdAt: sale.createdAt,
          items: sale.items,
          idempotencyKey: sale.idempotencyKey,
          isSynced: sale.isSynced,
        );
        await _saleRepository.create(processingSale);

        await _paymentService.processSalePayment(
          saleId: sale.id,
          customerId: customerId,
          totalAmount: totalAmount,
          paidAmount: finalPaidAmount,
          paymentMethod: paymentMethod,
        );
        await _inventoryService.decreaseStock(items);

        // Completed!
        final completedSale = SaleEntity(
          id: sale.id,
          customerId: sale.customerId,
          totalAmount: sale.totalAmount,
          paidAmount: sale.paidAmount,
          paymentMethod: sale.paymentMethod,
          status: 'completed',
          createdAt: sale.createdAt,
          items: sale.items,
          idempotencyKey: sale.idempotencyKey,
          isSynced: sale.isSynced,
        );
        await _saleRepository.update(completedSale);

        int parsedSaleId = 0;
        try {
          parsedSaleId = sale.id.hashCode.abs();
        } catch (_) {}

        _eventPublisher.publish(SaleCreatedEvent(
          saleId: parsedSaleId,
          customerId: 0,
          totalAmount: totalAmount,
          saleIdStr: sale.id,
          customerIdStr: customerId,
          paidAmount: finalPaidAmount,
          paymentMethod: paymentMethod,
          occurredAt: DateTime.now(),
        ));

        final elapsed = stopwatch.elapsedMilliseconds;
        await TelemetryService().logEvent('sale_checkout', {
          'sale_id': sale.id,
          'items_count': items.length,
          'total_amount': totalAmount,
          'time_ms': elapsed,
          'status': 'success',
        });

        // Verify ledger invariant post-condition
        if (_dataIntegrityService != null) {
          await _dataIntegrityService!.verifyLedgerInvariant(customerId);
        }

        return completedSale;
      });
    } catch (e) {
      _eventPublisher.publish(SaleFailedEvent(
        customerId: customerId.hashCode,
        reason: e.toString(),
        occurredAt: DateTime.now(),
      ));
      final elapsed = stopwatch.elapsedMilliseconds;
      await TelemetryService().logEvent('sale_checkout', {
        'items_count': items.length,
        'total_amount': totalAmount,
        'time_ms': elapsed,
        'status': 'failed',
        'error': e.toString(),
      });
      rethrow;
    }
  }

  /// Record payment for existing sale
  Future<void> recordPayment({
    required String saleId,
    required double amount,
    required String method,
  }) async {
    final sale = await _saleRepository.findById(saleId);
    if (sale == null) {
      throw SaleNotFoundException('Sale $saleId not found');
    }

    final newPaidAmount = sale.paidAmount + amount;
    final remainingDebt = (sale.totalAmount - newPaidAmount).abs();

    if (kIsWeb) {
      // Update sale record
      await _saleRepository.update(
        SaleEntity(
          id: sale.id,
          customerId: sale.customerId,
          totalAmount: sale.totalAmount,
          paidAmount: newPaidAmount,
          paymentMethod: method,
          status: remainingDebt == 0 ? 'completed' : 'partial',
          createdAt: sale.createdAt,
          items: sale.items,
        ),
      );

      // Delegate partial payment transactions
      await _paymentService.recordPartialPayment(
        saleId: saleId,
        customerId: sale.customerId,
        amount: amount,
        method: method,
        currentPaidAmount: sale.paidAmount,
        totalAmount: sale.totalAmount,
      );

      if (_dataIntegrityService != null) {
        await _dataIntegrityService!.verifyLedgerInvariant(sale.customerId);
      }
      return;
    }

    await _transactionRunner.transaction(() async {
      // Update sale record
      await _saleRepository.update(
        SaleEntity(
          id: sale.id,
          customerId: sale.customerId,
          totalAmount: sale.totalAmount,
          paidAmount: newPaidAmount,
          paymentMethod: method,
          status: remainingDebt == 0 ? 'completed' : 'partial',
          createdAt: sale.createdAt,
          items: sale.items,
        ),
      );

      // Delegate partial payment transactions
      await _paymentService.recordPartialPayment(
        saleId: saleId,
        customerId: sale.customerId,
        amount: amount,
        method: method,
        currentPaidAmount: sale.paidAmount,
        totalAmount: sale.totalAmount,
      );

      if (_dataIntegrityService != null) {
        await _dataIntegrityService!.verifyLedgerInvariant(sale.customerId);
      }
    });
  }

  /// Cancel a sale — restores stock and reverses customer debt
  Future<void> cancelSale(String saleId) async {
    final sale = await _saleRepository.findById(saleId);
    if (sale == null) throw SaleNotFoundException('Sale $saleId not found');
    if (sale.status == 'cancelled') return;

    if (kIsWeb) {
      // Update sale status to cancelled
      await _saleRepository.update(SaleEntity(
        id: sale.id,
        customerId: sale.customerId,
        totalAmount: sale.totalAmount,
        paidAmount: sale.paidAmount,
        paymentMethod: sale.paymentMethod,
        status: 'cancelled',
        createdAt: sale.createdAt,
        items: sale.items,
      ));

      // Convert items back to SaleItemInput list
      final restoredItems = <SaleItemInput>[];
      for (final item in sale.items) {
        final productId = item['product_id'] as String?;
        final qty = item['quantity'] as int? ?? 0;
        final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        if (productId != null && qty > 0) {
          restoredItems.add(SaleItemInput(
            productId: productId,
            quantity: qty,
            unitPrice: price,
          ));
        }
      }

      // 1. Restore stock
      await _inventoryService.increaseStock(restoredItems);

      // 2. Reverse customer balance debt and create cancellation ledger entry
      await _paymentService.processSaleCancellation(
        saleId: saleId,
        customerId: sale.customerId,
        totalAmount: sale.totalAmount,
        paidAmount: sale.paidAmount,
      );

      if (_dataIntegrityService != null) {
        await _dataIntegrityService!.verifyLedgerInvariant(sale.customerId);
      }
      return;
    }

    await _transactionRunner.transaction(() async {
      // Update sale status to cancelled
      await _saleRepository.update(SaleEntity(
        id: sale.id,
        customerId: sale.customerId,
        totalAmount: sale.totalAmount,
        paidAmount: sale.paidAmount,
        paymentMethod: sale.paymentMethod,
        status: 'cancelled',
        createdAt: sale.createdAt,
        items: sale.items,
      ));

      // Convert items back to SaleItemInput list
      final restoredItems = <SaleItemInput>[];
      for (final item in sale.items) {
        final productId = item['product_id'] as String?;
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        if (productId != null && qty > 0) {
          restoredItems.add(SaleItemInput(
            productId: productId,
            quantity: qty,
            unitPrice: price,
          ));
        }
      }

      // 1. Restore stock
      await _inventoryService.increaseStock(restoredItems);

      // 2. Reverse customer balance debt and create cancellation ledger entry
      await _paymentService.processSaleCancellation(
        saleId: saleId,
        customerId: sale.customerId,
        totalAmount: sale.totalAmount,
        paidAmount: sale.paidAmount,
      );

      if (_dataIntegrityService != null) {
        await _dataIntegrityService!.verifyLedgerInvariant(sale.customerId);
      }
    });
  }

  /// Return items from a completed sale
  Future<void> returnItems({
    required String saleId,
    required List<SaleItemInput> itemsToReturn,
    required String refundMethod, // 'balance' | 'cash'
  }) async {
    _checkSecurityGate();
    final sale = await _saleRepository.findById(saleId);
    if (sale == null) throw SaleNotFoundException('Sale $saleId not found');

    double refundTotal = 0;
    for (final item in itemsToReturn) {
      refundTotal += item.quantity * item.unitPrice;
    }

    final updatedItems = <Map<String, dynamic>>[];
    for (final item in sale.items) {
      final productId = item['product_id'] as String;
      final originalQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final price = (item['unit_price'] ?? item['unitPrice'] as num?)?.toDouble() ?? 0.0;
      
      final returnMatchIndex = itemsToReturn.indexWhere((ri) => ri.productId == productId);
      if (returnMatchIndex != -1) {
        final returnedQty = itemsToReturn[returnMatchIndex].quantity;
        final newQty = originalQty - returnedQty;
        if (newQty > 0) {
          updatedItems.add({
            ...item,
            'quantity': newQty,
            'subtotal': newQty * price,
          });
        }
      } else {
        updatedItems.add(item);
      }
    }

    final double newTotalAmount = updatedItems.fold<double>(
      0.0,
      (sum, item) => sum + (((item['quantity'] as num).toDouble()) * ((item['unit_price'] ?? item['unitPrice'] ?? 0.0) as num).toDouble()),
    );

    double newPaidAmount = sale.paidAmount;
    if (sale.paymentMethod != 'debt') {
      newPaidAmount = sale.paidAmount - refundTotal;
      if (newPaidAmount < 0) newPaidAmount = 0.0;
    }

    final String newStatus = updatedItems.isEmpty ? 'cancelled' : sale.status;

    final updatedSale = SaleEntity(
      id: sale.id,
      customerId: sale.customerId,
      totalAmount: newTotalAmount,
      paidAmount: newPaidAmount,
      paymentMethod: sale.paymentMethod,
      status: newStatus,
      createdAt: sale.createdAt,
      items: updatedItems,
      idempotencyKey: sale.idempotencyKey,
      isSynced: sale.isSynced,
    );

    if (kIsWeb) {
      // 1. Restore stock levels
      await _inventoryService.increaseStock(itemsToReturn);

      // 2. Process refund ledger records and balance updates
      await _paymentService.processRefund(
        saleId: saleId,
        customerId: sale.customerId,
        refundTotal: refundTotal,
        refundMethod: refundMethod,
      );

      // 3. Update sale and items
      await _saleRepository.update(updatedSale);

      if (_dataIntegrityService != null) {
        await _dataIntegrityService!.verifyLedgerInvariant(sale.customerId);
      }
      return;
    }

    await _transactionRunner.transaction(() async {
      // 1. Restore stock levels
      await _inventoryService.increaseStock(itemsToReturn);

      // 2. Process refund ledger records and balance updates
      await _paymentService.processRefund(
        saleId: saleId,
        customerId: sale.customerId,
        refundTotal: refundTotal,
        refundMethod: refundMethod,
      );

      // 3. Update sale and items
      await _saleRepository.update(updatedSale);

      if (_dataIntegrityService != null) {
        await _dataIntegrityService!.verifyLedgerInvariant(sale.customerId);
      }
    });
  }

  /// Get today's sales summary
  Future<SalesSummary> getTodaysSummary() async {
    final sales = await _saleRepository.getTodaySales();
    final revenue = await _saleRepository.getTodayRevenue();
    final itemsSold = await _saleRepository.getTotalItemsSold();

    return SalesSummary(
      totalSales: sales.length,
      totalRevenue: revenue,
      totalItemsSold: itemsSold,
      averageOrderValue: sales.isEmpty ? 0 : revenue / sales.length,
    );
  }
}

/// Sales summary DTO
class SalesSummary {
  final int totalSales;
  final double totalRevenue;
  final int totalItemsSold;
  final double averageOrderValue;

  SalesSummary({
    required this.totalSales,
    required this.totalRevenue,
    required this.totalItemsSold,
    required this.averageOrderValue,
  });
}

/// Custom Exceptions (moved from previous version or delegated)
class SaleEmptyException implements Exception {
  final String message;
  SaleEmptyException(this.message);

  @override
  String toString() => message;
}

class SaleNotFoundException implements Exception {
  final String message;
  SaleNotFoundException(this.message);

  @override
  String toString() => message;
}

/// Additional Events (for SalesService)
class SaleFailedEvent extends DomainEvent {
  final int customerId;
  final String reason;

  SaleFailedEvent({
    required this.customerId,
    required this.reason,
    super.occurredAt,
    super.metadata,
  }) : super(
    type: EventType.saleCancelled,
    aggregateType: 'Sale',
  );
}

/// Dummy transaction runner for fallback contexts where transactions are not supported.
class _DummyTransactionRunner implements IDbTransactionRunner {
  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    return await action();
  }
}
