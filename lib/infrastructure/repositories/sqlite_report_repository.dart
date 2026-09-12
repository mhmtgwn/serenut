// lib/infrastructure/repositories/sqlite_report_repository.dart
// Phase 2.3 — Analytics Engine SQLite Implementation
// Uses raw SQL aggregation queries against existing schema
// Generated: 21 Jun 2026

import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';

class SqliteReportRepository implements IReportRepository {
  final DbGateway _gateway;

  SqliteReportRepository(this._gateway);

  // ──────────────────────────────────────────────────────────
  // 1. Günlük Gelir (bar chart verisi)
  // ──────────────────────────────────────────────────────────
  @override
  Future<List<DailyRevenue>> getDailyRevenue(DateRange range) async {
    // Try v_financial_ledger first (Phase 2 records), fallback to sales table
    final ftRows = await _gateway.rawQuery('''
      SELECT 
        DATE(created_at) AS day,
        SUM(debit) AS total,
        SUM(CASE WHEN type = 'sale' THEN 1 ELSE -1 END) AS cnt,
        SUM(credit) AS cash,
        SUM(debit - credit) AS debt
      FROM v_financial_ledger
      WHERE type IN ('sale', 'cancellation')
        AND created_at >= ?
        AND created_at <= ?
      GROUP BY DATE(created_at)
      ORDER BY day ASC
    ''', [range.toIsoFrom(), range.toIsoTo()]);

    // Also query legacy sales table for completeness
    final salesRows = await _gateway.rawQuery('''
      SELECT 
        DATE(created_at) AS day,
        SUM(total_amount) AS total,
        COUNT(*) AS cnt,
        SUM(paid_amount) AS cash,
        SUM(total_amount - paid_amount) AS debt
      FROM sales
      WHERE status != 'cancelled'
        AND created_at >= ?
        AND created_at <= ?
      GROUP BY DATE(created_at)
      ORDER BY day ASC
    ''', [range.toIsoFrom(), range.toIsoTo()]);

    // Merge both sources by date key
    final Map<String, Map<String, dynamic>> merged = {};

    for (final row in salesRows) {
      final day = (row['day'] ?? '').toString();
      if (day.isEmpty) continue;
      merged[day] = {
        'day': day,
        'total': (row['total'] as num?)?.toDouble() ?? 0.0,
        'cnt': (row['cnt'] as num?)?.toInt() ?? 0,
        'cash': (row['cash'] as num?)?.toDouble() ?? 0.0,
        'debt': (row['debt'] as num?)?.toDouble() ?? 0.0,
      };
    }

    for (final row in ftRows) {
      final day = (row['day'] ?? '').toString();
      if (day.isEmpty) continue;
      if (merged.containsKey(day)) {
        // Prefer financial_transactions data (more accurate)
        merged[day] = {
          'day': day,
          'total': (row['total'] as num?)?.toDouble() ?? 0.0,
          'cnt': (row['cnt'] as num?)?.toInt() ?? 0,
          'cash': (row['cash'] as num?)?.toDouble() ?? 0.0,
          'debt': (row['debt'] as num?)?.toDouble() ?? 0.0,
        };
      } else {
        merged[day] = {
          'day': day,
          'total': (row['total'] as num?)?.toDouble() ?? 0.0,
          'cnt': (row['cnt'] as num?)?.toInt() ?? 0,
          'cash': (row['cash'] as num?)?.toDouble() ?? 0.0,
          'debt': (row['debt'] as num?)?.toDouble() ?? 0.0,
        };
      }
    }

    final sortedKeys = merged.keys.toList()..sort();
    return sortedKeys.map((day) {
      final m = merged[day]!;
      return DailyRevenue(
        date: DateTime.parse(day),
        totalAmount: m['total'] as double,
        saleCount: m['cnt'] as int,
        cashAmount: m['cash'] as double,
        debtAmount: m['debt'] as double,
      );
    }).toList();
  }

  // ──────────────────────────────────────────────────────────
  // 2. Kategori Bazlı Ciro
  // ──────────────────────────────────────────────────────────
  @override
  Future<List<CategoryRevenue>> getCategoryRevenue(DateRange range) async {
    final rows = await _gateway.rawQuery('''
      WITH combined_items AS (
        SELECT 
          si.product_id AS product_id,
          si.sale_id AS source_id,
          si.subtotal AS subtotal
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        WHERE s.status != 'cancelled'
          AND s.created_at >= ?
          AND s.created_at <= ?
        UNION ALL
        SELECT 
          oi.product_id AS product_id,
          oi.order_id AS source_id,
          (oi.quantity * oi.unit_price) AS subtotal
        FROM order_items oi
        JOIN orders o ON oi.order_id = o.id
        WHERE (o.is_deleted = 0 OR o.is_deleted IS NULL)
          AND o.status != 'cancelled'
          AND o.created_at >= ?
          AND o.created_at <= ?
      )
      SELECT 
        COALESCE(NULLIF(TRIM(p.category), ''), 'unknown') AS cat_id,
        COALESCE(NULLIF(TRIM(p.category), ''), 'Genel') AS cat_name,
        SUM(ci.subtotal) AS total,
        COUNT(DISTINCT ci.source_id) AS cnt
      FROM combined_items ci
      LEFT JOIN products p ON ci.product_id = p.id
      GROUP BY COALESCE(NULLIF(TRIM(p.category), ''), 'Genel')
      ORDER BY total DESC
    ''', [range.toIsoFrom(), range.toIsoTo(), range.toIsoFrom(), range.toIsoTo()]);

    // Also try categories table for names
    final categoryNames = <String, String>{};
    try {
      final catRows =
          await _gateway.query('categories', columns: ['id', 'name']);
      for (final r in catRows) {
        categoryNames[r['id'].toString()] = r['name'] as String;
      }
    } catch (_) {
      // categories table may be empty or differ in schema
    }

    if (rows.isEmpty) return [];

    final grandTotal = rows.fold<double>(
      0.0,
      (sum, r) => sum + ((r['total'] as num?)?.toDouble() ?? 0.0),
    );

    return rows.map((row) {
      final catId = row['cat_id'] as String? ?? 'unknown';
      final catName = categoryNames[catId] ?? 'Kategori $catId';
      final total = (row['total'] as num?)?.toDouble() ?? 0.0;
      final cnt = (row['cnt'] as num?)?.toInt() ?? 0;
      return CategoryRevenue(
        categoryId: catId,
        categoryName: catName,
        totalAmount: total,
        saleCount: cnt,
        percentage: grandTotal == 0 ? 0 : (total / grandTotal * 100),
      );
    }).toList();
  }

  // ──────────────────────────────────────────────────────────
  // 3. Top-N Ürün Performansı
  // ──────────────────────────────────────────────────────────
  @override
  Future<List<ProductPerformance>> getTopProducts(DateRange range,
      {int limit = 10}) async {
    final rows = await _gateway.rawQuery('''
      WITH combined_items AS (
        SELECT 
          si.product_id AS product_id,
          si.quantity AS quantity,
          si.subtotal AS subtotal,
          si.unit_price AS unit_price
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        WHERE s.status != 'cancelled'
          AND s.created_at >= ?
          AND s.created_at <= ?
        UNION ALL
        SELECT 
          oi.product_id AS product_id,
          oi.quantity AS quantity,
          (oi.quantity * oi.unit_price) AS subtotal,
          oi.unit_price AS unit_price
        FROM order_items oi
        JOIN orders o ON oi.order_id = o.id
        WHERE (o.is_deleted = 0 OR o.is_deleted IS NULL)
          AND o.status != 'cancelled'
          AND o.created_at >= ?
          AND o.created_at <= ?
      )
      SELECT 
        CAST(ci.product_id AS TEXT) AS pid,
        COALESCE(p.name, 'Bilinmeyen Ürün') AS pname,
        COALESCE(CAST(p.category AS TEXT), '') AS cat_id,
        SUM(ci.quantity) AS sold,
        SUM(ci.subtotal) AS revenue,
        AVG(ci.unit_price) AS avg_price
      FROM combined_items ci
      LEFT JOIN products p ON ci.product_id = p.id
      GROUP BY ci.product_id
      ORDER BY revenue DESC
      LIMIT ?
    ''', [
      range.toIsoFrom(),
      range.toIsoTo(),
      range.toIsoFrom(),
      range.toIsoTo(),
      limit,
    ]);

    // Resolve category names
    final categoryNames = <String, String>{};
    try {
      final catRows =
          await _gateway.query('categories', columns: ['id', 'name']);
      for (final r in catRows) {
        categoryNames[r['id'].toString()] = r['name'] as String;
      }
    } catch (_) {}

    return rows.asMap().entries.map((entry) {
      final i = entry.key;
      final row = entry.value;
      final catId = row['cat_id'] as String? ?? '';
      return ProductPerformance(
        productId: row['pid'] as String? ?? '',
        productName: row['pname'] as String? ?? 'Bilinmeyen',
        categoryName: categoryNames[catId] ?? 'Genel',
        totalSold: (row['sold'] as num?)?.toInt() ?? 0,
        totalRevenue: (row['revenue'] as num?)?.toDouble() ?? 0.0,
        avgPrice: (row['avg_price'] as num?)?.toDouble() ?? 0.0,
        rank: i + 1,
      );
    }).toList();
  }

  // ──────────────────────────────────────────────────────────
  // 4. Borç Yaşlandırma (Debt Aging)
  // ──────────────────────────────────────────────────────────
  @override
  Future<List<DebtAgingRow>> getDebtAging() async {
    // Strategy: use customers.balance (current debt) + v_financial_ledger aging
    final rows = await _gateway.rawQuery('''
      SELECT 
        c.id AS cid,
        c.name AS cname,
        SUM(CASE 
          WHEN CAST((julianday('now') - julianday(ft.created_at)) AS INTEGER) <= 30 
          THEN (ft.debit - ft.credit) ELSE 0 END) AS d0_30,
        SUM(CASE 
          WHEN CAST((julianday('now') - julianday(ft.created_at)) AS INTEGER) BETWEEN 31 AND 60 
          THEN (ft.debit - ft.credit) ELSE 0 END) AS d31_60,
        SUM(CASE 
          WHEN CAST((julianday('now') - julianday(ft.created_at)) AS INTEGER) BETWEEN 61 AND 90 
          THEN (ft.debit - ft.credit) ELSE 0 END) AS d61_90,
        SUM(CASE 
          WHEN CAST((julianday('now') - julianday(ft.created_at)) AS INTEGER) > 90 
          THEN (ft.debit - ft.credit) ELSE 0 END) AS d_over90
      FROM v_financial_ledger ft
      JOIN customers c ON CAST(ft.customer_id AS TEXT) = CAST(c.id AS TEXT)
      WHERE ft.type = 'sale' AND (ft.debit - ft.credit) > 0
      GROUP BY c.id
      HAVING (d0_30 + d31_60 + d61_90 + d_over90) > 0
      ORDER BY d_over90 DESC, d61_90 DESC
    ''');

    // Also include customers with negative balance but no FT records
    final balanceRows = await _gateway.rawQuery('''
      SELECT id, name, balance
      FROM customers
      WHERE balance < 0 AND is_active = 1
    ''');

    final ftCustomerIds = rows.map((r) => r['cid'].toString()).toSet();

    final result = rows.map((row) {
      return DebtAgingRow(
        customerId: row['cid'].toString(),
        customerName: _safeName(row['cname']),
        current: (row['d0_30'] as num?)?.toDouble() ?? 0.0,
        days31to60: (row['d31_60'] as num?)?.toDouble() ?? 0.0,
        days61to90: (row['d61_90'] as num?)?.toDouble() ?? 0.0,
        over90: (row['d_over90'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();

    // Add customers from balance table not already in FT result
    for (final row in balanceRows) {
      final id = row['id'].toString();
      if (!ftCustomerIds.contains(id)) {
        final debt = -((row['balance'] as num?)?.toDouble() ?? 0.0);
        if (debt > 0) {
          result.add(DebtAgingRow(
            customerId: id,
            customerName: _safeName(row['name']),
            current: debt,
            days31to60: 0,
            days61to90: 0,
            over90: 0,
          ));
        }
      }
    }

    return result;
  }

  // ──────────────────────────────────────────────────────────
  // 5. Dönem Özeti
  // ──────────────────────────────────────────────────────────
  @override
  Future<ReportSummary> getSummary(DateRange range) async {
    // Revenue & sales from v_financial_ledger view
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
    ''', [range.toIsoFrom(), range.toIsoTo()]);

    // Fallback: also check sales table
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
    ''', [range.toIsoFrom(), range.toIsoTo()]);

    // New customers in period
    final newCustomers = await _gateway.rawQuery('''
      SELECT COUNT(*) AS cnt FROM customers
      WHERE created_at >= ? AND created_at <= ? AND is_active = 1
    ''', [range.toIsoFrom(), range.toIsoTo()]);

    // Use financial_transactions if it has data, else sales table
    final ftData = ftSummary.first;
    final salesData = salesSummary.first;

    final ftSales = (ftData['total_sales'] as num?)?.toInt() ?? 0;
    final usesFT = ftSales > 0;

    final totalRevenue = usesFT
        ? (ftData['total_revenue'] as num?)?.toDouble() ?? 0.0
        : (salesData['total_revenue'] as num?)?.toDouble() ?? 0.0;
    final totalCollected = usesFT
        ? (ftData['total_collected'] as num?)?.toDouble() ?? 0.0
        : (salesData['total_collected'] as num?)?.toDouble() ?? 0.0;
    final totalDebt = usesFT
        ? (ftData['total_debt'] as num?)?.toDouble() ?? 0.0
        : (salesData['total_debt'] as num?)?.toDouble() ?? 0.0;
    final totalSales =
        usesFT ? ftSales : (salesData['total_sales'] as num?)?.toInt() ?? 0;

    return ReportSummary(
      totalRevenue: totalRevenue,
      totalSales: totalSales,
      totalDebt: totalDebt,
      totalCollected: totalCollected,
      avgBasket: totalSales == 0 ? 0 : totalRevenue / totalSales,
      newCustomers: (newCustomers.first['cnt'] as num?)?.toInt() ?? 0,
      range: range,
    );
  }

  // ──────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────
  String _safeName(dynamic val) {
    if (val == null) return 'Bilinmeyen';
    final s = val.toString().trim();
    return s.isEmpty ? 'Bilinmeyen' : s;
  }

  @override
  Future<List<Map<String, dynamic>>> getVatBreakdown(
      DateTime start, DateTime end) async {
    return await _gateway.rawQuery('''
      SELECT 
        COALESCE(p.vat, 0) as vat_rate,
        SUM(si.subtotal / (1.0 + COALESCE(p.vat, 0) / 100.0)) as taxable_amount,
        SUM(si.subtotal - (si.subtotal / (1.0 + COALESCE(p.vat, 0) / 100.0))) as vat_amount
      FROM sale_items si
      JOIN products p ON si.product_id = p.id
      JOIN sales s ON si.sale_id = s.id
      WHERE s.status != 'cancelled'
        AND s.created_at >= ?
        AND s.created_at <= ?
      GROUP BY COALESCE(p.vat, 0)
    ''', [start.toIso8601String(), end.toIso8601String()]);
  }
}
