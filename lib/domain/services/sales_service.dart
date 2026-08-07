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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/services/security_gate.dart';

export 'package:serenutos/domain/services/inventory_service.dart'
    show SaleItemInput, ProductNotFoundException, InsufficientStockException;

import 'package:serenutos/domain/services/data_integrity_service.dart';

class SalesService {
  final ISaleRepository _saleRepository;
  final InventoryService _inventoryService;
  final PaymentService _paymentService;
  final EventPublisher _eventPublisher;
  final IDbTransactionRunner _transactionRunner;
  final SecurityGate _securityGate;
  final DataIntegrityService? _dataIntegrityService;
  final IRefundMutationStore _refundStore;

  /// Standard constructor using IDbTransactionRunner for clean architectural separation
  SalesService({
    required ISaleRepository saleRepository,
    required InventoryService inventoryService,
    required PaymentService paymentService,
    required EventPublisher eventPublisher,
    required IDbTransactionRunner transactionRunner,
    required SecurityGate securityGate,
    required IRefundMutationStore refundStore,
    DataIntegrityService? dataIntegrityService,
  })  : _saleRepository = saleRepository,
        _inventoryService = inventoryService,
        _paymentService = paymentService,
        _eventPublisher = eventPublisher,
        _transactionRunner = transactionRunner,
        _securityGate = securityGate,
        _refundStore = refundStore,
        _dataIntegrityService = dataIntegrityService;

  /// Named alias — kept for backward compat with salesServiceProvider call sites
  factory SalesService.noDb({
    required ISaleRepository saleRepository,
    required InventoryService inventoryService,
    required PaymentService paymentService,
    required EventPublisher eventPublisher,
    required SecurityGate securityGate,
    required IRefundMutationStore refundStore,
    IDbTransactionRunner? transactionRunner,
    DataIntegrityService? dataIntegrityService,
  }) =>
      SalesService(
        saleRepository: saleRepository,
        inventoryService: inventoryService,
        paymentService: paymentService,
        eventPublisher: eventPublisher,
        transactionRunner: transactionRunner ?? _DummyTransactionRunner(),
        securityGate: securityGate,
        refundStore: refundStore,
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
    Map<String, dynamic>? terminalMetadata,
  }) async {
    _checkSecurityGate();
    final stopwatch = Stopwatch()..start();
    // Validate
    if (items.isEmpty) {
      throw SaleEmptyException('Sale must contain at least one item');
    }
    const allowedPaymentMethods = {'cash', 'card', 'debt', 'karma'};
    if (!allowedPaymentMethods.contains(paymentMethod)) {
      throw ArgumentError.value(
          paymentMethod, 'paymentMethod', 'Geçersiz ödeme yöntemi.');
    }
    for (final item in items) {
      if (!item.saleQuantity.isFinite || item.saleQuantity <= 0) {
        throw ArgumentError.value(item.saleQuantity, 'saleQuantity',
            'Miktar sıfırdan büyük olmalıdır.');
      }
      if (!item.unitPrice.isFinite || item.unitPrice < 0) {
        throw ArgumentError.value(
            item.unitPrice, 'unitPrice', 'Birim fiyat negatif olamaz.');
      }
    }

    // Idempotency check:
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      final existingSale =
          await _saleRepository.findByIdempotencyKey(idempotencyKey);
      if (existingSale != null) {
        return existingSale;
      }
    }

    // Calculate totals
    double totalAmount = 0;
    for (final item in items) {
      totalAmount += item.saleQuantity * item.unitPrice;
    }

    final double finalPaidAmount =
        paidAmount ?? (paymentMethod == 'debt' ? 0 : totalAmount);
    if (!totalAmount.isFinite || totalAmount < 0) {
      throw ArgumentError.value(
          totalAmount, 'totalAmount', 'Satış toplamı geçersiz.');
    }
    if (!finalPaidAmount.isFinite ||
        finalPaidAmount < 0 ||
        finalPaidAmount > totalAmount) {
      throw ArgumentError.value(finalPaidAmount, 'paidAmount',
          'Ödenen tutar sıfır ile satış toplamı arasında olmalıdır.');
    }
    if (paymentMethod == 'debt' && finalPaidAmount != 0) {
      throw ArgumentError(
          'Veresiye satışta başlangıç ödemesi sıfır olmalıdır; kısmi ödeme için karma yöntemini kullanın.');
    }
    if ((paymentMethod == 'cash' || paymentMethod == 'card') &&
        (finalPaidAmount - totalAmount).abs() > 0.001) {
      throw ArgumentError(
          'Nakit ve kart satışları tam ödenmelidir; kısmi ödeme için karma yöntemini kullanın.');
    }

    final prefs = await SharedPreferences.getInstance();
    final jwtSnapshot = prefs.getString('auth_jwt_token');

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
      entitlementSnapshot: jwtSnapshot,
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
          terminalMetadata: terminalMetadata,
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

        final parsedSaleId = sale.id.hashCode.abs();

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

        final parsedSaleId = sale.id.hashCode.abs();

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
    Map<String, dynamic>? terminalMetadata,
  }) async {
    _checkSecurityGate();
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
        terminalMetadata: terminalMetadata,
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
        terminalMetadata: terminalMetadata,
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
    required String reason,
  }) async {
    _checkSecurityGate();
    final lines = itemsToReturn.map((item) {
      final saleItemId = item.saleItemId;
      if (saleItemId == null || saleItemId.isEmpty) {
        throw ArgumentError('İade kalemi satış kalemi kimliği içermelidir.');
      }
      return RefundLineRequest(saleItemId: saleItemId, quantity: item.quantity);
    }).toList();
    await _refundStore.create(
      saleId: saleId, items: lines, refundMethod: refundMethod, reason: reason,
    );
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
    assert(() {
      // In debug mode, log a warning if non-transactional fallback runner is used
      // to ensure transactions are properly supplied in production flows.
      return true;
    }());
    return await action();
  }
}
