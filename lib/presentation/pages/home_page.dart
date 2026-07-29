import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/services/dashboard_service.dart';
import 'package:serenutos/infrastructure/repositories/dashboard_repository.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/presentation/widgets/realtime_status_indicator.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    return Scaffold(
      backgroundColor: POSColors.surface,
      body: SafeArea(
        child: dashboard.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _DashboardError(
            message: error.toString(),
            onRetry: () => ref.invalidate(dashboardProvider),
          ),
          data: (data) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(dashboardProvider),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 16,
                      wide ? 28 : 16, 96),
                  children: [
                    _DashboardHeader(onReports: () =>
                        context.push(AppRoutes.reports)),
                    const SizedBox(height: 10),
                    const RealtimeStatusIndicator(compact: false),
                    const SizedBox(height: 16),
                    _KpiGrid(summary: data.summary),
                    const SizedBox(height: 16),
                    _AttentionStrip(data: data),
                    const SizedBox(height: 16),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _TrendCard(points: data.weeklyTrend),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: _TopProductsCard(
                                products: data.topProducts),
                          ),
                        ],
                      )
                    else ...[
                      _TrendCard(points: data.weeklyTrend),
                      const SizedBox(height: 16),
                      _TopProductsCard(products: data.topProducts),
                    ],
                    const SizedBox(height: 16),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _CategoryCard(items: data.categoryShares),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _RecentSalesCard(sales: data.recentSales),
                          ),
                        ],
                      )
                    else ...[
                      _CategoryCard(items: data.categoryShares),
                      const SizedBox(height: 16),
                      _RecentSalesCard(sales: data.recentSales),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.onReports});
  final VoidCallback onReports;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMMM EEEE', 'tr_TR').format(DateTime.now());
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('İşletme özeti',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900, color: POSColors.text)),
              const SizedBox(height: 3),
              Text(date,
                  style: const TextStyle(color: POSColors.textSecondary)),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: onReports,
          icon: const Icon(Icons.analytics_outlined, size: 18),
          label: const Text('Raporlar'),
        ),
      ],
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.summary});
  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final items = [
      ('Bugünkü satış', currency.format(summary.todayRevenue),
       '${summary.totalSalesToday} işlem', Icons.point_of_sale_rounded, POSColors.green),
      ('Tahsilat', currency.format(summary.todayCollected),
       'Bugün alınan', Icons.payments_rounded, POSColors.blue),
      ('Vadeli satış', currency.format(summary.todayDebt),
       'Bugünkü açık', Icons.schedule_rounded, POSColors.orange),
      ('Toplam alacak', currency.format(summary.totalReceivables),
       'Müşteri bakiyeleri', Icons.account_balance_wallet_rounded, POSColors.red),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900 ? 4 : 2;
      final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: items
            .map((item) => SizedBox(
                  width: width,
                  child: _KpiCard(
                    label: item.$1,
                    value: item.$2,
                    detail: item.$3,
                    icon: item.$4,
                    color: item.$5,
                  ),
                ))
            .toList(),
      );
    });
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value, required this.detail,
    required this.icon, required this.color});
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: POSColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(height: 12),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 12,
              fontWeight: FontWeight.w700, color: POSColors.text)),
          Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: POSColors.textSecondary)),
        ]),
      );
}

class _AttentionStrip extends StatelessWidget {
  const _AttentionStrip({required this.data});
  final DashboardData data;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: _AttentionTile(
          icon: Icons.pending_actions_rounded,
          label: 'Bekleyen sipariş',
          value: '${data.summary.pendingOrdersCount}',
          color: POSColors.orange,
          onTap: () => context.go(AppRoutes.orders),
        )),
        const SizedBox(width: 10),
        Expanded(child: _AttentionTile(
          icon: Icons.inventory_2_outlined,
          label: 'Kritik stok',
          value: '${data.lowStockProducts.length}',
          color: POSColors.red,
          onTap: () => context.go(AppRoutes.products),
        )),
      ]);
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({required this.icon, required this.label,
    required this.value, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(label, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(value, style: TextStyle(fontSize: 20,
                  color: color, fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
      );
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.points});
  final List<SalesTrendPoint> points;

  @override
  Widget build(BuildContext context) => _Panel(
        title: '7 günlük satış eğilimi',
        subtitle: 'Gerçekleşen satış cirosu',
        child: SizedBox(
          height: 220,
          child: points.isEmpty
              ? const _EmptyData()
              : LineChart(LineChartData(
                  minY: 0,
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= points.length) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(DateFormat('E', 'tr_TR').format(points[index].date),
                              style: const TextStyle(fontSize: 10)),
                        );
                      },
                    )),
                  ),
                  lineBarsData: [LineChartBarData(
                    isCurved: true,
                    color: POSColors.green,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true,
                        color: POSColors.green.withValues(alpha: .1)),
                    spots: [for (var i = 0; i < points.length; i++)
                      FlSpot(i.toDouble(), points[i].revenue)],
                  )],
                )),
        ),
      );
}

class _TopProductsCard extends StatelessWidget {
  const _TopProductsCard({required this.products});
  final List<DashboardProductPerformance> products;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'En çok satanlar',
        subtitle: 'Son 30 gün',
        child: products.isEmpty
            ? const SizedBox(height: 160, child: _EmptyData())
            : Column(children: products.take(5).map((product) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(radius: 15,
                    backgroundColor: POSColors.greenLight,
                    child: Text('${product.rank}', style: const TextStyle(
                      color: POSColors.greenDark, fontWeight: FontWeight.w800))),
                  title: Text(product.productName, maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                  subtitle: Text(product.category),
                  trailing: Text('${product.totalSold} adet',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                )).toList()),
      );
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.items});
  final List<DashboardCategoryShare> items;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Kategori dağılımı',
        subtitle: 'Son 30 günlük ciro payı',
        child: items.isEmpty
            ? const SizedBox(height: 140, child: _EmptyData())
            : Column(children: items.take(5).map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: Text(item.category,
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                      Text('%${item.percentage.toStringAsFixed(0)}'),
                    ]),
                    const SizedBox(height: 5),
                    LinearProgressIndicator(value: (item.percentage / 100).clamp(0, 1),
                      minHeight: 6, borderRadius: BorderRadius.circular(8)),
                  ]),
                )).toList()),
      );
}

class _RecentSalesCard extends StatelessWidget {
  const _RecentSalesCard({required this.sales});
  final List<dynamic> sales;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    return _Panel(
      title: 'Son satışlar',
      subtitle: 'En yeni tamamlanan işlemler',
      child: sales.isEmpty
          ? const SizedBox(height: 140, child: _EmptyData())
          : Column(children: sales.take(5).map((sale) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_outlined, color: POSColors.green),
                title: Text(currency.format(sale.totalAmount),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(DateFormat('dd.MM HH:mm').format(sale.createdAt)),
                trailing: Text(sale.paymentMethod.toString()),
              )).toList()),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: POSColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16,
              fontWeight: FontWeight.w900, color: POSColors.text)),
          Text(subtitle, style: const TextStyle(fontSize: 11,
              color: POSColors.textSecondary)),
          const SizedBox(height: 16),
          child,
        ]),
      );
}

class _EmptyData extends StatelessWidget {
  const _EmptyData();
  @override
  Widget build(BuildContext context) => const Center(child: Text('Henüz veri yok',
      style: TextStyle(color: POSColors.textSecondary)));
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [SizedBox(height: MediaQuery.sizeOf(context).height * .7,
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: POSColors.red),
            const SizedBox(height: 12),
            const Text('Ana sayfa verileri alınamadı'),
            const SizedBox(height: 6),
            Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Tekrar dene')),
          ])))],
      );
}
