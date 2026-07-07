// lib/presentation/controllers/sales_flow_controller.dart
// Serenut POS — Sales Flow FSM Controller
// Revized: 22 Jun 2026

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/services/cart_persistence_service.dart';
import 'package:serenutos/infrastructure/services/financial_integrity_service.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Must override sharedPreferencesProvider in ProviderScope');
});

final cartPersistenceServiceProvider = Provider<CartPersistenceService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return CartPersistenceService(prefs);
});

final auditLoggerProvider = Provider<AuditLogger>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AuditLogger(prefs);
});

final syncQueueProvider = Provider<OperationQueueService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return OperationQueueService(prefs);
});

final reconciliationProvider = Provider<PaymentReconciliationService>((ref) {
  final logger = ref.watch(auditLoggerProvider);
  return PaymentReconciliationService(logger);
});

enum SalesFlowStatus {
  idle,
  customerSelected,
  productsAdded,
  paymentPending,
  processing,
  completed,
  failed,
}

enum SalesFlowEvent {
  selectCustomer,
  deselectCustomer,
  addProduct,
  removeProduct,
  clearCart,
  proceedToPayment,
  submitPayment,
  completePayment,
  failPayment,
  reset,
  restoreSession,
}

class SalesFlowState {
  final SalesFlowStatus status;
  final Map<String, int> cartQuantities; // productId -> quantity
  final Map<String, ProductEntity> cartProducts; // productId -> ProductEntity
  final CustomerEntity? selectedCustomer;
  final String paymentMethod; // 'cash', 'card', 'debt', 'karma'
  final double paidAmount;
  final bool isSubmitting;
  final String idempotencyKey;

  const SalesFlowState({
    this.status = SalesFlowStatus.idle,
    this.cartQuantities = const {},
    this.cartProducts = const {},
    this.selectedCustomer,
    this.paymentMethod = 'cash',
    this.paidAmount = 0.0,
    this.isSubmitting = false,
    this.idempotencyKey = '',
  });

  double get total {
    double sum = 0;
    cartQuantities.forEach((id, qty) {
      final prod = cartProducts[id];
      if (prod != null) {
        sum += prod.price * qty;
      }
    });
    return sum;
  }

  SalesFlowState copyWith({
    SalesFlowStatus? status,
    Map<String, int>? cartQuantities,
    Map<String, ProductEntity>? cartProducts,
    CustomerEntity? Function()? selectedCustomer,
    String? paymentMethod,
    double? paidAmount,
    bool? isSubmitting,
    String? idempotencyKey,
  }) {
    return SalesFlowState(
      status: status ?? this.status,
      cartQuantities: cartQuantities ?? this.cartQuantities,
      cartProducts: cartProducts ?? this.cartProducts,
      selectedCustomer: selectedCustomer != null ? selectedCustomer() : this.selectedCustomer,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paidAmount: paidAmount ?? this.paidAmount,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    );
  }
}

class SalesFlowNotifier extends StateNotifier<SalesFlowState> {
  final CartPersistenceService? _persistenceService;
  final AuditLogger? _auditLogger;

  SalesFlowNotifier([this._persistenceService, this._auditLogger]) : super(const SalesFlowState());

  // ── Transition Table Definition ──────────────────────────────────────────────
  static const Map<SalesFlowStatus, Map<SalesFlowEvent, SalesFlowStatus>> _transitions = {
    SalesFlowStatus.idle: {
      SalesFlowEvent.selectCustomer: SalesFlowStatus.customerSelected,
      SalesFlowEvent.addProduct: SalesFlowStatus.productsAdded,
      SalesFlowEvent.reset: SalesFlowStatus.idle,
      SalesFlowEvent.restoreSession: SalesFlowStatus.paymentPending,
    },
    SalesFlowStatus.customerSelected: {
      SalesFlowEvent.deselectCustomer: SalesFlowStatus.idle,
      SalesFlowEvent.selectCustomer: SalesFlowStatus.customerSelected,
      SalesFlowEvent.addProduct: SalesFlowStatus.productsAdded,
      SalesFlowEvent.reset: SalesFlowStatus.idle,
    },
    SalesFlowStatus.productsAdded: {
      SalesFlowEvent.selectCustomer: SalesFlowStatus.productsAdded,
      SalesFlowEvent.deselectCustomer: SalesFlowStatus.productsAdded,
      SalesFlowEvent.addProduct: SalesFlowStatus.productsAdded,
      SalesFlowEvent.removeProduct: SalesFlowStatus.productsAdded,
      SalesFlowEvent.clearCart: SalesFlowStatus.idle,
      SalesFlowEvent.proceedToPayment: SalesFlowStatus.paymentPending,
      SalesFlowEvent.reset: SalesFlowStatus.idle,
    },
    SalesFlowStatus.paymentPending: {
      SalesFlowEvent.selectCustomer: SalesFlowStatus.paymentPending,
      SalesFlowEvent.deselectCustomer: SalesFlowStatus.paymentPending,
      SalesFlowEvent.addProduct: SalesFlowStatus.productsAdded,
      SalesFlowEvent.removeProduct: SalesFlowStatus.productsAdded,
      SalesFlowEvent.clearCart: SalesFlowStatus.idle,
      SalesFlowEvent.submitPayment: SalesFlowStatus.processing,
      SalesFlowEvent.reset: SalesFlowStatus.idle,
    },
    SalesFlowStatus.processing: {
      SalesFlowEvent.completePayment: SalesFlowStatus.completed,
      SalesFlowEvent.failPayment: SalesFlowStatus.failed,
      SalesFlowEvent.reset: SalesFlowStatus.idle,
    },
    SalesFlowStatus.completed: {
      SalesFlowEvent.reset:            SalesFlowStatus.idle,
      // Hızlı yeni satış: completed'dan direkt ilerleyebilir
      SalesFlowEvent.selectCustomer:   SalesFlowStatus.customerSelected,
      SalesFlowEvent.addProduct:       SalesFlowStatus.productsAdded,
      SalesFlowEvent.clearCart:        SalesFlowStatus.idle,
    },
    SalesFlowStatus.failed: {
      SalesFlowEvent.reset:               SalesFlowStatus.idle,
      SalesFlowEvent.proceedToPayment:    SalesFlowStatus.paymentPending,
      SalesFlowEvent.selectCustomer:      SalesFlowStatus.failed,
      SalesFlowEvent.deselectCustomer:    SalesFlowStatus.failed,
      SalesFlowEvent.addProduct:          SalesFlowStatus.productsAdded,
      SalesFlowEvent.clearCart:           SalesFlowStatus.idle,
      SalesFlowEvent.submitPayment:       SalesFlowStatus.processing,
      SalesFlowEvent.removeProduct:       SalesFlowStatus.productsAdded,
    },

  };

  void _dispatch(SalesFlowEvent event) {
    final allowedTransitions = _transitions[state.status];
    if (allowedTransitions == null || !allowedTransitions.containsKey(event)) {
      throw StateError('🔴 FSM TRANSITION FAILURE: Invalid transition from ${state.status} using event $event.');
    }
    
    final before = state.status;
    final after = allowedTransitions[event]!;
    
    String nextKey = state.idempotencyKey;
    if ((after == SalesFlowStatus.paymentPending || after == SalesFlowStatus.processing) && nextKey.isEmpty) {
      nextKey = IdempotencyKeyGenerator.generateKey();
    }
    if (after == SalesFlowStatus.idle || after == SalesFlowStatus.completed) {
      nextKey = '';
    }

    state = state.copyWith(
      status: after,
      idempotencyKey: nextKey,
    );

    _auditLogger?.logAction(
      action: event.name,
      beforeState: before.name,
      afterState: after.name,
      metadata: {
        'idempotencyKey': state.idempotencyKey,
        'paymentMethod': state.paymentMethod,
        'paidAmount': state.paidAmount,
        'total': state.total,
      },
    );

    _persistState();
  }

  void _persistState() {
    _persistenceService?.saveCart(
      cartQuantities: state.cartQuantities,
      cartProducts: state.cartProducts,
      selectedCustomer: state.selectedCustomer,
      paymentMethod: state.paymentMethod,
      paidAmount: state.paidAmount,
      fsmStatus: state.status.name,
      idempotencyKey: state.idempotencyKey,
    );
  }

  void restoreSession() {
    if (_persistenceService == null) return;
    final cached = _persistenceService!.loadCart();
    final quantities = cached['cartQuantities'] as Map<String, int>;
    if (quantities.isNotEmpty) {
      final statusName = cached['fsmStatus'] as String;
      final parsedStatus = SalesFlowStatus.values.firstWhere(
        (s) => s.name == statusName,
        orElse: () => SalesFlowStatus.paymentPending,
      );

      state = SalesFlowState(
        status: parsedStatus == SalesFlowStatus.processing ? SalesFlowStatus.failed : parsedStatus,
        cartQuantities: quantities,
        cartProducts: cached['cartProducts'] as Map<String, ProductEntity>,
        selectedCustomer: cached['selectedCustomer'] as CustomerEntity?,
        paymentMethod: cached['paymentMethod'] as String,
        paidAmount: cached['paidAmount'] as double,
        isSubmitting: false,
        idempotencyKey: cached['idempotencyKey'] as String? ?? '',
      );
    }
  }

  void addToCart(ProductEntity product) {
    final currentQty = state.cartQuantities[product.id] ?? 0;

    _dispatch(SalesFlowEvent.addProduct);

    final newQuantities = Map<String, int>.from(state.cartQuantities);
    final newProducts = Map<String, ProductEntity>.from(state.cartProducts);

    newQuantities[product.id] = currentQty + 1;
    newProducts[product.id] = product;

    double nextPaid = state.paidAmount;
    if (state.paymentMethod == 'cash' || state.paymentMethod == 'card') {
      nextPaid = _calculateTotal(newQuantities, newProducts);
    }

    state = state.copyWith(
      cartQuantities: newQuantities,
      cartProducts: newProducts,
      paidAmount: nextPaid,
    );
    _persistState();

    if (state.status == SalesFlowStatus.productsAdded) {
      _dispatch(SalesFlowEvent.proceedToPayment);
    }
  }

  void removeFromCart(ProductEntity product) {
    final currentQty = state.cartQuantities[product.id] ?? 0;
    if (currentQty == 0) return;

    _dispatch(SalesFlowEvent.removeProduct);

    final newQuantities = Map<String, int>.from(state.cartQuantities);
    final newProducts = Map<String, ProductEntity>.from(state.cartProducts);

    if (currentQty <= 1) {
      newQuantities.remove(product.id);
      newProducts.remove(product.id);
    } else {
      newQuantities[product.id] = currentQty - 1;
    }

    if (newQuantities.isEmpty) {
      _dispatch(SalesFlowEvent.clearCart);
      state = state.copyWith(
        cartQuantities: const {},
        cartProducts: const {},
        paidAmount: 0.0,
      );
      _persistState();
      return;
    }

    double nextPaid = state.paidAmount;
    if (state.paymentMethod == 'cash' || state.paymentMethod == 'card') {
      nextPaid = _calculateTotal(newQuantities, newProducts);
    }

    state = state.copyWith(
      cartQuantities: newQuantities,
      cartProducts: newProducts,
      paidAmount: nextPaid,
    );
    _persistState();
  }

  void deleteFromCart(ProductEntity product) {
    final newQuantities = Map<String, int>.from(state.cartQuantities);
    final newProducts = Map<String, ProductEntity>.from(state.cartProducts);

    newQuantities.remove(product.id);
    newProducts.remove(product.id);

    if (newQuantities.isEmpty) {
      _dispatch(SalesFlowEvent.clearCart);
      state = state.copyWith(
        cartQuantities: const {},
        cartProducts: const {},
        paidAmount: 0.0,
      );
      _persistState();
      return;
    }

    double nextPaid = state.paidAmount;
    if (state.paymentMethod == 'cash' || state.paymentMethod == 'card') {
      nextPaid = _calculateTotal(newQuantities, newProducts);
    }

    state = state.copyWith(
      cartQuantities: newQuantities,
      cartProducts: newProducts,
      paidAmount: nextPaid,
    );
    _persistState();
  }

  void updateQuantity(ProductEntity product, int newQty) {
    if (newQty <= 0) {
      deleteFromCart(product);
      return;
    }

    final newQuantities = Map<String, int>.from(state.cartQuantities);
    final newProducts = Map<String, ProductEntity>.from(state.cartProducts);

    newQuantities[product.id] = newQty;
    newProducts[product.id] = product;

    double nextPaid = state.paidAmount;
    if (state.paymentMethod == 'cash' || state.paymentMethod == 'card') {
      nextPaid = _calculateTotal(newQuantities, newProducts);
    }

    state = state.copyWith(
      cartQuantities: newQuantities,
      cartProducts: newProducts,
      paidAmount: nextPaid,
    );
    _persistState();
  }

  void clearCart() {
    _dispatch(SalesFlowEvent.clearCart);
    state = const SalesFlowState();
    _persistenceService?.clearCart();
  }

  void selectCustomer(CustomerEntity? customer) {
    if (customer == null) {
      _dispatch(SalesFlowEvent.deselectCustomer);
    } else {
      _dispatch(SalesFlowEvent.selectCustomer);
    }
    state = state.copyWith(selectedCustomer: () => customer);
    _persistState();
  }

  void setPaymentMethod(String method) {
    double nextPaid = state.paidAmount;
    final currentTotal = state.total;

    if (method == 'cash' || method == 'card') {
      nextPaid = currentTotal;
    } else if (method == 'debt') {
      nextPaid = 0.0;
    } else if (method == 'karma') {
      nextPaid = currentTotal / 2;
    }

    state = state.copyWith(
      paymentMethod: method,
      paidAmount: nextPaid,
    );
    _persistState();
  }

  void setPaidAmount(double amount) {
    state = state.copyWith(paidAmount: amount);
    _persistState();
  }

  void setSubmitting(bool submitting) {
    if (submitting) {
      _dispatch(SalesFlowEvent.submitPayment);
    } else {
      if (state.status == SalesFlowStatus.processing) {
        _dispatch(SalesFlowEvent.completePayment);
      }
    }
    state = state.copyWith(isSubmitting: submitting);
    _persistState();
  }

  void failPayment() {
    _dispatch(SalesFlowEvent.failPayment);
  }

  void retryPayment() {
    _dispatch(SalesFlowEvent.proceedToPayment);
  }

  void reset() {
    _dispatch(SalesFlowEvent.reset);
    state = const SalesFlowState();
    _persistenceService?.clearCart();
  }

  double _calculateTotal(Map<String, int> quantities, Map<String, ProductEntity> products) {
    double sum = 0;
    quantities.forEach((id, qty) {
      final prod = products[id];
      if (prod != null) {
        sum += prod.price * qty;
      }
    });
    return sum;
  }
}

final salesFlowProvider = StateNotifierProvider<SalesFlowNotifier, SalesFlowState>((ref) {
  final persistence = ref.watch(cartPersistenceServiceProvider);
  final audit = ref.watch(auditLoggerProvider);
  final notifier = SalesFlowNotifier(persistence, audit);
  // Restore any unfinished sessions on build startup initialization
  notifier.restoreSession();
  return notifier;
});
