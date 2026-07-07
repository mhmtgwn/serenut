// lib/infrastructure/services/cart_persistence_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

class CartPersistenceService {
  static const String _kCartQuantitiesKey = 'serenut_cart_quantities';
  static const String _kCartProductsKey = 'serenut_cart_products';
  static const String _kSelectedCustomerKey = 'serenut_cart_customer';
  static const String _kPaymentMethodKey = 'serenut_cart_payment_method';
  static const String _kPaidAmountKey = 'serenut_cart_paid_amount';
  static const String _kFsmStatusKey = 'serenut_cart_fsm_status';
  static const String _kIdempotencyKeyKey = 'serenut_cart_idempotency_key';

  final SharedPreferences _prefs;

  CartPersistenceService(this._prefs);

  Future<void> saveCart({
    required Map<String, int> cartQuantities,
    required Map<String, ProductEntity> cartProducts,
    required CustomerEntity? selectedCustomer,
    required String paymentMethod,
    required double paidAmount,
    required String fsmStatus,
    required String idempotencyKey,
  }) async {
    final quantitiesJson = jsonEncode(cartQuantities);
    final productsMap = cartProducts.map((key, value) => MapEntry(key, value.toMap()));
    final productsJson = jsonEncode(productsMap);

    await _prefs.setString(_kCartQuantitiesKey, quantitiesJson);
    await _prefs.setString(_kCartProductsKey, productsJson);
    await _prefs.setString(_kPaymentMethodKey, paymentMethod);
    await _prefs.setDouble(_kPaidAmountKey, paidAmount);
    await _prefs.setString(_kFsmStatusKey, fsmStatus);
    await _prefs.setString(_kIdempotencyKeyKey, idempotencyKey);

    if (selectedCustomer != null) {
      await _prefs.setString(_kSelectedCustomerKey, jsonEncode(selectedCustomer.toMap()));
    } else {
      await _prefs.remove(_kSelectedCustomerKey);
    }
  }

  Map<String, dynamic> loadCart() {
    final quantitiesRaw = _prefs.getString(_kCartQuantitiesKey);
    final productsRaw = _prefs.getString(_kCartProductsKey);
    final customerRaw = _prefs.getString(_kSelectedCustomerKey);
    final paymentMethod = _prefs.getString(_kPaymentMethodKey) ?? 'cash';
    final paidAmount = _prefs.getDouble(_kPaidAmountKey) ?? 0.0;
    final fsmStatus = _prefs.getString(_kFsmStatusKey) ?? 'idle';
    final idempotencyKey = _prefs.getString(_kIdempotencyKeyKey) ?? '';

    final Map<String, int> cartQuantities = {};
    if (quantitiesRaw != null) {
      final Map<String, dynamic> decoded = jsonDecode(quantitiesRaw);
      decoded.forEach((key, value) {
        cartQuantities[key] = value as int;
      });
    }

    final Map<String, ProductEntity> cartProducts = {};
    if (productsRaw != null) {
      final Map<String, dynamic> decoded = jsonDecode(productsRaw);
      decoded.forEach((key, value) {
        cartProducts[key] = ProductEntity.fromMap(value as Map<String, dynamic>);
      });
    }

    CustomerEntity? selectedCustomer;
    if (customerRaw != null) {
      selectedCustomer = CustomerEntity.fromMap(jsonDecode(customerRaw));
    }

    return {
      'cartQuantities': cartQuantities,
      'cartProducts': cartProducts,
      'selectedCustomer': selectedCustomer,
      'paymentMethod': paymentMethod,
      'paidAmount': paidAmount,
      'fsmStatus': fsmStatus,
      'idempotencyKey': idempotencyKey,
    };
  }

  Future<void> clearCart() async {
    await _prefs.remove(_kCartQuantitiesKey);
    await _prefs.remove(_kCartProductsKey);
    await _prefs.remove(_kSelectedCustomerKey);
    await _prefs.remove(_kPaymentMethodKey);
    await _prefs.remove(_kPaidAmountKey);
    await _prefs.remove(_kFsmStatusKey);
    await _prefs.remove(_kIdempotencyKeyKey);
  }
}
