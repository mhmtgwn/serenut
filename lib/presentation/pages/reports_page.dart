import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/services/report_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';
import 'package:serenutos/presentation/controllers/report_controller.dart';
import 'package:serenutos/presentation/pages/end_of_day_page.dart';
import 'package:serenutos/presentation/widgets/product_image.dart';
import 'package:serenutos/presentation/widgets/reports/sales_tab.dart';
import 'package:serenutos/presentation/widgets/reports/shared_report_widgets.dart';
import 'package:serenutos/providers/auth_provider.dart';
import 'package:serenutos/providers/repository_providers.dart';

import 'package:serenutos/presentation/widgets/app_notification_host.dart';
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
    _tabController = TabController(length: 5, vsync: this);
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
      await ref
          .read(reportControllerProvider.notifier)
          .exportReport(type: type, range: _selectedRange);
    } catch (error) {
      if (mounted) {
        AppNotificationHost.show(
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
                          const EndOfDayPage(),
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
