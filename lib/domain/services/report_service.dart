// lib/domain/services/report_service.dart
// Phase 2.3 — Analytics Engine Service Layer
// Pure aggregation & business logic over IReportRepository
// Generated: 21 Jun 2026

import 'package:serenutos/infrastructure/repositories/report_repository.dart';

/// ════════════════════════════════════════════════════════════
/// ReportService
/// ════════════════════════════════════════════════════════════
///
/// Single-responsibility: data aggregation for reports.
/// Does NOT write any data. Read-only.
/// Intentionally separate from SalesService to avoid God-Service.

class ReportService {
  final IReportRepository _repo;

  ReportService(this._repo);

  // ──────────────────────────────────────────────────────────
  // Sales Tab
  // ──────────────────────────────────────────────────────────

  /// Dönem özeti — dashboard summary cards
  Future<ReportSummary> getSummary(DateRange range) {
    return _repo.getSummary(range);
  }

  /// Günlük gelir listesi — bar chart
  Future<List<DailyRevenue>> getRevenueChart(DateRange range) {
    return _repo.getDailyRevenue(range);
  }

  /// Kategori ciro breakdown — pie / bar list
  Future<List<CategoryRevenue>> getCategoryBreakdown(DateRange range) {
    return _repo.getCategoryRevenue(range);
  }

  // ──────────────────────────────────────────────────────────
  // Products Tab
  // ──────────────────────────────────────────────────────────

  /// Top-10 ürün (gelire göre)
  Future<List<ProductPerformance>> getTopProducts(DateRange range,
      {int limit = 10}) {
    return _repo.getTopProducts(range, limit: limit);
  }

  // ──────────────────────────────────────────────────────────
  // Customers Tab (Debt Aging)
  // ──────────────────────────────────────────────────────────

  /// Borç yaşlandırma — tüm aktif borçlu müşteriler
  Future<List<DebtAgingRow>> getDebtAging() {
    return _repo.getDebtAging();
  }

  /// Aging özeti — 4 bucket toplamı
  Future<AgingSummary> getAgingSummary() async {
    final rows = await _repo.getDebtAging();
    if (rows.isEmpty) {
      return const AgingSummary(
        total0to30: 0,
        total31to60: 0,
        total61to90: 0,
        totalOver90: 0,
        affectedCustomers: 0,
      );
    }

    return AgingSummary(
      total0to30: rows.fold(0.0, (s, r) => s + r.current),
      total31to60: rows.fold(0.0, (s, r) => s + r.days31to60),
      total61to90: rows.fold(0.0, (s, r) => s + r.days61to90),
      totalOver90: rows.fold(0.0, (s, r) => s + r.over90),
      affectedCustomers: rows.length,
    );
  }

  // ──────────────────────────────────────────────────────────
  // Convenience: full report state in one call
  // ──────────────────────────────────────────────────────────
  Future<FullReportData> getFullReport(DateRange range) async {
    final results = await Future.wait([
      _repo.getSummary(range),
      _repo.getDailyRevenue(range),
      _repo.getCategoryRevenue(range),
      _repo.getTopProducts(range),
      _repo.getDebtAging(),
    ]);

    final debtRows = results[4] as List<DebtAgingRow>;

    return FullReportData(
      summary: results[0] as ReportSummary,
      dailyRevenue: results[1] as List<DailyRevenue>,
      categoryRevenue: results[2] as List<CategoryRevenue>,
      topProducts: results[3] as List<ProductPerformance>,
      debtAging: debtRows,
      agingSummary: AgingSummary(
        total0to30: debtRows.fold(0.0, (s, r) => s + r.current),
        total31to60: debtRows.fold(0.0, (s, r) => s + r.days31to60),
        total61to90: debtRows.fold(0.0, (s, r) => s + r.days61to90),
        totalOver90: debtRows.fold(0.0, (s, r) => s + r.over90),
        affectedCustomers: debtRows.length,
      ),
      range: range,
    );
  }
}

/// ════════════════════════════════════════════════════════════
/// Aggregated Data Classes
/// ════════════════════════════════════════════════════════════

class AgingSummary {
  final double total0to30;
  final double total31to60;
  final double total61to90;
  final double totalOver90;
  final int affectedCustomers;

  const AgingSummary({
    required this.total0to30,
    required this.total31to60,
    required this.total61to90,
    required this.totalOver90,
    required this.affectedCustomers,
  });

  double get grandTotal => total0to30 + total31to60 + total61to90 + totalOver90;
}

class FullReportData {
  final ReportSummary summary;
  final List<DailyRevenue> dailyRevenue;
  final List<CategoryRevenue> categoryRevenue;
  final List<ProductPerformance> topProducts;
  final List<DebtAgingRow> debtAging;
  final AgingSummary agingSummary;
  final DateRange range;

  const FullReportData({
    required this.summary,
    required this.dailyRevenue,
    required this.categoryRevenue,
    required this.topProducts,
    required this.debtAging,
    required this.agingSummary,
    required this.range,
  });
}
