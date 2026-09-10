part of '../reports_page.dart';

class _AnalyticsTab extends ConsumerWidget {
  const _AnalyticsTab({required this.range});

  final DateRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(dailyRevenueProvider(range));
    final categories = ref.watch(categoryRevenueProvider(range));
    return ReportScrollView(
      onRefresh: () async {
        ref.invalidate(dailyRevenueProvider(range));
        ref.invalidate(categoryRevenueProvider(range));
      },
      children: [
        const ReportSectionHeader(
          eyebrow: 'Zaman serisi',
          title: 'Satış ve alacak eğilimi',
          subtitle: 'Günlük ciro ile vadeli satışların karşılaştırması',
          icon: Icons.show_chart_rounded,
        ),
        const SizedBox(height: 14),
        daily.when(
          skipLoadingOnReload: true,
          data: (data) => data.isEmpty
              ? const ReportEmptyState(
                  icon: Icons.show_chart_rounded,
                  title: 'Grafik için veri yok',
                  message: 'Seçili dönemde tamamlanmış satış bulunamadı.',
                )
              : ReportPanel(child: _SalesTrendChart(data: data)),
          loading: () => const ReportLoadingCard(height: 300),
          error: (error, _) => ReportErrorCard(
            message: 'Satış eğilimi yüklenemedi.',
            onRetry: () => ref.invalidate(dailyRevenueProvider(range)),
          ),
        ),
        const SizedBox(height: 24),
        const ReportSectionHeader(
          eyebrow: 'Dağılım',
          title: 'Kategori katkısı',
          subtitle: 'Toplam cironun kategorilere göre paylaşımı',
          icon: Icons.donut_large_rounded,
        ),
        const SizedBox(height: 14),
        categories.when(
          skipLoadingOnReload: true,
          data: (data) => data.isEmpty
              ? const ReportEmptyState(
                  icon: Icons.category_outlined,
                  title: 'Kategori verisi yok',
                  message: 'Bu dönem için kategori dağılımı oluşturulamadı.',
                )
              : _CategoryContribution(categories: data),
          loading: () => const ReportLoadingCard(height: 260),
          error: (error, _) => ReportErrorCard(
            message: 'Kategori dağılımı yüklenemedi.',
            onRetry: () => ref.invalidate(categoryRevenueProvider(range)),
          ),
        ),
      ],
    );
  }
}

class _SalesTrendChart extends StatelessWidget {
  const _SalesTrendChart({required this.data});

  final List<DailyRevenue> data;

  @override
  Widget build(BuildContext context) {
    final interval = math.max(1, (data.length / 5).ceil()).toDouble();
    final maxY =
        data.fold<double>(0, (value, row) => math.max(value, row.totalAmount));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            ReportLegend(label: 'Toplam ciro', color: POSColors.green),
            ReportLegend(label: 'Vadeli satış', color: POSColors.amber),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 240,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY == 0 ? 1 : maxY * 1.15,
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: POSColors.border,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    getTitlesWidget: (value, meta) => Text(
                      _compactNumber(value),
                      style: const TextStyle(
                        color: POSColors.textDisabled,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: interval,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= data.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          DateFormat('dd.MM').format(data[index].date),
                          style: const TextStyle(
                            color: POSColors.textDisabled,
                            fontSize: 9,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => POSColors.darkSurface,
                  getTooltipItems: (spots) => spots
                      .map((spot) => LineTooltipItem(
                            '${formatReportCurrency(spot.y)} TL',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ))
                      .toList(),
                ),
              ),
              lineBarsData: [
                _line(data.map((row) => row.totalAmount).toList(),
                    POSColors.green,
                    fill: true),
                _line(data.map((row) => row.debtAmount).toList(),
                    POSColors.amber),
              ],
            ),
          ),
        ),
      ],
    );
  }

  LineChartBarData _line(List<double> values, Color color,
      {bool fill = false}) {
    return LineChartBarData(
      spots: values
          .asMap()
          .entries
          .map((entry) => FlSpot(entry.key.toDouble(), entry.value))
          .toList(),
      isCurved: values.length > 2,
      curveSmoothness: .22,
      color: color,
      barWidth: 3,
      dotData: FlDotData(show: values.length <= 10),
      belowBarData: BarAreaData(
        show: fill,
        color: color.withValues(alpha: .08),
      ),
    );
  }
}

class _CategoryContribution extends StatelessWidget {
  const _CategoryContribution({required this.categories});

  final List<CategoryRevenue> categories;

  @override
  Widget build(BuildContext context) {
    final colors = [
      POSColors.green,
      POSColors.amber,
      POSColors.blue,
      POSColors.orange,
      POSColors.greenDark,
      POSColors.textSecondary,
    ];
    final visible = categories.take(6).toList();
    return ReportPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chart = SizedBox(
            width: 190,
            height: 190,
            child: PieChart(
              PieChartData(
                centerSpaceRadius: 48,
                sectionsSpace: 3,
                sections: visible.asMap().entries.map((entry) {
                  final category = entry.value;
                  return PieChartSectionData(
                    value: category.totalAmount,
                    color: colors[entry.key % colors.length],
                    radius: 30,
                    showTitle: false,
                  );
                }).toList(),
              ),
            ),
          );
          final legend = Column(
            children: visible.asMap().entries.map((entry) {
              final category = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: colors[entry.key % colors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        category.categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '%${category.percentage.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: POSColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${formatReportCurrency(category.totalAmount)} TL',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
          if (constraints.maxWidth < 650) {
            return Column(children: [chart, const SizedBox(height: 8), legend]);
          }
          return Row(
            children: [
              chart,
              const SizedBox(width: 28),
              Expanded(child: legend),
            ],
          );
        },
      ),
    );
  }
}

String _rangeDescription(DateRange range) {
  final format = DateFormat('d MMM', 'tr_TR');
  if (range.preset == DateRangePreset.today) return 'Bugünün';
  return '${format.format(range.from)} – ${format.format(range.to)}';
}

String _compactNumber(double value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)} Mn';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)} B';
  return value.toStringAsFixed(0);
}
