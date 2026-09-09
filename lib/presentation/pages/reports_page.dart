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


part 'reports/reports_controls.dart';
part 'reports/products_tab.dart';
part 'reports/receivables_tab.dart';
part 'reports/analytics_tab.dart';

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
