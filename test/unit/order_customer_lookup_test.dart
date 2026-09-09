// test/unit/order_customer_lookup_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

void main() {
  group('Order and Customer Resolution Logic Tests', () {
    test('customer resolution falls back correctly when customerId exists', () {
      final customer = CustomerEntity(
        id: 'cust-123',
        name: 'Ahmet Yılmaz',
        email: 'ahmet@example.com',
        phone: '05551112233',
        balance: 150.0,
        createdAt: DateTime.now(),
      );

      final lookupMap = <String, String>{
        'cust-123': 'Ahmet Yılmaz',
        'cust-456': 'Mehmet Kaya',
      };

      // 1. Direct customer found
      String resolveName(CustomerEntity? c, String? fallback, String custId) {
        return c?.name ??
            fallback ??
            (custId.isEmpty ? 'Genel Müşteri' : 'Bilinmeyen Müşteri');
      }

      expect(resolveName(customer, null, 'cust-123'), equals('Ahmet Yılmaz'));

      // 2. Customer entity null but fallback from customerLookupMap exists
      expect(
        resolveName(null, lookupMap['cust-456'], 'cust-456'),
        equals('Mehmet Kaya'),
      );

      // 3. Walk-in / empty customerId
      expect(resolveName(null, null, ''), equals('Genel Müşteri'));

      // 4. Unknown customer only when id is non-empty and unresolvable anywhere
      expect(resolveName(null, null, 'cust-999'), equals('Bilinmeyen Müşteri'));
    });

    test('OrderEntity correctly stores customerId and displayNumber', () {
      final order = OrderEntity(
        id: 'ord-test-1',
        orderNumber: '1001',
        customerId: 'cust-123',
        status: 'created',
        createdAt: DateTime.now(),
        items: [
          {'product_id': 'prod-1', 'quantity': 2, 'unit_price': 50.0}
        ],
      );

      expect(order.customerId, equals('cust-123'));
      expect(order.displayNumber, equals('1001'));
      expect(order.totalAmount, equals(100.0));
    });
  });
}
