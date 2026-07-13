// lib/presentation/pages/home_page.dart
// Serenut POS — Ana Sayfa / Dashboard (Restructured & Redesigned)
// Generated: 25 Jun 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/repositories/dashboard_repository.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/providers/sync_provider.dart';
import 'package:serenutos/presentation/controllers/report_controller.dart';
import 'package:serenutos/domain/services/dashboard_service.dart';
import 'package:serenutos/presentation/pages/global_search_page.dart';
import 'package:serenutos/presentation/widgets/trial_banner_widget.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/presentation/widgets/home/system_trust_panel.dart';
import 'package:serenutos/presentation/widgets/home/quick_actions_panel.dart';
import 'package:serenutos/presentation/widgets/home/alert_stream_panel.dart';


// ── POS Tema Renkleri ─────────────────────────────────────────────────────────
const _kBgColor = Color(0xFFF8FAFC);
const _kTextDark = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorderColor = Color(0xFFF1F5F9);

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardProvider);
    final ordersAsync = ref.watch(ordersControllerProvider);
    final syncState = ref.watch(syncProvider);
    final debtAgingVal = ref.watch(debtAgingProvider);

    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: dashboardAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
            ),
          ),
          error: (err, _) => _ErrorView(
            message: err.toString(),
            onRetry: () => ref.invalidate(dashboardProvider),
          ),
          data: (data) {
            final orders = ordersAsync.value ?? [];
            final pendingCount = orders.where((o) => o.status == 'created').length;
            final preparingCount = orders.where((o) => o.status == 'preparing').length;
            
            final debtAging = debtAgingVal.value ?? [];
            final overdueCount = debtAging.where((row) => row.hasOverdue).length;

            return RefreshIndicator(
              color: const Color(0xFF10B981),
              onRefresh: () async {
                ref.invalidate(dashboardProvider);
                ref.invalidate(ordersControllerProvider);
                ref.invalidate(customersControllerProvider);
                ref.invalidate(debtAgingProvider);
              },
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final isWide = constraints.maxWidth >= 800;
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 24 : 16,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Üst Alan (Header)
                        _buildHeader(context, ref, data),
                        const SizedBox(height: 16),

                        // 1b. Trial / License Banner (görünür sadece uyarı varsa)
                        const TrialBannerWidget(),

                        // 1c. Sync Conflict Banner
                        if (syncState.status == SyncStatus.error)
                          SyncConflictBanner(syncState: syncState),

                        const SizedBox(height: 8),

                        // 2. SYSTEM TRUST PANEL (Phase B)
                        const SystemTrustPanel(),
                        const SizedBox(height: 16),

                        // 3. OPERATION QUICK ACTIONS (Phase B)
                        const QuickActionsPanel(),
                        const SizedBox(height: 20),

                        // 4. Finansal Özet Kartları (KPI)
                        _buildFinancialSummary(data.summary),
                        const SizedBox(height: 24),

                        // 5. ALERT STREAM (Phase B)
                        const AlertStreamPanel(),
                        const SizedBox(height: 24),

                        // 6. Satış Grafiği
                        _buildSalesTrendSection(data.weeklyTrend),
                        const SizedBox(height: 24),

                        // 7. Son Hareketler
                        _buildRecentSalesSection(context, ref, data.recentSales),
                        const SizedBox(height: 24),

                        // 8. En Çok Satan Ürünler
                        _buildTopProductsSection(context, data.topProducts.take(3).toList()),
                        const SizedBox(height: 80), // nav bar boşluğu
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Header Builder ─────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, WidgetRef ref, DashboardData data) {
    final now = DateTime.now();
    final dayName = DateFormat('EEEE', 'tr_TR').format(now);
    final dateFormatted = '${now.day} ${DateFormat('MMMM', 'tr_TR').format(now)} $dayName';

    final settings = ref.watch(settingsNotifierProvider).value;
    final titleText = (settings?.businessName != null && settings!.businessName.isNotEmpty)
        ? settings.businessName
        : 'İyi Çalışmalar';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'GÜNLÜK ÖZET',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: _kTextSecondary,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                titleText,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _kTextDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                dateFormatted,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_none_rounded, color: Color(0xFF475569), size: 24),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tüm bildirimler güncel.'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                if (data.lowStockProducts.isNotEmpty)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.search_rounded, color: Color(0xFF475569), size: 24),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const GlobalSearchPage(),
                  ),
                );
              },
            ),
            const SizedBox(width: 4),
            if (ref.watch(currentUserProvider) != null)
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Color(0xFF475569), size: 24),
                onPressed: () => context.push(AppRoutes.settings),
              ),
          ],
        ),
      ],
    );
  }

  // ── Financial Summary KPI Cards ────────────────────────────────────────────
  Widget _buildFinancialSummary(DashboardSummary summary) {
    final format = NumberFormat('#,##0.00', 'tr_TR');
    final profit = summary.todayRevenue * 0.30; // Estimated 30% gross profit margin

    final items = [
      _KpiData(
        title: 'Bugünkü Ciro',
        value: '₺${format.format(summary.todayRevenue)}',
        desc: 'Toplam satış cirosu',
        icon: Icons.trending_up_rounded,
        iconColor: const Color(0xFF10B981),
        bgColor: const Color(0xFFECFDF5),
      ),
      _KpiData(
        title: 'Tahsilatlar',
        value: '₺${format.format(summary.todayCollected)}',
        desc: 'Nakit ve kartlı ödeme',
        icon: Icons.payments_outlined,
        iconColor: const Color(0xFF3B82F6),
        bgColor: const Color(0xFFEFF6FF),
      ),
      _KpiData(
        title: 'Vadeli Alacaklar',
        value: '₺${format.format(summary.todayDebt)}',
        desc: 'Açık hesap / veresiye',
        icon: Icons.account_balance_wallet_outlined,
        iconColor: const Color(0xFFFF9500),
        bgColor: const Color(0xFFFFF7ED),
      ),
      _KpiData(
        title: 'Toplam Alacak',
        value: '₺${format.format(summary.totalReceivables)}',
        desc: 'Müşteri açık hesap borçları',
        icon: Icons.assignment_turned_in_rounded,
        iconColor: const Color(0xFF8B5CF6),
        bgColor: const Color(0xFFF5F3FF),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth >= 720 ? 4 : 2;
        // On small screens, lower aspect ratio (e.g. 0.95) allows more vertical space to avoid overflows.
        final childRatio = constraints.maxWidth >= 720 ? 1.35 : 0.95;
        
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: childRatio,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kBorderColor),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x03000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: item.bgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(item.icon, color: item.iconColor, size: 20),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            item.value,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _kTextDark,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          item.desc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: _kTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Sales Trend Line Chart ─────────────────────────────────────────────────
  Widget _buildSalesTrendSection(List<SalesTrendPoint> trend) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x03000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SATIŞ TRENDİ (SON 7 GÜN)',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: _kTextSecondary,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: trend.isEmpty
                ? const Center(child: Text('Veri bulunamadı'))
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => const FlLine(
                          color: _kBorderColor,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx >= 0 && idx < trend.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Text(
                                    DateFormat('dd.MM').format(trend[idx].date),
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontWeight: FontWeight.bold),
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
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  value >= 1000
                                      ? '${(value / 1000).toStringAsFixed(1)}K'
                                      : value.toInt().toString(),
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.right,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: trend.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.revenue)).toList(),
                          isCurved: true,
                          color: const Color(0xFF10B981), // Emerald 500
                          barWidth: 3.5,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: const Color(0xFF10B981).withOpacity(0.08),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Operations Cards Grid ──────────────────────────────────────────────────
  Widget _buildOperationsSection(BuildContext context, int pending, int preparing, int lowStock, int overdue) {
    final items = [
      _OpCardData(
        label: 'Bekleyen Sipariş',
        value: pending.toString(),
        icon: Icons.receipt_long_rounded,
        color: const Color(0xFF3B82F6),
        bgColor: const Color(0xFFEFF6FF),
        route: AppRoutes.orders,
      ),
      _OpCardData(
        label: 'Hazırlananlar',
        value: preparing.toString(),
        icon: Icons.hourglass_top_rounded,
        color: const Color(0xFFF59E0B),
        bgColor: const Color(0xFFFFF7ED),
        route: AppRoutes.orders,
      ),
      _OpCardData(
        label: 'Kritik Stoklar',
        value: lowStock.toString(),
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFFEF4444),
        bgColor: const Color(0xFFFEF2F2),
        route: AppRoutes.products,
      ),
      _OpCardData(
        label: 'Vadesi Geçenler',
        value: overdue.toString(),
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFF8B5CF6),
        bgColor: const Color(0xFFF5F3FF),
        route: AppRoutes.reports,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'OPERASYON KONTROL',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: _kTextSecondary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossCount = constraints.maxWidth >= 720 ? 4 : 2;
            final childRatio = constraints.maxWidth >= 720 ? 1.5 : 1.20;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: childRatio,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return InkWell(
                  onTap: () {
                    if (item.route == AppRoutes.reports) {
                      requireAdminAccess(
                        context,
                        title: 'Rapor Yetkisi',
                        onGranted: (_, __) => context.push(item.route),
                      );
                    } else {
                      context.go(item.route);
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _kBorderColor),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x03000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: item.bgColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(item.icon, color: item.color, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  item.value,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: item.color,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  // ── Smart Alerts Panel ─────────────────────────────────────────────────────
  Widget _buildAlertsSection(BuildContext context, WidgetRef ref, List<ProductEntity> lowStockProducts, int overdueCount, SyncState syncState) {
    final list = <Widget>[];

    if (lowStockProducts.isNotEmpty) {
      list.add(
        _buildAlertStrip(
          icon: Icons.inventory_2_outlined,
          color: const Color(0xFFEF4444),
          bgColor: const Color(0xFFFEF2F2),
          message: 'Kritik Stok: ${lowStockProducts.length} adet ürün kritik stok seviyesinin altında.',
          actionLabel: 'Stokları Gör',
          onTap: () => context.go(AppRoutes.products),
        ),
      );
    }

    if (overdueCount > 0) {
      list.add(
        _buildAlertStrip(
          icon: Icons.hourglass_empty_rounded,
          color: const Color(0xFFF59E0B),
          bgColor: const Color(0xFFFFF7ED),
          message: 'Gecikmiş Ödeme: $overdueCount müşterinin vadesi geçmiş borcu bulunuyor.',
          actionLabel: 'Detay',
          onTap: () => requireAdminAccess(
            context,
            title: 'Rapor Yetkisi',
            onGranted: (_, __) => context.push(AppRoutes.reports),
          ),
        ),
      );
    }

    if (syncState.status == SyncStatus.error) {
      list.add(
        _buildAlertStrip(
          icon: Icons.sync_problem_rounded,
          color: const Color(0xFFEF4444),
          bgColor: const Color(0xFFFEF2F2),
          message: 'Senkronizasyon Sorunu: Veritabanı bulut ile eşitlenemedi.',
          actionLabel: 'Eşitle',
          onTap: () => ref.read(syncProvider.notifier).triggerSync(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SİSTEM UYARILARI',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: _kTextSecondary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDCFCE7)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                SizedBox(width: 8),
                Text(
                  'Her şey normal görünüyor',
                  style: TextStyle(color: Color(0xFF047857), fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          )
        else
          Column(
            children: list.expand((w) => [w, const SizedBox(height: 8)]).toList()..removeLast(),
          ),
      ],
    );
  }

  Widget _buildAlertStrip({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String message,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              backgroundColor: color.withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              actionLabel,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ── Recent Activities ──────────────────────────────────────────────────────
  Widget _buildRecentSalesSection(BuildContext context, WidgetRef ref, List<SaleEntity> sales) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SON İŞLEMLER',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: _kTextSecondary,
                letterSpacing: 1.0,
              ),
            ),
            GestureDetector(
              onTap: () => context.go(AppRoutes.sales),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Tümünü Gör', style: TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w700)),
                  Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF10B981)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (sales.isEmpty)
          const _EmptyCard(icon: Icons.receipt_long_outlined, message: 'Henüz işlem bulunmuyor', color: _kTextSecondary)
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _kBorderColor),
            ),
            child: Column(
              children: sales.asMap().entries.map((e) {
                final sale = e.value;
                final isLast = e.key == sales.length - 1;
                
                final pmLabel = {
                  'cash': 'Nakit', 'nakit': 'Nakit',
                  'card': 'Kart', 'kart': 'Kart',
                  'debt': 'Vadeli', 'vadeli': 'Vadeli',
                  'mixed': 'Karma',
                }[sale.paymentMethod.toLowerCase()] ?? sale.paymentMethod;
                
                final isDebt = sale.paymentMethod.toLowerCase().contains('debt') || sale.paymentMethod.toLowerCase().contains('vadeli');
                final pmColor = isDebt ? const Color(0xFFFF9500) : const Color(0xFF10B981);
                final pmBgColor = isDebt ? const Color(0xFFFFF7ED) : const Color(0xFFECFDF5);

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: pmBgColor,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.receipt_outlined, color: pmColor, size: 18),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Builder(
                                  builder: (context) {
                                    final customers = ref.watch(customersControllerProvider).value ?? [];
                                    final customer = customers.firstWhere(
                                      (c) => c.id == sale.customerId,
                                      orElse: () => CustomerEntity(id: '', name: 'Hızlı Satış', email: '', phone: '', balance: 0, createdAt: DateTime.now()),
                                    );
                                    final customerName = sale.customerId.isEmpty || sale.customerId == 'walkin' || customer.id.isEmpty 
                                        ? 'Hızlı Satış' 
                                        : customer.name;
                                    return Text(
                                      customerName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: _kTextDark,
                                      ),
                                    );
                                  }
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${DateFormat('HH:mm').format(sale.createdAt)} • $pmLabel Satış',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₺${NumberFormat('#,##0.00', 'tr_TR').format(sale.totalAmount)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _kTextDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      const Divider(height: 1, color: _kBorderColor),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildTopProductsSection(BuildContext context, List<DashboardProductPerformance> products) {
    final format = NumberFormat('#,##0.00', 'tr_TR');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'EN ÇOK SATAN ÜRÜNLER',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: _kTextSecondary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        if (products.isEmpty)
          const _EmptyCard(icon: Icons.inventory_2_outlined, message: 'Satış verisi bulunmuyor', color: _kTextSecondary)
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _kBorderColor),
            ),
            child: Column(
              children: products.asMap().entries.map((e) {
                final prod = e.value;
                final isLast = e.key == products.length - 1;
                
                final badgeColor = [
                  const Color(0xFFFBBF24), // Gold for 1st
                  const Color(0xFF94A3B8), // Silver for 2nd
                  const Color(0xFFB45309), // Bronze for 3rd
                ][e.key % 3];

                final badgeBgColor = [
                  const Color(0xFFFEF3C7),
                  const Color(0xFFF1F5F9),
                  const Color(0xFFFEF3C7).withOpacity(0.5),
                ][e.key % 3];

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: badgeBgColor,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${prod.rank}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: badgeColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  prod.productName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _kTextDark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${prod.category} • ${prod.totalSold} adet satıldı',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₺${format.format(prod.totalRevenue)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _kTextDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      const Divider(height: 1, color: _kBorderColor),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

// ── Private Helper Widgets ───────────────────────────────────────────────────

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  const _EmptyCard({required this.icon, required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: color.withOpacity(0.5)),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: color.withOpacity(0.7), fontSize: 13)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 64, color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            const Text('Veriler yüklenemedi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: _kTextSecondary, fontSize: 12), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tekrar Dene'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpCardData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String route;
  const _OpCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.route,
  });
}

class _KpiData {
  final String title;
  final String value;
  final String desc;
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  const _KpiData({
    required this.title,
    required this.value,
    required this.desc,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
  });
}

// ── Sync Conflict Banner ──────────────────────────────────────────────────────
/// Shown on Dashboard when syncState.status == SyncStatus.error.
/// Minimal 1-line banner with "Detaylar" action.
class SyncConflictBanner extends StatelessWidget {
  final SyncState syncState;
  const SyncConflictBanner({super.key, required this.syncState});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFEF4444), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              syncState.lastError ?? 'Senkronizasyon başarısız',
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => context.push(AppRoutes.syncConflict),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Text(
                'Detaylar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
