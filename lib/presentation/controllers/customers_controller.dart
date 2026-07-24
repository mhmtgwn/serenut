// lib/presentation/controllers/customers_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/domain/services/pagination_service.dart';
import 'package:serenutos/providers/audit_provider.dart';

final customerSearchQueryProvider = StateProvider<String>((ref) => '');

class CustomersController extends AsyncNotifier<List<CustomerEntity>> {
  late ICustomerRepository _repository;
  PaginationService<CustomerEntity>? _paginationService;

  @override
  FutureOr<List<CustomerEntity>> build() async {
    _repository = await ref.watch(customerRepositoryProvider.future);
    final searchService = await ref.watch(customerSearchServiceProvider.future);

    final searchQuery = ref.watch(customerSearchQueryProvider);

    _paginationService = PaginationService<CustomerEntity>(
      dataLoader: (offset, limit, query) async {
        final result = await searchService.searchCustomers(
          query: query ?? '',
          page: offset ~/ limit,
          limit: limit,
        );
        return result.items;
      },
      pageSize: 50,
    );

    await _paginationService!.loadFirstPage(searchQuery: searchQuery);
    return _paginationService!.items;
  }

  bool get hasMoreData => _paginationService?.hasMoreData ?? false;
  bool get isLoadingMore => _paginationService?.isLoading ?? false;

  Future<void> loadNextPage() async {
    if (_paginationService == null) return;
    if (_paginationService!.isLoading || !_paginationService!.hasMoreData) {
      return;
    }
    try {
      await _paginationService!.loadNextPage();
      state = AsyncValue.data(List.from(_paginationService!.items));
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> addCustomer(CustomerEntity customer) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.create(customer);
      try {
        final auditService = await ref.read(auditServiceProvider.future);
        await auditService.logEvent(
          eventType: 'customer_created',
          entityType: 'customer',
          entityId: customer.id,
          newValue: 'Ad: ${customer.name}, Bakiye: ₺${customer.balance}',
          notes: 'Yeni müşteri eklendi: ${customer.name}',
        );
      } catch (_) {}
      await _paginationService?.refresh();
      return _paginationService?.items ?? [];
    });
    _invalidateAll();
  }

  Future<void> updateCustomer(CustomerEntity customer) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final original = await _repository.findById(customer.id);
      await _repository.update(customer);
      try {
        final auditService = await ref.read(auditServiceProvider.future);
        await auditService.logCustomerUpdate(
          customer.id,
          customer.name,
          'Eski bakiye: ₺${original?.balance}, Yeni bakiye: ₺${customer.balance}',
        );
      } catch (_) {}
      await _paginationService?.refresh();
      return _paginationService?.items ?? [];
    });
    _invalidateAll();
  }

  Future<void> deleteCustomer(String id,
      {String? approvedByUserId, String? approvedByUserName}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final original = await _repository.findById(id);
      await _repository.delete(id);
      try {
        final auditService = await ref.read(auditServiceProvider.future);
        await auditService.logDelete(
          'customer',
          id,
          original?.name ?? 'Bilinmeyen Müşteri',
          approvedByUserId: approvedByUserId,
          approvedByUserName: approvedByUserName,
        );
      } catch (_) {}
      await _paginationService?.refresh();
      return _paginationService?.items ?? [];
    });
    _invalidateAll();
  }

  Future<void> updateBalance(String id, double amount) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.updateBalance(id, amount);
      await _paginationService?.refresh();
      return _paginationService?.items ?? [];
    });
    ref.invalidate(customerTransactionsProvider(id));
    ref.invalidate(customerBalanceDetailsProvider(id));
    _invalidateAll();
  }

  Future<void> recordCollection({
    required String customerId,
    required double amount,
    required String method,
    String? notes,
  }) async {
    final paymentService = await ref.read(paymentServiceProvider.future);
    await paymentService.recordCollection(
      customerId: customerId,
      amount: amount,
      method: method,
      notes: notes,
    );
    try {
      final auditService = await ref.read(auditServiceProvider.future);
      final customer = await _repository.findById(customerId);
      await auditService.logPayment(
        customerId,
        customer?.name ?? 'Bilinmeyen Müşteri',
        amount,
        method,
      );
    } catch (_) {}
    ref.invalidate(customerTransactionsProvider(customerId));
    ref.invalidate(customerBalanceDetailsProvider(customerId));

    // Refresh customers list
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _paginationService?.refresh();
      return _paginationService?.items ?? [];
    });
    _invalidateAll();
  }

  Future<void> recordManualDebt({
    required String customerId,
    required double amount,
    String? notes,
  }) async {
    final paymentService = await ref.read(paymentServiceProvider.future);
    await paymentService.recordManualDebt(
      customerId: customerId,
      amount: amount,
      notes: notes,
    );
    try {
      final auditService = await ref.read(auditServiceProvider.future);
      final customer = await _repository.findById(customerId);
      await auditService.logEvent(
        eventType: 'manual_debt_created',
        entityType: 'customer',
        entityId: customerId,
        newValue: 'Borç: ₺${amount.toStringAsFixed(2)}',
        notes: notes?.trim().isNotEmpty == true
            ? notes!.trim()
            : '${customer?.name ?? 'Müşteri'} için elle borç eklendi',
      );
    } catch (_) {}
    ref.invalidate(customerTransactionsProvider(customerId));
    ref.invalidate(customerBalanceDetailsProvider(customerId));
    await refresh();
    _invalidateAll();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _paginationService?.refresh();
      return _paginationService?.items ?? [];
    });
  }

  void _invalidateAll() {
    Future.microtask(() {
      ref.invalidate(customersControllerProvider);
      ref.invalidate(salesCustomersControllerProvider);
      ref.invalidate(ordersCustomersControllerProvider);
      ref.invalidate(collectionCustomersControllerProvider);
    });
  }
}

final customersControllerProvider =
    AsyncNotifierProvider<CustomersController, List<CustomerEntity>>(() {
  return CustomersController();
});

// Screen-specific Customer Search Providers
final salesCustomerSearchQueryProvider = StateProvider<String>((ref) => '');
final ordersCustomerSearchQueryProvider = StateProvider<String>((ref) => '');
final collectionCustomerSearchQueryProvider =
    StateProvider<String>((ref) => '');

// Sales-specific customers list notifier and provider
class SalesCustomersController extends CustomersController {
  @override
  FutureOr<List<CustomerEntity>> build() async {
    _repository = await ref.watch(customerRepositoryProvider.future);
    final searchService = await ref.watch(customerSearchServiceProvider.future);

    final searchQuery = ref.watch(salesCustomerSearchQueryProvider);

    _paginationService = PaginationService<CustomerEntity>(
      dataLoader: (offset, limit, query) async {
        final result = await searchService.searchCustomers(
          query: query ?? '',
          page: offset ~/ limit,
          limit: limit,
        );
        return result.items;
      },
      pageSize: 50,
    );

    await _paginationService!.loadFirstPage(searchQuery: searchQuery);
    return _paginationService!.items;
  }
}

final salesCustomersControllerProvider =
    AsyncNotifierProvider<SalesCustomersController, List<CustomerEntity>>(() {
  return SalesCustomersController();
});

// Orders-specific customers list notifier and provider
class OrdersCustomersController extends CustomersController {
  @override
  FutureOr<List<CustomerEntity>> build() async {
    _repository = await ref.watch(customerRepositoryProvider.future);
    final searchService = await ref.watch(customerSearchServiceProvider.future);

    final searchQuery = ref.watch(ordersCustomerSearchQueryProvider);

    _paginationService = PaginationService<CustomerEntity>(
      dataLoader: (offset, limit, query) async {
        final result = await searchService.searchCustomers(
          query: query ?? '',
          page: offset ~/ limit,
          limit: limit,
        );
        return result.items;
      },
      pageSize: 50,
    );

    await _paginationService!.loadFirstPage(searchQuery: searchQuery);
    return _paginationService!.items;
  }
}

final ordersCustomersControllerProvider =
    AsyncNotifierProvider<OrdersCustomersController, List<CustomerEntity>>(() {
  return OrdersCustomersController();
});

// Collection-specific customers list notifier and provider
class CollectionCustomersController extends CustomersController {
  @override
  FutureOr<List<CustomerEntity>> build() async {
    _repository = await ref.watch(customerRepositoryProvider.future);
    final searchService = await ref.watch(customerSearchServiceProvider.future);

    final searchQuery = ref.watch(collectionCustomerSearchQueryProvider);

    _paginationService = PaginationService<CustomerEntity>(
      dataLoader: (offset, limit, query) async {
        final result = await searchService.searchCustomers(
          query: query ?? '',
          page: offset ~/ limit,
          limit: limit,
        );
        return result.items;
      },
      pageSize: 50,
    );

    await _paginationService!.loadFirstPage(searchQuery: searchQuery);
    return _paginationService!.items;
  }
}

final collectionCustomersControllerProvider =
    AsyncNotifierProvider<CollectionCustomersController, List<CustomerEntity>>(
        () {
  return CollectionCustomersController();
});

/// Per-customer transactions provider
final customerTransactionsProvider =
    FutureProvider.family<List<FinancialTransactionEntity>, String>(
        (ref, customerId) async {
  final repo = await ref.watch(financialTransactionRepositoryProvider.future);
  return repo.getByCustomerId(customerId);
});

/// Per-customer balance details provider
final customerBalanceDetailsProvider =
    FutureProvider.family<Map<String, double>, String>((ref, customerId) async {
  final repo = await ref.watch(customerRepositoryProvider.future);
  final balance = await repo.getBalance(customerId);
  final totalDebt = await repo.getTotalDebt(customerId);
  final totalPaid = await repo.getTotalPaid(customerId);
  return {
    'balance': balance,
    'totalDebt': totalDebt,
    'totalPaid': totalPaid,
  };
});

/// Provider to load details (items) of a financial transaction (sale or order)
final transactionItemsProvider = FutureProvider.family<
    List<Map<String, dynamic>>, FinancialTransactionEntity>((ref, txn) async {
  if (txn.referenceId == null || txn.referenceId!.isEmpty) {
    return [];
  }

  final productRepo = await ref.watch(productRepositoryProvider.future);

  if (txn.referenceId!.startsWith('ord-')) {
    final orderRepo = await ref.watch(orderRepositoryProvider.future);
    final order = await orderRepo.findById(txn.referenceId!);
    if (order != null) {
      final list = <Map<String, dynamic>>[];
      for (final item in order.items) {
        final prodId = item['product_id'] as String;
        final storedName =
            item['product_name'] as String? ?? item['name'] as String?;
        if (storedName != null && storedName.isNotEmpty) {
          list.add({
            'name': storedName,
            'quantity': (item['quantity'] as num?)?.toDouble() ?? 0.0,
            'unit_price': (item['unit_price'] as num?)?.toDouble() ?? 0.0,
          });
        } else {
          final prod = await productRepo.findById(prodId);
          list.add({
            'name': prod?.name ?? 'Bilinmeyen Ürün',
            'quantity': (item['quantity'] as num?)?.toDouble() ?? 0.0,
            'unit_price': (item['unit_price'] as num?)?.toDouble() ?? 0.0,
          });
        }
      }
      return list;
    }
  } else if (txn.referenceId!.startsWith('sale-')) {
    final saleRepo = await ref.watch(saleRepositoryProvider.future);
    final sale = await saleRepo.findById(txn.referenceId!);
    if (sale != null) {
      final list = <Map<String, dynamic>>[];
      for (final item in sale.items) {
        final prodId = item['product_id'] as String;
        final storedName =
            item['name'] as String? ?? item['product_name'] as String?;
        if (storedName != null && storedName.isNotEmpty) {
          list.add({
            'name': storedName,
            'quantity': (item['quantity'] as num?)?.toDouble() ?? 0.0,
            'unit_price': (item['unit_price'] as num?)?.toDouble() ?? 0.0,
          });
        } else {
          final prod = await productRepo.findById(prodId);
          list.add({
            'name': prod?.name ?? 'Bilinmeyen Ürün',
            'quantity': (item['quantity'] as num?)?.toDouble() ?? 0.0,
            'unit_price': (item['unit_price'] as num?)?.toDouble() ?? 0.0,
          });
        }
      }
      return list;
    }
  }
  return [];
});
