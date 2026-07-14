// lib/presentation/pages/system_hub_page.dart
// Serenut OS — System Observability & Diagnostics Center
// Created: Phase E — 01 Jul 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/providers/sync_provider.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/presentation/pages/admin/observability_dashboard.dart';
import 'package:serenutos/presentation/pages/settings/print_queue_page.dart';
import 'package:serenutos/presentation/widgets/trial_banner_widget.dart';

// ── Design Constants ──────────────────────────────────────────────────────────
const _kBgColor = Color(0xFFF8FAFC);
const _kCardBg = Colors.white;
const _kBorderColor = Color(0xFFE2E8F0);
const _kTextPrimary = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kBlue = Color(0xFF3B82F6);
const _kAmber = Color(0xFFF59E0B);
const _kPurple = Color(0xFF8B5CF6);
const _kTeal = Color(0xFF0D9488);

// ── Page ──────────────────────────────────────────────────────────────────────

class SystemHubPage extends ConsumerWidget {
  const SystemHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncProvider);
    final licStatus = ref.watch(licenseStatusProvider);
    final printQueue = ref.watch(persistentPrintQueueProvider);

    final hasSyncError = syncState.status == SyncStatus.error;

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Sistem Sağlık & İzleme',
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
          // ── System Health Overview ─────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 12),
            child: Text(
              'SİSTEM TELEMETRİ GÖSTERGELERİ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _kTextSecondary,
                letterSpacing: 0.6,
              ),
            ),
          ),

          // Observability grid
          _buildHealthStatusCard(syncState, licStatus),
          const SizedBox(height: 20),

          // ── Section: Operasyonel Kuyruklar ────────────────────────────────
          _buildSectionHeader('⚙️ OPERASYONEL KUYRUKLAR'),
          const SizedBox(height: 8),
          _buildSystemCard(children: [
            _SystemTile(
              icon: Icons.print_rounded,
              color: _kTeal,
              title: 'Yazıcı Kuyruğu Denetimi',
              subtitle: 'Başarısız fişler, bekleyen işler ve el ile tetikleme',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PrintQueuePage())),
            ),
            const _Divider(),
            _SystemTile(
              icon: Icons.sms_rounded,
              color: _kBlue,
              title: 'SMS Gönderim Geçmişi',
              subtitle: 'Müşteri bildirimleri, kurye SMS günlükleri',
              onTap: () => context.push('/settings/sms-history'),
            ),
          ]),
          const SizedBox(height: 20),

          // ── Section: Teşhis & Güvenlik ────────────────────────────────────
          _buildSectionHeader('⚡ TEŞHİS VE GÜVENLİK'),
          const SizedBox(height: 8),
          _buildSystemCard(children: [
            _SystemTile(
              icon: Icons.monitor_heart_rounded,
              color: _kGreen,
              title: 'Canlı Telemetri Dashboard',
              subtitle: 'Sapma oranı (drift), anomali ve hata günlükleri',
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ObservabilityDashboard())),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Health Card ────────────────────────────────────────────────────────────

  Widget _buildHealthStatusCard(SyncState sync, LicenseStatus license) {
    final isHealthy =
        sync.status != SyncStatus.error && license.status == 'valid';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isHealthy ? _kGreen.withOpacity(0.04) : _kRed.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHealthy ? _kGreen.withOpacity(0.2) : _kRed.withOpacity(0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
                  isHealthy ? _kGreen.withOpacity(0.1) : _kRed.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isHealthy ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded,
              color: isHealthy ? _kGreen : _kRed,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHealthy
                      ? 'Sistem Sağlığı: Stabil'
                      : 'Sistem Sağlığı: İnceleme Gerekli',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isHealthy ? _kGreen : _kRed,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isHealthy
                      ? 'Tüm yerel işlemler güvenle işlendi, bulut bağlantısı stabil ve donanım kuyrukları temiz.'
                      : 'Lütfen aktif veri çakışmalarını veya süresi biten lisans bildirimlerini inceleyin.',
                  style: const TextStyle(
                    color: _kTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(children: children),
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

// ── System Tile Widget ────────────────────────────────────────────────────────

class _SystemTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SystemTile({
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
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13, color: _kTextPrimary)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: _kTextSecondary, fontSize: 11)),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: _kTextSecondary, size: 18),
      onTap: onTap,
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 64, endIndent: 16, color: _kBorderColor);
}
