// lib/presentation/controllers/order_details_controller.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart' show paymentServiceProvider;
import 'package:serenutos/providers/payment_terminal_provider.dart';
import 'package:serenutos/providers/settings_provider.dart';

/// Provider for single order detail (cached or fetched)
final orderDetailProvider = FutureProvider.autoDispose
    .family<OrderEntity?, String>((ref, orderId) async {
  // 1. Önce hafızadaki (OrdersController) güncel siparişi kontrol et (0ms tepki hızı)
  final inMemoryList = ref.watch(ordersControllerProvider).valueOrNull;
  final inMemory = inMemoryList?.where((o) => o.id == orderId).firstOrNull;
  if (inMemory != null && inMemory.items.isNotEmpty) {
    return inMemory;
  }
  final repo = await ref.watch(orderRepositoryProvider.future);
  return repo.findById(orderId);
});

/// Provider for order payment info and customer balance
final orderPaymentInfoProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, orderId) async {
  final repo = await ref.watch(financialTransactionRepositoryProvider.future);
  var txs = await repo.getByReferenceId(orderId);
  FinancialTransactionEntity? saleTx;
  double totalPaid = 0.0;
  for (final t in txs) {
    if (t.referenceId == orderId) {
      if (t.type == 'sale') {
        saleTx = t;
        totalPaid += t.paidAmount;
      } else if (t.type == 'payment' || t.type == 'collection') {
        totalPaid += t.paidAmount;
      }
    }
  }

  String customerId = saleTx?.customerId ?? '';
  if (customerId.isEmpty) {
    try {
      final orderRepo = await ref.watch(orderRepositoryProvider.future);
      final order = await orderRepo.findById(orderId);
      if (order != null && order.customerId.isNotEmpty) {
        customerId = order.customerId;
      }
    } catch (_) {
      // Ignored: fallback or safe default applied
    }
  }

  double? customerBalance;
  if (customerId.isNotEmpty) {
    try {
      final custRepo = await ref.watch(customerRepositoryProvider.future);
      final cust = await custRepo.findById(customerId);
      customerBalance = cust?.balance;
    } catch (_) {
      // Ignored: fallback or safe default applied
    }
  }

  return {
    'saleTx': saleTx,
    'totalPaid': totalPaid,
    'customerBalance': customerBalance,
    'customerId': customerId,
  };
});

/// Actions controller for order details operations (receipt, label print)
class OrderDetailsActions {
  final Ref _ref;

  OrderDetailsActions(this._ref);

  Future<Settings?> _resolveSettings(Settings? initialSettings) async {
    var settings = initialSettings;
    if (settings == null) {
      try {
        final repo = await _ref.read(settingsRepositoryProvider.future);
        settings = await repo.getSettings();
      } catch (_) {
        // Ignored: fallback or safe default applied
      }
    }
    return settings;
  }

  Future<void> printReceipt({
    required OrderEntity order,
    CustomerEntity? customer,
    Settings? currentSettings,
  }) async {
    final settings = await _resolveSettings(currentSettings);
    if (settings == null) {
      throw StateError('Ayarlar yüklenemedi.');
    }

    // Load customer
    CustomerEntity? customerToUse = customer;
    if (customerToUse == null && order.customerId.isNotEmpty) {
      try {
        final custRepo = await _ref.read(customerRepositoryProvider.future);
        customerToUse = await custRepo.findById(order.customerId);
      } catch (_) {
        // Ignored: fallback or safe default applied
      }
    }

    // Resolve product names
    final prodRepo = await _ref.read(productRepositoryProvider.future);
    final receiptItems = await Future.wait(order.items.map((item) async {
      var name = (item['product_name'] ?? item['name'])?.toString();
      final productId = item['product_id']?.toString() ?? '';
      if (name == null || name.isEmpty || name == productId) {
        if (productId.isNotEmpty) {
          final p = await prodRepo.findById(productId);
          if (p != null) name = p.name;
        }
      }
      name ??= 'Ürün';
      return {
        'product_id': productId,
        'product_name': name,
        'barcode': productId,
        'quantity': item['quantity'],
        'unit_price': item['unit_price'],
      };
    }));

    final effectiveCustomer = customerToUse != null && customerToUse.id.isNotEmpty
        ? customerToUse
        : (customer != null && customer.id.isNotEmpty ? customer : null);

    try {
      await _ref.read(printingApplicationServiceProvider).queueOrderReceipt(
            order,
            receiptItems,
            effectiveCustomer,
            settings,
          );
    } catch (queueErr) {
      debugPrint('Queue print error, fallback to direct printer: $queueErr');
      final printerService = _ref.read(printerServiceProvider);
      await printerService.printOrderReceipt(
        order,
        receiptItems,
        effectiveCustomer,
        settings,
      );
    }
  }

  Future<void> printLabel({
    required OrderEntity order,
    CustomerEntity? customer,
    Settings? currentSettings,
  }) async {
    final settings = await _resolveSettings(currentSettings);
    if (settings == null) {
      throw StateError('Ayarlar yüklenemedi.');
    }

    bool hasLabelPrinter = false;
    try {
      hasLabelPrinter = await _ref
          .read(printingRepositoryProvider)
          .hasUsableDevice(PrintDocumentKind.orderLabel);
    } catch (_) {
      // Ignored: fallback or safe default applied
    }
    if (!hasLabelPrinter) {
      hasLabelPrinter = (settings.labelPrinterEnabled &&
          ((settings.labelPrinterName?.isNotEmpty == true) ||
              (settings.labelPrinterIp?.isNotEmpty == true)));
    }
    if (!hasLabelPrinter) {
      throw StateError('Lütfen Ayarlar sayfasından bir etiket yazıcısı tanımlayın.');
    }

    CustomerEntity? customerToUse = customer;
    if (customerToUse == null && order.customerId.isNotEmpty) {
      try {
        final customerRepo = await _ref.read(customerRepositoryProvider.future);
        customerToUse = await customerRepo.findById(order.customerId);
      } catch (_) {
        // Ignored: fallback or safe default applied
      }
    }

    double totalPaid = 0.0;
    try {
      final txRepo = await _ref.read(financialTransactionRepositoryProvider.future);
      var txs = await txRepo.getByReferenceId(order.id);
      if (txs.isEmpty && order.customerId.isNotEmpty) {
        txs = await txRepo.getByCustomerId(order.customerId);
      }
      for (final t in txs) {
        if (t.referenceId == order.id) {
          if (t.type == 'sale' || t.type == 'payment' || t.type == 'collection') {
            totalPaid += t.paidAmount;
          }
        }
      }
    } catch (_) {
      // Ignored: fallback or safe default applied
    }

    final prodRepo = await _ref.read(productRepositoryProvider.future);
    final items = await Future.wait(order.items.map((item) async {
      final normalized = Map<String, dynamic>.from(item);
      final productId = item['product_id']?.toString() ?? '';
      var name = (item['product_name'] ?? item['name'])?.toString();
      if (name == null || name.isEmpty || name == productId) {
        if (productId.isNotEmpty) {
          final p = await prodRepo.findById(productId);
          if (p != null) name = p.name;
        }
      }
      normalized['product_name'] = name ?? productId;
      return normalized;
    }));

    try {
      await _ref.read(printingApplicationServiceProvider).queueOrderLabel(
            order,
            items,
            settings,
            customer: customerToUse,
            paidAmount: totalPaid,
          );
    } catch (queueErr) {
      debugPrint('Queue label print error, fallback to direct printer: $queueErr');
      final printerService = _ref.read(printerServiceProvider);
      await printerService.printOrderLabels(
        order,
        items,
        settings,
        customer: customerToUse,
      );
    }
  }

  Future<AuthorizedCardPayment?> authorizeCardPayment({
    required num amount,
    required String idempotencyKey,
  }) async {
    return _ref.read(physicalCardPaymentServiceProvider).authorize(
      amount: amount.toDouble(),
      idempotencyKey: idempotencyKey,
    );
  }

  Future<void> recordPartialPayment({
    required String saleId,
    required String customerId,
    required num amount,
    required String method,
    required num currentPaidAmount,
    required num totalAmount,
    Map<String, dynamic>? terminalMetadata,
  }) async {
    final paymentService = await _ref.read(paymentServiceProvider.future);
    await paymentService.recordPartialPayment(
      saleId: saleId,
      customerId: customerId,
      amount: amount.toDouble(),
      method: method,
      currentPaidAmount: currentPaidAmount.toDouble(),
      totalAmount: totalAmount.toDouble(),
      terminalMetadata: terminalMetadata,
    );
  }

  Future<void> commitCardPayment(
    AuthorizedCardPayment cardPayment, {
    required String contextId,
  }) async {
    await _ref.read(physicalCardPaymentServiceProvider).markLocalCommit(
      cardPayment,
      contextId: contextId,
    );
  }
}

final orderDetailsActionsProvider = Provider<OrderDetailsActions>((ref) {
  return OrderDetailsActions(ref);
});
