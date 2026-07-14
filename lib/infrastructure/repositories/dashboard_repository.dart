// lib/infrastructure/repositories/dashboard_repository.dart
// Phase 3 — Dashboard Repository and SQLite Engine
// Generated: 21 Jun 2026

import 'package:sqflite/sqflite.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

/// DTO representing the high-level summary cards on the Dashboard
class DashboardSummary {
  final int totalSalesToday;
  final double todayRevenue;
  final double todayDebt;
  final double todayCollected;
  final int pendingOrdersCount;
  final double totalReceivables;

  const DashboardSummary({
    required this.totalSalesToday,
    required this.todayRevenue,
    required this.todayDebt,
    required this.todayCollected,
    required this.pendingOrdersCount,
    required this.totalReceivables,
  });
}

/// DTO representing a single data point in the sales trend line chart
class SalesTrendPoint {
  final DateTime date;
  final double revenue;
  final int saleCount;

  const SalesTrendPoint({
    required this.date,
    required this.revenue,
    required this.saleCount,
  });
}

/// DTO representing a category ciro share for pie charts
class DashboardCategoryShare {
  final String category;
  final double totalAmount;
  final double percentage;

  const DashboardCategoryShare({
    required this.category,
    required this.totalAmount,
    required this.percentage,
  });
}

/// DTO representing top product performances for bar charts
class DashboardProductPerformance {
  final String productId;
  final String productName;
  final String category;
  final int totalSold;
  final double totalRevenue;
  final int rank;

  const DashboardProductPerformance({
    required this.productId,
    required this.productName,
    required this.category,
    required this.totalSold,
    required this.totalRevenue,
    required this.rank,
  });
}

/// Interface for Dashboard data extraction
abstract class IDashboardRepository {
  /// Fetches summary metrics for today
  Future<DashboardSummary> getTodaySummary();

  /// Fetches daily sales for the last 7 days
  Future<List<SalesTrendPoint>> getWeeklyTrend();

  /// Fetches top products in the last 30 days
  Future<List<DashboardProductPerformance>> getTopProducts({int limit = 5});

  /// Fetches category ciro shares in the last 30 days
  Future<List<DashboardCategoryShare>> getCategoryShares();

  /// Fetches recent 5 sales
  Future<List<SaleEntity>> getRecentSales({int limit = 5});

  /// Fetches critical low stock products
  Future<List<ProductEntity>> getLowStockProducts(
      {int threshold = 5, int limit = 5});
}

/// SQLite Implementation of IDashboardRepository
class SqliteDashboardRepository implements IDashboardRepository {
  final DbGateway _gateway;

  SqliteDashboardRepository(this._gateway);

  @override
  Future<DashboardSummary> getTodaySummary() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
    final todayEnd =
        DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();

    // 1. Query pending orders count
    final orderResult = await _gateway.rawQuery('''
      SELECT COUNT(*) as count 
      FROM orders 
      WHERE status IN ('created', 'preparing', 'ready')
    ''');
    final pendingOrders = Sqflite.firstIntValue(orderResult) ?? 0;

    // Query total receivables (Toplam Alacak)
    final receivablesResult = await _gateway.rawQuery('''
      SELECT COALESCE(ABS(SUM(balance)), 0) as total_receivables 
      FROM customers 
      WHERE balance < 0
    ''');
    final totalReceivables =
        (receivablesResult.first['total_receivables'] as num?)?.toDouble() ??
            0.0;

    // 2. Query today's sales from v_financial_ledger first (as primary financial ledger)
    final ftSummary = await _gateway.rawQuery('''
      SELECT 
        COALESCE(SUM(debit), 0) AS total_revenue,
        COALESCE(SUM(credit), 0) AS total_collected,
        COALESCE(SUM(debit - credit), 0) AS total_debt,
        COALESCE(SUM(CASE WHEN type = 'sale' THEN 1 ELSE -1 END), 0) AS total_sales
      FROM v_financial_ledger
      WHERE type IN ('sale', 'cancellation')
        AND created_at >= ?
        AND created_at <= ?
    ''', [todayStart, todayEnd]);

    final ftData = ftSummary.first;
    final ftSalesCount = (ftData['total_sales'] as num?)?.toInt() ?? 0;

    if (ftSalesCount > 0) {
      return DashboardSummary(
        totalSalesToday: ftSalesCount,
        todayRevenue: (ftData['total_revenue'] as num?)?.toDouble() ?? 0.0,
        todayDebt: (ftData['total_debt'] as num?)?.toDouble() ?? 0.0,
        todayCollected: (ftData['total_collected'] as num?)?.toDouble() ?? 0.0,
        pendingOrdersCount: pendingOrders,
        totalReceivables: totalReceivables,
      );
    }

    // 3. Fallback: Query today's sales from the sales table directly
    final salesSummary = await _gateway.rawQuery('''
      SELECT 
        COALESCE(SUM(total_amount), 0) AS total_revenue,
        COALESCE(SUM(paid_amount), 0) AS total_collected,
        COALESCE(SUM(total_amount - paid_amount), 0) AS total_debt,
        COUNT(*) AS total_sales
      FROM sales
      WHERE status != 'cancelled'
        AND created_at >= ?
        AND created_at <= ?
    ''', [todayStart, todayEnd]);

    final salesData = salesSummary.first;
    final salesCount = (salesData['total_sales'] as num?)?.toInt() ?? 0;

    return DashboardSummary(
      totalSalesToday: salesCount,
      todayRevenue: (salesData['total_revenue'] as num?)?.toDouble() ?? 0.0,
      todayDebt: (salesData['total_debt'] as num?)?.toDouble() ?? 0.0,
      todayCollected: (salesData['total_collected'] as num?)?.toDouble() ?? 0.0,
      pendingOrdersCount: pendingOrders,
      totalReceivables: totalReceivables,
    );
  }

  @override
  Future<List<SalesTrendPoint>> getWeeklyTrend() async {
    final now = DateTime.now();
    // 7 days ago start
    final sevenDaysAgo = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    final startDate = sevenDaysAgo.toIso8601String();

    // Query daily revenue trend from v_financial_ledger
    final ftRows = await _gateway.rawQuery('''
      SELECT 
        DATE(created_at) AS day,
        SUM(debit) AS total,
        SUM(CASE WHEN type = 'sale' THEN 1 ELSE -1 END) AS cnt
      FROM v_financial_ledger
      WHERE type IN ('sale', 'cancellation')
        AND created_at >= ?
      GROUP BY DATE(created_at)
      ORDER BY day ASC
    ''', [startDate]);

    // Query from sales table as fallback/complement
    final salesRows = await _gateway.rawQuery('''
      SELECT 
        DATE(created_at) AS day,
        SUM(total_amount) AS total,
        COUNT(*) AS cnt
      FROM sales
      WHERE status != 'cancelled'
        AND created_at >= ?
      GROUP BY DATE(created_at)
      ORDER BY day ASC
    ''', [startDate]);

    // Merge both sources
    final Map<String, Map<String, dynamic>> merged = {};
    for (final r in salesRows) {
      final day = r['day'] as String;
      merged[day] = {
        'total': (r['total'] as num?)?.toDouble() ?? 0.0,
        'cnt': (r['cnt'] as num?)?.toInt() ?? 0,
      };
    }
    for (final r in ftRows) {
      final day = r['day'] as String;
      merged[day] = {
        'total': (r['total'] as num?)?.toDouble() ?? 0.0,
        'cnt': (r['cnt'] as num?)?.toInt() ?? 0,
      };
    }

    // Prepare complete list of last 7 days to fill missing dates with 0
    final List<SalesTrendPoint> trend = [];
    for (int i = 0; i < 7; i++) {
      final date = sevenDaysAgo.add(Duration(days: i));
      final dateKey = DateTime(date.year, date.month, date.day)
          .toIso8601String()
          .substring(0, 10);

      final data = merged[dateKey];
      trend.add(SalesTrendPoint(
        date: date,
        revenue: data != null ? data['total'] as double : 0.0,
        saleCount: data != null ? data['cnt'] as int : 0,
      ));
    }

    return trend;
  }

  @override
  Future<List<DashboardProductPerformance>> getTopProducts(
      {int limit = 5}) async {
    final now = DateTime.now();
    final thirtyDaysAgo = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 29))
        .toIso8601String();

    final rows = await _gateway.rawQuery('''
      SELECT 
        si.product_id AS pid,
        COALESCE(p.name, 'Bilinmeyen Ürün') AS pname,
        COALESCE(p.category, 'Genel') AS category,
        SUM(si.quantity) AS sold,
        SUM(si.subtotal) AS revenue
      FROM sale_items si
      JOIN products p ON si.product_id = p.id
      JOIN sales s ON si.sale_id = s.id
      WHERE s.status != 'cancelled'
        AND s.created_at >= ?
      GROUP BY si.product_id
      ORDER BY revenue DESC
      LIMIT ?
    ''', [thirtyDaysAgo, limit]);

    return rows.asMap().entries.map((entry) {
      final idx = entry.key;
      final r = entry.value;
      return DashboardProductPerformance(
        productId: r['pid'] as String? ?? '',
        productName: r['pname'] as String? ?? '',
        category: r['category'] as String? ?? 'Genel',
        totalSold: (r['sold'] as num?)?.toInt() ?? 0,
        totalRevenue: (r['revenue'] as num?)?.toDouble() ?? 0.0,
        rank: idx + 1,
      );
    }).toList();
  }

  @override
  Future<List<DashboardCategoryShare>> getCategoryShares() async {
    final now = DateTime.now();
    final thirtyDaysAgo = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 29))
        .toIso8601String();

    final rows = await _gateway.rawQuery('''
      SELECT 
        COALESCE(p.category, 'Diğer') AS category,
        SUM(si.subtotal) AS total
      FROM sale_items si
      JOIN products p ON si.product_id = p.id
      JOIN sales s ON si.sale_id = s.id
      WHERE s.status != 'cancelled'
        AND s.created_at >= ?
      GROUP BY p.category
      ORDER BY total DESC
    ''', [thirtyDaysAgo]);

    if (rows.isEmpty) return [];

    final grandTotal = rows.fold<double>(
        0.0, (sum, r) => sum + ((r['total'] as num?)?.toDouble() ?? 0.0));

    return rows.map((r) {
      final category = r['category'] as String? ?? 'Diğer';
      final total = (r['total'] as num?)?.toDouble() ?? 0.0;
      final percentage = grandTotal == 0 ? 0.0 : (total / grandTotal) * 100;
      return DashboardCategoryShare(
        category: category,
        totalAmount: total,
        percentage: percentage,
      );
    }).toList();
  }

  @override
  Future<List<SaleEntity>> getRecentSales({int limit = 5}) async {
    final rows = await _gateway.query(
      'sales',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map((row) => SaleEntity.fromMap(row)).toList();
  }

  @override
  Future<List<ProductEntity>> getLowStockProducts(
      {int threshold = 5, int limit = 5}) async {
    final rows = await _gateway.query(
      'products',
      where: 'quantity <= ? AND is_active = 1',
      whereArgs: [threshold],
      orderBy: 'quantity ASC',
      limit: limit,
    );
    return rows.map((row) => ProductEntity.fromMap(row)).toList();
  }
}
