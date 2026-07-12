// lib/infrastructure/repositories/report_repository.dart
// Phase 2.3 — Analytics Engine
// Report DTOs and IReportRepository interface
// Generated: 21 Jun 2026

/// ════════════════════════════════════════════════════════════
/// Date Range Value Class
/// ════════════════════════════════════════════════════════════
library;


class DateRange {
  final DateTime from;
  final DateTime to;
  final DateRangePreset preset;

  const DateRange._({
    required this.from,
    required this.to,
    required this.preset,
  });

  /// Today (00:00 – 23:59)
  factory DateRange.today() {
    final now = DateTime.now();
    return DateRange._(
      from: DateTime(now.year, now.month, now.day),
      to: DateTime(now.year, now.month, now.day, 23, 59, 59),
      preset: DateRangePreset.today,
    );
  }

  /// This week (Monday – Sunday)
  factory DateRange.thisWeek() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    return DateRange._(
      from: DateTime(monday.year, monday.month, monday.day),
      to: DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59),
      preset: DateRangePreset.thisWeek,
    );
  }

  /// This month (1st – last day)
  factory DateRange.thisMonth() {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0);
    return DateRange._(
      from: DateTime(now.year, now.month, 1),
      to: DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59),
      preset: DateRangePreset.thisMonth,
    );
  }

  /// Last 3 months
  factory DateRange.last3Months() {
    final now = DateTime.now();
    final threeMonthsAgo = DateTime(now.year, now.month - 3, 1);
    return DateRange._(
      from: threeMonthsAgo,
      to: DateTime(now.year, now.month, now.day, 23, 59, 59),
      preset: DateRangePreset.last3Months,
    );
  }

  /// Custom range
  factory DateRange.custom(DateTime from, DateTime to) {
    return DateRange._(
      from: DateTime(from.year, from.month, from.day),
      to: DateTime(to.year, to.month, to.day, 23, 59, 59),
      preset: DateRangePreset.custom,
    );
  }

  String toIsoFrom() => from.toIso8601String();
  String toIsoTo() => to.toIso8601String();

  String get label {
    switch (preset) {
      case DateRangePreset.today:
        return 'Bugün';
      case DateRangePreset.thisWeek:
        return 'Bu Hafta';
      case DateRangePreset.thisMonth:
        return 'Bu Ay';
      case DateRangePreset.last3Months:
        return 'Son 3 Ay';
      case DateRangePreset.custom:
        return 'Özel Aralık';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.from == from && other.to == to;

  @override
  int get hashCode => from.hashCode ^ to.hashCode;
}

enum DateRangePreset { today, thisWeek, thisMonth, last3Months, custom }

/// ════════════════════════════════════════════════════════════
/// Report DTOs
/// ════════════════════════════════════════════════════════════

/// Günlük gelir verisi (bar chart için)
class DailyRevenue {
  final DateTime date;
  final double totalAmount;
  final int saleCount;
  final double cashAmount;
  final double debtAmount;

  const DailyRevenue({
    required this.date,
    required this.totalAmount,
    required this.saleCount,
    required this.cashAmount,
    required this.debtAmount,
  });

  double get collectionRate =>
      totalAmount == 0 ? 0 : (cashAmount / totalAmount * 100);
}

/// Kategori bazlı ciro
class CategoryRevenue {
  final String categoryId;
  final String categoryName;
  final double totalAmount;
  final int saleCount;
  final double percentage; // yüzde (toplama göre)

  const CategoryRevenue({
    required this.categoryId,
    required this.categoryName,
    required this.totalAmount,
    required this.saleCount,
    required this.percentage,
  });
}

/// Ürün performansı
class ProductPerformance {
  final String productId;
  final String productName;
  final String categoryName;
  final int totalSold;
  final double totalRevenue;
  final double avgPrice;
  final int rank;

  const ProductPerformance({
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.totalSold,
    required this.totalRevenue,
    required this.avgPrice,
    required this.rank,
  });
}

/// Borç yaşlandırma satırı (müşteri başına)
class DebtAgingRow {
  final String customerId;
  final String customerName;
  final double current; // 0-30 gün
  final double days31to60;
  final double days61to90;
  final double over90;

  const DebtAgingRow({
    required this.customerId,
    required this.customerName,
    required this.current,
    required this.days31to60,
    required this.days61to90,
    required this.over90,
  });

  double get total => current + days31to60 + days61to90 + over90;
  bool get hasOverdue => days31to60 > 0 || days61to90 > 0 || over90 > 0;
}

/// Dönem özeti (tek kart grubu için)
class ReportSummary {
  final double totalRevenue;
  final int totalSales;
  final double totalDebt;
  final double totalCollected;
  final double avgBasket;
  final int newCustomers;
  final DateRange range;

  const ReportSummary({
    required this.totalRevenue,
    required this.totalSales,
    required this.totalDebt,
    required this.totalCollected,
    required this.avgBasket,
    required this.newCustomers,
    required this.range,
  });

  double get collectionRate =>
      totalRevenue == 0 ? 0 : (totalCollected / totalRevenue * 100);
}

/// ════════════════════════════════════════════════════════════
/// IReportRepository Interface
/// ════════════════════════════════════════════════════════════

abstract class IReportRepository {
  /// Günlük gelir listesi (bar chart için)
  Future<List<DailyRevenue>> getDailyRevenue(DateRange range);

  /// Kategori bazlı ciro
  Future<List<CategoryRevenue>> getCategoryRevenue(DateRange range);

  /// Top-N ürün performansı (gelire göre sıralı)
  Future<List<ProductPerformance>> getTopProducts(DateRange range, {int limit = 10});

  /// Müşteri borç yaşlandırma tablosu
  Future<List<DebtAgingRow>> getDebtAging();

  /// Dönem özet metrikleri
  Future<ReportSummary> getSummary(DateRange range);

  /// KDV Oranlarına göre matrah ve vergi kırılımını döndürür.
  Future<List<Map<String, dynamic>>> getVatBreakdown(DateTime start, DateTime end);
}

