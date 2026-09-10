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

/// DTO representing order metrics on the Dashboard
class DashboardOrderSummary {
  final int todayOrdersCount;
  final double todayOrdersRevenue;
  final int createdCount;
  final int preparingCount;
  final int shippedCount;
  final int deliveredCount;

  const DashboardOrderSummary({
    this.todayOrdersCount = 0,
    this.todayOrdersRevenue = 0.0,
    this.createdCount = 0,
    this.preparingCount = 0,
    this.shippedCount = 0,
    this.deliveredCount = 0,
  });
}

/// DTO representing recent orders on the Dashboard
class DashboardRecentOrder {
  final String id;
  final String orderNumber;
  final String customerName;
  final String customerPhone;
  final String status;
  final double totalAmount;
  final int itemCount;
  final DateTime createdAt;

  const DashboardRecentOrder({
    required this.id,
    required this.orderNumber,
    required this.customerName,
    required this.customerPhone,
    required this.status,
    required this.totalAmount,
    required this.itemCount,
    required this.createdAt,
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

  /// Fetches order metrics and status breakdown
  Future<DashboardOrderSummary> getOrderSummary();

  /// Fetches recent orders
  Future<List<DashboardRecentOrder>> getRecentOrders({int limit = 5});
}

/// SQLite Implementation of IDashboardRepository
class SqliteDashboardRepository implements IDashboardRepository {
  final DbGateway _gateway;

  SqliteDashboardRepository(this._gateway);

  @override
  Future<DashboardSummary> getTodaySummary() async {
    final now = DateTime.now();
    final todayDate =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
    final todayEnd =
        DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();

    // 1. Query pending orders count (bekleyen / hazırlanan aktif siparişler)
    final orderResult = await _gateway.rawQuery('''
      SELECT COUNT(*) as count 
      FROM orders 
      WHERE (is_deleted = 0 OR is_deleted IS NULL)
        AND status IN ('created', 'pending', 'preparing', 'ready', 'hazirlaniyor', 'yeni')
    ''');
    final pendingOrders = Sqflite.firstIntValue(orderResult) ?? 0;

    // 2. Query total receivables from customers (İşletmenin piyasadaki toplam vadeli alacağı)
    // Serenut'ta customer.balance < 0 müşterinin borçlu (işletmenin alacaklı) olduğunu belirtir
    final receivablesResult = await _gateway.rawQuery('''
      SELECT COALESCE(SUM(-balance), 0) as total_receivables 
      FROM customers 
      WHERE balance < 0
    ''');
    final totalReceivables =
        (receivablesResult.first['total_receivables'] as num?)?.toDouble() ??
            0.0;

    // 3. Query direct POS sales today (Kasa Satışları)
    // Sadece kasadan doğrudan yapılan ve iptal edilmemiş fiş/satış kayıtları
    final salesSummary = await _gateway.rawQuery('''
      SELECT 
        COUNT(*) AS total_sales,
        COALESCE(SUM(total_amount), 0) AS total_revenue,
        COALESCE(SUM(paid_amount), 0) AS total_collected,
        COALESCE(SUM(total_amount - paid_amount), 0) AS total_debt
      FROM sales
      WHERE status != 'cancelled'
        AND (
          substr(created_at, 1, 10) = ?
          OR DATE(created_at, 'localtime') = ?
          OR (created_at >= ? AND created_at <= ?)
        )
    ''', [todayDate, todayDate, todayStart, todayEnd]);

    final salesData = salesSummary.first;
    final posSalesCount = (salesData['total_sales'] as num?)?.toInt() ?? 0;
    final posRevenue = (salesData['total_revenue'] as num?)?.toDouble() ?? 0.0;
    final posPaid = (salesData['total_collected'] as num?)?.toDouble() ?? 0.0;
    final posDebt = (salesData['total_debt'] as num?)?.toDouble() ?? 0.0;

    // 4. Query total actual collections today (Bugün kasaya fiilen giren tüm tahsilat parası)
    // Satış anında ödenen peşinatlar + Müşteri cari/borç tahsilatları (type IN ('collection', 'payment'))
    double totalCollected = posPaid;
    try {
      final ftCollectionResult = await _gateway.rawQuery('''
        SELECT 
          COALESCE(SUM(
            CASE 
              WHEN type = 'sale' THEN paid_amount
              WHEN type IN ('collection', 'payment') THEN amount
              WHEN type = 'cancellation' THEN -paid_amount
              WHEN type = 'refund' THEN -paid_amount
              ELSE 0
            END
          ), 0) AS total_collected
        FROM financial_transactions
        WHERE (
          substr(created_at, 1, 10) = ?
          OR DATE(created_at, 'localtime') = ?
          OR (created_at >= ? AND created_at <= ?)
        )
      ''', [todayDate, todayDate, todayStart, todayEnd]);

      final ftCollected =
          (ftCollectionResult.first['total_collected'] as num?)?.toDouble() ??
              0.0;
      if (ftCollected > 0) {
        totalCollected = ftCollected;
      }
    } catch (_) {
      // Fallback to posPaid
    }

    return DashboardSummary(
      totalSalesToday: posSalesCount,
      todayRevenue: posRevenue,
      todayDebt: posDebt,
      todayCollected: totalCollected,
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

  @override
  Future<DashboardOrderSummary> getOrderSummary() async {
    final now = DateTime.now();
    final todayDate =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final todayStart =
        DateTime(now.year, now.month, now.day).toIso8601String();

    try {
      final rows = await _gateway.rawQuery('''
        SELECT 
          status,
          COUNT(*) AS cnt,
          SUM(CASE WHEN (substr(created_at, 1, 10) = ? OR DATE(created_at, 'localtime') = ? OR created_at >= ?) THEN 1 ELSE 0 END) AS today_cnt,
          SUM(CASE WHEN (substr(created_at, 1, 10) = ? OR DATE(created_at, 'localtime') = ? OR created_at >= ?) 
              THEN COALESCE(total_amount, (SELECT SUM(quantity * unit_price) FROM order_items WHERE order_id = orders.id), 0) 
              ELSE 0 END) AS today_rev
        FROM orders
        WHERE (is_deleted = 0 OR is_deleted IS NULL)
        GROUP BY status
      ''', [todayDate, todayDate, todayStart, todayDate, todayDate, todayStart]);

      int todayCount = 0;
      double todayRevenue = 0.0;
      int created = 0;
      int preparing = 0;
      int shipped = 0;
      int delivered = 0;

      for (final r in rows) {
        final status = (r['status'] as String? ?? '').toLowerCase();
        final count = (r['cnt'] as num?)?.toInt() ?? 0;
        final tCount = (r['today_cnt'] as num?)?.toInt() ?? 0;
        final tRev = (r['today_rev'] as num?)?.toDouble() ?? 0.0;

        // İptal edilmiş siparişler ciroya ve geçerli işlem adedine dahil edilmez
        if (status != 'cancelled' && status != 'iptal') {
          todayCount += tCount;
          todayRevenue += tRev;
        }

        switch (status) {
          case 'created':
          case 'pending':
          case 'yeni':
            created += count;
            break;
          case 'preparing':
          case 'hazirlaniyor':
            preparing += count;
            break;
          case 'shipped':
          case 'yolda':
          case 'kargoda':
            shipped += count;
            break;
          case 'delivered':
          case 'completed':
          case 'teslim':
            delivered += count;
            break;
        }
      }

      return DashboardOrderSummary(
        todayOrdersCount: todayCount,
        todayOrdersRevenue: todayRevenue,
        createdCount: created,
        preparingCount: preparing,
        shippedCount: shipped,
        deliveredCount: delivered,
      );
    } catch (_) {
      return const DashboardOrderSummary();
    }
  }

  @override
  Future<List<DashboardRecentOrder>> getRecentOrders({int limit = 5}) async {
    try {
      final rows = await _gateway.rawQuery('''
        SELECT 
          o.id,
          COALESCE(o.order_number, o.id) AS order_number,
          COALESCE(c.name, 'Müşteri') AS customer_name,
          COALESCE(c.phone, '') AS customer_phone,
          o.status,
          COALESCE(o.total_amount, 0) AS total_amount,
          (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) AS item_count,
          o.created_at
        FROM orders o
        LEFT JOIN customers c ON o.customer_id = c.id
        WHERE (o.is_deleted = 0 OR o.is_deleted IS NULL)
        ORDER BY o.created_at DESC
        LIMIT ?
      ''', [limit]);

      return rows.map((r) {
        return DashboardRecentOrder(
          id: r['id']?.toString() ?? '',
          orderNumber: r['order_number']?.toString() ?? '',
          customerName: r['customer_name']?.toString() ?? 'Müşteri',
          customerPhone: r['customer_phone']?.toString() ?? '',
          status: r['status']?.toString() ?? 'created',
          totalAmount: (r['total_amount'] as num?)?.toDouble() ?? 0.0,
          itemCount: (r['item_count'] as num?)?.toInt() ?? 0,
          createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ??
              DateTime.now(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
