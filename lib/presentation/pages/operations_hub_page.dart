// lib/presentation/pages/operations_hub_page.dart
// Serenut OS — Daily Operations & Transaction Center
// Created: Phase C — 01 Jul 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/presentation/controllers/orders_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';

// ── Design Constants ──────────────────────────────────────────────────────────
const _kBgColor = Color(0xFFF8FAFC);
const _kCardBg = Colors.white;
const _kBorderColor = Color(0xFFE2E8F0);
const _kTextPrimary = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kGreen = Color(0xFF10B981);
const _kBlue = Color(0xFF3B82F6);
const _kPurple = Color(0xFF8B5CF6);
const _kTeal = Color(0xFF0D9488);

// ── Page ──────────────────────────────────────────────────────────────────────

class OperationsHubPage extends ConsumerWidget {
  const OperationsHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersControllerProvider);
    final dashboardAsync = ref.watch(dashboardProvider);

    final pendingOrdersCount = ordersAsync.maybeWhen(
      data: (list) => list
          .where((o) => o.status == 'created' || o.status == 'preparing')
          .length,
      orElse: () => 0,
    );

    final lowStockCount = dashboardAsync.maybeWhen(
      data: (data) => data.lowStockProducts.length,
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'İşlem & Operasyon Merkezi',
          style: TextStyle(
            color: _kTextPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header section
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GÜNLÜK HIZLI İŞLEMLER',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _kTextSecondary,
                    letterSpacing: 0.6,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Satış, sipariş ve stok yönetimi araçları',
                  style: TextStyle(color: _kTextSecondary, fontSize: 13),
                ),
              ],
            ),
          ),

          // Primary Grid
          _buildHubGrid(context, pendingOrdersCount, lowStockCount),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHubGrid(BuildContext context, int pendingOrders, int lowStock) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.15,
      children: [
        _HubCard(
          title: 'Hızlı POS Satış',
          subtitle: 'Yeni veresiye veya nakit satış başlat',
          icon: Icons.point_of_sale_rounded,
          color: _kGreen,
          onTap: () => context.go(AppRoutes.sales),
        ),
        _HubCard(
          title: 'Siparişler',
          subtitle: 'Aktif mutfak/hazırlık siparişleri',
          icon: Icons.receipt_long_rounded,
          color: _kBlue,
          badge: pendingOrders > 0 ? '$pendingOrders' : null,
          badgeColor: _kBlue,
          onTap: () => context.go(AppRoutes.orders),
        ),
        _HubCard(
          title: 'Müşteriler',
          subtitle: 'Cari hesaplar ve bakiye detayları',
          icon: Icons.people_alt_rounded,
          color: _kPurple,
          onTap: () => context.go(AppRoutes.customers),
        ),
        _HubCard(
          title: 'Ürün & Stok',
          subtitle: 'Ürün kataloğu ve stok kontrolü',
          icon: Icons.inventory_2_rounded,
          color: _kTeal,
          badge: lowStock > 0 ? '$lowStock' : null,
          badgeColor: Colors.red,
          onTap: () => context.go(AppRoutes.products),
        ),
      ],
    );
  }
}

// ── Hub Card Widget ───────────────────────────────────────────────────────────

class _HubCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _HubCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.badge,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kCardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const Spacer(),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeColor ?? color,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: _kTextPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 10,
                  color: _kTextSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
