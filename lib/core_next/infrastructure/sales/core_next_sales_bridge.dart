// core_next/client_core/lib/infrastructure/sales/core_next_sales_bridge.dart
// SERENUT OS — STAGE 10.12.97
// Core Next Sales & Refund Bridge Builders
// Creates production-ready executors bridging Riverpod SalesController to Core Next domain use cases

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/sales_service.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import '../../domain/models/core_entities.dart' as core;
import '../../domain/models/money_cents.dart';
import '../../domain/models/rbac_models.dart';
import '../../domain/usecases/checkout_use_case.dart';
import '../../domain/usecases/refund_use_case.dart';
import '../repositories/sqlite_product_repository.dart';
import '../../presentation/sales/sales_engine_adapter.dart';
import '../../presentation/sales/core_sales_flow_state.dart';
import '../database/app_database.dart';

class CoreNextSalesBridge {
  CoreNextSalesBridge._();

  static AppRole _mapRole(String? role) {
    return switch (role?.toLowerCase()) {
      'owner' || 'patron' => AppRole.owner,
      'admin' || 'administrator' || 'yonetici' => AppRole.admin,
      'manager' || 'mudur' => AppRole.manager,
      _ => AppRole.cashier,
    };
  }

  static CoreNextSaleExecutor createSaleExecutor({
    required CoreCheckoutUseCase checkoutUseCase,
    required SqliteProductRepository productRepo,
    required SalesEngineAdapter adapter,
    CoreAppDatabase? coreDb,
  }) {
    return ({
      required String customerId,
      required List<SaleItemInput> items,
      required String paymentMethod,
      double? paidAmount,
      double? discountAmount,
      String? idempotencyKey,
      String? cashierName,
      Map<String, dynamic>? terminalMetadata,
      String? userId,
      String? userRole,
      dynamic actor,
    }) async {
      // 1. Müşteriyi Core Next veritabanından yükle (Veresiye ve bakiye işlemleri için)
      core.CustomerEntity? selectedCustomer;
      if (customerId.isNotEmpty && coreDb != null) {
        final custRows = await coreDb.query(
          'customers',
          where: 'id = ?',
          whereArgs: [customerId],
          limit: 1,
        );
        if (custRows.isNotEmpty) {
          selectedCustomer = core.CustomerEntity.fromMap(custRows.first);
        }
      }

      // 2. Ürünleri yükle ve sepeti doldur (Ayrı poşetler ve kalemler korunur)
      final cartItems = <CoreCartItem>[];

      for (final item in items) {
        var prod = await productRepo.getById(item.productId);
        prod ??= core.ProductEntity(
          id: item.productId,
          barcode: item.productId,
          name: item.productName ?? 'Ürün',
          price: MoneyCents((item.unitPrice * 100).round()),
          updatedAt: DateTime.now(),
        );
        final rawQty = item.saleQuantity != 1.0 || item.quantity == 1
            ? item.saleQuantity
            : item.quantity.toDouble();
        final itemQty = prod.isWeighed
            ? (rawQty < 100 ? (rawQty * 1000).round() : rawQty.round())
            : rawQty.round().clamp(1, 1000000000);
        final effectiveUnitPrice = item.unitPrice > 0
            ? MoneyCents((item.unitPrice * 100).round())
            : prod.price;
        cartItems.add(CoreCartItem(
          product: prod,
          quantity: itemQty,
          unitPrice: effectiveUnitPrice,
          isWeighed: prod.isWeighed,
        ));
      }

      // 3. Tutar ve İskonto Hesapları
      final subtotalCents = cartItems.fold<int>(
        0,
        (sum, it) => sum + it.lineTotal.value,
      );
      final discountCents = MoneyCents(((discountAmount ?? 0.0) * 100).round());
      final rawTotal = subtotalCents - discountCents.value;
      final totalCents = rawTotal < 0 ? 0 : rawTotal;

      // 4. Parçalı / Karma Ödeme Ayrıştırması
      final splits = <core.PaymentSplitEntity>[];
      final isDebtMethod = ['on_account', 'veresiye', 'debt', 'credit'].contains(paymentMethod.toLowerCase());

      if (isDebtMethod) {
        // Tamamen veresiye / açık hesap satışı
        splits.add(core.PaymentSplitEntity(
          type: core.PaymentType.onAccount,
          amount: MoneyCents(totalCents),
          referenceNote: selectedCustomer?.name,
        ));
      } else if (terminalMetadata != null && terminalMetadata['splits'] is List) {
        // terminalMetadata içinde açık parçalı ödemeler
        for (final sp in (terminalMetadata['splits'] as List)) {
          if (sp is Map) {
            final tStr = (sp['type'] ?? 'cash').toString().toLowerCase();
            final amt = ((sp['amount'] as num?)?.toDouble() ?? 0.0) * 100;
            final pType = switch (tStr) {
              'card' || 'credit_card' || 'kart' => core.PaymentType.creditCard,
              'on_account' || 'veresiye' || 'debt' => core.PaymentType.onAccount,
              'bank_transfer' || 'havale' => core.PaymentType.bankTransfer,
              _ => core.PaymentType.cash,
            };
            if (amt > 0) {
              splits.add(core.PaymentSplitEntity(
                type: pType,
                amount: MoneyCents(amt.round()),
                referenceNote: sp['note']?.toString(),
              ));
            }
          }
        }
      } else if (terminalMetadata != null &&
          (terminalMetadata['cash_amount'] != null || terminalMetadata['card_amount'] != null)) {
        // POS / Nakit karma tahsilat
        final cashAmt = (((terminalMetadata['cash_amount'] as num?)?.toDouble() ?? 0.0) * 100).round();
        final cardAmt = (((terminalMetadata['card_amount'] as num?)?.toDouble() ?? 0.0) * 100).round();
        if (cashAmt > 0) splits.add(core.PaymentSplitEntity(type: core.PaymentType.cash, amount: MoneyCents(cashAmt)));
        if (cardAmt > 0) splits.add(core.PaymentSplitEntity(type: core.PaymentType.creditCard, amount: MoneyCents(cardAmt)));
      } else {
        // Standart tek yöntemli veya kısmi ödemeli satış
        final core.PaymentType pType = switch (paymentMethod.toLowerCase()) {
          'credit_card' || 'card' || 'kart' => core.PaymentType.creditCard,
          'bank_transfer' || 'havale' || 'eft' => core.PaymentType.bankTransfer,
          _ => core.PaymentType.cash,
        };

        final paidCents = paidAmount != null ? (paidAmount * 100).round() : totalCents;
        if (paidCents > 0) {
          splits.add(core.PaymentSplitEntity(
            type: pType,
            amount: MoneyCents(paidCents.clamp(0, totalCents)),
          ));
        }
        if (paidCents < totalCents) {
          // Kalan bakiye veresiye / açık hesap
          splits.add(core.PaymentSplitEntity(
            type: core.PaymentType.onAccount,
            amount: MoneyCents(totalCents - paidCents),
            referenceNote: selectedCustomer?.name,
          ));
        }
      }

      if (splits.isEmpty) {
        splits.add(core.PaymentSplitEntity(
          type: core.PaymentType.cash,
          amount: MoneyCents(totalCents),
        ));
      }

      // 5. Sepeti müşteri, iskonto ve ödeme parçalarıyla deterministik doldur
      adapter.syncFromCartItems(
        items: cartItems,
        customer: selectedCustomer,
        discount: discountCents,
        paymentSplits: splits,
      );

      // 6. Gerçek Aktör Bağlamı
      final effectiveActor = (actor is ActorContext)
          ? actor
          : ActorContext(
              userId: userId ?? 'usr-cashier-active',
              username: cashierName ?? 'Kasiyer',
              role: _mapRole(userRole),
            );

      final result = await adapter.executeCheckout(
        receiptNo: 'RCP-${DateTime.now().millisecondsSinceEpoch}',
        storeTitle: 'Serenut OS Kasa',
        idempotencyKey: idempotencyKey,
        actor: effectiveActor,
      );

      if (!result.isSuccess) {
        throw StateError(
          'CoreNext satış motoru hatası: Satış başarısız. Sebep: ${result.errorMessage}',
        );
      }

      final saleMap = result.toSaleEntityMap(
        paymentMethod: paymentMethod,
        createdBy: cashierName,
      );
      return SaleEntity.fromMap(saleMap);
    };
  }

  static CoreNextRefundExecutor createRefundExecutor({
    required CoreRefundUseCase refundUseCase,
  }) {
    return ({
      required String saleId,
      required List<SaleItemInput> itemsToReturn,
      required String refundMethod,
      required String reason,
      String? idempotencyKey,
      String? userId,
      String? cashierName,
      String? userRole,
      dynamic actor,
    }) async {
      final refundItems = itemsToReturn
          .map((it) => RefundItemRequest(
                productId: it.productId,
                saleItemId: it.saleItemId,
                quantity: it.quantity.toInt(),
              ))
          .toList();

      final effectiveActor = (actor is ActorContext)
          ? actor
          : ActorContext(
              userId: userId ?? 'usr-manager-active',
              username: cashierName ?? 'Yetkili Kasiyer / Yönetici',
              role: _mapRole(userRole ?? 'manager'),
            );

      final normalizedMethod = refundMethod.trim().toLowerCase();
      final allowManual = normalizedMethod == 'cash' ||
          normalizedMethod == 'balance' ||
          normalizedMethod == 'credit';

      final request = RefundRequest(
        originalSaleId: saleId,
        items: refundItems,
        reason: reason.trim().isNotEmpty ? reason.trim() : 'Müşteri İadesi',
        idempotencyKey: idempotencyKey,
        actor: effectiveActor,
        allowManualRefundToCashOrBalance: allowManual,
      );

      await refundUseCase.execute(request);
    };
  }
}
