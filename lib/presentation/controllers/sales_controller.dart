// lib/presentation/controllers/sales_controller.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/services/sales_service.dart';
import 'package:serenutos/domain/services/inventory_service.dart';
import 'package:serenutos/domain/services/payment_service.dart';
import 'package:serenutos/domain/services/data_integrity_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/event_providers.dart';
import 'package:serenutos/providers/database_provider.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/audit_provider.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';

final inventoryServiceProvider = FutureProvider<InventoryService>((ref) async {
  final productRepo = await ref.watch(productRepositoryProvider.future);
  final eventPublisher = ref.watch(eventPublisherProvider);

  return InventoryService(
    productRepository: productRepo,
    eventPublisher: eventPublisher,
  );
});

final paymentServiceProvider = FutureProvider<PaymentService>((ref) async {
  final customerRepo = await ref.watch(customerRepositoryProvider.future);
  final transactionRepo =
      await ref.watch(financialTransactionRepositoryProvider.future);
  final eventPublisher = ref.watch(eventPublisherProvider);
  final auditLogService = ref.watch(auditLogServiceProvider);

  return PaymentService(
    customerRepository: customerRepo,
    transactionRepository: transactionRepo,
    eventPublisher: eventPublisher,
    auditLogService: auditLogService,
  );
});

final dataIntegrityServiceProvider =
    FutureProvider<DataIntegrityService>((ref) async {
  final customerRepo = await ref.watch(customerRepositoryProvider.future);
  final transactionRepo =
      await ref.watch(financialTransactionRepositoryProvider.future);
  final healthRepo = ref.watch(databaseHealthRepositoryProvider);
  return DataIntegrityService(
    customerRepository: customerRepo,
    transactionRepository: transactionRepo,
    healthRepository: healthRepo,
  );
});

final salesServiceProvider = FutureProvider<SalesService>((ref) async {
  final saleRepo = await ref.watch(saleRepositoryProvider.future);
  final inventoryService = await ref.watch(inventoryServiceProvider.future);
  final paymentService = await ref.watch(paymentServiceProvider.future);
  final eventPublisher = ref.watch(eventPublisherProvider);
  final gateway = ref.watch(dbGatewayProvider);
  final securityGate = ref.watch(securityGateProvider);
  final dataIntegrity = await ref.watch(dataIntegrityServiceProvider.future);

  return SalesService(
    saleRepository: saleRepo,
    inventoryService: inventoryService,
    paymentService: paymentService,
    eventPublisher: eventPublisher,
    transactionRunner: gateway,
    securityGate: securityGate,
    dataIntegrityService: dataIntegrity,
  );
});

class SalesController extends AsyncNotifier<List<SaleEntity>> {
  late ISaleRepository _saleRepository;
  late SalesService _salesService;

  @override
  FutureOr<List<SaleEntity>> build() async {
    _saleRepository = await ref.watch(saleRepositoryProvider.future);
    _salesService = await ref.watch(salesServiceProvider.future);
    return _saleRepository.findAll();
  }

  Future<SaleEntity?> createSale({
    required String customerId,
    required List<SaleItemInput> items,
    required String paymentMethod,
    double? paidAmount,
  }) async {
    await future;
    SaleEntity? created;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      try {
        final currentUser = ref.read(currentUserProvider);
        final cashierName = currentUser?.name ?? 'Kasiyer';

        created = await _salesService.createSale(
          customerId: customerId,
          items: items,
          paymentMethod: paymentMethod,
          paidAmount: paidAmount,
          createdBy: cashierName,
        );
        if (created != null) {
          try {
            final auditService = await ref.read(auditServiceProvider.future);
            await auditService.logEvent(
              eventType: 'sale_created',
              entityType: 'sale',
              entityId: created!.id,
              newValue:
                  'Miktar: ₺${created!.totalAmount.toStringAsFixed(2)}, Yöntem: ${created!.paymentMethod}',
            );
          } catch (e) {
            debugPrint('Failed to log sale_created audit event: $e');
          }
        }
      } catch (e) {
        // print('🔴 EXCEPTION inside SalesService.createSale: $e\n$st');
        rethrow;
      }
      return _saleRepository.findAll();
    });
    if (state.hasError) {
      // print('🔴 SalesController.createSale state error: ${state.error}');
    }
    if (created != null && customerId.isNotEmpty) {
      ref.invalidate(customersControllerProvider);
      ref.invalidate(customerTransactionsProvider(customerId));
      ref.invalidate(customerBalanceDetailsProvider(customerId));
    }
    return created;
  }

  Future<void> cancelSale(String saleId) async {
    await future;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final sale = await _saleRepository.findById(saleId);
      await _salesService.cancelSale(saleId);
      try {
        final auditService = await ref.read(auditServiceProvider.future);
        await auditService.logDelete('sale', saleId,
            'Satış İptali: ₺${sale?.totalAmount.toStringAsFixed(2)}');
      } catch (e) {
        debugPrint('Failed to log sale cancellation audit event: $e');
      }
      if (sale != null && sale.customerId.isNotEmpty) {
        ref.invalidate(customersControllerProvider);
        ref.invalidate(customerTransactionsProvider(sale.customerId));
        ref.invalidate(customerBalanceDetailsProvider(sale.customerId));
      }
      ref.invalidate(productsControllerProvider);
      ref.invalidate(dashboardProvider);
      return _saleRepository.findAll();
    });
  }

  Future<void> returnItems({
    required String saleId,
    required List<SaleItemInput> itemsToReturn,
    required String refundMethod,
  }) async {
    await future;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final sale = await _saleRepository.findById(saleId);
      await _salesService.returnItems(
        saleId: saleId,
        itemsToReturn: itemsToReturn,
        refundMethod: refundMethod,
      );
      try {
        final auditService = await ref.read(auditServiceProvider.future);
        await auditService.logEvent(
          eventType: 'items_returned',
          entityType: 'sale',
          entityId: saleId,
          notes: 'Satıştan iade alındı: $saleId, Yöntem: $refundMethod',
        );
      } catch (e) {
        debugPrint('Failed to log items_returned audit event: $e');
      }
      if (sale != null && sale.customerId.isNotEmpty) {
        ref.invalidate(customersControllerProvider);
        ref.invalidate(customerTransactionsProvider(sale.customerId));
        ref.invalidate(customerBalanceDetailsProvider(sale.customerId));
      }
      ref.invalidate(productsControllerProvider);
      ref.invalidate(dashboardProvider);
      return _saleRepository.findAll();
    });
  }

  Future<void> recordPartialPayment({
    required String saleId,
    required double amount,
    required String method,
  }) async {
    await future;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final sale = await _saleRepository.findById(saleId);
      await _salesService.recordPayment(
          saleId: saleId, amount: amount, method: method);

      try {
        final auditService = await ref.read(auditServiceProvider.future);
        final customerRepo = await ref.read(customerRepositoryProvider.future);
        final customer =
            sale != null ? await customerRepo.findById(sale.customerId) : null;
        await auditService.logPayment(
          sale?.customerId ?? '',
          customer?.name ?? 'Bilinmeyen Müşteri',
          amount,
          'Kısmi Ödeme ($method) - Satış ID: $saleId',
        );
      } catch (e) {
        debugPrint('Failed to log partial payment audit event: $e');
      }

      if (sale != null && sale.customerId.isNotEmpty) {
        ref.invalidate(customersControllerProvider);
        ref.invalidate(customerTransactionsProvider(sale.customerId));
        ref.invalidate(customerBalanceDetailsProvider(sale.customerId));
      }
      return _saleRepository.findAll();
    });
  }

  Future<void> refresh() async {
    await future;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      return _saleRepository.findAll();
    });
  }
}

final salesControllerProvider =
    AsyncNotifierProvider<SalesController, List<SaleEntity>>(() {
  return SalesController();
});

/// Per-sale detail provider
final saleDetailProvider =
    FutureProvider.family<SaleEntity?, String>((ref, saleId) async {
  final repo = await ref.watch(saleRepositoryProvider.future);
  return repo.findById(saleId);
});

// ─── Sales History — Paginated Controller ────────────────────────────────────

const _kSalesHistoryPageSize = 25;

/// Dedicated paginated controller for the Sales History page.
/// Keeps the existing [SalesController] untouched so that the sales flow,
/// dashboard, and reports pages are not affected.
class SalesHistoryController extends AsyncNotifier<List<SaleEntity>> {
  late ISaleRepository _repository;

  int _offset = 0;
  bool _hasMore = true;
  String? _searchQuery;

  bool get hasMore => _hasMore;

  @override
  FutureOr<List<SaleEntity>> build() async {
    _repository = await ref.watch(saleRepositoryProvider.future);
    _offset = 0;
    _hasMore = true;
    final page = await _repository.findFiltered(
      searchQuery: _searchQuery,
      limit: _kSalesHistoryPageSize,
      offset: 0,
    );
    _offset = page.length;
    _hasMore = (page.length == _kSalesHistoryPageSize);
    return page;
  }

  Future<void> applySearch(String? query) async {
    _searchQuery = (query == null || query.isEmpty) ? null : query;
    _offset = 0;
    _hasMore = true;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.findFiltered(
          searchQuery: _searchQuery,
          limit: _kSalesHistoryPageSize,
          offset: 0,
        ));
    _offset = state.valueOrNull?.length ?? 0;
    _hasMore = (_offset == _kSalesHistoryPageSize);
  }

  Future<void> loadNextPage() async {
    if (!_hasMore) return;
    final current = state.valueOrNull ?? [];
    final next = await _repository.findFiltered(
      searchQuery: _searchQuery,
      limit: _kSalesHistoryPageSize,
      offset: _offset,
    );
    if (next.length < _kSalesHistoryPageSize) _hasMore = false;
    _offset += next.length;
    state = AsyncValue.data([...current, ...next]);
  }

  Future<void> refresh() async {
    _offset = 0;
    _hasMore = true;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.findFiltered(
          searchQuery: _searchQuery,
          limit: _kSalesHistoryPageSize,
          offset: 0,
        ));
    _offset = state.valueOrNull?.length ?? 0;
    _hasMore = (_offset == _kSalesHistoryPageSize);
  }
}

final salesHistoryControllerProvider =
    AsyncNotifierProvider<SalesHistoryController, List<SaleEntity>>(() {
  return SalesHistoryController();
});
