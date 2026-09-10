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
import 'package:serenutos/presentation/pages/order_details_page.dart';


part 'home/hero_executive_metrics.dart';
part 'home/order_pipeline_card.dart';
part 'home/quick_utilities_card.dart';
part 'home/operations_feed.dart';
part 'home/home_dashboard_cards.dart';

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
        skipLoadingOnReload: true,
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
