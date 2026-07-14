// lib/presentation/controllers/report_controller.dart
// Phase 2.3 — Analytics Engine Controller
// AsyncNotifier with date range state management
// Generated: 21 Jun 2026

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/domain/services/report_service.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';

// ════════════════════════════════════════════════════════════
// ReportController
// ════════════════════════════════════════════════════════════

class ReportController extends AsyncNotifier<FullReportData> {
  DateRange _range = DateRange.thisMonth();
  late ReportService _service;

  DateRange get currentRange => _range;

  @override
  FutureOr<FullReportData> build() async {
    _service = await ref.watch(reportServiceProvider.future);
    return _service.getFullReport(_range);
  }

  Future<void> setRange(DateRange range) async {
    await future;
    _range = range;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.getFullReport(_range));
  }

  Future<void> refresh() async {
    await future;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.getFullReport(_range));
  }
}

final reportControllerProvider =
    AsyncNotifierProvider<ReportController, FullReportData>(() {
  return ReportController();
});

// ════════════════════════════════════════════════════════════
// Family Providers (for individual sections that refresh independently)
// ════════════════════════════════════════════════════════════

/// Günlük gelir — bar chart
final dailyRevenueProvider =
    FutureProvider.family<List<DailyRevenue>, DateRange>(
  (ref, range) async {
    final service = await ref.watch(reportServiceProvider.future);
    return service.getRevenueChart(range);
  },
);

/// Kategori ciro
final categoryRevenueProvider =
    FutureProvider.family<List<CategoryRevenue>, DateRange>(
  (ref, range) async {
    final service = await ref.watch(reportServiceProvider.future);
    return service.getCategoryBreakdown(range);
  },
);

/// Top-10 ürün
final topProductsProvider =
    FutureProvider.family<List<ProductPerformance>, DateRange>(
  (ref, range) async {
    final service = await ref.watch(reportServiceProvider.future);
    return service.getTopProducts(range);
  },
);

/// Borç yaşlandırma (date-range independent)
final debtAgingProvider = FutureProvider<List<DebtAgingRow>>((ref) async {
  final service = await ref.watch(reportServiceProvider.future);
  return service.getDebtAging();
});

/// Aging özeti (4 bucket toplamı)
final agingSummaryProvider = FutureProvider<AgingSummary>((ref) async {
  final service = await ref.watch(reportServiceProvider.future);
  return service.getAgingSummary();
});

/// Dönem özeti
final reportSummaryProvider =
    FutureProvider.family<ReportSummary, DateRange>((ref, range) async {
  final service = await ref.watch(reportServiceProvider.future);
  return service.getSummary(range);
});
