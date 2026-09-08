// lib/presentation/pages/home_page.dart
// Serenut OS — Yönetici ve İşletme Operasyon Kokpiti (Ana Sayfa)
// Tamamen Serenut OS Tasarım Sistemine (PosPageLayout, PosHeader, POSColors, Outfit + Inter) Uygun

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
import 'package:serenutos/presentation/widgets/home/fast_collection_bottom_sheet.dart';
import 'package:serenutos/presentation/widgets/pos_page_layout.dart';
import 'package:serenutos/presentation/widgets/serenut_ui.dart';

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

    return PosPageLayout(
      title: 'Ana Sayfa',
      showRefresh: true,
      onRefresh: () => ref.invalidate(dashboardProvider),
      showStatusIndicator: true,
      showSettings: true,
      body: dashboard.when(
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
              final double horizontalPadding = isWide ? 28 : 16;

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  16,
                  horizontalPadding,
                  96,
                ),
                children: [
                  // ── 1. Tarih ve Kokpit Özet Şeridi ──
                  _CockpitDateBanner(
                    totalTransactions:
                        data.summary.totalSalesToday + data.orderSummary.todayOrdersCount,
                  ),
                  const SizedBox(height: 16),

                  // ── 2. 4'lü Kurumsal Serenut KPI Metrik Kartları ──
                  _HeroExecutiveMetrics(
                    summary: data.summary,
                    orderSummary: data.orderSummary,
                    isWide: isWide,
                  ),
                  const SizedBox(height: 20),

                  // ── 3. Kokpit Gövdesi (Masaüstü Çift Sütun / Mobil Tek Sütun) ──
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Sol Sütun: Canlı İşlem Akışı & Analitik ──
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
                                      products: data.topProducts,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _CategoryCard(
                                      items: data.categoryShares,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),

                        // ── Sağ Sütun: Pipeline, Kritik Stok & Yardımcı Araçlar ──
                        Expanded(
                          flex: 40,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _OrderPipelineCard(orderSummary: data.orderSummary),
                              const SizedBox(height: 16),
                              if (data.lowStockProducts.isNotEmpty) ...[
                                _CriticalStockBanner(
                                  lowStockCount: data.lowStockProducts.length,
                                  onTap: () => context.go(AppRoutes.products),
                                ),
                                const SizedBox(height: 16),
                              ],
                              const _QuickUtilitiesCard(),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    // Mobil Tek Sütunlu Düzen
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _OrderPipelineCard(orderSummary: data.orderSummary),
                        const SizedBox(height: 16),
                        if (data.lowStockProducts.isNotEmpty) ...[
                          _CriticalStockBanner(
                            lowStockCount: data.lowStockProducts.length,
                            onTap: () => context.go(AppRoutes.products),
                          ),
                          const SizedBox(height: 16),
                        ],
                        const _QuickUtilitiesCard(),
                        const SizedBox(height: 16),
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
    );
  }
}

// ── 1. Tarih ve Kokpit Özet Şeridi ──────────────────────────────────────────
class _CockpitDateBanner extends StatelessWidget {
  const _CockpitDateBanner({required this.totalTransactions});

  final int totalTransactions;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, d MMMM yyyy', 'tr_TR').format(now);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: POSColors.green,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                dateStr,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: POSColors.text,
                    ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: POSColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              '$totalTransactions İşlem Tamamlandı',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: POSColors.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 2. 4'lü Kurumsal Serenut KPI Metrik Kartları ──────────────────────────────
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
      _SerenutMetricCard(
        title: 'BUGÜNKÜ CİRO',
        amount: currency.format(totalTurnover),
        subtitle: '$totalTxCount İşlem (Kasa + Sipariş)',
        icon: Icons.account_balance_wallet_rounded,
        accentColor: POSColors.green,
      ),
      _SerenutMetricCard(
        title: 'KASA SATIŞI',
        amount: currency.format(summary.todayRevenue),
        subtitle: '${summary.totalSalesToday} Fiş / Kasa Satışı',
        icon: Icons.point_of_sale_rounded,
        accentColor: POSColors.greenDark,
      ),
      _SerenutMetricCard(
        title: 'SİPARİŞLER',
        amount: currency.format(orderSummary.todayOrdersRevenue),
        subtitle: '${orderSummary.todayOrdersCount} Kargo & Paket',
        icon: Icons.local_shipping_rounded,
        accentColor: POSColors.amberDark,
      ),
      _SerenutMetricCard(
        title: 'TAHSİLAT & VADELİ',
        amount: currency.format(summary.todayCollected),
        subtitle: 'Vadeli Alacak: ₺${summary.todayDebt.toStringAsFixed(2)}',
        icon: Icons.payments_rounded,
        accentColor: const Color(0xFF0284C7),
      ),
    ];

    if (isWide) {
      return Row(
        children: cards
            .map((c) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: c,
                  ),
                ))
            .toList(),
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
            childAspectRatio: 2.1,
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

class _SerenutMetricCard extends StatelessWidget {
  const _SerenutMetricCard({
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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 30,
                height: 4,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: accentColor, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: POSColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            amount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: POSColors.text,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: POSColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

// ── 3. Sipariş Operasyon Takip Kartı (Pipeline) ──────────────────────────────
class _OrderPipelineCard extends StatelessWidget {
  const _OrderPipelineCard({required this.orderSummary});

  final DashboardOrderSummary orderSummary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
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
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: POSColors.amber,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sipariş Operasyon Aşamaları',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: POSColors.text,
                        ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => context.go(AppRoutes.orders),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  children: [
                    Text(
                      'Tümünü Gör',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: POSColors.greenDark,
                          ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        size: 16, color: POSColors.greenDark),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
                  label: 'Teslim',
                  count: orderSummary.deliveredCount,
                  color: POSColors.green,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: POSColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 4. Kritik Stok Uyarısı Banner ─────────────────────────────────────────────
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
      color: POSColors.redLight,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: POSColors.red.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: POSColors.red,
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF991B1B),
                          ),
                    ),
                    Text(
                      'Tükenmek üzere olan ürünleri inceleyin.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFB91C1C),
                            fontSize: 11,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 13, color: Color(0xFF991B1B)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 5. Yardımcı Operasyonel Araçlar Kartı (Quick Utilities) ───────────────────
class _QuickUtilitiesCard extends StatelessWidget {
  const _QuickUtilitiesCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: POSColors.green,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Operasyonel Yardımcı Araçlar',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: POSColors.text,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _UtilityTile(
                  title: 'Hızlı Tahsilat',
                  subtitle: 'Borç Kapatma',
                  icon: Icons.payments_outlined,
                  color: POSColors.greenDark,
                  onTap: () => FastCollectionBottomSheet.show(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _UtilityTile(
                  title: 'Etiket Kuyruğu',
                  subtitle: 'Raf & Barkod',
                  icon: Icons.qr_code_2_rounded,
                  color: const Color(0xFFD97706),
                  onTap: () => context.push(AppRoutes.printQueue),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _UtilityTile(
                  title: 'Kasa & Raporlar',
                  subtitle: 'Gün Sonu Dökümü',
                  icon: Icons.assessment_outlined,
                  color: const Color(0xFF2563EB),
                  onTap: () => requirePermissionAccess(
                    context,
                    permission: Permission.reportsView,
                    title: 'Raporlar Yetkisi',
                    onGranted: (_, __) => context.push(AppRoutes.reports),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _UtilityTile(
                  title: 'Finans Merkezi',
                  subtitle: 'Nakit & Alacak',
                  icon: Icons.account_balance_outlined,
                  color: const Color(0xFF7C3AED),
                  onTap: () => requirePermissionAccess(
                    context,
                    permission: Permission.settingsFinance,
                    title: 'Finans Yetkisi',
                    onGranted: (_, __) => context.push(AppRoutes.finance),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UtilityTile extends StatelessWidget {
  const _UtilityTile({
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
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: POSColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: POSColors.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: POSColors.text,
                          ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10,
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

// ── 6. Canlı İşlem Akışı Paneli ───────────────────────────────────────────────
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
        color: POSColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Segmented Tab Switcher
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: POSColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadii.sm),
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
          const SizedBox(height: 14),

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
                  final timeStr = DateFormat('HH:mm').format(order.createdAt);
                  return InkWell(
                    onTap: () => context.push('/orders/detail/${order.id}'),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: POSColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.shopping_bag_outlined,
                                color: POSColors.textSecondary, size: 18),
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
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: POSColors.text,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '#${order.orderNumber}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: POSColors.textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${order.itemCount} Kalem Ürün · $timeStr',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
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
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: POSColors.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              _OrderCompactBadge(status: order.status),
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
                  final timeStr = DateFormat('HH:mm').format(sale.createdAt);
                  return InkWell(
                    onTap: () => context.push('/sales/detail/${sale.id}'),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: POSColors.greenLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.receipt_rounded,
                                color: POSColors.greenDark, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currency.format(sale.totalAmount),
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: POSColors.text,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$timeStr · Fiş: ${sale.id.toString().substring(0, 8)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: POSColors.textSecondary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: POSColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              sale.paymentMethod.toString().toUpperCase(),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    fontSize: 10,
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
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? POSColors.greenDark : POSColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? POSColors.text : POSColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCompactBadge extends StatelessWidget {
  const _OrderCompactBadge({required this.status});
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
          POSColors.greenDark,
          POSColors.greenLight
        ),
      'cancelled' || 'iptal' => (
          'İptal',
          POSColors.red,
          POSColors.redLight
        ),
      _ => ('Yeni', const Color(0xFFD97706), const Color(0xFFFFFBEB)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: POSColors.greenDark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'En Çok Satan Ürünler',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: POSColors.text,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (products.isEmpty)
            const SizedBox(
              height: 80,
              child: Center(
                child: Text('Henüz satış verisi yok',
                    style: TextStyle(color: POSColors.textSecondary)),
              ),
            )
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
                            color: POSColors.surfaceMuted,
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
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: POSColors.text,
                                ),
                          ),
                        ),
                        Text(
                          currency.format(product.totalRevenue),
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: POSColors.text,
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
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.items});
  final List<DashboardCategoryShare> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Kategori Ciro Dağılımı',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: POSColors.text,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            const SizedBox(
              height: 80,
              child: Center(
                child: Text('Henüz kategori verisi yok',
                    style: TextStyle(color: POSColors.textSecondary)),
              ),
            )
          else
            ...items.take(3).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.category,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            Text(
                              '%${item.percentage.toStringAsFixed(0)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: (item.percentage / 100).clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: POSColors.surfaceMuted,
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
