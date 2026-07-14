// lib/presentation/pages/finance_hub_page.dart
// Serenut OS — Finance & Ledger Center
// Created: Phase D — 01 Jul 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';

// ── Design Constants ──────────────────────────────────────────────────────────
const _kBgColor = Color(0xFFF8FAFC);
const _kCardBg = Colors.white;
const _kBorderColor = Color(0xFFE2E8F0);
const _kTextPrimary = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kGreen = Color(0xFF10B981);
const _kGreenDark = Color(0xFF047857);
const _kRed = Color(0xFFEF4444);
const _kRedLight = Color(0xFFFEF2F2);
const _kBlue = Color(0xFF3B82F6);
const _kBlueLight = Color(0xFFEFF6FF);
const _kAmber = Color(0xFFF59E0B);
const _kAmberLight = Color(0xFFFEF3C7);
const _kPurple = Color(0xFF8B5CF6);

// ── Page ──────────────────────────────────────────────────────────────────────

class FinanceHubPage extends ConsumerWidget {
  const FinanceHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardProvider);
    final debtorsAsync = ref.watch(debtorsProvider);

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Finans & Ledger Yönetimi',
          style: TextStyle(
            color: _kTextPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: _kGreen,
        onRefresh: () async {
          ref.invalidate(dashboardProvider);
          ref.invalidate(debtorsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Financial Receivables Card ─────────────────────────────────
            dashboardAsync.when(
              loading: () => const _LoadingPlaceholder(height: 120),
              error: (e, _) => _ErrorCard(message: e.toString()),
              data: (data) => _buildReceivablesHeader(data.summary),
            ),
            const SizedBox(height: 20),

            // ── Section: Raporlar & Dışa Aktarma ───────────────────────────
            _buildSectionHeader('📊 HIZLI RAPORLAR'),
            const SizedBox(height: 8),
            _buildReportsGroup(context),
            const SizedBox(height: 20),

            // ── Section: Riski Cari / Borçlu Müşteriler ────────────────────
            _buildSectionHeader('⚠️ BORÇLU CARİLER'),
            const SizedBox(height: 8),
            debtorsAsync.when(
              loading: () => const _LoadingPlaceholder(height: 180),
              error: (e, _) => _ErrorCard(message: e.toString()),
              data: (list) => _buildDebtorsList(context, list),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Receivables Card ──────────────────────────────────────────────────────

  Widget _buildReceivablesHeader(dynamic summary) {
    final receivables = summary.totalReceivables as double;
    final todayRevenue = summary.todayRevenue as double;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Toplam Cari Alacak',
            style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            '₺${receivables.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFF334155), height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Günlük Ciro',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  const SizedBox(height: 2),
                  Text('₺${todayRevenue.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ],
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _kGreen.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kGreen.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified_user_rounded, color: _kGreen, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'Ledger Güvenli',
                      style: TextStyle(
                          color: _kGreen,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Reports Group ─────────────────────────────────────────────────────────

  Widget _buildReportsGroup(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        children: [
          _ReportTile(
            icon: Icons.analytics_rounded,
            color: _kBlue,
            title: 'Detaylı Finans Raporları',
            subtitle: 'Ciro grafikleri, satış trendleri ve KDV analizleri',
            onTap: () => context.push(AppRoutes.reports),
          ),
          const Divider(height: 1, indent: 56, color: _kBorderColor),
          _ReportTile(
            icon: Icons.list_alt_rounded,
            color: _kPurple,
            title: 'Toplu Cari Ekstreleri',
            subtitle: 'Müşterilerin bakiye değişim dökümlerini inceleyin',
            onTap: () => context.go(AppRoutes.customers),
          ),
        ],
      ),
    );
  }

  // ── Debtors List ──────────────────────────────────────────────────────────

  Widget _buildDebtorsList(BuildContext context, List<dynamic> list) {
    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorderColor),
        ),
        child: const Center(
          child: Text(
            'Borçlu cari hesap bulunmuyor.',
            style: TextStyle(color: _kTextSecondary, fontSize: 13),
          ),
        ),
      );
    }

    final topDebtors = list.take(15).toList();

    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        children: topDebtors.asMap().entries.map((entry) {
          final customer = entry.value;
          final isLast = entry.key == topDebtors.length - 1;
          final balance = customer.balance as double;

          return Column(
            children: [
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: CircleAvatar(
                  backgroundColor: _kRedLight,
                  child: Text(
                    customer.name.isNotEmpty
                        ? customer.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: _kRed, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(
                  customer.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _kTextPrimary,
                      fontSize: 14),
                ),
                subtitle: Text(
                  customer.phone.isNotEmpty ? customer.phone : 'Telefon yok',
                  style: const TextStyle(color: _kTextSecondary, fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '₺${balance.abs().toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: _kRed,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded,
                        color: _kTextSecondary, size: 20),
                  ],
                ),
                onTap: () => context.push('/customers/detail/${customer.id}'),
              ),
              if (!isLast)
                const Divider(height: 1, indent: 72, color: _kBorderColor),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: _kTextSecondary,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ── Report Tile ───────────────────────────────────────────────────────────────

class _ReportTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ReportTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14, color: _kTextPrimary)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: _kTextSecondary, fontSize: 11)),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: _kTextSecondary, size: 20),
      onTap: onTap,
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _LoadingPlaceholder extends StatelessWidget {
  final double height;
  const _LoadingPlaceholder({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderColor),
      ),
      child: const Center(
        child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(_kGreen), strokeWidth: 2),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kRed.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kRed.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: _kRed),
          const SizedBox(width: 12),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: _kRed, fontSize: 12))),
        ],
      ),
    );
  }
}
