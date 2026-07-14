// lib/presentation/pages/admin/admin_page.dart
// Serenut POS — Admin Control Center
// Access: Settings > Admin Panel (admin role only)
// Created: Phase 5 — 01 Jul 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/sync_provider.dart';
import 'package:serenutos/presentation/pages/admin/observability_dashboard.dart';
import 'package:serenutos/presentation/pages/admin/recovery_center_page.dart';
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
const _kAmber = Color(0xFFF59E0B);
const _kBlue = Color(0xFF3B82F6);
const _kPurple = Color(0xFF8B5CF6);
const _kTeal = Color(0xFF0D9488);

// ── Page ──────────────────────────────────────────────────────────────────────

class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final syncState = ref.watch(syncProvider);
    final licStatus = ref.watch(licenseStatusProvider);
    final printQueue = ref.watch(persistentPrintQueueProvider);

    // Guard — admin, owner, or sysadmin only
    if (currentUser == null ||
        !(currentUser.role == UserRole.admin ||
            currentUser.role == UserRole.owner ||
            currentUser.role == UserRole.sysadmin)) {
      return Scaffold(
        backgroundColor: _kBgColor,
        appBar: AppBar(
          title: const Text('Admin Paneli'),
          backgroundColor: Colors.white,
          elevation: 0.5,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 52, color: Color(0xFFCBD5E1)),
              SizedBox(height: 12),
              Text(
                'Bu alana erişim için yönetici yetkisi gereklidir.',
                style: TextStyle(color: Color(0xFF64748B)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final hasConflict = syncState.status == SyncStatus.error;

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Admin Kontrol Merkezi',
          style: TextStyle(
            color: _kTextPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          // System Health Pulse
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _SystemPulseDot(
                isHealthy: !hasConflict && licStatus.status == 'valid'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Trial / License Banner ─────────────────────────────────────────
          const TrialBannerWidget(),

          // ── Welcome Header ────────────────────────────────────────────────
          _buildWelcomeCard(currentUser, licStatus),
          const SizedBox(height: 20),

          // ── Alert Banners ─────────────────────────────────────────────────
          if (hasConflict) ...[
            _buildAlertCard(
              icon: Icons.sync_problem_rounded,
              color: _kRed,
              title: 'Aktif Senkronizasyon Çakışması',
              subtitle: syncState.lastError ?? 'Bilinmeyen hata',
              actionLabel: 'İncele',
              onAction: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const RecoveryCenterPage())),
            ),
            const SizedBox(height: 12),
          ],

          // ── Section: Sistem İzleme ────────────────────────────────────────
          _buildSectionHeader('⚡ SİSTEM İZLEME'),
          const SizedBox(height: 8),
          _buildAdminCard(children: [
            _AdminTile(
              icon: Icons.monitor_heart_rounded,
              color: _kGreen,
              title: 'Sistem Sağlık Durumu',
              subtitle: 'Drift rate, anomali, sync failure oranı',
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ObservabilityDashboard())),
            ),
            const _Divider(),
            _AdminTile(
              icon: Icons.cloud_sync_rounded,
              color: hasConflict ? _kRed : _kBlue,
              title: 'Senkronizasyon & Kurtarma',
              subtitle: hasConflict
                  ? '⚠️ Aktif çakışma — dokunun'
                  : 'Tüm sync oturumları ve incident geçmişi',
              badge: hasConflict ? '!' : null,
              badgeColor: _kRed,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const RecoveryCenterPage())),
            ),
          ]),
          const SizedBox(height: 16),

          // ── Section: Operasyonel Araçlar ──────────────────────────────────
          _buildSectionHeader('🔧 OPERASYONEL ARAÇLAR'),
          const SizedBox(height: 8),
          _buildAdminCard(children: [
            _AdminTile(
              icon: Icons.print_rounded,
              color: _kTeal,
              title: 'Yazıcı Kuyruğu',
              subtitle: 'Bekleyen fiş işleri ve yeniden deneme',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PrintQueuePage())),
            ),
            const _Divider(),
            _AdminTile(
              icon: Icons.sms_rounded,
              color: _kAmber,
              title: 'SMS Gönderim Geçmişi',
              subtitle: 'Gönderim durumu, başarısız SMS\'ler',
              onTap: () => context.push('/settings/sms-history'),
            ),
            const _Divider(),
            _AdminTile(
              icon: Icons.health_and_safety_rounded,
              color: _kPurple,
              title: 'Veritabanı Sağlık Kontrolü',
              subtitle: 'Yetim kayıtlar ve veri bütünlüğü',
              onTap: () => context.push('/settings/db-health'),
            ),
          ]),
          const SizedBox(height: 16),

          // ── Section: Lisans & Cihaz ───────────────────────────────────────
          _buildSectionHeader('🔑 LİSANS VE CİHAZ'),
          const SizedBox(height: 8),
          _buildAdminCard(children: [
            _AdminTile(
              icon: Icons.verified_rounded,
              color: licStatus.status == 'valid' ? _kGreen : _kRed,
              title: 'Lisans Yönetimi',
              subtitle: _buildLicenseSubtitle(licStatus),
              onTap: () => context.push('/license'),
            ),
            const _Divider(),
            _AdminTile(
              icon: Icons.devices_rounded,
              color: _kBlue,
              title: 'Cihaz Kimliği',
              subtitle: '${licStatus.deviceUuid.substring(0, 18)}...',
              onTap: () => _showDeviceUuidDialog(context, licStatus.deviceUuid),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _buildWelcomeCard(AuthUser user, LicenseStatus licStatus) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: _kGreen.withValues(alpha: 0.2),
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : 'A',
              style: const TextStyle(
                color: _kGreen,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    )),
                Text(
                  'Yönetici • ${licStatus.tierName}',
                  style:
                      const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: licStatus.status == 'valid'
                  ? _kGreen.withValues(alpha: 0.15)
                  : _kRed.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: licStatus.status == 'valid'
                    ? _kGreen.withValues(alpha: 0.4)
                    : _kRed.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              licStatus.status == 'valid' ? '● Aktif' : '● ${licStatus.status}',
              style: TextStyle(
                color: licStatus.status == 'valid' ? _kGreen : _kRed,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                Text(subtitle,
                    style:
                        const TextStyle(color: _kTextSecondary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(actionLabel,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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

  String _buildLicenseSubtitle(LicenseStatus licStatus) {
    switch (licStatus.status) {
      case 'valid':
        return '${licStatus.tierName} — ${licStatus.daysLeft} gün kaldı';
      case 'expired':
        return '❌ Lisans sona erdi';
      case 'unlicensed':
        return '⚠️ Lisans bulunamadı';
      case 'tampered':
        return '🚨 Saat manipülasyonu';
      default:
        return licStatus.status;
    }
  }

  void _showDeviceUuidDialog(BuildContext context, String uuid) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.devices_rounded, size: 20, color: _kBlue),
            SizedBox(width: 8),
            Text('Cihaz Kimliği', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Destek veya lisans yenileme için bu ID\'yi paylaşın:',
              style: TextStyle(color: _kTextSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorderColor),
              ),
              child: SelectableText(
                uuid,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: _kTextPrimary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
}

// ── Admin Tile ────────────────────────────────────────────────────────────────

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _AdminTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.badge,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  if (badge != null)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: badgeColor ?? _kRed,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: _kTextPrimary,
                        )),
                    Text(subtitle,
                        style: const TextStyle(
                          color: _kTextSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: _kTextSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 68, endIndent: 16, color: _kBorderColor);
}

// ── System Pulse Dot ──────────────────────────────────────────────────────────

class _SystemPulseDot extends StatefulWidget {
  final bool isHealthy;
  const _SystemPulseDot({required this.isHealthy});

  @override
  State<_SystemPulseDot> createState() => _SystemPulseDotState();
}

class _SystemPulseDotState extends State<_SystemPulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isHealthy ? _kGreen : _kRed;
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.2 + _controller.value * 0.4),
              blurRadius: 4 + _controller.value * 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
