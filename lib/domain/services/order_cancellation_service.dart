// lib/domain/services/order_cancellation_service.dart
import 'dart:async';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/inventory_service.dart';
import 'package:serenutos/domain/services/payment_service.dart';
import 'package:serenutos/domain/services/data_integrity_service.dart';
import 'package:serenutos/domain/services/math_engine.dart';

class OrderCancellationService {
  final IOrderRepository _orderRepository;
  final InventoryService _inventoryService;
  final PaymentService _paymentService;
  final IFinancialTransactionRepository _transactionRepository;
  final IDbTransactionRunner _transactionRunner;
  final DataIntegrityService? _dataIntegrityService;

  OrderCancellationService({
    required IOrderRepository orderRepository,
    required InventoryService inventoryService,
    required PaymentService paymentService,
    required IFinancialTransactionRepository transactionRepository,
    required IDbTransactionRunner transactionRunner,
    DataIntegrityService? dataIntegrityService,
  })  : _orderRepository = orderRepository,
        _inventoryService = inventoryService,
        _paymentService = paymentService,
        _transactionRepository = transactionRepository,
        _transactionRunner = transactionRunner,
        _dataIntegrityService = dataIntegrityService;

  /// Cancels an uncompleted order atomically.
  /// 1. Updates state to 'cancelled'.
  /// 2. Restores stock.
  /// 3. Reverses ledger transactions.
  Future<void> cancel({
    required String id,
  }) async {
    await _transactionRunner.transaction(() async {
      late final String customerId;
      late final List<Map<String, dynamic>> items;
      late final double totalAmount;
      late final double paidAmount;

      final order = await _orderRepository.findById(id);
      if (order == null || order.status == 'cancelled') {
        return;
      }
      if (order.status == 'delivered') {
        throw StateError('Teslim edilmiş sipariş iptal edilemez; satış iadesi kullanılmalıdır.');
      }
      customerId = order.customerId;
      items = order.items;
      final transactions =
          await _transactionRepository.getByCustomerId(order.customerId);
      final relatedTransactions = transactions.where(
        (tx) => tx.referenceId == order.id && (tx.type == 'sale' || tx.type == 'payment'),
      );
      final saleTx = relatedTransactions.where((tx) => tx.type == 'sale').firstOrNull;
      totalAmount = saleTx?.amount ?? order.totalAmount;
      final saleDebt = saleTx?.debtAmount ?? (totalAmount - order.discountAmount).clamp(0.0, double.infinity);
      final subsequentPayments = relatedTransactions.where((tx) => tx.type == 'payment' || tx.type == 'collection');
      final subsequentPaid = subsequentPayments.fold<double>(0.0, (sum, tx) => sum + tx.paidAmount);
      final actualOrderDebt = (saleDebt - subsequentPaid).clamp(0.0, double.infinity);
      final actualMoneyPaid = (saleTx?.paidAmount ?? 0.0) + subsequentPaid;
      paidAmount = (totalAmount - actualOrderDebt).clamp(0.0, totalAmount);
      await _orderRepository.updateStatus(id, 'cancelled');

      // 2. Restore stock
      final restoredItems = <SaleItemInput>[];
      for (final item in items) {
        final productId =
            item['product_id'] as String? ?? item['productId'] as String?;
        final double rawQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final price = (item['unit_price'] as num?)?.toDouble() ??
            (item['unitPrice'] as num?)?.toDouble() ??
            0.0;
        if (productId != null && rawQty > 0) {
          restoredItems.add(SaleItemInput(
            productId: productId,
            quantity: rawQty >= 1.0 ? rawQty.round() : 1,
            saleQuantity: rawQty,
            unitPrice: price,
          ));
        }
      }
      if (restoredItems.isNotEmpty) {
        await _inventoryService.increaseStock(restoredItems);
      }

      // 3. Process Ledger Reversal
      await _paymentService.processSaleCancellation(
        saleId: id,
        customerId: customerId,
        totalAmount: totalAmount,
        paidAmount: paidAmount,
      );

      // 3.1 Sipariş için daha önce fiilen ödeme/tahsilat yapılmışsa, para müşterinin cari hesabına alacak olarak iade edilir
      if (actualMoneyPaid > 0.009 && customerId.isNotEmpty) {
        await _paymentService.processRefund(
          saleId: id,
          customerId: customerId,
          refundTotal: actualMoneyPaid,
          refundMethod: 'balance',
        );
      }

      // 4. Verify Ledger invariant
      if (_dataIntegrityService != null) {
        await _dataIntegrityService!.verifyLedgerInvariant(customerId);
      }
    });
  }
}
