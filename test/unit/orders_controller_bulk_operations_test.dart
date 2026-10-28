// test/unit/orders_controller_bulk_operations_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
import 'package:serenutos/domain/services/data_integrity_service.dart';
import 'package:serenutos/domain/services/inventory_service.dart';
import 'package:serenutos/domain/services/payment_service.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/services/telemetry_upload_service.dart';
import 'package:serenutos/core_next/infrastructure/database/app_database.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_customer_repository.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_financial_transaction_repository.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_product_repository.dart';
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
    var active =
        orders.values.where((o) => !deletedIds.contains(o.id)).toList();
    if (status != null && status.isNotEmpty) {
      active = active
          .where((o) => o.status.toLowerCase() == status.toLowerCase())
          .toList();
    }
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
  Future<void> insert(dynamic event) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockApiClient implements ApiClient {
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

  test(
      'ordersControllerProvider preserves active statusFilter across sync invalidation when remote device updates order status',
      () async {
    await container.read(ordersControllerProvider.future);
    final notifier = container.read(ordersControllerProvider.notifier);

    // User filters by 'created' (Yeni) on laptop
    await notifier.applyFilter('created');
    final beforeSync = await container.read(ordersControllerProvider.future);
    expect(beforeSync.map((o) => o.id), equals(['ord-created']));

    // Desktop PC transitions 'ord-created' from 'created' -> 'preparing' and sync pulls it
    await mockRepo.updateStatus('ord-created', 'preparing');
    container.invalidate(ordersControllerProvider);

    // After invalidation, 'created' filter is preserved and 'ord-created' is no longer in 'Yeni'
    final afterSyncCreated =
        await container.read(ordersControllerProvider.future);
    expect(afterSyncCreated, isEmpty);

    // Switching to 'preparing' (Hazırlanıyor) shows both preparing orders
    await container
        .read(ordersControllerProvider.notifier)
        .applyFilter('preparing');
    final preparingList = await container.read(ordersControllerProvider.future);
    expect(
      preparingList.map((o) => o.id),
      containsAll(['ord-created', 'ord-preparing']),
    );
  });

  test(
      'deleteOrder and OrderCancellationService do not deadlock SQLite or trigger false silent_data_corruption_alarm when TelemetryUploadService is active',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final tempDir =
        await Directory.systemTemp.createTemp('serenut_order_delete_freeze_');
    final coreDb = await CoreAppDatabase.open(
      inMemoryOrCustomPath: '${tempDir.path}/core.db',
    );

    final prevOverridePath = DatabaseManager.overrideDatabasePath;
    DatabaseManager.overrideDatabasePath = '${tempDir.path}/legacy.db';
    DatabaseManager.instance.reset();
    final legacyDb = await DatabaseManager.instance.getDatabase();

    final dbGateway = DbGatewayImpl(DatabaseManager.instance);
    final telemetryUpload = TelemetryUploadService(MockApiClient(), dbGateway);
    final prevOpCallback = TelemetryService().onOperationalEvent;
    TelemetryService().onOperationalEvent = (event) async {
      await telemetryUpload.recordMetric(
        event.event,
        event.level.index.toDouble(),
        metadata: event.metadata,
      );
    };

    try {
      final customerRepo =
          CoreNextCustomerRepository.fromCoreAppDatabase(coreDb);
      final productRepo = CoreNextProductRepository.fromCoreAppDatabase(coreDb);
      final ftRepo =
          CoreNextFinancialTransactionRepository.fromCoreAppDatabase(coreDb);
      final eventPub = EventPublisher();

      final custId = await customerRepo.create(
        CustomerEntity(
          id: 'cust-1',
          name: 'Test Müşteri',
          phone: '05551112233',
          balance: 0.0,
          createdAt: DateTime.now(),
        ),
      );
      expect(custId, isNotNull);

      await productRepo.create(
        ProductEntity(
          id: 'prod-freeze-1',
          name: 'Test Ürün',
          description: 'Açıklama',
          category: 'Genel',
          price: 150.0,
          quantity: 10.0,
        ),
      );

      // 1. Order with partial upfront payment (total=300, paid=100, debt=200)
      await ftRepo.create(
        FinancialTransactionEntity(
          id: 'tx-sale-ord-created',
          type: 'sale',
          customerId: 'cust-1',
          amount: 300.0,
          paidAmount: 100.0,
          debtAmount: 200.0,
          date: DateTime.now(),
          referenceId: 'ord-created',
          metadata: const {'origin': 'order'},
        ),
      );

      final integrityService = DataIntegrityService(
        customerRepository: customerRepo,
        transactionRepository: ftRepo,
        telemetryService: TelemetryService(),
      );

      // Verify invariant holds right after order creation (balance = -200)
      expect(
        await integrityService.verifyLedgerInvariant('cust-1'),
        isTrue,
      );

      final realCancellationService = OrderCancellationService(
        orderRepository: mockRepo,
        inventoryService: InventoryService(
          productRepository: productRepo,
          eventPublisher: eventPub,
        ),
        paymentService: PaymentService(
          customerRepository: customerRepo,
          transactionRepository: ftRepo,
          eventPublisher: eventPub,
        ),
        transactionRepository: ftRepo,
        transactionRunner: dbGateway,
        dataIntegrityService: integrityService,
      );

      // Also verify that even a direct critical log inside an active SQLite transaction
      // never deadlocks DbGatewayImpl or Database.txnSynchronized!
      await dbGateway
          .transaction(() async {
            await TelemetryService().logStructured(
              event: 'test_in_txn_telemetry',
              level: LogLevel.critical,
              metadata: const {'order_id': 'ord-created'},
            );
          })
          .timeout(const Duration(seconds: 3));

      // Cancel & delete 'ord-created' via real OrderCancellationService inside SQLite transaction
      await realCancellationService
          .cancel(id: 'ord-created')
          .timeout(const Duration(seconds: 3));

      // After cancelling order with 200 debt and 100 upfront payment:
      // - 200 debt is reversed by CANCELLATION (+200) -> balance = 0
      // - 100 upfront payment is credited to customer balance by REFUND (+100) -> balance = +100
      // And verifyLedgerInvariant MUST be 100% consistent (true)!
      expect(
        await integrityService.verifyLedgerInvariant('cust-1'),
        isTrue,
      );
      final updatedCustomer = await customerRepo.findById('cust-1');
      expect(updatedCustomer?.balance, closeTo(100.0, 0.001));

      // Subsequent DB write on DbGatewayImpl must complete immediately (no queue deadlock)
      await dbGateway
          .transaction(() async {
            await dbGateway.rawQuery('SELECT 1');
          })
          .timeout(const Duration(seconds: 2));
    } finally {
      TelemetryService().onOperationalEvent = prevOpCallback;
      await coreDb.close();
      await legacyDb.close();
      DatabaseManager.overrideDatabasePath = prevOverridePath;
      DatabaseManager.instance.reset();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });
}
