// lib/presentation/controllers/installment_controller.dart
// Serenut OS — Installment Controller & Providers

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/installment_models.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';

/// Active installment plans for a given customer
final customerInstallmentPlansProvider =
    FutureProvider.family<List<CustomerInstallmentPlanEntity>, String>(
        (ref, customerId) async {
  final repo = ref.watch(installmentRepositoryProvider);
  return repo.getPlansForCustomer(customerId);
});

/// All installments for a given customer
final customerInstallmentsProvider =
    FutureProvider.family<List<CustomerInstallmentEntity>, String>(
        (ref, customerId) async {
  final repo = ref.watch(installmentRepositoryProvider);
  return repo.getInstallmentsForCustomer(customerId);
});

/// Installments for a specific plan
final planInstallmentsProvider =
    FutureProvider.family<List<CustomerInstallmentEntity>, String>(
        (ref, planId) async {
  final repo = ref.watch(installmentRepositoryProvider);
  return repo.getInstallmentsForPlan(planId);
});

/// Summary of overdue, today, and upcoming installments
final dueInstallmentsSummaryProvider =
    FutureProvider<Map<String, int>>((ref) async {
  final repo = ref.watch(installmentRepositoryProvider);
  return repo.getDueSummary();
});

/// Installments due within 7 days or overdue
final upcomingInstallmentsProvider =
    FutureProvider<List<CustomerInstallmentEntity>>((ref) async {
  final repo = ref.watch(installmentRepositoryProvider);
  return repo.getDueOrOverdueInstallments(daysAhead: 7);
});

/// Controller for installment operations
class InstallmentsNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  InstallmentsNotifier(this._ref) : super(const AsyncValue.data(null));

  Future<CustomerInstallmentPlanEntity> createPlan({
    required String customerId,
    required double totalAmount,
    double downPayment = 0.0,
    String downPaymentMethod = 'cash',
    required int installmentCount,
    required DateTime firstDueDate,
    String description = '',
    List<double>? customAmounts,
    List<DateTime>? customDueDates,
  }) async {
    state = const AsyncValue.loading();
    try {
      final repo = _ref.read(installmentRepositoryProvider);
      final plan = await repo.createPlan(
        customerId: customerId,
        totalAmount: totalAmount,
        downPayment: downPayment,
        downPaymentMethod: downPaymentMethod,
        installmentCount: installmentCount,
        firstDueDate: firstDueDate,
        description: description,
        customAmounts: customAmounts,
        customDueDates: customDueDates,
      );

      _invalidateAll(customerId);
      state = const AsyncValue.data(null);
      return plan;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> payInstallment({
    required String customerId,
    required String installmentId,
    required double amount,
    required String paymentMethod,
    String? note,
  }) async {
    state = const AsyncValue.loading();
    try {
      final repo = _ref.read(installmentRepositoryProvider);
      await repo.payInstallment(
        installmentId: installmentId,
        amount: amount,
        paymentMethod: paymentMethod,
        note: note,
      );

      _invalidateAll(customerId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> cancelPlan({
    required String planId,
    required String customerId,
  }) async {
    state = const AsyncValue.loading();
    try {
      final repo = _ref.read(installmentRepositoryProvider);
      await repo.cancelPlan(planId);

      _invalidateAll(customerId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  void _invalidateAll(String customerId) {
    _ref.invalidate(customerInstallmentPlansProvider(customerId));
    _ref.invalidate(customerInstallmentsProvider(customerId));
    _ref.invalidate(dueInstallmentsSummaryProvider);
    _ref.invalidate(upcomingInstallmentsProvider);

    _ref.invalidate(customerTransactionsProvider(customerId));
    _ref.invalidate(customerBalanceDetailsProvider(customerId));
    _ref.invalidate(customerDetailProvider(customerId));
    _ref.invalidate(customersControllerProvider);
    _ref.invalidate(customerBalanceSummaryProvider);
  }
}

final installmentsControllerProvider =
    StateNotifierProvider<InstallmentsNotifier, AsyncValue<void>>((ref) {
  return InstallmentsNotifier(ref);
});
