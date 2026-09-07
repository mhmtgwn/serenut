// test/unit/orders_controller_bulk_operations_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/audit_provider.dart';
import 'package:serenutos/providers/event_providers.dart';
import 'package:serenutos/domain/events/event_publisher.dart';
import 'package:serenutos/domain/events/domain_event.dart';
import 'package:serenutos/domain/repositories/audit_repository.dart';
import 'package:serenutos/domain/services/audit_service.dart';
import 'package:serenutos/domain/services/order_cancellation_service.dart';
import 'package:serenutos/providers/sync_provider.dart';

class MockOrderRepo implements IOrderRepository {
  final Map<String, OrderEntity> orders;
  final Set<String> deletedIds = {};
  final Map<String, String> updatedStatuses = {};

  MockOrderRepo(List<OrderEntity> list)
      : orders = {for (final o in list) o.id: o};

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
    final active =
        orders.values.where((o) => !deletedIds.contains(o.id)).toList();
    return active.skip(offset).take(limit).toList();
  }

  @override
  Future<OrderEntity?> findById(dynamic id) async {
    final key = id.toString();
    if (deletedIds.contains(key)) return null;
    final order = orders[key];
    if (order == null) return null;
    if (updatedStatuses.containsKey(key)) {
      return order.copyWith(status: updatedStatuses[key]!);
    }
    return order;
  }

  @override
  Future<int> delete(dynamic id) async {
    final key = id.toString();
    deletedIds.add(key);
    orders.remove(key);
    return 1;
  }

  @override
  Future<void> updateStatus(String id, String status) async {
    updatedStatuses[id] = status;
    if (orders.containsKey(id)) {
      orders[id] = orders[id]!.copyWith(status: status);
    }
  }

  @override
  Future<Map<String, int>> getStatusCounts({
    String? searchQuery,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool overdueOnly = false,
  }) async =>
      {'all': orders.length};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuditRepo implements IAuditRepository {
  @override
  Future<void> insert(dynamic event) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockCancellationService implements OrderCancellationService {
  final Set<String> cancelledIds = {};

  @override
  Future<void> cancel({
    required String id,
    String? reason,
    String? refundMethod,
    bool notifyCustomer = true,
  }) async {
    cancelledIds.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockEventPublisher implements EventPublisher {
  @override
  void publish<T extends DomainEvent>(T event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSyncNotifier extends StateNotifier<SyncState>
    implements SyncNotifier {
  MockSyncNotifier() : super(const SyncState());

  @override
  Future<void> triggerSync() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<OrderEntity> sampleOrders;
  late MockOrderRepo mockRepo;
  late MockCancellationService mockCancellation;
  late AuditService auditService;
  late ProviderContainer container;

  setUp(() {
    sampleOrders = [
      OrderEntity(
        id: 'ord-created',
        orderNumber: 'SP-101',
        customerId: 'cust-1',
        status: 'created',
        createdAt: DateTime.now(),
        items: const [],
      ),
      OrderEntity(
        id: 'ord-preparing',
        orderNumber: 'SP-102',
        customerId: 'cust-2',
        status: 'preparing',
        createdAt: DateTime.now(),
        items: const [],
      ),
      OrderEntity(
        id: 'ord-delivered',
        orderNumber: 'SP-103',
        customerId: 'cust-3',
        status: 'delivered',
        createdAt: DateTime.now(),
        items: const [],
      ),
    ];

    mockRepo = MockOrderRepo(sampleOrders);
    mockCancellation = MockCancellationService();
    auditService = AuditService(repository: MockAuditRepo());

    container = ProviderContainer(
      overrides: [
        orderRepositoryProvider.overrideWith((ref) async => mockRepo),
        orderCancellationServiceProvider
            .overrideWith((ref) async => mockCancellation),
        auditServiceProvider.overrideWith((ref) async => auditService),
        eventPublisherProvider.overrideWithValue(MockEventPublisher()),
        syncProvider.overrideWith((ref) => MockSyncNotifier()),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('bulkDeleteOrders skips delivered orders and deletes eligible orders',
      () async {
    await container.read(ordersControllerProvider.future);
    final notifier = container.read(ordersControllerProvider.notifier);

    final deletedCount = await notifier.bulkDeleteOrders([
      'ord-created',
      'ord-delivered', // MUST BE SKIPPED
    ]);

    expect(deletedCount, equals(1));
    expect(mockRepo.deletedIds, contains('ord-created'));
    expect(mockRepo.deletedIds, isNot(contains('ord-delivered')));
    expect(mockRepo.orders.containsKey('ord-delivered'), isTrue);
  });

  test('bulkCancelOrders skips delivered orders and cancels eligible orders',
      () async {
    await container.read(ordersControllerProvider.future);
    final notifier = container.read(ordersControllerProvider.notifier);

    final cancelledCount = await notifier.bulkCancelOrders([
      'ord-preparing',
      'ord-delivered', // MUST BE SKIPPED
    ]);

    expect(cancelledCount, equals(1));
    expect(mockCancellation.cancelledIds, contains('ord-preparing'));
    expect(mockCancellation.cancelledIds, isNot(contains('ord-delivered')));
  });

  test('bulkUpdateStatus rejects delivered target status with ArgumentError',
      () async {
    await container.read(ordersControllerProvider.future);
    final notifier = container.read(ordersControllerProvider.notifier);

    expect(
      () => notifier.bulkUpdateStatus(['ord-created'], 'delivered'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test(
      'bulkUpdateStatus skips already delivered orders when transitioning to ready',
      () async {
    await container.read(ordersControllerProvider.future);
    final notifier = container.read(ordersControllerProvider.notifier);

    final updatedCount = await notifier.bulkUpdateStatus([
      'ord-created',
      'ord-delivered', // MUST BE SKIPPED
    ], 'ready');

    expect(updatedCount, equals(1));
    expect(mockRepo.updatedStatuses['ord-created'], equals('ready'));
    expect(mockRepo.updatedStatuses.containsKey('ord-delivered'), isFalse);
  });
}
