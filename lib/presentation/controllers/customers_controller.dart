// lib/presentation/controllers/customers_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/domain/services/pagination_service.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/providers/audit_provider.dart';
import 'package:serenutos/providers/sync_provider.dart';

final customerSearchQueryProvider = StateProvider<String>((ref) => '');
final customerBalanceFilterProvider =
    StateProvider<CustomerBalanceFilter>((ref) => CustomerBalanceFilter.all);

/// Reactive indicator for customer pagination loading state
final customerLoadingMoreProvider = StateProvider<bool>((ref) => false);

final customerBalanceSummaryProvider =
    FutureProvider<CustomerBalanceSummary>((ref) async {
  final repository = await ref.watch(customerRepositoryProvider.future);
  final query = ref.watch(customerSearchQueryProvider);
  return repository.getBalanceSummary(searchQuery: query);
});

class CustomersController extends AsyncNotifier<List<CustomerEntity>> {
  late ICustomerRepository _repository;
  PaginationService<CustomerEntity>? _paginationService;

  @override
  FutureOr<List<CustomerEntity>> build() async {
    _repository = await ref.watch(customerRepositoryProvider.future);
    final searchService = await ref.watch(customerSearchServiceProvider.future);

    final searchQuery = ref.watch(customerSearchQueryProvider);
    final balanceFilter = ref.watch(customerBalanceFilterProvider);

    _paginationService = PaginationService<CustomerEntity>(
      dataLoader: (offset, limit, query) async {
        final result = await searchService.searchCustomers(
          query: query ?? '',
          page: offset ~/ limit,
          limit: limit,
          balanceFilter: balanceFilter,
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
    ref.read(customerLoadingMoreProvider.notifier).state = true;
    try {
      await _paginationService!.loadNextPage();
      state = AsyncValue.data(List.from(_paginationService!.items));
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    } finally {
      ref.read(customerLoadingMoreProvider.notifier).state = false;
    }
  }

  Future<CustomerDuplicateCheckResult> checkDuplicates({
    required String name,
    required String phone,
    String? excludeId,
  }) async {
    await future;
    return _repository.checkDuplicates(
      name: name,
      phone: phone,
      excludeId: excludeId,
    );
  }

  Future<void> addCustomer(CustomerEntity customer, {bool force = false}) async {
    await future;
    final dupCheck = await _repository.checkDuplicates(
      name: customer.name,
      phone: customer.phone,
      excludeId: customer.id,
    );

    if (dupCheck.isExactMatch) {
      throw DuplicateCustomerException(
        'Bu isim ve telefon numarasına sahip müşteri zaten kayıtlı: '
        '${dupCheck.matchedCustomer!.name} (${dupCheck.matchedCustomer!.phone})',
        matchedCustomer: dupCheck.matchedCustomer,
      );
    }

    if (dupCheck.hasPhoneConflict && !force) {
      throw CustomerPhoneConflictException(
        'Bu telefon numarası başka bir müşteride kayıtlı: '
        '${dupCheck.matchedCustomer!.name}',
        conflictingCustomer: dupCheck.matchedCustomer!,
      );
    }

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
      } catch (e, st) {
        TelemetryService().logError(e, st,
            context: 'customers_controller', level: LogLevel.warning);
      }
      await _paginationService?.refresh();
      return _paginationService?.items ?? [];
    });
    _invalidateAll();
  }

  Future<void> updateCustomer(CustomerEntity customer, {bool force = false}) async {
    await future;
    final dupCheck = await _repository.checkDuplicates(
      name: customer.name,
      phone: customer.phone,
      excludeId: customer.id,
    );

    if (dupCheck.isExactMatch) {
      throw DuplicateCustomerException(
        'Bu isim ve telefon numarasına sahip başka bir müşteri zaten kayıtlı: '
        '${dupCheck.matchedCustomer!.name} (${dupCheck.matchedCustomer!.phone})',
        matchedCustomer: dupCheck.matchedCustomer,
      );
    }

    if (dupCheck.hasPhoneConflict && !force) {
      throw CustomerPhoneConflictException(
        'Bu telefon numarası başka bir müşteride kayıtlı: '
        '${dupCheck.matchedCustomer!.name}',
        conflictingCustomer: dupCheck.matchedCustomer!,
      );
    }

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
      } catch (e, st) {
        TelemetryService().logError(e, st,
            context: 'customers_controller', level: LogLevel.warning);
      }
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
      if (original != null && original.balance.abs() > 0.01) {
        final bal = original.balance;
        final formattedBal = bal.abs().toStringAsFixed(2);
        final direction = bal < 0 ? 'borcu' : 'alacağı';
        throw StateError(
            'Bakiyesi sıfır olmayan müşteri silinemez. Müşterinin ₺$formattedBal $direction bulunmaktadır. Lütfen önce bakiyeyi kapatınız.');
      }
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
      } catch (e, st) {
        TelemetryService().logError(e, st,
            context: 'customers_controller', level: LogLevel.warning);
      }
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
    ref.invalidate(customerDetailProvider(id));
    _invalidateAll();
  }

  Future<void> recordCollection({
    required String customerId,
    required double amount,
    required String method,
    String? notes,
    Map<String, dynamic>? terminalMetadata,
  }) async {
    final paymentService = await ref.read(paymentServiceProvider.future);
    await paymentService.recordCollection(
      customerId: customerId,
      amount: amount,
      method: method,
      notes: notes,
      terminalMetadata: terminalMetadata,
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
    } catch (e, st) {
      TelemetryService().logError(e, st,
          context: 'customers_controller', level: LogLevel.warning);
    }
    ref.invalidate(customerTransactionsProvider(customerId));
    ref.invalidate(customerBalanceDetailsProvider(customerId));
    ref.invalidate(customerDetailProvider(customerId));

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
    } catch (e, st) {
      TelemetryService().logError(e, st,
          context: 'customers_controller', level: LogLevel.warning);
    }
    ref.invalidate(customerTransactionsProvider(customerId));
    ref.invalidate(customerBalanceDetailsProvider(customerId));
    ref.invalidate(customerDetailProvider(customerId));
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
      ref.invalidateSelf();
      ref.invalidate(salesCustomersControllerProvider);
      ref.invalidate(ordersCustomersControllerProvider);
      ref.invalidate(collectionCustomersControllerProvider);
      ref.invalidate(customerBalanceSummaryProvider);
      ref.invalidate(customerLookupMapProvider);
      unawaited(ref.read(syncProvider.notifier).triggerSync());
    });
  }
}

final customersControllerProvider =
    AsyncNotifierProvider<CustomersController, List<CustomerEntity>>(() {
  return CustomersController();
});

/// Unfiltered global map of {customerId: customerName} for order & sales listings
final customerLookupMapProvider = FutureProvider<Map<String, String>>((ref) async {
  final repository = await ref.watch(customerRepositoryProvider.future);
  return repository.getLookupMap();
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

/// Per-customer reliable unpaginated provider by ID
final customerDetailProvider =
    FutureProvider.family<CustomerEntity?, String>((ref, customerId) async {
  if (customerId.isEmpty) return null;
  final repo = await ref.watch(customerRepositoryProvider.future);
  return repo.findById(customerId);
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
  final refId = txn.referenceId?.trim();
  if (refId == null || refId.isEmpty) {
    return [];
  }

  final productRepo = await ref.watch(productRepositoryProvider.future);

  Future<List<Map<String, dynamic>>> extractItems(List<dynamic> rawItems) async {
    final list = <Map<String, dynamic>>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final prodId = (item['product_id'] ?? '').toString();
      final storedName =
          (item['product_name'] ?? item['name'])?.toString();
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;

      if (storedName != null && storedName.isNotEmpty) {
        list.add({
          'name': storedName,
          'quantity': qty,
          'unit_price': price,
        });
      } else if (prodId.isNotEmpty) {
        final prod = await productRepo.findById(prodId);
        list.add({
          'name': prod?.name ?? 'Ürün #$prodId',
          'quantity': qty,
          'unit_price': price,
        });
      } else {
        list.add({
          'name': 'Hizmet / Kalem',
          'quantity': qty,
          'unit_price': price,
        });
      }
    }
    return list;
  }

  // 1. Try order if prefix matches or directly
  if (refId.startsWith('ord-') || !refId.startsWith('sale-')) {
    final orderRepo = await ref.watch(orderRepositoryProvider.future);
    final order = await orderRepo.findById(refId);
    if (order != null && order.items.isNotEmpty) {
      return extractItems(order.items);
    }
  }

  // 2. Try sale if prefix matches or fallback
  final saleRepo = await ref.watch(saleRepositoryProvider.future);
  final sale = await saleRepo.findById(refId);
  if (sale != null && sale.items.isNotEmpty) {
    return extractItems(sale.items);
  }

  return [];
});
