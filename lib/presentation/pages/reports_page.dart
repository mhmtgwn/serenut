// lib/presentation/pages/reports_page.dart
// Phase 2.3 — Analytics Engine UI
// 3-tab layout: Sales | Products | Customer Debt + Cloud BI
// Generated: 21 Jun 2026

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/presentation/controllers/report_controller.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';
import 'package:serenutos/domain/services/report_service.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/config/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:serenutos/domain/services/document_export_service.dart';
// Sprint 7 Cloud BI Imports
import 'package:serenutos/domain/models/analytics_models.dart';
import 'package:serenutos/infrastructure/repositories/cloud_analytics_repository.dart';
import 'package:serenutos/infrastructure/services/analytics_ws_service.dart';
import 'package:serenutos/providers/auth_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:serenutos/presentation/widgets/reports/sales_tab.dart';

// ════════════════════════════════════════════════════════════
// Main Reports Page
// ════════════════════════════════════════════════════════════

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateRange _selectedRange = DateRange.thisMonth();
  bool _isLoading = false;
  AnalyticsWsService? _wsService;
  DashboardMetrics? _liveMetrics;
  // DÜZELTME: StreamSubscription tutularak dispose'da cancel() çağrılabilsin
  StreamSubscription<dynamic>? _wsSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this); // Extended to 6 tabs (including Cloud BI)
    _setupWebSocket();
  }

  void _setupWebSocket() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final authState = ref.read(authProvider);
        final token = authState.token;
        if (token != null) {
          _wsService = ref.read(analyticsWsServiceProvider);
          await _wsService!.connect(jwtToken: token);
          // DÜZELTME: mounted kontrolü connect()'ten SONRA yapılıyor
          if (!mounted) return;
          _wsSub = _wsService!.eventStream.listen((event) {
            if (event['event'] == 'sale_sync' && mounted) {
              // Trigger reload of Cloud BI data or update local cache
              setState(() {
                // Instantly update Today Revenue for micro-animation
                if (_liveMetrics != null) {
                  final newSaleAmt = (event['data']['total_amount'] as num).toDouble();
                  _liveMetrics = DashboardMetrics(
                    todayRevenue: _liveMetrics!.todayRevenue + newSaleAmt,
                    todayOrders: _liveMetrics!.todayOrders + 1,
                    avgBasket: _liveMetrics!.todayOrders + 1 > 0 
                        ? ((_liveMetrics!.todayRevenue + newSaleAmt) / (_liveMetrics!.todayOrders + 1)).round()
                        : 0,
                    weeklyRevenue: _liveMetrics!.weeklyRevenue + newSaleAmt,
                    weeklyGrowth: _liveMetrics!.weeklyGrowth,
                    monthlyRevenue: _liveMetrics!.monthlyRevenue + newSaleAmt,
                    monthlyGrowth: _liveMetrics!.monthlyGrowth,
                    topProduct: _liveMetrics!.topProduct,
                    busiestHour: _liveMetrics!.busiestHour,
                    paymentBreakdown: _liveMetrics!.paymentBreakdown,
                  );
                }
              });
            }
          });
        }
      } catch (e) {
        debugPrint('[ReportsPage] WebSocket bağlantı hatası: $e');
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    // DÜZELTME: StreamSubscription cancel eklendi — bellek sızıntısı giderildi
    _wsSub?.cancel();
    _wsService?.disconnect();
    super.dispose();
  }

  void _onRangeSelected(DateRange range) {
    setState(() => _selectedRange = range);
    ref.read(reportControllerProvider.notifier).setRange(range);
  }

  Future<void> _exportReport(String type) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final exportService = DocumentExportService();
      const currency = 'TL';
      String filePath;
      String subject;

      if (type == 'sales') {
        final saleRepo = await ref.read(saleRepositoryProvider.future);
        final sales = await saleRepo.getSalesByDateRange(_selectedRange.from, _selectedRange.to);
        filePath = await exportService.exportSalesReportExcel(sales, _selectedRange.label, currency);
        subject = '${_selectedRange.label} Satış Raporu';
        await exportService.shareFile(filePath, subject);
      } else if (type == 'stock') {
        final productRepo = await ref.read(productRepositoryProvider.future);
        final products = await productRepo.findAll();
        filePath = await exportService.exportStockReportExcel(products);
        subject = 'Stok Raporu';
        await exportService.shareFile(filePath, subject);
      } else if (type == 'end_of_day') {
        final today = DateTime.now();
        final startOfDay = DateTime(today.year, today.month, today.day);
        final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);

        final saleRepo = await ref.read(saleRepositoryProvider.future);
        final sales = await saleRepo.getSalesByDateRange(startOfDay, endOfDay);
        
        final dashboardRepo = await ref.read(dashboardRepositoryProvider.future);
        final summary = await dashboardRepo.getTodaySummary();

        filePath = await exportService.exportEndOfDayReportExcel(
          date: today,
          totalRevenue: summary.todayRevenue,
          totalCollected: summary.todayCollected,
          totalDebt: summary.todayDebt,
          salesCount: summary.totalSalesToday,
          sales: sales,
          currency: currency,
        );
        subject = 'Gün Sonu Raporu - ${DateFormat('dd.MM.yyyy').format(today)}';
        await exportService.shareFile(filePath, subject);
      } else if (type == 'vat') {
        final reportRepo = await ref.read(reportRepositoryProvider.future);
        final rows = await reportRepo.getVatBreakdown(_selectedRange.from, _selectedRange.to);


        filePath = await exportService.exportVatReportExcel(
          startDate: _selectedRange.from,
          endDate: _selectedRange.to,
          vatSummaryRows: rows,
          currency: currency,
        );
        subject = 'KDV Matrah Raporu';
        await exportService.shareFile(filePath, subject);
      } else if (type.startsWith('cloud_')) {
        final cloudAnalytics = ref.read(cloudAnalyticsRepositoryProvider);
        final reportType = type.replaceAll('cloud_', '');
        final file = await cloudAnalytics.exportReportCsv(type: reportType);
        await Share.shareXFiles([XFile(file.path)], subject: 'Cloud BI Raporu - $reportType');
      } else {
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rapor dışa aktarma hatası: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(authProvider).token;
    final isOnline = token != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Raporlar & Analitik'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Color(0xFF16A34A)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              // Date Range Picker
              _DateRangePicker(
                selected: _selectedRange,
                onSelected: _onRangeSelected,
              ),
              // Tab Bar (Real-time Cloud tabs are hidden if offline)
              TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF16A34A),
                unselectedLabelColor: const Color(0xFF64748B),
                indicatorColor: const Color(0xFF16A34A),
                indicatorWeight: 2,
                isScrollable: true,
                tabs: [
                  const Tab(icon: Icon(Icons.trending_up, size: 18), text: 'Satış'),
                  const Tab(icon: Icon(Icons.inventory_2_outlined, size: 18), text: 'Ürün'),
                  const Tab(icon: Icon(Icons.account_balance_wallet_outlined, size: 18), text: 'Borç'),
                  const Tab(icon: Icon(Icons.bar_chart_rounded, size: 18), text: 'Grafikler'),
                  if (isOnline) const Tab(icon: Icon(Icons.cloud_done_rounded, size: 18), text: 'Cloud BI'),
                  if (isOnline) const Tab(icon: Icon(Icons.people_alt_outlined, size: 18), text: 'Kasiyer/Şube'),
                ],
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _isLoading
                ? null
                : () {
                    ref.read(reportControllerProvider.notifier).refresh();
                    setState(() {}); // Triggers FutureBuilder redraw
                  },
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Color(0xFF16A34A)),
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.share_rounded, color: Color(0xFF16A34A)),
              tooltip: 'Raporu Dışa Aktar',
              onSelected: _exportReport,
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'sales',
                  child: ListTile(
                    leading: Icon(Icons.trending_up_rounded, color: Color(0xFF16A34A)),
                    title: Text('Satış Raporu (Excel)'),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'stock',
                  child: ListTile(
                    leading: Icon(Icons.inventory_2_outlined, color: Color(0xFF16A34A)),
                    title: Text('Stok Raporu (Excel)'),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'end_of_day',
                  child: ListTile(
                    leading: Icon(Icons.today_rounded, color: Color(0xFF16A34A)),
                    title: Text('Gün Sonu Z Raporu (Excel)'),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'vat',
                  child: ListTile(
                    leading: Icon(Icons.receipt_long_rounded, color: Color(0xFF16A34A)),
                    title: Text('KDV Matrah Raporu (Excel)'),
                  ),
                ),
                if (isOnline) ...[
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'cloud_sales',
                    child: ListTile(
                      leading: Icon(Icons.cloud_download_rounded, color: Colors.blue),
                      title: Text('Bulut Satış Geçmişi (CSV)'),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'cloud_products',
                    child: ListTile(
                      leading: Icon(Icons.cloud_download_rounded, color: Colors.blue),
                      title: Text('Bulut Ürün Analitiği (CSV)'),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'cloud_debtors',
                    child: ListTile(
                      leading: Icon(Icons.cloud_download_rounded, color: Colors.blue),
                      title: Text('Bulut Cari Veresiye Listesi (CSV)'),
                    ),
                  ),
                ]
              ],
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SalesTab(range: _selectedRange),
          _ProductsTab(range: _selectedRange),
          const _DebtTab(),
          _AnalyticsTab(range: _selectedRange),
          if (isOnline) _CloudBiTab(onMetricsLoaded: (metrics) {
            _liveMetrics ??= metrics;
          }, liveMetrics: _liveMetrics),
          if (isOnline) const _CloudStaffBranchTab(),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Sprint 7 Cloud BI Tabs and Widgets
// ════════════════════════════════════════════════════════════

class _CloudBiTab extends ConsumerWidget {
  final Function(DashboardMetrics) onMetricsLoaded;
  final DashboardMetrics? liveMetrics;

  const _CloudBiTab({required this.onMetricsLoaded, required this.liveMetrics});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cloudAnalytics = ref.watch(cloudAnalyticsRepositoryProvider);

    return FutureBuilder<DashboardMetrics>(
      future: liveMetrics != null ? Future.value(liveMetrics) : cloudAnalytics.getDashboard(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && liveMetrics == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Bulut analitik yüklenemedi: ${snapshot.error}'));
        }

        final data = snapshot.data!;
        onMetricsLoaded(data);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Real-time badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('WebSocket Gerçek Zamanlı Bulut BI Aktif', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // KPI Cards
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      title: 'Bugün Ciro',
                      value: '${data.todayRevenue.toStringAsFixed(0)} TL',
                      icon: Icons.monetization_on_rounded,
                      color: Colors.green,
                      subtitle: '${data.todayOrders} Sipariş | E.Fiş: ${data.avgBasket} TL',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _KpiCard(
                      title: 'Haftalık Ciro',
                      value: '${data.weeklyRevenue.toStringAsFixed(0)} TL',
                      icon: Icons.show_chart_rounded,
                      color: Colors.blue,
                      subtitle: 'Büyüme: +${data.weeklyGrowth}%',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      title: 'Aylık Ciro',
                      value: '${data.monthlyRevenue.toStringAsFixed(0)} TL',
                      icon: Icons.calendar_today_rounded,
                      color: Colors.purple,
                      subtitle: 'Büyüme: +${data.monthlyGrowth}%',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _KpiCard(
                      title: 'En Popüler Ürün',
                      value: data.topProduct?.name ?? 'Veri yok',
                      icon: Icons.star_rounded,
                      color: Colors.orange,
                      subtitle: data.topProduct != null 
                          ? '${data.topProduct!.quantity.toStringAsFixed(0)} Adet satıldı'
                          : 'Son 30 günde',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Payment breakdown chart
              Card(
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ödeme Yöntemi Dağılımı (Son 30 Gün)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 140,
                              child: PieChart(
                                PieChartData(
                                  sectionsSpace: 2,
                                  centerSpaceRadius: 30,
                                  sections: [
                                    PieChartSectionData(
                                      color: Colors.green,
                                      value: data.paymentBreakdown.cash.toDouble(),
                                      title: '%${data.paymentBreakdown.cash}',
                                      radius: 40,
                                      titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    PieChartSectionData(
                                      color: Colors.blue,
                                      value: data.paymentBreakdown.card.toDouble(),
                                      title: '%${data.paymentBreakdown.card}',
                                      radius: 40,
                                      titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    PieChartSectionData(
                                      color: Colors.red,
                                      value: data.paymentBreakdown.credit.toDouble(),
                                      title: '%${data.paymentBreakdown.credit}',
                                      radius: 40,
                                      titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ChartLegend(color: Colors.green, label: 'Nakit'),
                                SizedBox(height: 6),
                                _ChartLegend(color: Colors.blue, label: 'Kart'),
                                SizedBox(height: 6),
                                _ChartLegend(color: Colors.red, label: 'Veresiye'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Sales Trend Chart
              _CloudSalesTrendWidget(cloudAnalytics: cloudAnalytics),
              const SizedBox(height: 16),
              // Critical Stock Widget
              _CloudStockAlertWidget(cloudAnalytics: cloudAnalytics),
            ],
          ),
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
                Icon(icon, color: color.withOpacity(0.8), size: 20),
              ],
            ),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _ChartLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _CloudSalesTrendWidget extends StatefulWidget {
  final CloudAnalyticsRepository cloudAnalytics;
  const _CloudSalesTrendWidget({required this.cloudAnalytics});

  @override
  State<_CloudSalesTrendWidget> createState() => _CloudSalesTrendWidgetState();
}

class _CloudSalesTrendWidgetState extends State<_CloudSalesTrendWidget> {
  String _period = 'daily';

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Satış Trend Analizi', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: _period,
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Günlük', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'weekly', child: Text('Haftalık', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'monthly', child: Text('Aylık', style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _period = val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<SalesTrendPoint>>(
              future: widget.cloudAnalytics.getSalesTrend(period: _period),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SizedBox(height: 100, child: Center(child: Text('Trend verisi yüklenemedi.')));
                }

                final trendPoints = snapshot.data!;
                final maxRevenue = trendPoints.map((p) => p.revenue).reduce(math.max);

                return SizedBox(
                  height: 160,
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: true, drawVerticalLine: false),
                      titlesData: FlTitlesData(
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 35,
                            getTitlesWidget: (val, meta) => Text('${(val/1000).toStringAsFixed(0)}K', style: const TextStyle(fontSize: 9, color: Colors.grey)),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (val, meta) {
                              if (val.toInt() >= 0 && val.toInt() < trendPoints.length) {
                                final point = trendPoints[val.toInt()];
                                final date = DateTime.tryParse(point.time);
                                if (date != null) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(DateFormat('dd.MM').format(date), style: const TextStyle(fontSize: 8, color: Colors.grey)),
                                  );
                                }
                              }
                              return const SizedBox();
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      minY: 0,
                      maxY: maxRevenue * 1.2,
                      lineBarsData: [
                        LineChartBarData(
                          spots: List.generate(
                            trendPoints.length,
                            (index) => FlSpot(index.toDouble(), trendPoints[index].revenue),
                          ),
                          isCurved: true,
                          color: Colors.green,
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: Colors.green.withOpacity(0.1),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudStockAlertWidget extends StatelessWidget {
  final CloudAnalyticsRepository cloudAnalytics;
  const _CloudStockAlertWidget({required this.cloudAnalytics});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                const SizedBox(width: 8),
                Text('Kritik Stok Uyarısı (Bulut)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<StockAnalytics>(
              future: cloudAnalytics.getStockStats(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData || snapshot.data!.criticalItems.isEmpty) {
                  return const Text('Kritik stokta ürün bulunmuyor.', style: TextStyle(fontSize: 12, color: Colors.grey));
                }

                final items = snapshot.data!.criticalItems;
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(item.category ?? 'Genel', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: item.quantity <= 3 ? Colors.red.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${item.quantity} Adet',
                          style: TextStyle(
                            color: item.quantity <= 3 ? Colors.red : Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudStaffBranchTab extends ConsumerWidget {
  const _CloudStaffBranchTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cloudAnalytics = ref.watch(cloudAnalyticsRepositoryProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Branch performance
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mağaza / Şube Karşılaştırması', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  FutureBuilder<List<BranchStat>>(
                    future: cloudAnalytics.getBranchStats(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Text('Şube karşılaştırma verisi yok.');
                      }

                      final branches = snapshot.data!;
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: branches.length,
                        itemBuilder: (context, index) {
                          final branch = branches[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('${index + 1}. ${branch.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    Text('${branch.revenue.toStringAsFixed(0)} TL', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: branch.revenue / (branches.first.revenue > 0 ? branches.first.revenue : 1),
                                    backgroundColor: Colors.grey.withOpacity(0.2),
                                    valueColor: const AlwaysStoppedAnimation(Colors.green),
                                    minHeight: 8,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Staff performance
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kasiyer / Personel Analizi', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  FutureBuilder<List<StaffStat>>(
                    future: cloudAnalytics.getStaffStats(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Text('Personel analiz verisi yok.');
                      }

                      final staffList = snapshot.data!;
                      return Table(
                        columnWidths: const {
                          0: FlexColumnWidth(2),
                          1: FlexColumnWidth(1),
                          2: FlexColumnWidth(1),
                        },
                        children: [
                          TableRow(
                            decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1)),
                            children: const [
                              Padding(padding: EdgeInsets.all(8.0), child: Text('Personel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Padding(padding: EdgeInsets.all(8.0), child: Text('Sipariş', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Padding(padding: EdgeInsets.all(8.0), child: Text('Ciro', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            ],
                          ),
                          ...staffList.map((staff) => TableRow(
                                children: [
                                  Padding(padding: const EdgeInsets.all(8.0), child: Text(staff.name, style: const TextStyle(fontSize: 12))),
                                  Padding(padding: const EdgeInsets.all(8.0), child: Text('${staff.salesCount}', style: const TextStyle(fontSize: 12))),
                                  Padding(padding: const EdgeInsets.all(8.0), child: Text('${staff.revenue.toStringAsFixed(0)} TL', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green))),
                                ],
                              )),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Date Range Picker
// ════════════════════════════════════════════════════════════

class _DateRangePicker extends StatelessWidget {
  final DateRange selected;
  final ValueChanged<DateRange> onSelected;

  const _DateRangePicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final presets = [
      DateRange.today(),
      DateRange.thisWeek(),
      DateRange.thisMonth(),
      DateRange.last3Months(),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: presets.map((range) {
                  final isSelected = selected.preset == range.preset;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => onSelected(range),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? POSColors.green : Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? POSColors.green : Colors.grey[300]!,
                          ),
                        ),
                        child: Text(
                          range.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Custom date range button
          OutlinedButton.icon(
            onPressed: () => _showCustomDatePicker(context),
            icon: const Icon(Icons.date_range, size: 14),
            label: const Text('Özel', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              side: BorderSide(color: Colors.grey[400]!),
              foregroundColor: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  void _showCustomDatePicker(BuildContext context) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: selected.from,
        end: selected.to,
      ),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: POSColors.green,
          ),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      onSelected(DateRange.custom(range.start, range.end));
    }
  }
}

// ════════════════════════════════════════════════════════════
// Tab 1 — Satış Özeti
// ════════════════════════════════════════════════════════════



// ════════════════════════════════════════════════════════════
// Tab 2 — Ürün Analizi
// ════════════════════════════════════════════════════════════

class _ProductsTab extends ConsumerWidget {
  final DateRange range;

  const _ProductsTab({required this.range});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topProductsVal = ref.watch(topProductsProvider(range));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(topProductsProvider(range)),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              title: 'En Çok Satan Ürünler',
              subtitle: 'Gelire göre top-10',
              icon: Icons.emoji_events_outlined,
            ),
            const SizedBox(height: 8),
            topProductsVal.when(
              data: (products) => products.isEmpty
                  ? _emptyState('Bu dönemde satış verisi yok')
                  : _buildProductList(products),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => _errorCard('Ürünler yüklenemedi: $e'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductList(List<ProductPerformance> products) {
    final maxRevenue = products.fold<double>(0, (m, p) => p.totalRevenue > m ? p.totalRevenue : m);
    final rankColors = [Colors.amber[700]!, Colors.grey[500]!, Colors.brown[400]!];

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: products.asMap().entries.map((entry) {
          final i = entry.key;
          final product = entry.value;
          final barFrac = maxRevenue == 0 ? 0.0 : product.totalRevenue / maxRevenue;
          final rankColor = i < 3 ? rankColors[i] : Colors.grey[400]!;

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Rank badge
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: rankColor.withAlpha(30),
                        shape: BoxShape.circle,
                        border: Border.all(color: rankColor, width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          '#${product.rank}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: rankColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.productName,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          Text(product.categoryName,
                              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${_fmt(product.totalRevenue)} TL',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${product.totalSold} adet',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: barFrac,
                    minHeight: 4,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      i == 0 ? POSColors.amberDark : POSColors.green,
                    ),
                  ),
                ),
                if (i < products.length - 1)
                  Divider(height: 1, color: Colors.grey[100]),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Tab 3 — Müşteri Borçları (Debt Aging)
// ════════════════════════════════════════════════════════════

class _DebtTab extends ConsumerWidget {
  const _DebtTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agingSummaryVal = ref.watch(agingSummaryProvider);
    final debtAgingVal = ref.watch(debtAgingProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(agingSummaryProvider);
        ref.invalidate(debtAgingProvider);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Aging Summary Buckets
            agingSummaryVal.when(
              data: (s) => _buildAgingBuckets(s),
              loading: () => _shimmerBuckets(),
              error: (e, _) => _errorCard('Özet yüklenemedi: $e'),
            ),
            const SizedBox(height: 20),

            const _SectionHeader(
              title: 'Müşteri Detayı',
              subtitle: 'Tüm vadeli müşteriler',
              icon: Icons.people_outline,
            ),
            const SizedBox(height: 8),

            debtAgingVal.when(
              data: (rows) => rows.isEmpty
                  ? _emptyState('Vadeli müşteri yok 🎉')
                  : _buildAgingTable(rows),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => _errorCard('Tablo yüklenemedi: $e'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgingBuckets(AgingSummary s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Borç Yaşlandırma',
          subtitle: '${s.affectedCustomers} vadeli müşteri',
          icon: Icons.hourglass_top_outlined,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _AgingBucket(
              label: '0–30 gün',
              amount: s.total0to30,
              color: Colors.green[600]!,
              icon: Icons.check_circle_outline,
            )),
            const SizedBox(width: 8),
            Expanded(child: _AgingBucket(
              label: '31–60 gün',
              amount: s.total31to60,
              color: Colors.orange[600]!,
              icon: Icons.schedule,
            )),
            const SizedBox(width: 8),
            Expanded(child: _AgingBucket(
              label: '61–90 gün',
              amount: s.total61to90,
              color: Colors.deepOrange[600]!,
              icon: Icons.warning_amber_outlined,
            )),
            const SizedBox(width: 8),
            Expanded(child: _AgingBucket(
              label: '90+ gün',
              amount: s.totalOver90,
              color: Colors.red[700]!,
              icon: Icons.cancel_outlined,
            )),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Toplam Açık Borç',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${_fmt(s.grandTotal)} TL',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: s.totalOver90 > 0 ? Colors.red[700] : Colors.orange[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAgingTable(List<DebtAgingRow> rows) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Expanded(child: Text('Müşteri',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                _tableHeader('0-30', Colors.green[700]!),
                _tableHeader('31-60', Colors.orange[700]!),
                _tableHeader('61-90', Colors.deepOrange[700]!),
                _tableHeader('90+', Colors.red[700]!),
                _tableHeader('Toplam', Colors.black87),
              ],
            ),
          ),
          const Divider(height: 1),
          ...rows.map((row) => _buildAgingRow(row)),
        ],
      ),
    );
  }

  Widget _tableHeader(String text, Color color) {
    return SizedBox(
      width: 58,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: color),
      ),
    );
  }

  Widget _buildAgingRow(DebtAgingRow row) {
    final hasOverdue = row.hasOverdue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: row.over90 > 0
            ? Colors.red[50]
            : hasOverdue
                ? Colors.orange[50]
                : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(row.customerName,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
          _amountCell(row.current, Colors.green[700]!),
          _amountCell(row.days31to60, Colors.orange[700]!),
          _amountCell(row.days61to90, Colors.deepOrange[700]!),
          _amountCell(row.over90, Colors.red[700]!, bold: row.over90 > 0),
          _amountCell(row.total, Colors.black87, bold: true),
        ],
      ),
    );
  }

  Widget _amountCell(double amount, Color color, {bool bold = false}) {
    return SizedBox(
      width: 58,
      child: Text(
        amount > 0 ? _fmt(amount) : '—',
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 12,
          color: amount > 0 ? color : Colors.grey[400],
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _shimmerBuckets() {
    return Row(
      children: List.generate(4, (_) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      )),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Shared Widgets
// ════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;

  const _SectionHeader({required this.title, this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: POSColors.greenDark),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        if (subtitle != null) ...[
          const SizedBox(width: 8),
          Text(subtitle!,
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color bg;
  final String? subtitle;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bg,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  )),
              if (subtitle != null)
                Text(subtitle!,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgingBucket extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _AgingBucket({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            _fmt(amount),
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 9, color: color),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Helpers (module-level)
// ════════════════════════════════════════════════════════════

Widget _emptyState(String message) {
  return Container(
    padding: const EdgeInsets.all(40),
    decoration: BoxDecoration(
      color: Colors.grey[50],
      borderRadius: BorderRadius.circular(12),
    ),
    child: Center(
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    ),
  );
}

Widget _errorCard(String message) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.red[50],
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.red[200]!),
    ),
    child: Row(
      children: [
        Icon(Icons.error_outline, color: Colors.red[700]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              style: TextStyle(color: Colors.red[700], fontSize: 13)),
        ),
      ],
    ),
  );
}

String _fmt(double val) {
  if (val >= 1000000) {
    return '${NumberFormat('#,###.##', 'tr_TR').format(val / 1000000)}M';
  }
  if (val >= 1000) {
    return NumberFormat('#,###', 'tr_TR').format(val);
  }
  return NumberFormat('#,###.##', 'tr_TR').format(val);
}

class _AnalyticsTab extends ConsumerWidget {
  final DateRange range;

  const _AnalyticsTab({required this.range});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryVal = ref.watch(reportSummaryProvider(range));
    final dailyVal = ref.watch(dailyRevenueProvider(range));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(reportSummaryProvider(range));
        ref.invalidate(dailyRevenueProvider(range));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Satış ve Alacak Trendi (Weekly/Monthly Trend)
            const _SectionHeader(
              title: 'Satış Trendi',
              subtitle: 'Gelir ve Alacak Çizgisi',
              icon: Icons.show_chart_rounded,
            ),
            const SizedBox(height: 10),
            Card(
              color: Colors.white,
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
                child: SizedBox(
                  height: 220,
                  child: dailyVal.when(
                    data: (data) {
                      if (data.isEmpty) return _emptyState('Trend verisi yok');
                      return _buildLineChart(data);
                    },
                    loading: () => const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(POSColors.green))),
                    error: (e, _) => _errorCard('Grafik yüklenemedi: $e'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 2. Kâr ve Maliyet Dağılımı (Profitability Analysis)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeader(
                        title: 'Karlılık Oranı',
                        subtitle: 'Tahmini Kâr/Maliyet',
                        icon: Icons.pie_chart_rounded,
                      ),
                      const SizedBox(height: 10),
                      Card(
                        color: Colors.white,
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            height: 180,
                            child: summaryVal.when(
                              data: (s) {
                                if (s.totalRevenue == 0) return _emptyState('Veri yok');
                                return _buildProfitabilityPie(s);
                              },
                              loading: () => const Center(child: CircularProgressIndicator()),
                              error: (e, _) => _errorCard('Hata'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeader(
                        title: 'Tahsilat Kırılımı',
                        subtitle: 'Nakit vs Alacak',
                        icon: Icons.donut_large_rounded,
                      ),
                      const SizedBox(height: 10),
                      Card(
                        color: Colors.white,
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            height: 180,
                            child: summaryVal.when(
                              data: (s) {
                                if (s.totalRevenue == 0) return _emptyState('Veri yok');
                                return _buildCollectionsPie(s);
                              },
                              loading: () => const Center(child: CircularProgressIndicator()),
                              error: (e, _) => _errorCard('Hata'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 3. Stok Hareketleri / Günlük Satış Hacmi
            const _SectionHeader(
              title: 'Günlük Stok Çıkış Hacmi',
              subtitle: 'İşlem Sayısı',
              icon: Icons.bar_chart_rounded,
            ),
            const SizedBox(height: 10),
            Card(
              color: Colors.white,
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
                child: SizedBox(
                  height: 200,
                  child: dailyVal.when(
                    data: (data) {
                      if (data.isEmpty) return _emptyState('Veri yok');
                      return _buildBarChart(data);
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => _errorCard('Hata'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart(List<DailyRevenue> data) {
    final spots = data.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.totalAmount);
    }).toList();

    final debtSpots = data.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.debtAmount);
    }).toList();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1000,
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: math.max(1, (data.length / 5).floor()).toDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < data.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      DateFormat('dd.MM').format(data[index].date),
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 9),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) {
                return Text(
                  _fmt(value),
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 9),
                  textAlign: TextAlign.left,
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: POSColors.green,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: POSColors.green.withValues(alpha: 0.1),
            ),
          ),
          LineChartBarData(
            spots: debtSpots,
            isCurved: true,
            color: POSColors.amber,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitabilityPie(ReportSummary s) {
    final profit = s.totalRevenue * 0.3;
    final cost = s.totalRevenue * 0.7;

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 30,
        sections: [
          PieChartSectionData(
            color: const Color(0xFF007AFF),
            value: profit,
            title: '%30\nKâr',
            radius: 45,
            titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          PieChartSectionData(
            color: const Color(0xFFFF2D55),
            value: cost,
            title: '%70\nMaliyet',
            radius: 40,
            titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionsPie(ReportSummary s) {
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 30,
        sections: [
          PieChartSectionData(
            color: POSColors.green,
            value: s.totalCollected,
            title: 'Nakit\n%${s.collectionRate.toStringAsFixed(0)}',
            radius: 45,
            titleStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          PieChartSectionData(
            color: POSColors.amber,
            value: s.totalDebt,
            title: 'Vadeli\n%${(100 - s.collectionRate).toStringAsFixed(0)}',
            radius: 40,
            titleStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<DailyRevenue> data) {
    final barGroups = data.asMap().entries.map((e) {
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: e.value.saleCount.toDouble(),
            color: POSColors.green,
            width: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    }).toList();

    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: math.max(1, (data.length / 5).floor()).toDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < data.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      DateFormat('dd.MM').format(data[index].date),
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 9),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 9),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: barGroups,
      ),
    );
  }
}
