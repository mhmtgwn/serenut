// core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/core_entities.dart';
import '../../domain/models/money_cents.dart';
import '../../domain/models/rbac_models.dart';
import '../../domain/usecases/checkout_use_case.dart';
import 'core_sales_flow_state.dart';

class CoreSalesFlowNotifier extends StateNotifier<CoreSalesFlowState> {
  final CoreCheckoutUseCase _checkoutUseCase;
  final ActorContext? _defaultActor;

  CoreSalesFlowNotifier(
    this._checkoutUseCase, {
    ActorContext? defaultActor,
  })  : _defaultActor = defaultActor,
        super(const CoreSalesFlowState());

  /// Ürünü sepete ekler veya adedini 1 artırır
  void addProduct(ProductEntity product, {int quantity = 1}) {
    final existingIndex =
        state.items.indexWhere((item) => item.product.id == product.id && !item.isWeighed);

    if (existingIndex >= 0) {
      final existingItem = state.items[existingIndex];
      final updatedList = List<CoreCartItem>.from(state.items);
      updatedList[existingIndex] = existingItem.copyWith(
        quantity: existingItem.quantity + quantity,
      );
      state = state.copyWith(items: updatedList);
    } else {
      final newItem = CoreCartItem(
        product: product,
        quantity: quantity,
        unitPrice: product.price,
        isWeighed: false,
      );
      state = state.copyWith(items: [...state.items, newItem]);
    }
  }

  /// Teraziden gelen tartılı ürünü gramajıyla sepete ekler
  void addWeighedProduct(ProductEntity product, int grams) {
    if (grams <= 0) return;
    final newItem = CoreCartItem(
      product: product,
      quantity: grams,
      unitPrice: product.price,
      isWeighed: true,
    );
    state = state.copyWith(items: [...state.items, newItem]);
  }

  /// Ürünü sepetten tamamen çıkarır
  void removeItem(int index) {
    if (index >= 0 && index < state.items.length) {
      final updated = List<CoreCartItem>.from(state.items)..removeAt(index);
      state = state.copyWith(items: updated);
    }
  }

  /// Ürün adedini günceller
  void updateQuantity(int index, int newQuantity) {
    if (index >= 0 && index < state.items.length) {
      if (newQuantity <= 0) {
        removeItem(index);
        return;
      }
      final updated = List<CoreCartItem>.from(state.items);
      updated[index] = updated[index].copyWith(quantity: newQuantity);
      state = state.copyWith(items: updated);
    }
  }

  /// Cari müşteri seçimi
  void selectCustomer(CustomerEntity? customer) {
    state = state.copyWith(selectedCustomer: () => customer);
  }

  /// Genel sepet iskontosu uygula
  void setGeneralDiscount(MoneyCents discount) {
    state = state.copyWith(generalDiscount: discount);
  }

  /// Parçalı / Karma ödeme ekle (Nakit, Kart vb.)
  void setPaymentSplits(List<PaymentSplitEntity> splits) {
    state = state.copyWith(paymentSplits: splits);
  }

  /// Sepeti tamamen temizle
  void clearCart() {
    state = const CoreSalesFlowState();
  }

  /// Satışı onaylar ve tamamlar (Atomik Use-Case)
  Future<SaleOrderEntity> completeCheckout({
    required String receiptNo,
    required String storeTitle,
    String? storeAddress,
    String? storePhone,
    bool autoPrintReceipt = true,
    bool openCashDrawer = false,
    String? idempotencyKey,
    ActorContext? actor,
  }) async {
    state = state.copyWith(isSubmitting: true, errorMessage: () => null);

    try {
      final result = await _checkoutUseCase.execute(
        CheckoutRequest(
          flowState: state,
          receiptNo: receiptNo,
          storeTitle: storeTitle,
          storeAddress: storeAddress,
          storePhone: storePhone,
          autoPrintReceipt: autoPrintReceipt,
          openCashDrawer: openCashDrawer,
          idempotencyKey: idempotencyKey,
          actor: actor ?? _defaultActor,
        ),
      );

      // Başarılı satış sonrası sepeti sıfırla, son satışı state'e koy
      state = CoreSalesFlowState(lastCompletedSale: result);
      return result;
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: () => e.toString(),
      );
      rethrow;
    }
  }
}
