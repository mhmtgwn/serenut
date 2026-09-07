// lib/presentation/pages/home_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/infrastructure/repositories/dashboard_repository.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/presentation/widgets/realtime_status_indicator.dart';
import 'package:serenutos/presentation/pages/orders/widgets/order_creation_dialog.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _selectedFeedTab = 0; // 0: Canlı Siparişler, 1: Son Satışlar

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: dashboard.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: POSColors.green),
          ),
          error: (error, _) => _DashboardError(
            message: error.toString(),
            onRetry: () => ref.invalidate(dashboardProvider),
          ),
          data: (data) => RefreshIndicator(
            color: POSColors.green,
            onRefresh: () async => ref.invalidate(dashboardProvider),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 960;
                final double horizontalPadding = isWide ? 32 : 16;

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    16,
                    horizontalPadding,
                    96,
                  ),
                  children: [
                    // ── 1. Başlık, Canlı Durum ve Hızlı Butonlar ──
                    _DashboardHeader(
                      isWide: isWide,
                      onRefresh: () => ref.invalidate(dashboardProvider),
                      onSettings: () => requirePermissionAccess(
                        context,
                        permission: Permission.settingsView,
                        title: 'Ayarlar Yetkisi',
                        onGranted: (_, __) => context.push(AppRoutes.settings),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── 2. 4'lü Temiz Kurumsal KPI Metrik Kartları ──
                    _HeroExecutiveMetrics(
                      summary: data.summary,
                      orderSummary: data.orderSummary,
                      isWide: isWide,
                    ),
                    const SizedBox(height: 20),

                    // ── 3. Bento Dashboard Gövdesi ──
                    if (isWide)
                      // Masaüstü Çift Sütunlu Kokpit
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Sol Sütun (Canlı İşlem Akışı & Analitik) ──
                          Expanded(
                            flex: 60,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _OperationsFeed(
                                  selectedTab: _selectedFeedTab,
                                  onTabChanged: (tab) =>
                                      setState(() => _selectedFeedTab = tab),
                                  recentOrders: data.recentOrders,
                                  recentSales: data.recentSales,
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _TopProductsCard(
                                          products: data.topProducts),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _CategoryCard(
                                          items: data.categoryShares),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),

                          // ── Sağ Sütun (Hızlı Aksiyonlar, Pipeline, Uyarılar) ──
                          Expanded(
                            flex: 40,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _QuickActionDock(),
                                const SizedBox(height: 16),
                                _OrderPipelineBar(
                                    orderSummary: data.orderSummary),
                                const SizedBox(height: 16),
                                if (data.lowStockProducts.isNotEmpty)
                                  _CriticalStockBanner(
                                    lowStockCount: data.lowStockProducts.length,
                                    onTap: () => context.go(AppRoutes.products),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      )
                    else
                      // Mobil Tek Sütunlu Akış
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _QuickActionDock(),
                          const SizedBox(height: 16),
                          _OrderPipelineBar(orderSummary: data.orderSummary),
                          const SizedBox(height: 16),
                          if (data.lowStockProducts.isNotEmpty) ...[
                            _CriticalStockBanner(
                              lowStockCount: data.lowStockProducts.length,
                              onTap: () => context.go(AppRoutes.products),
                            ),
                            const SizedBox(height: 16),
                          ],
                          _OperationsFeed(
                            selectedTab: _selectedFeedTab,
                            onTabChanged: (tab) =>
                                setState(() => _selectedFeedTab = tab),
                            recentOrders: data.recentOrders,
                            recentSales: data.recentSales,
                          ),
                          const SizedBox(height: 16),
                          _TopProductsCard(products: data.topProducts),
                          const SizedBox(height: 16),
                          _CategoryCard(items: data.categoryShares),
                        ],
                      ),
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

// ── 1. Başlık Widget'ı ────────────────────────────────────────────────────────
class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.isWide,
    required this.onRefresh,
    required this.onSettings,
  });

  final bool isWide;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, d MMMM yyyy', 'tr_TR').format(now);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'İşletme Komuta Merkezi',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: POSColors.text,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const RealtimeStatusIndicator(compact: true),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                dateStr,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: POSColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (isWide) ...[
          FilledButton.icon(
            onPressed: () => context.go(AppRoutes.sales),
            icon: const Icon(Icons.point_of_sale_rounded, size: 18),
            label: const Text('Yeni Satış'),
            style: FilledButton.styleFrom(
              backgroundColor: POSColors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => OrderCreationDialog.show(context),
            icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
            label: const Text('Yeni Sipariş'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
            ),
          ),
          const SizedBox(width: 10),
        ],
        IconButton.filledTonal(
          onPressed: onRefresh,
          tooltip: 'Yenile',
          icon: const Icon(Icons.refresh_rounded, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: POSColors.textSecondary,
            side: const BorderSide(color: POSColors.border),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: onSettings,
          tooltip: 'Ayarlar',
          icon: const Icon(Icons.settings_outlined, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: POSColors.text,
            side: const BorderSide(color: POSColors.border),
          ),
        ),
      ],
    );
  }
}

// ── 2. 4'lü Temiz Kurumsal KPI Metrik Kartları ─────────────────────────────────
class _HeroExecutiveMetrics extends StatelessWidget {
  const _HeroExecutiveMetrics({
    required this.summary,
    required this.orderSummary,
    required this.isWide,
  });

  final DashboardSummary summary;
  final DashboardOrderSummary orderSummary;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final totalTurnover = summary.todayRevenue + orderSummary.todayOrdersRevenue;
    final totalTxCount = summary.totalSalesToday + orderSummary.todayOrdersCount;

    final cards = [
      _MetricCard(
        title: 'BUGÜNKÜ CİRO',
        amount: currency.format(totalTurnover),
        subtitle: '$totalTxCount İşlem (Kasa + Sipariş)',
        icon: Icons.payments_rounded,
        accentColor: const Color(0xFF16A34A),
      ),
      _MetricCard(
        title: 'KASA SATIŞI',
        amount: currency.format(summary.todayRevenue),
        subtitle: '${summary.totalSalesToday} Fiş Düzenlendi',
        icon: Icons.point_of_sale_rounded,
        accentColor: const Color(0xFF0D9488),
      ),
      _MetricCard(
        title: 'SİPARİŞLER',
        amount: currency.format(orderSummary.todayOrdersRevenue),
        subtitle: '${orderSummary.todayOrdersCount} Kargo / Paket',
        icon: Icons.local_shipping_rounded,
        accentColor: const Color(0xFF2563EB),
      ),
      _MetricCard(
        title: 'TAHSİLAT & VADELİ',
        amount: currency.format(summary.todayCollected),
        subtitle: 'Vadeli: ₺${summary.todayDebt.toStringAsFixed(2)}',
        icon: Icons.account_balance_wallet_rounded,
        accentColor: const Color(0xFFD97706),
      ),
    ];

    if (isWide) {
      return Row(
        children: cards.map((c) => Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: c,
        ))).toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 520) {
          return GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.2,
            children: cards,
          );
        }
        return Column(
          children: cards
              .map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: c,
                  ))
              .toList(),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
  });

  final String title;
  final String amount;
  final String subtitle;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: POSColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              Text(
                title,
                style: GoogleFonts.inter(
                  color: POSColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            amount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: POSColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: POSColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 3. Hızlı Aksiyon Dock'u ───────────────────────────────────────────────────
class _QuickActionDock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: POSColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flash_on_rounded,
                  size: 18, color: Color(0xFFD97706)),
              const SizedBox(width: 8),
              Text(
                'Hızlı İşlemler',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: POSColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 2.3,
                children: [
                  _ActionDockButton(
                    title: 'Yeni Sipariş',
                    subtitle: 'Modal Aç',
                    icon: Icons.add_shopping_cart_rounded,
                    color: const Color(0xFF2563EB),
                    onTap: () => OrderCreationDialog.show(context),
                  ),
                  _ActionDockButton(
                    title: 'Hızlı Satış',
                    subtitle: 'Kasa Ekranı',
                    icon: Icons.point_of_sale_rounded,
                    color: const Color(0xFF10B981),
                    onTap: () => context.go(AppRoutes.sales),
                  ),
                  _ActionDockButton(
                    title: 'Yeni Müşteri',
                    subtitle: 'Kayıt Formu',
                    icon: Icons.person_add_rounded,
                    color: const Color(0xFF8B5CF6),
                    onTap: () => context.push(AppRoutes.customerAdd),
                  ),
                  _ActionDockButton(
                    title: 'Etiket Kuyruğu',
                    subtitle: 'Yazıcıya Gönder',
                    icon: Icons.qr_code_2_rounded,
                    color: const Color(0xFFF59E0B),
                    onTap: () => context.push(AppRoutes.printQueue),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ActionDockButton extends StatelessWidget {
  const _ActionDockButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: POSColors.text,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: POSColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 4. Canlı Sipariş Takip Barı (Pipeline) ────────────────────────────────────
class _OrderPipelineBar extends StatelessWidget {
  const _OrderPipelineBar({required this.orderSummary});

  final DashboardOrderSummary orderSummary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: POSColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.inventory_rounded,
                      size: 18, color: POSColors.text),
                  const SizedBox(width: 8),
                  Text(
                    'Sipariş Operasyon Durumu',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: POSColors.text,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => context.go(AppRoutes.orders),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  children: [
                    Text(
                      'Tümünü Gör',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: POSColors.greenDark,
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        size: 18, color: POSColors.greenDark),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PipelineBadge(
                  label: 'Yeni',
                  count: orderSummary.createdCount,
                  color: const Color(0xFFF59E0B),
                  onTap: () => context.go('/orders?status=created'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PipelineBadge(
                  label: 'Hazırlanıyor',
                  count: orderSummary.preparingCount,
                  color: const Color(0xFF3B82F6),
                  onTap: () => context.go('/orders?status=preparing'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PipelineBadge(
                  label: 'Yolda',
                  count: orderSummary.shippedCount,
                  color: const Color(0xFF8B5CF6),
                  onTap: () => context.go('/orders?status=shipped'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PipelineBadge(
                  label: 'Teslim Edildi',
                  count: orderSummary.deliveredCount,
                  color: const Color(0xFF10B981),
                  onTap: () => context.go('/orders?status=delivered'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PipelineBadge extends StatelessWidget {
  const _PipelineBadge({
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: POSColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 5. Kritik Stok Uyarısı Banner ─────────────────────────────────────────────
class _CriticalStockBanner extends StatelessWidget {
  const _CriticalStockBanner({
    required this.lowStockCount,
    required this.onTap,
  });

  final int lowStockCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFCA5A5)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$lowStockCount ürün kritik stok seviyesinde!',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF991B1B),
                      ),
                    ),
                    Text(
                      'Tükenmek üzere olan ürünleri incelemek için tıklayın.',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: const Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: Color(0xFF991B1B)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 6. Çift Akışlı Operasyon Paneli ───────────────────────────────────────────
class _OperationsFeed extends StatelessWidget {
  const _OperationsFeed({
    required this.selectedTab,
    required this.onTabChanged,
    required this.recentOrders,
    required this.recentSales,
  });

  final int selectedTab;
  final ValueChanged<int> onTabChanged;
  final List<DashboardRecentOrder> recentOrders;
  final List<dynamic> recentSales;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: POSColors.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Segmented Tab Switcher
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                Expanded(
                  child: _FeedTabButton(
                    title: 'Canlı Siparişler (${recentOrders.length})',
                    icon: Icons.local_shipping_outlined,
                    isSelected: selectedTab == 0,
                    onTap: () => onTabChanged(0),
                  ),
                ),
                Expanded(
                  child: _FeedTabButton(
                    title: 'Son Satışlar (${recentSales.length})',
                    icon: Icons.receipt_long_outlined,
                    isSelected: selectedTab == 1,
                    onTap: () => onTabChanged(1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Liste İçeriği
          if (selectedTab == 0) ...[
            if (recentOrders.isEmpty)
              const SizedBox(
                height: 120,
                child: Center(
                  child: Text('Henüz sipariş kaydı bulunmuyor.',
                      style: TextStyle(color: POSColors.textSecondary)),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentOrders.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: POSColors.border, height: 16),
                itemBuilder: (context, index) {
                  final order = recentOrders[index];
                  final timeStr =
                      DateFormat('HH:mm').format(order.createdAt);
                  return InkWell(
                    onTap: () => context.push('/orders/detail/${order.id}'),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.shopping_bag_outlined,
                                color: POSColors.textSecondary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        order.customerName,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: POSColors.text,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '#${order.orderNumber}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: POSColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${order.itemCount} Kalem Ürün · $timeStr',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: POSColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                currency.format(order.totalAmount),
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: POSColors.text,
                                ),
                              ),
                              const SizedBox(height: 3),
                              _StatusBadge(status: order.status),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ] else ...[
            if (recentSales.isEmpty)
              const SizedBox(
                height: 120,
                child: Center(
                  child: Text('Henüz satış kaydı bulunmuyor.',
                      style: TextStyle(color: POSColors.textSecondary)),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentSales.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: POSColors.border, height: 16),
                itemBuilder: (context, index) {
                  final sale = recentSales[index];
                  final timeStr =
                      DateFormat('HH:mm').format(sale.createdAt);
                  return InkWell(
                    onTap: () => context.push('/sales/detail/${sale.id}'),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.receipt_rounded,
                                color: POSColors.green, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currency.format(sale.totalAmount),
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: POSColors.text,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$timeStr · Fiş: ${sale.id.toString().substring(0, 8)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: POSColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              sale.paymentMethod.toString().toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: POSColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _FeedTabButton extends StatelessWidget {
  const _FeedTabButton({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? POSColors.greenDark : POSColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: isSelected ? POSColors.text : POSColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (status.toLowerCase()) {
      'preparing' || 'hazirlaniyor' => (
          'Hazırlanıyor',
          const Color(0xFF2563EB),
          const Color(0xFFEFF6FF)
        ),
      'shipped' || 'yolda' => (
          'Yolda',
          const Color(0xFF7C3AED),
          const Color(0xFFF5F3FF)
        ),
      'delivered' || 'completed' || 'teslim' => (
          'Teslim Edildi',
          const Color(0xFF059669),
          const Color(0xFFECFDF5)
        ),
      'cancelled' || 'iptal' => (
          'İptal',
          const Color(0xFFDC2626),
          const Color(0xFFFEF2F2)
        ),
      _ => ('Yeni', const Color(0xFFD97706), const Color(0xFFFFFBEB)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ── 7. En Çok Satanlar & Kategori Dağılımı Kartları ────────────────────────────
class _TopProductsCard extends StatelessWidget {
  const _TopProductsCard({required this.products});
  final List<DashboardProductPerformance> products;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: POSColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded,
                  size: 18, color: POSColors.greenDark),
              const SizedBox(width: 8),
              Text(
                'En Çok Satan Ürünler',
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: POSColors.text),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (products.isEmpty)
            const SizedBox(
                height: 80,
                child: Center(
                    child: Text('Henüz satış verisi yok',
                        style: TextStyle(color: POSColors.textSecondary))))
          else
            ...products.take(4).map(
                  (product) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${product.rank}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: POSColors.text),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            product.productName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          currency.format(product.totalRevenue),
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: POSColors.text),
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

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.items});
  final List<DashboardCategoryShare> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: POSColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_outline_rounded,
                  size: 18, color: Color(0xFF3B82F6)),
              const SizedBox(width: 8),
              Text(
                'Kategori Ciro Dağılımı',
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: POSColors.text),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            const SizedBox(
                height: 80,
                child: Center(
                    child: Text('Henüz kategori verisi yok',
                        style: TextStyle(color: POSColors.textSecondary))))
          else
            ...items.take(3).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(item.category,
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ),
                            Text('%${item.percentage.toStringAsFixed(0)}',
                                style: GoogleFonts.inter(
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: (item.percentage / 100).clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: const Color(0xFFF1F5F9),
                          color: POSColors.greenDark,
                          borderRadius: BorderRadius.circular(4),
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

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * .7,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 48, color: POSColors.red),
                  const SizedBox(height: 12),
                  const Text('Ana sayfa verileri alınamadı',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tekrar Dene'),
                  ),
                ],
              ),
            ),
          )
        ],
      );
}
