// lib/domain/models/analytics_models.dart
// Serenut Platform — Cloud BI Analytics Models (Sprint 7)
// Data representations for dashboard KPIs, trends, stock, finance, staff and branches.
// Created: 04 Jul 2026

class DashboardMetrics {
  final double todayRevenue;
  final int todayOrders;
  final int avgBasket;
  final double weeklyRevenue;
  final double weeklyGrowth;
  final double monthlyRevenue;
  final double monthlyGrowth;
  final TopProductStat? topProduct;
  final int? busiestHour;
  final PaymentBreakdown paymentBreakdown;

  const DashboardMetrics({
    required this.todayRevenue,
    required this.todayOrders,
    required this.avgBasket,
    required this.weeklyRevenue,
    required this.weeklyGrowth,
    required this.monthlyRevenue,
    required this.monthlyGrowth,
    this.topProduct,
    this.busiestHour,
    required this.paymentBreakdown,
  });

  factory DashboardMetrics.fromJson(Map<String, dynamic> json) {
    final today = json['today'] as Map<String, dynamic>? ?? {};
    final week = json['week'] as Map<String, dynamic>? ?? {};
    final month = json['month'] as Map<String, dynamic>? ?? {};
    final top = json['topProduct'] as Map<String, dynamic>?;
    final breakdown = json['paymentBreakdown'] as Map<String, dynamic>? ?? {};

    return DashboardMetrics(
      todayRevenue: (today['revenue'] as num? ?? 0.0).toDouble(),
      todayOrders: today['orders'] as int? ?? 0,
      avgBasket: today['avgBasket'] as int? ?? 0,
      weeklyRevenue: (week['revenue'] as num? ?? 0.0).toDouble(),
      weeklyGrowth: (week['growth_pct'] as num? ?? 0.0).toDouble(),
      monthlyRevenue: (month['revenue'] as num? ?? 0.0).toDouble(),
      monthlyGrowth: (month['growth_pct'] as num? ?? 0.0).toDouble(),
      topProduct: top != null ? TopProductStat.fromJson(top) : null,
      busiestHour: json['busiestHour'] as int?,
      paymentBreakdown: PaymentBreakdown.fromJson(breakdown),
    );
  }
}

class TopProductStat {
  final String name;
  final double quantity;

  const TopProductStat({required this.name, required this.quantity});

  factory TopProductStat.fromJson(Map<String, dynamic> json) => TopProductStat(
        name: json['name'] as String? ?? '',
        quantity: (json['qty'] as num? ?? 0.0).toDouble(),
      );
}

class PaymentBreakdown {
  final int cash;
  final int card;
  final int credit;

  const PaymentBreakdown(
      {required this.cash, required this.card, required this.credit});

  factory PaymentBreakdown.fromJson(Map<String, dynamic> json) =>
      PaymentBreakdown(
        cash: json['cash'] as int? ?? 0,
        card: json['card'] as int? ?? 0,
        credit: json['credit'] as int? ?? 0,
      );
}

class SalesTrendPoint {
  final String time;
  final double revenue;
  final int count;

  const SalesTrendPoint(
      {required this.time, required this.revenue, required this.count});

  factory SalesTrendPoint.fromJson(Map<String, dynamic> json) =>
      SalesTrendPoint(
        time: json['time'] as String? ?? '',
        revenue: (json['revenue'] as num? ?? 0.0).toDouble(),
        count: json['count'] as int? ?? 0,
      );
}

class ProductStat {
  final String id;
  final String name;
  final String? category;
  final int stock;
  final double unitsSold;
  final double revenue;

  const ProductStat({
    required this.id,
    required this.name,
    this.category,
    required this.stock,
    required this.unitsSold,
    required this.revenue,
  });

  factory ProductStat.fromJson(Map<String, dynamic> json) => ProductStat(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        category: json['category'] as String?,
        stock: json['stock'] as int? ?? 0,
        unitsSold: (json['unitsSold'] as num? ?? 0.0).toDouble(),
        revenue: (json['revenue'] as num? ?? 0.0).toDouble(),
      );
}

class StockAnalytics {
  final List<CriticalStockItem> criticalItems;
  final int criticalCount;

  const StockAnalytics(
      {required this.criticalItems, required this.criticalCount});

  factory StockAnalytics.fromJson(Map<String, dynamic> json) {
    final list = json['criticalItems'] as List<dynamic>? ?? [];
    return StockAnalytics(
      criticalItems:
          list.map((item) => CriticalStockItem.fromJson(item)).toList(),
      criticalCount: json['criticalCount'] as int? ?? 0,
    );
  }
}

class CriticalStockItem {
  final String id;
  final String name;
  final String? category;
  final int quantity;

  const CriticalStockItem(
      {required this.id,
      required this.name,
      this.category,
      required this.quantity});

  factory CriticalStockItem.fromJson(Map<String, dynamic> json) =>
      CriticalStockItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        category: json['category'] as String?,
        quantity: json['quantity'] as int? ?? 0,
      );
}

class FinanceAnalytics {
  final double receivables;
  final double payables;
  final List<DebtorStat> topDebtors;

  const FinanceAnalytics(
      {required this.receivables,
      required this.payables,
      required this.topDebtors});

  factory FinanceAnalytics.fromJson(Map<String, dynamic> json) {
    final list = json['topDebtors'] as List<dynamic>? ?? [];
    return FinanceAnalytics(
      receivables: (json['receivables'] as num? ?? 0.0).toDouble(),
      payables: (json['payables'] as num? ?? 0.0).toDouble(),
      topDebtors: list.map((item) => DebtorStat.fromJson(item)).toList(),
    );
  }
}

class DebtorStat {
  final String id;
  final String name;
  final String? phone;
  final double balance;

  const DebtorStat(
      {required this.id,
      required this.name,
      this.phone,
      required this.balance});

  factory DebtorStat.fromJson(Map<String, dynamic> json) => DebtorStat(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String?,
        balance: (json['balance'] as num? ?? 0.0).toDouble(),
      );
}

class BranchStat {
  final String id;
  final String name;
  final double revenue;
  final int orders;

  const BranchStat(
      {required this.id,
      required this.name,
      required this.revenue,
      required this.orders});

  factory BranchStat.fromJson(Map<String, dynamic> json) => BranchStat(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        revenue: (json['revenue'] as num? ?? 0.0).toDouble(),
        orders: json['orders'] as int? ?? 0,
      );
}

class StaffStat {
  final String id;
  final String name;
  final int salesCount;
  final double revenue;

  const StaffStat(
      {required this.id,
      required this.name,
      required this.salesCount,
      required this.revenue});

  factory StaffStat.fromJson(Map<String, dynamic> json) => StaffStat(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        salesCount: json['salesCount'] as int? ?? 0,
        revenue: (json['revenue'] as num? ?? 0.0).toDouble(),
      );
}
