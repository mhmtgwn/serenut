import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pagination & Scroll Reactivity Tests', () {
    test('ordersLoadingMoreProvider defaults to false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(ordersLoadingMoreProvider), isFalse);
    });

    test('customerLoadingMoreProvider defaults to false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(customerLoadingMoreProvider), isFalse);
    });
  });
}
