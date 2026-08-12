import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/services/document_export_service.dart';
import 'package:serenutos/domain/services/report_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';
import 'package:serenutos/presentation/controllers/report_controller.dart';
import 'package:serenutos/presentation/widgets/product_image.dart';
import 'package:serenutos/presentation/widgets/reports/sales_tab.dart';
import 'package:serenutos/presentation/widgets/reports/shared_report_widgets.dart';
import 'package:serenutos/providers/auth_provider.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:share_plus/share_plus.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  DateRange _selectedRange = DateRange.thisMonth();
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _selectRange(DateRange range) {
    setState(() => _selectedRange = range);
    ref.read(reportControllerProvider.notifier).setRange(range);
  }

  Future<void> _exportReport(String type) async {
    setState(() => _isExporting = true);
    try {
      final exportService = DocumentExportService();
      String filePath;
      String subject;

      switch (type) {
        case 'sales':
          final repo = await ref.read(saleRepositoryProvider.future);
          final sales = await repo.getSalesByDateRange(
            _selectedRange.from,
            _selectedRange.to,
          );
          filePath = await exportService.exportSalesReportExcel(
            sales,
            _selectedRange.label,
            'TL',
          );
          subject = '${_selectedRange.label} Satış Raporu';
          await exportService.shareFile(filePath, subject);
        case 'stock':
          final repo = await ref.read(productRepositoryProvider.future);
          filePath = await exportService.exportStockReportExcel(
            await repo.findAll(),
          );
          await exportService.shareFile(filePath, 'Stok Raporu');
        case 'end_of_day':
          final now = DateTime.now();
          final start = DateTime(now.year, now.month, now.day);
          final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
          final salesRepo = await ref.read(saleRepositoryProvider.future);
          final dashboardRepo =
              await ref.read(dashboardRepositoryProvider.future);
          final summary = await dashboardRepo.getTodaySummary();
          filePath = await exportService.exportEndOfDayReportExcel(
            date: now,
            totalRevenue: summary.todayRevenue,
            totalCollected: summary.todayCollected,
            totalDebt: summary.todayDebt,
            salesCount: summary.totalSalesToday,
            sales: await salesRepo.getSalesByDateRange(start, end),
            currency: 'TL',
          );
          subject = 'Gün Sonu Raporu - ${DateFormat('dd.MM.yyyy').format(now)}';
          await exportService.shareFile(filePath, subject);
        case 'vat':
          final repo = await ref.read(reportRepositoryProvider.future);
          filePath = await exportService.exportVatReportExcel(
            startDate: _selectedRange.from,
            endDate: _selectedRange.to,
            vatSummaryRows: await repo.getVatBreakdown(
              _selectedRange.from,
              _selectedRange.to,
            ),
            currency: 'TL',
          );
          await exportService.shareFile(filePath, 'KDV Matrah Raporu');
        default:
          if (!type.startsWith('cloud_')) return;
          final reportType = type.substring('cloud_'.length);
          final file = await ref
              .read(cloudAnalyticsRepositoryProvider)
              .exportReportCsv(type: reportType);
          await Share.shareXFiles(
            [XFile(file.path)],
            subject: 'Bulut Raporu - $reportType',
          );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rapor oluşturulamadı: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(authProvider).token != null;
    return Scaffold(
      backgroundColor: POSColors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            return Column(
              children: [
                _ReportsTopBar(
                  compact: compact,
                  range: _selectedRange,
                  isExporting: _isExporting,
                  isOnline: isOnline,
                  onExport: _exportReport,
                ),
                _ReportsControls(
                  compact: compact,
                  selectedRange: _selectedRange,
                  tabController: _tabController,
                  onRangeSelected: _selectRange,
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1440),
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          SalesTab(range: _selectedRange),
                          _ProductsTab(range: _selectedRange),
                          const _ReceivablesTab(),
                          _AnalyticsTab(range: _selectedRange),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReportsTopBar extends StatelessWidget {
  const _ReportsTopBar({
    required this.compact,
    required this.range,
    required this.isExporting,
    required this.isOnline,
    required this.onExport,
  });

  final bool compact;
  final DateRange range;
  final bool isExporting;
  final bool isOnline;
  final ValueChanged<String> onExport;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: POSColors.card,
        border: Border(bottom: BorderSide(color: POSColors.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 24,
              vertical: compact ? 10 : 16,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  tooltip: 'Geri',
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: POSColors.greenLight,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: const Icon(
                    Icons.query_stats_rounded,
                    color: POSColors.greenDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Raporlar',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (!compact)
                        Text(
                          '${_rangeDescription(range)} işletme görünümü',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (!compact)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: _LiveDataBadge(),
                  ),
                if (isExporting)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  _ExportMenu(
                    compact: compact,
                    isOnline: isOnline,
                    onSelected: onExport,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveDataBadge extends StatelessWidget {
  const _LiveDataBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: POSColors.greenLight,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: POSColors.green),
          SizedBox(width: 6),
          Text(
            'Güncel veri',
            style: TextStyle(
              color: POSColors.greenDark,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportMenu extends StatelessWidget {
  const _ExportMenu({
    required this.compact,
    required this.isOnline,
    required this.onSelected,
  });

  final bool compact;
  final bool isOnline;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Raporu dışa aktar',
      onSelected: onSelected,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'sales',
          child: _ExportItem(
            icon: Icons.receipt_long_outlined,
            title: 'Satış raporu',
            format: 'Excel',
          ),
        ),
        const PopupMenuItem(
          value: 'stock',
          child: _ExportItem(
            icon: Icons.inventory_2_outlined,
            title: 'Stok raporu',
            format: 'Excel',
          ),
        ),
        const PopupMenuItem(
          value: 'end_of_day',
          child: _ExportItem(
            icon: Icons.today_outlined,
            title: 'Gün sonu raporu',
            format: 'Excel',
          ),
        ),
        const PopupMenuItem(
          value: 'vat',
          child: _ExportItem(
            icon: Icons.percent_rounded,
            title: 'KDV matrah raporu',
            format: 'Excel',
          ),
        ),
        if (isOnline) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'cloud_sales',
            child: _ExportItem(
              icon: Icons.cloud_download_outlined,
              title: 'Bulut satış geçmişi',
              format: 'CSV',
            ),
          ),
          const PopupMenuItem(
            value: 'cloud_products',
            child: _ExportItem(
              icon: Icons.cloud_download_outlined,
              title: 'Bulut ürün analizi',
              format: 'CSV',
            ),
          ),
          const PopupMenuItem(
            value: 'cloud_debtors',
            child: _ExportItem(
              icon: Icons.cloud_download_outlined,
              title: 'Bulut alacak listesi',
              format: 'CSV',
            ),
          ),
        ],
      ],
      child: Container(
        height: 42,
        padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 14),
        decoration: BoxDecoration(
          color: POSColors.green,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.ios_share_rounded, color: Colors.white, size: 18),
            if (!compact) ...[
              const SizedBox(width: 8),
              const Text(
                'Dışa aktar',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExportItem extends StatelessWidget {
  const _ExportItem({
    required this.icon,
    required this.title,
    required this.format,
  });

  final IconData icon;
  final String title;
  final String format;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: POSColors.green, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(title)),
        Text(
          format,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: POSColors.textDisabled,
              ),
        ),
      ],
    );
  }
}

class _ReportsControls extends StatelessWidget {
  const _ReportsControls({
    required this.compact,
    required this.selectedRange,
    required this.tabController,
    required this.onRangeSelected,
  });

  final bool compact;
  final DateRange selectedRange;
  final TabController tabController;
  final ValueChanged<DateRange> onRangeSelected;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1440),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 24,
            compact ? 12 : 18,
            compact ? 12 : 24,
            0,
          ),
          child: Column(
            children: [
              _DateRangeSelector(
                selected: selectedRange,
                onSelected: onRangeSelected,
              ),
              SizedBox(height: compact ? 10 : 14),
              _ReportTabs(controller: tabController, compact: compact),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateRangeSelector extends StatelessWidget {
  const _DateRangeSelector({
    required this.selected,
    required this.onSelected,
  });

  final DateRange selected;
  final ValueChanged<DateRange> onSelected;

  @override
  Widget build(BuildContext context) {
    final presets = [
      DateRange.today(),
      DateRange.thisWeek(),
      DateRange.thisMonth(),
      DateRange.last3Months(),
    ];
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.border),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.calendar_month_outlined,
              size: 19,
              color: POSColors.textSecondary,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: presets.map((range) {
                  final active = selected.preset == range.preset;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Material(
                      color: active ? POSColors.greenLight : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () => onSelected(range),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          child: Text(
                            range.label,
                            style: TextStyle(
                              color: active
                                  ? POSColors.greenDark
                                  : POSColors.textSecondary,
                              fontSize: 12,
                              fontWeight:
                                  active ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => _pickCustomRange(context),
            tooltip: 'Özel tarih aralığı',
            icon: Icon(
              selected.preset == DateRangePreset.custom
                  ? Icons.event_available_rounded
                  : Icons.tune_rounded,
              size: 19,
            ),
            style: IconButton.styleFrom(
              foregroundColor: selected.preset == DateRangePreset.custom
                  ? POSColors.green
                  : POSColors.textSecondary,
              backgroundColor: selected.preset == DateRangePreset.custom
                  ? POSColors.greenLight
                  : POSColors.surfaceMuted,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: DateTimeRange(start: selected.from, end: selected.to),
      helpText: 'RAPOR DÖNEMİNİ SEÇİN',
      saveText: 'Uygula',
      cancelText: 'Vazgeç',
    );
    if (result != null) onSelected(DateRange.custom(result.start, result.end));
  }
}

class _ReportTabs extends StatelessWidget {
  const _ReportTabs({required this.controller, required this.compact});

  final TabController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: POSColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: TabBar(
        controller: controller,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: POSColors.text,
        unselectedLabelColor: POSColors.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        indicator: BoxDecoration(
          color: POSColors.card,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: POSColors.border),
          boxShadow: const [
            BoxShadow(
              color: POSColors.shadowColor,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        tabs: [
          _tab(Icons.point_of_sale_rounded, 'Satış'),
          _tab(Icons.inventory_2_outlined, 'Ürünler'),
          _tab(Icons.account_balance_wallet_outlined,
              compact ? 'Alacak' : 'Alacaklar'),
          _tab(Icons.insights_rounded, 'Analiz'),
        ],
      ),
    );
  }

  Tab _tab(IconData icon, String label) => Tab(
        height: 46,
        iconMargin: EdgeInsets.only(bottom: compact ? 2 : 0, right: 6),
        icon: Icon(icon, size: 18),
        text: label,
      );
}

class _ProductsTab extends ConsumerWidget {
  const _ProductsTab({required this.range});

  final DateRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(topProductsProvider(range));
    final catalog = ref.watch(allProductsProvider);
    final catalogById = <String, ProductEntity>{
      for (final product in catalog.value ?? const <ProductEntity>[])
        product.id: product,
    };
    return ReportScrollView(
      onRefresh: () async {
        ref.invalidate(topProductsProvider(range));
        ref.invalidate(allProductsProvider);
      },
      children: [
        const ReportSectionHeader(
          eyebrow: 'Ürün performansı',
          title: 'En çok satan ürünler',
          subtitle: 'Seçili dönemde gelire göre ilk 10 ürün',
          icon: Icons.emoji_events_outlined,
        ),
        const SizedBox(height: 14),
        products.when(
          data: (items) => items.isEmpty
              ? const ReportEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Henüz ürün verisi yok',
                  message: 'Seçili dönemde tamamlanmış satış bulunamadı.',
                )
              : _ProductRanking(items: items, catalogById: catalogById),
          loading: () => const ReportLoadingCard(height: 360),
          error: (error, _) => ReportErrorCard(
            message: 'Ürün performansı yüklenemedi.',
            onRetry: () => ref.invalidate(topProductsProvider(range)),
          ),
        ),
      ],
    );
  }
}

class _ProductRanking extends StatelessWidget {
  const _ProductRanking({required this.items, required this.catalogById});

  final List<ProductPerformance> items;
  final Map<String, ProductEntity> catalogById;

  @override
  Widget build(BuildContext context) {
    final maxRevenue = items.fold<double>(
      0,
      (current, item) => math.max(current, item.totalRevenue),
    );
    return ReportPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final product = catalogById[item.productId];
          final progress =
              maxRevenue == 0 ? 0.0 : item.totalRevenue / maxRevenue;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _RankedProductImage(
                      rank: item.rank,
                      productId: item.productId,
                      imageUrl: product?.imageUrl,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.productName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${formatReportCurrency(item.totalRevenue)} TL',
                                style: const TextStyle(
                                  color: POSColors.greenDark,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.categoryName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              Text(
                                '${item.totalSold} adet',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              backgroundColor: POSColors.surfaceMuted,
                              color: index == 0
                                  ? POSColors.amber
                                  : POSColors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (index != items.length - 1)
                const Divider(height: 1, indent: 64),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _RankedProductImage extends StatelessWidget {
  const _RankedProductImage({
    required this.rank,
    required this.productId,
    required this.imageUrl,
  });

  final int rank;
  final String productId;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final color = switch (rank) {
      1 => POSColors.amberDark,
      2 => POSColors.textSecondary,
      3 => POSColors.orange,
      _ => POSColors.green,
    };
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: ProductImage(
                imageUrl: imageUrl,
                barcode: productId,
                size: 52,
              ),
            ),
          ),
          Positioned(
            left: -4,
            top: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: POSColors.card, width: 2),
              ),
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceivablesTab extends ConsumerWidget {
  const _ReceivablesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(agingSummaryProvider);
    final rows = ref.watch(debtAgingProvider);
    return ReportScrollView(
      onRefresh: () async {
        ref.invalidate(agingSummaryProvider);
        ref.invalidate(debtAgingProvider);
      },
      children: [
        const ReportSectionHeader(
          eyebrow: 'Risk görünümü',
          title: 'Alacak yaşlandırma',
          subtitle: 'Açık bakiyelerin gecikme süresine göre dağılımı',
          icon: Icons.account_balance_wallet_outlined,
        ),
        const SizedBox(height: 14),
        summary.when(
          data: (data) => _AgingOverview(summary: data),
          loading: () => const ReportLoadingCard(height: 170),
          error: (error, _) => ReportErrorCard(
            message: 'Alacak özeti yüklenemedi.',
            onRetry: () => ref.invalidate(agingSummaryProvider),
          ),
        ),
        const SizedBox(height: 24),
        const ReportSectionHeader(
          eyebrow: 'Müşteriler',
          title: 'Açık hesaplar',
          subtitle: 'Gecikmiş bakiyesi bulunan müşteriler önce gösterilir',
          icon: Icons.people_outline_rounded,
        ),
        const SizedBox(height: 14),
        rows.when(
          data: (items) => items.isEmpty
              ? const ReportEmptyState(
                  icon: Icons.task_alt_rounded,
                  title: 'Açık alacak yok',
                  message: 'Tüm müşteri bakiyeleri kapalı görünüyor.',
                )
              : _ReceivablesList(rows: items),
          loading: () => const ReportLoadingCard(height: 320),
          error: (error, _) => ReportErrorCard(
            message: 'Müşteri bakiyeleri yüklenemedi.',
            onRetry: () => ref.invalidate(debtAgingProvider),
          ),
        ),
      ],
    );
  }
}

class _AgingOverview extends StatelessWidget {
  const _AgingOverview({required this.summary});

  final AgingSummary summary;

  @override
  Widget build(BuildContext context) {
    final buckets = [
      ('0–30 gün', summary.total0to30, POSColors.green),
      ('31–60 gün', summary.total31to60, POSColors.amberDark),
      ('61–90 gün', summary.total61to90, POSColors.orange),
      ('90+ gün', summary.totalOver90, POSColors.red),
    ];
    return ReportPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 600 ? 2 : 4;
          final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Toplam açık alacak',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 3),
                        Text(
                          '${formatReportCurrency(summary.grandTotal)} TL',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  ReportPill(
                    label: '${summary.affectedCustomers} müşteri',
                    icon: Icons.people_outline,
                    color: summary.totalOver90 > 0
                        ? POSColors.red
                        : POSColors.green,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: buckets
                    .map((bucket) => SizedBox(
                          width: width,
                          child: _AgingTile(
                            label: bucket.$1,
                            amount: bucket.$2,
                            color: bucket.$3,
                          ),
                        ))
                    .toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AgingTile extends StatelessWidget {
  const _AgingTile({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            '${formatReportCurrency(amount)} TL',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ReceivablesList extends StatelessWidget {
  const _ReceivablesList({required this.rows});

  final List<DebtAgingRow> rows;

  @override
  Widget build(BuildContext context) {
    final sorted = [...rows]..sort((a, b) {
        final overdue = b.over90.compareTo(a.over90);
        return overdue != 0 ? overdue : b.total.compareTo(a.total);
      });
    return ReportPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: sorted.asMap().entries.map((entry) {
          final row = entry.value;
          final riskColor = row.over90 > 0
              ? POSColors.red
              : row.hasOverdue
                  ? POSColors.orange
                  : POSColors.green;
          return Column(
            children: [
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                shape: const Border(),
                collapsedShape: const Border(),
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: riskColor.withValues(alpha: .10),
                  child: Icon(Icons.person_outline, size: 18, color: riskColor),
                ),
                title: Text(
                  row.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  row.hasOverdue ? 'Gecikmiş bakiye var' : 'Vadesi geçmemiş',
                  style: TextStyle(color: riskColor, fontSize: 11),
                ),
                trailing: Text(
                  '${formatReportCurrency(row.total)} TL',
                  style:
                      TextStyle(color: riskColor, fontWeight: FontWeight.w800),
                ),
                children: [
                  _DebtBreakdown(row: row),
                ],
              ),
              if (entry.key != sorted.length - 1)
                const Divider(height: 1, indent: 68),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _DebtBreakdown extends StatelessWidget {
  const _DebtBreakdown({required this.row});

  final DebtAgingRow row;

  @override
  Widget build(BuildContext context) {
    final values = [
      ('0–30 gün', row.current, POSColors.green),
      ('31–60 gün', row.days31to60, POSColors.amberDark),
      ('61–90 gün', row.days61to90, POSColors.orange),
      ('90+ gün', row.over90, POSColors.red),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: values
            .map((value) => SizedBox(
                  width: (constraints.maxWidth - 8) / 2,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: POSColors.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(value.$1,
                            style: Theme.of(context).textTheme.bodySmall),
                        Text(
                          '${formatReportCurrency(value.$2)} TL',
                          style: TextStyle(
                            color: value.$3,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

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
