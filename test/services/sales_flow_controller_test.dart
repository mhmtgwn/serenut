import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/infrastructure/services/cart_persistence_service.dart';

void main() {
  group('SalesFlowNotifier State Registry Tests', () {
    late SalesFlowNotifier notifier;
    late CartPersistenceService persistenceService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      persistenceService = CartPersistenceService(prefs);
      notifier = SalesFlowNotifier(persistenceService);
    });

    test('Initial state parameters check', () {
      expect(notifier.state.cartQuantities, isEmpty);
      expect(notifier.state.cartProducts, isEmpty);
      expect(notifier.state.selectedCustomer, isNull);
      expect(notifier.state.total, 0.0);
    });

    test('Cart state increment and pricing calculations integrity', () {
      final product = ProductEntity(
        id: 'test-prod-1',
        name: 'Organic Milk',
        description: 'Fresh organic milk',
        price: 45.0,
        quantity: 5,
        category: 'Dairy',
      );

      notifier.addToCart(product);
      expect(notifier.state.cartQuantities['test-prod-1'], 1);
      expect(notifier.state.total, 45.0);
      expect(
          notifier.state.status,
          SalesFlowStatus
              .paymentPending); // auto transitions to paymentPending since cart is not empty

      notifier.addToCart(product);
      expect(notifier.state.cartQuantities['test-prod-1'], 2);
      expect(notifier.state.total, 90.0);
    });

    test('Selected customer assignment and payment split configuration', () {
      final customer = CustomerEntity(
        id: 'cust-1',
        name: 'John Doe',
        email: 'john@example.com',
        phone: '12345678',
        balance: 100.0,
        createdAt: DateTime.now(),
      );

      notifier.selectCustomer(customer);
      expect(notifier.state.selectedCustomer?.id, 'cust-1');
      expect(notifier.state.status, SalesFlowStatus.customerSelected);

      // Test payment method changes
      final product = ProductEntity(
          id: 'p1',
          name: 'Bread',
          description: '',
          price: 10.0,
          quantity: 10,
          category: 'Bakery');
      notifier.addToCart(product);

      notifier.setPaymentMethod('karma');
      expect(notifier.state.paymentMethod, 'karma');
      expect(notifier.state.paidAmount, 5.0); // Split check: total / 2
    });

    test('FSM transition restrictions safety validation', () {
      // Transition table blocks finalizing payment without adding items or selection first
      expect(() => notifier.setSubmitting(true), throwsA(isA<StateError>()));
    });

    test('Financial Integrity - Idempotency Key Generation and Re-use on Retry',
        () async {
      final product = ProductEntity(
        id: 'test-prod-1',
        name: 'Organic Milk',
        description: 'Fresh organic milk',
        price: 45.0,
        quantity: 5,
        category: 'Dairy',
      );

      // 1. Initial key should be empty
      expect(notifier.state.idempotencyKey, isEmpty);

      // 2. Entering paymentPending (by adding a product) generates the key
      notifier.addToCart(product);
      expect(notifier.state.status, SalesFlowStatus.paymentPending);
      final firstKey = notifier.state.idempotencyKey;
      expect(firstKey, isNotEmpty);

      // 3. Move to processing
      notifier.setSubmitting(true);
      expect(notifier.state.status, SalesFlowStatus.processing);
      expect(notifier.state.idempotencyKey, equals(firstKey));

      // 4. Fail the payment
      notifier.failPayment();
      expect(notifier.state.status, SalesFlowStatus.failed);
      expect(notifier.state.idempotencyKey, equals(firstKey));

      // 5. Retry payment (FSM: failed -> proceedToPayment -> paymentPending)
      notifier.retryPayment();
      expect(notifier.state.status, SalesFlowStatus.paymentPending);
      expect(notifier.state.idempotencyKey, equals(firstKey));

      // 6. Resetting the cart/state clears the key
      notifier.reset();
      expect(notifier.state.status, SalesFlowStatus.idle);
      expect(notifier.state.idempotencyKey, isEmpty);
    });

    test('FSM transition from failed state using removeProduct', () {
      final product = ProductEntity(
          id: 'p1',
          name: 'Bread',
          description: '',
          price: 10.0,
          quantity: 10,
          category: 'Bakery');
      notifier.addToCart(product);
      notifier.addToCart(product);

      notifier.setSubmitting(true);
      expect(notifier.state.status, SalesFlowStatus.processing);

      notifier.failPayment();
      expect(notifier.state.status, SalesFlowStatus.failed);

      notifier.removeFromCart(product);
      expect(notifier.state.status, SalesFlowStatus.productsAdded);
    });
  });
}
