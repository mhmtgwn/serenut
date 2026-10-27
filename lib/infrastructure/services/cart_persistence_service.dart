// lib/infrastructure/services/cart_persistence_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

class CartPersistenceService {
  static const String _kCartQuantitiesKey = 'serenut_cart_quantities';
  static const String _kCartProductsKey = 'serenut_cart_products';
  static const String _kSelectedCustomerKey = 'serenut_cart_customer';
  static const String _kPaymentMethodKey = 'serenut_cart_payment_method';
  static const String _kPaidAmountKey = 'serenut_cart_paid_amount';
  static const String _kPaidAmountCentsKey = 'serenut_cart_paid_amount_cents';
  static const String _kDiscountAmountKey = 'serenut_cart_discount_amount';
  static const String _kDiscountAmountCentsKey = 'serenut_cart_discount_amount_cents';
  static const String _kFsmStatusKey = 'serenut_cart_fsm_status';
  static const String _kIdempotencyKeyKey = 'serenut_cart_idempotency_key';
  static const String _kKarmaCashTenderedKey = 'serenut_cart_karma_cash_tendered';
  static const String _kKarmaCashAppliedKey = 'serenut_cart_karma_cash_applied';
  static const String _kKarmaCardKey = 'serenut_cart_karma_card';
  static const String _kKarmaDebtKey = 'serenut_cart_karma_debt';
  static const String _kKarmaChangeKey = 'serenut_cart_karma_change';

  final SharedPreferences _prefs;

  CartPersistenceService(this._prefs);

  Future<void> saveCart({
    required Map<String, int> cartQuantities,
    required Map<String, ProductEntity> cartProducts,
    required CustomerEntity? selectedCustomer,
    required String paymentMethod,
    required double paidAmount,
    double discountAmount = 0.0,
    int? paidAmountCents,
    int? discountAmountCents,
    double karmaCashTendered = 0.0,
    double karmaCashApplied = 0.0,
    double karmaCard = 0.0,
    double karmaDebt = 0.0,
    double karmaChange = 0.0,
    required String fsmStatus,
    required String idempotencyKey,
  }) async {
    final quantitiesJson = jsonEncode(cartQuantities);
    final productsMap =
        cartProducts.map((key, value) => MapEntry(key, value.toMap()));
    final productsJson = jsonEncode(productsMap);

    final resolvedPaidCents = paidAmountCents ?? (paidAmount * 100).round();
    final resolvedDiscountCents =
        discountAmountCents ?? (discountAmount * 100).round();

    await _prefs.setString(_kCartQuantitiesKey, quantitiesJson);
    await _prefs.setString(_kCartProductsKey, productsJson);
    await _prefs.setString(_kPaymentMethodKey, paymentMethod);
    await _prefs.setDouble(_kPaidAmountKey, paidAmount);
    await _prefs.setInt(_kPaidAmountCentsKey, resolvedPaidCents);
    await _prefs.setDouble(_kDiscountAmountKey, discountAmount);
    await _prefs.setInt(_kDiscountAmountCentsKey, resolvedDiscountCents);
    await _prefs.setString(_kFsmStatusKey, fsmStatus);
    await _prefs.setString(_kIdempotencyKeyKey, idempotencyKey);

    if (paymentMethod == 'karma') {
      await _prefs.setDouble(_kKarmaCashTenderedKey, karmaCashTendered);
      await _prefs.setDouble(_kKarmaCashAppliedKey, karmaCashApplied);
      await _prefs.setDouble(_kKarmaCardKey, karmaCard);
      await _prefs.setDouble(_kKarmaDebtKey, karmaDebt);
      await _prefs.setDouble(_kKarmaChangeKey, karmaChange);
    } else {
      await _prefs.remove(_kKarmaCashTenderedKey);
      await _prefs.remove(_kKarmaCashAppliedKey);
      await _prefs.remove(_kKarmaCardKey);
      await _prefs.remove(_kKarmaDebtKey);
      await _prefs.remove(_kKarmaChangeKey);
    }

    if (selectedCustomer != null) {
      await _prefs.setString(
          _kSelectedCustomerKey, jsonEncode(selectedCustomer.toMap()));
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
    final paidAmountCents = _prefs.getInt(_kPaidAmountCentsKey) ??
        (paidAmount * 100).round();
    final discountAmount = _prefs.getDouble(_kDiscountAmountKey) ?? 0.0;
    final discountAmountCents = _prefs.getInt(_kDiscountAmountCentsKey) ??
        (discountAmount * 100).round();
    final fsmStatus = _prefs.getString(_kFsmStatusKey) ?? 'idle';
    final idempotencyKey = _prefs.getString(_kIdempotencyKeyKey) ?? '';
    final karmaCashTendered = _prefs.getDouble(_kKarmaCashTenderedKey) ?? 0.0;
    final karmaCashApplied = _prefs.getDouble(_kKarmaCashAppliedKey) ?? 0.0;
    final karmaCard = _prefs.getDouble(_kKarmaCardKey) ?? 0.0;
    final karmaDebt = _prefs.getDouble(_kKarmaDebtKey) ?? 0.0;
    final karmaChange = _prefs.getDouble(_kKarmaChangeKey) ?? 0.0;

    final Map<String, int> cartQuantities = {};
    if (quantitiesRaw != null) {
      try {
        final decoded = jsonDecode(quantitiesRaw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            int? qty;
            if (value is num) {
              qty = value.toInt();
            } else if (value != null) {
              qty = int.tryParse(value.toString());
            }
            if (qty != null && qty > 0) {
              cartQuantities[key.toString()] = qty;
            }
          });
        }
      } catch (e) {
        debugPrint('⚠️ CartPersistenceService.loadCart failed to decode quantities: $e');
      }
    }

    final Map<String, ProductEntity> cartProducts = {};
    if (productsRaw != null) {
      try {
        final decoded = jsonDecode(productsRaw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (value is Map) {
              try {
                cartProducts[key.toString()] =
                    ProductEntity.fromMap(Map<String, dynamic>.from(value));
              } catch (e) {
                debugPrint('⚠️ CartPersistenceService: Failed to restore product $key: $e');
              }
            }
          });
        }
      } catch (e) {
        debugPrint('⚠️ CartPersistenceService.loadCart failed to decode products: $e');
      }
    }

    CustomerEntity? selectedCustomer;
    if (customerRaw != null) {
      try {
        final decoded = jsonDecode(customerRaw);
        if (decoded is Map) {
          selectedCustomer =
              CustomerEntity.fromMap(Map<String, dynamic>.from(decoded));
        }
      } catch (e) {
        debugPrint('⚠️ CartPersistenceService.loadCart failed to decode customer: $e');
      }
    }

    return {
      'cartQuantities': cartQuantities,
      'cartProducts': cartProducts,
      'selectedCustomer': selectedCustomer,
      'paymentMethod': paymentMethod,
      'paidAmount': paidAmount,
      'paidAmountCents': paidAmountCents,
      'discountAmount': discountAmount,
      'discountAmountCents': discountAmountCents,
      'karmaCashTendered': karmaCashTendered,
      'karmaCashApplied': karmaCashApplied,
      'karmaCard': karmaCard,
      'karmaDebt': karmaDebt,
      'karmaChange': karmaChange,
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
    await _prefs.remove(_kPaidAmountCentsKey);
    await _prefs.remove(_kDiscountAmountKey);
    await _prefs.remove(_kDiscountAmountCentsKey);
    await _prefs.remove(_kFsmStatusKey);
    await _prefs.remove(_kIdempotencyKeyKey);
    await _prefs.remove(_kKarmaCashTenderedKey);
    await _prefs.remove(_kKarmaCashAppliedKey);
    await _prefs.remove(_kKarmaCardKey);
    await _prefs.remove(_kKarmaDebtKey);
    await _prefs.remove(_kKarmaChangeKey);
  }
}
