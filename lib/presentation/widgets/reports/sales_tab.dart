import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/controllers/report_controller.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/presentation/widgets/revenue_bar_chart.dart';
import 'package:serenutos/presentation/widgets/reports/shared_report_widgets.dart';

class SalesTab extends ConsumerWidget {
  final DateRange range;

  const SalesTab({super.key, required this.range});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryVal = ref.watch(reportSummaryProvider(range));
    final dailyVal = ref.watch(dailyRevenueProvider(range));
    final categoryVal = ref.watch(categoryRevenueProvider(range));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(reportSummaryProvider(range));
        ref.invalidate(dailyRevenueProvider(range));
        ref.invalidate(categoryRevenueProvider(range));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary Cards
            summaryVal.when(
              data: (s) => _buildSummaryGrid(s),
              loading: () => _shimmerGrid(),
              error: (e, _) => buildErrorReportCard('Özet yüklenemedi: $e'),
            ),
            const SizedBox(height: 20),
            Card(
              color: Colors.white,
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey[200]!),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(Icons.print_outlined, color: POSColors.green),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Yazıcı Raporları',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            'Termal yazıcıdan gün içi (X) veya gün sonu (Z) raporu alın.',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final summary = summaryVal.value;
                        final categories = categoryVal.value;
                        final settings = ref.read(settingsNotifierProvider).value;

                        if (summary == null || categories == null || settings == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Veriler yukleniyor, lutfen bekleyin...'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        final hasPrinter = (settings.printerIp != null && settings.printerIp!.isNotEmpty) ||
                                           (settings.printerName != null && settings.printerName!.isNotEmpty);
                        if (!hasPrinter) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Lütfen Ayarlar sayfasından bir yazıcı tanımlayın.'),
                              backgroundColor: Colors.orange,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        try {
                          ref.read(printerServiceProvider).enqueue(
                            'X Raporu (${range.label})',
                            () => ref.read(printerServiceProvider).printXReport(
                              summary,
                              categories,
                              settings,
                            ),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('X Raporu yazdırma sırasına eklendi.'),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Yazdirma hatasi: $e'),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: POSColors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.print_outlined, size: 16),
                      label: const Text('X Raporu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final summary = summaryVal.value;
                        final categories = categoryVal.value;
                        final settings = ref.read(settingsNotifierProvider).value;

                        if (summary == null || categories == null || settings == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Veriler yukleniyor, lutfen bekleyin...'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        final hasPrinter = (settings.printerIp != null && settings.printerIp!.isNotEmpty) ||
                                           (settings.printerName != null && settings.printerName!.isNotEmpty);
                        if (!hasPrinter) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Lütfen Ayarlar sayfasından bir yazıcı tanımlayın.'),
                              backgroundColor: Colors.orange,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        try {
                          ref.read(printerServiceProvider).enqueue(
                            'Z Raporu',
                            () => ref.read(printerServiceProvider).printZReport(
                              summary,
                              categories,
                              settings,
                            ),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Z Raporu yazdırma sırasına eklendi.'),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Yazdirma hatasi: $e'),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E293B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.print_outlined, size: 16),
                      label: const Text('Z Raporu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Bar Chart
            ReportSectionHeader(
              title: 'Günlük Gelir',
              subtitle: range.label,
              icon: Icons.bar_chart,
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: dailyVal.when(
                  data: (data) => RevenueBarChart(data: data, height: 180),
                  loading: () => const SizedBox(
                    height: 220,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => buildErrorReportCard('Grafik yüklenemedi: $e'),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Category breakdown
            const ReportSectionHeader(
              title: 'Kategori Dağılımı',
              icon: Icons.donut_large,
            ),
            const SizedBox(height: 8),
            categoryVal.when(
              data: (cats) => cats.isEmpty
                  ? buildEmptyReportState('Kategori verisi yok')
                  : _buildCategoryList(cats),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => buildErrorReportCard('Kategori yüklenemedi: $e'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryGrid(ReportSummary s) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        ReportMetricCard(
          label: 'Toplam Gelir',
          value: '${formatReportCurrency(s.totalRevenue)} TL',
          icon: Icons.attach_money,
          color: POSColors.greenDark,
          bg: POSColors.greenLight,
        ),
        ReportMetricCard(
          label: 'Satış Adedi',
          value: '${s.totalSales}',
          icon: Icons.receipt_long_outlined,
          color: POSColors.green,
          bg: POSColors.greenLight,
        ),
        ReportMetricCard(
          label: 'Ortalama Sepet',
          value: '${formatReportCurrency(s.avgBasket)} TL',
          icon: Icons.shopping_basket_outlined,
          color: POSColors.amberDark,
          bg: POSColors.amberLight,
        ),
        ReportMetricCard(
          label: 'Tahsilat Oranı',
          value: '%${s.collectionRate.toStringAsFixed(1)}',
          icon: Icons.percent,
          color: s.collectionRate >= 80 ? POSColors.greenDark : POSColors.amberDark,
          bg: s.collectionRate >= 80 ? POSColors.greenLight : POSColors.amberLight,
          subtitle: 'Toplam Borç: ${formatReportCurrency(s.totalDebt)} TL',
        ),
      ],
    );
  }

  Widget _buildCategoryList(List<CategoryRevenue> cats) {
    final maxAmount = cats.fold<double>(0, (m, c) => c.totalAmount > m ? c.totalAmount : m);
    final colors = [
      POSColors.green,
      POSColors.amber,
      Colors.teal,
      Colors.orange,
      Colors.indigo,
      Colors.purple,
      Colors.red,
    ];

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: cats.asMap().entries.map((entry) {
            final i = entry.key;
            final cat = entry.value;
            final color = colors[i % colors.length];
            final barFrac = maxAmount == 0 ? 0.0 : cat.totalAmount / maxAmount;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(cat.categoryName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      ),
                      Text(
                        '%${cat.percentage.toStringAsFixed(1)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${formatReportCurrency(cat.totalAmount)} TL',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: barFrac,
                      minHeight: 5,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _shimmerGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: List.generate(4, (_) => Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
      )),
    );
  }
}
