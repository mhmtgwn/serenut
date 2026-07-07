// lib/domain/services/dashboard_service.dart
// Phase 3 — Dashboard Domain Service
// Generated: 21 Jun 2026

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/repositories/dashboard_repository.dart';

/// Aggregated data wrapper for the Dashboard
class DashboardData {
  final DashboardSummary summary;
  final List<SalesTrendPoint> weeklyTrend;
  final List<DashboardCategoryShare> categoryShares;
  final List<DashboardProductPerformance> topProducts;
  final List<SaleEntity> recentSales;
  final List<ProductEntity> lowStockProducts;

  const DashboardData({
    required this.summary,
    required this.weeklyTrend,
    required this.categoryShares,
    required this.topProducts,
    required this.recentSales,
    required this.lowStockProducts,
  });
}

/// Service layer to orchestrate dashboard query executions
class DashboardService {
  final IDashboardRepository _repo;

  DashboardService(this._repo);

  /// Performs concurrent calls to fetch all necessary metrics for the dashboard
  Future<DashboardData> getDashboardData() async {
    final results = await Future.wait([
      _repo.getTodaySummary(),
      _repo.getWeeklyTrend(),
      _repo.getTopProducts(limit: 5),
      _repo.getCategoryShares(),
      _repo.getRecentSales(limit: 5),
      _repo.getLowStockProducts(threshold: 5, limit: 5),
    ]);

    return DashboardData(
      summary: results[0] as DashboardSummary,
      weeklyTrend: results[1] as List<SalesTrendPoint>,
      topProducts: results[2] as List<DashboardProductPerformance>,
      categoryShares: results[3] as List<DashboardCategoryShare>,
      recentSales: results[4] as List<SaleEntity>,
      lowStockProducts: results[5] as List<ProductEntity>,
    );
  }
}
