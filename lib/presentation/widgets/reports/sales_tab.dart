import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';
import 'package:serenutos/presentation/controllers/report_controller.dart';
import 'package:serenutos/presentation/widgets/reports/shared_report_widgets.dart';
import 'package:serenutos/presentation/widgets/revenue_bar_chart.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';

class SalesTab extends ConsumerWidget {
  const SalesTab({super.key, required this.range});

  final DateRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(reportSummaryProvider(range));
    final daily = ref.watch(dailyRevenueProvider(range));
    final categories = ref.watch(categoryRevenueProvider(range));

    return ReportScrollView(
      onRefresh: () async {
        ref.invalidate(reportSummaryProvider(range));
        ref.invalidate(dailyRevenueProvider(range));
        ref.invalidate(categoryRevenueProvider(range));
      },
      children: [
        ReportSectionHeader(
          eyebrow: 'Dönem özeti',
          title: 'Satış performansı',
          subtitle: '${range.label} için temel işletme göstergeleri',
          icon: Icons.point_of_sale_rounded,
          trailing: ReportPill(
            label: range.label,
            icon: Icons.calendar_today_outlined,
          ),
        ),
        const SizedBox(height: 14),
        summary.when(
          data: (data) => _SummaryMetrics(summary: data),
          loading: () => const ReportLoadingCard(height: 150),
          error: (error, _) => ReportErrorCard(
            message: 'Satış özeti yüklenemedi.',
            onRetry: () => ref.invalidate(reportSummaryProvider(range)),
          ),
        ),
        const SizedBox(height: 18),
        _PrintActions(
          onPrintX: () => _printReport(
            context,
            ref,
            'X',
            summary.value,
            categories.value,
          ),
          onPrintZ: () => _printReport(
            context,
            ref,
            'Z',
            summary.value,
            categories.value,
          ),
        ),
        const SizedBox(height: 24),
        const ReportSectionHeader(
          eyebrow: 'Ciro',
          title: 'Günlük satış hareketi',
          subtitle: 'Seçili dönemde gün bazında gerçekleşen toplam gelir',
          icon: Icons.bar_chart_rounded,
        ),
        const SizedBox(height: 14),
        daily.when(
          data: (data) => data.isEmpty
              ? const ReportEmptyState(
                  icon: Icons.bar_chart_rounded,
                  title: 'Satış hareketi yok',
                  message: 'Bu dönem için grafik oluşturacak veri bulunamadı.',
                )
              : ReportPanel(
                  child: RevenueBarChart(data: data, height: 230),
                ),
          loading: () => const ReportLoadingCard(height: 260),
          error: (error, _) => ReportErrorCard(
            message: 'Günlük satış grafiği yüklenemedi.',
            onRetry: () => ref.invalidate(dailyRevenueProvider(range)),
          ),
        ),
        const SizedBox(height: 24),
        const ReportSectionHeader(
          eyebrow: 'Kategoriler',
          title: 'Ciro dağılımı',
          subtitle: 'Hangi kategorinin toplam satışa ne kadar katkı verdiği',
          icon: Icons.category_outlined,
        ),
        const SizedBox(height: 14),
        categories.when(
          data: (data) => data.isEmpty
              ? const ReportEmptyState(
                  icon: Icons.category_outlined,
                  title: 'Kategori verisi yok',
                  message: 'Seçili dönem için kategori satışı bulunamadı.',
                )
              : _CategoryList(categories: data),
          loading: () => const ReportLoadingCard(height: 260),
          error: (error, _) => ReportErrorCard(
            message: 'Kategori dağılımı yüklenemedi.',
            onRetry: () => ref.invalidate(categoryRevenueProvider(range)),
          ),
        ),
      ],
    );
  }

  Future<void> _printReport(
    BuildContext context,
    WidgetRef ref,
    String type,
    ReportSummary? summary,
    List<CategoryRevenue>? categories,
  ) async {
    final settings = ref.read(settingsNotifierProvider).value;
    if (summary == null || categories == null || settings == null) {
      _showMessage(context, 'Rapor verileri henüz hazır değil.');
      return;
    }

    final route = await ref
        .read(printingRepositoryProvider)
        .getRoute(PrintDocumentKind.receipt);
    if (!context.mounted) return;
    if (route == null) {
      _showMessage(
        context,
        'Önce Ayarlar bölümünden bir yazıcı tanımlayın.',
        warning: true,
      );
      return;
    }

    try {
      await ref
          .read(printingApplicationServiceProvider)
          .queueReport(type, summary, categories, settings);
      if (context.mounted) {
        _showMessage(context, '$type raporu yazdırma sırasına eklendi.');
      }
    } catch (error) {
      if (context.mounted) {
        _showMessage(context, 'Yazdırma işlemi başlatılamadı: $error',
            warning: true);
      }
    }
  }

  void _showMessage(
    BuildContext context,
    String message, {
    bool warning = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: warning ? POSColors.orange : POSColors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _SummaryMetrics extends StatelessWidget {
  const _SummaryMetrics({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ReportMetricCard(
        label: 'Toplam ciro',
        value: '${formatReportCurrency(summary.totalRevenue)} TL',
        icon: Icons.payments_outlined,
        color: POSColors.green,
        subtitle: '${summary.totalSales} tamamlanan satış',
      ),
      ReportMetricCard(
        label: 'Ortalama sepet',
        value: '${formatReportCurrency(summary.avgBasket)} TL',
        icon: Icons.shopping_basket_outlined,
        color: POSColors.blue,
        subtitle: 'Satış başına ortalama',
      ),
      ReportMetricCard(
        label: 'Tahsil edilen',
        value: '${formatReportCurrency(summary.totalCollected)} TL',
        icon: Icons.account_balance_wallet_outlined,
        color: POSColors.greenDark,
        subtitle:
            '%${summary.collectionRate.toStringAsFixed(1)} tahsilat oranı',
      ),
      ReportMetricCard(
        label: 'Vadeli satış',
        value: '${formatReportCurrency(summary.totalDebt)} TL',
        icon: Icons.schedule_outlined,
        color: summary.totalDebt > 0 ? POSColors.orange : POSColors.green,
        subtitle: '${summary.newCustomers} yeni müşteri',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 4
            : constraints.maxWidth >= 520
                ? 2
                : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: metrics
              .map((metric) => SizedBox(width: width, child: metric))
              .toList(),
        );
      },
    );
  }
}

class _PrintActions extends StatelessWidget {
  const _PrintActions({required this.onPrintX, required this.onPrintZ});

  final VoidCallback onPrintX;
  final VoidCallback onPrintZ;

  @override
  Widget build(BuildContext context) {
    return ReportPanel(
      color: POSColors.darkSurface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final copy = Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.print_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Yazıcı raporları',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Ara toplam için X, gün kapanışı için Z raporu alın.',
                      style: TextStyle(color: Color(0xFFB9C6C0), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          );
          final buttons = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PrintButton(label: 'X Raporu', onPressed: onPrintX),
              const SizedBox(width: 8),
              _PrintButton(
                label: 'Z Raporu',
                onPressed: onPrintZ,
                emphasized: true,
              ),
            ],
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                copy,
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerRight, child: buttons),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 18),
              buttons,
            ],
          );
        },
      ),
    );
  }
}

class _PrintButton extends StatelessWidget {
  const _PrintButton({
    required this.label,
    required this.onPressed,
    this.emphasized = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.print_outlined, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: emphasized ? POSColors.darkSurface : Colors.white,
        backgroundColor: emphasized ? POSColors.amber : Colors.transparent,
        side: BorderSide(
          color: emphasized
              ? POSColors.amber
              : Colors.white.withValues(alpha: .35),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.categories});

  final List<CategoryRevenue> categories;

  @override
  Widget build(BuildContext context) {
    final maxAmount = categories.fold<double>(
      0,
      (value, category) => math.max(value, category.totalAmount),
    );
    final colors = [
      POSColors.green,
      POSColors.amber,
      POSColors.blue,
      POSColors.orange,
      POSColors.greenDark,
    ];
    return ReportPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: categories.asMap().entries.map((entry) {
          final category = entry.value;
          final color = colors[entry.key % colors.length];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            category.categoryName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '%${category.percentage.toStringAsFixed(1)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${formatReportCurrency(category.totalAmount)} TL',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maxAmount == 0
                            ? 0
                            : category.totalAmount / maxAmount,
                        minHeight: 6,
                        color: color,
                        backgroundColor: POSColors.surfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (entry.key != categories.length - 1)
                const Divider(height: 1, indent: 16, endIndent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }
}
