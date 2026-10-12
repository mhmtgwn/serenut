// lib/presentation/controllers/report_controller.dart
// Phase 2.3 — Analytics Engine Controller
// AsyncNotifier with date range state management
// Generated: 21 Jun 2026

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/domain/services/report_service.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';

import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:serenutos/domain/services/document_export_service.dart';

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

  Future<void> exportReport({
    required String type,
    required DateRange range,
  }) async {
    final exportService = DocumentExportService();
    String filePath;
    String subject;

    switch (type) {
      case 'sales':
        final repo = await ref.read(saleRepositoryProvider.future);
        final sales = await repo.getSalesByDateRange(
          range.from,
          range.to,
        );
        filePath = await exportService.exportSalesReportExcel(
          sales,
          range.label,
          'TL',
        );
        subject = '${range.label} Satış Raporu';
        await exportService.shareFile(filePath, subject);
      case 'stock':
        final repo = await ref.read(productRepositoryProvider.future);
        filePath = await exportService.exportStockReportExcel(
          await repo.findAll(),
        );
        await exportService.shareFile(filePath, 'Stok Raporu');
      case 'end_of_day':
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        final salesRepo = await ref.read(saleRepositoryProvider.future);
        final dashboardRepo =
            await ref.read(dashboardRepositoryProvider.future);
        final summary = await dashboardRepo.getTodaySummary();
        filePath = await exportService.exportEndOfDayReportExcel(
          date: now,
          totalRevenue: summary.todayRevenue,
          totalCollected: summary.todayCollected,
          totalDebt: summary.todayDebt,
          salesCount: summary.totalSalesToday,
          sales: await salesRepo.getSalesByDateRange(start, end),
          currency: 'TL',
        );
        subject = 'Gün Sonu Raporu - ${DateFormat('dd.MM.yyyy').format(now)}';
        await exportService.shareFile(filePath, subject);
      case 'vat':
        final repo = await ref.read(reportRepositoryProvider.future);
        filePath = await exportService.exportVatReportExcel(
          startDate: range.from,
          endDate: range.to,
          vatSummaryRows: await repo.getVatBreakdown(
            range.from,
            range.to,
          ),
          currency: 'TL',
        );
        await exportService.shareFile(filePath, 'KDV Matrah Raporu');
      default:
        if (!type.startsWith('cloud_')) return;
        final reportType = type.substring('cloud_'.length);
        final file = await ref
            .read(cloudAnalyticsRepositoryProvider)
            .exportReportCsv(type: reportType);
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Bulut Raporu - $reportType',
        );
    }
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
