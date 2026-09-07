// test/unit/orders_controller_pagination_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';

class MockOrderRepository implements IOrderRepository {
  final List<OrderEntity> _allOrders;

  MockOrderRepository(this._allOrders);

  @override
  Future<List<OrderEntity>> findFiltered({
    String? searchQuery,
    String? status,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool overdueOnly = false,
    int limit = 25,
    int offset = 0,
  }) async {
    await Future.delayed(const Duration(milliseconds: 10));
    if (offset >= _allOrders.length) return [];
    return _allOrders.skip(offset).take(limit).toList();
  }

  @override
  Future<Map<String, int>> getStatusCounts({
    String? searchQuery,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool overdueOnly = false,
  }) async =>
      {'all': _allOrders.length};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('OrdersController paginates correctly with deduplication and guards',
      () async {
    // 60 mock orders
    final List<OrderEntity> mockOrders = List.generate(
      60,
      (i) => OrderEntity(
        id: 'ord-$i',
        orderNumber: 'SP-${1000 + i}',
        customerId: 'cust-1',
        status: 'created',
        createdAt: DateTime.now().subtract(Duration(minutes: i)),
        items: const [],
      ),
    );

    final mockRepo = MockOrderRepository(mockOrders);

    final container = ProviderContainer(
      overrides: [
        orderRepositoryProvider.overrideWith((ref) async => mockRepo),
      ],
    );

    // Initial page load (0..25)
    final initialList = await container.read(ordersControllerProvider.future);
    expect(initialList.length, equals(25));
    expect(initialList.first.id, equals('ord-0'));
    expect(initialList.last.id, equals('ord-24'));

    final notifier = container.read(ordersControllerProvider.notifier);
    expect(notifier.hasMore, isTrue);

    // Load second page (25..50)
    await notifier.loadNextPage();
    final page2List = container.read(ordersControllerProvider).value!;
    expect(page2List.length, equals(50));
    expect(page2List[25].id, equals('ord-25'));
    expect(page2List.last.id, equals('ord-49'));
    expect(notifier.hasMore, isTrue);

    // Load third page (50..60) -> 10 items remaining (< 25)
    await notifier.loadNextPage();
    final page3List = container.read(ordersControllerProvider).value!;
    expect(page3List.length, equals(60));
    expect(page3List.last.id, equals('ord-59'));
    expect(notifier.hasMore, isFalse);

    // Fourth load should be a no-op since hasMore is false
    await notifier.loadNextPage();
    final page4List = container.read(ordersControllerProvider).value!;
    expect(page4List.length, equals(60));

    container.dispose();
  });
}
