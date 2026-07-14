// lib/presentation/pages/management_hub_page.dart
// Serenut OS — Admin Control Plane & Management Hub
// Redesigned to match SettingsPage design guidelines: 01 Jul 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/presentation/pages/license_page.dart';
import 'package:serenutos/presentation/widgets/trial_banner_widget.dart';
import 'package:serenutos/presentation/pages/admin/audit_center_page.dart';
import 'package:serenutos/presentation/pages/admin/recovery_center_page.dart';

// ── Design Constants (Aligned with SettingsPage) ──────────────────────────────
const _kBgColor = Color(0xFFFAFAFC);
const _kCardBg = Colors.white;
const _kBorderColor = Color(0xFFF0F0F3);
const _kTextPrimary = Color(0xFF1E293B);
const _kTextSecondary = Color(0xFF64748B);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kBlue = Color(0xFF3B82F6);
const _kPurple = Color(0xFF8B5CF6);
const _kTeal = Color(0xFF0D9488);
const _kAmber = Color(0xFFF59E0B);

// ── Page ──────────────────────────────────────────────────────────────────────

class ManagementHubPage extends ConsumerStatefulWidget {
  const ManagementHubPage({super.key});

  @override
  ConsumerState<ManagementHubPage> createState() => _ManagementHubPageState();
}

class _ManagementHubPageState extends ConsumerState<ManagementHubPage> {
  bool _isUnlocked = false;

  void _runGuardedAction(VoidCallback action) {
    if (_isUnlocked) {
      action();
    } else {
      requireAdminAccess(
        context,
        title: 'Yönetim Doğrulaması',
        onGranted: (approvedByUserId, approvedByUserName) {
          if (mounted) {
            setState(() {
              _isUnlocked = true;
            });
            action();
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final licStatus = ref.watch(licenseStatusProvider);

    // Guard — user must be logged in
    if (currentUser == null) {
      return const Scaffold(
        backgroundColor: _kBgColor,
        body: Center(
          child: Text('Lütfen oturum açın.',
              style: TextStyle(color: _kTextSecondary)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: _kBgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Yönetim & Ayarlar',
          style: TextStyle(
            color: _kTextPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(
              _isUnlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
              color: _isUnlocked ? _kGreen : _kPurple,
            ),
            tooltip: _isUnlocked
                ? 'Yönetici yetkileri açık (Kilitle)'
                : 'Yetkileri Aç',
            onPressed: () {
              if (_isUnlocked) {
                setState(() => _isUnlocked = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Yönetici yetkileri kilitlendi.')),
                );
              } else {
                _runGuardedAction(() {});
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── Welcome Profile Card ──────────────────────────────────────────
          _buildUserWelcomeBanner(currentUser, licStatus),
          const SizedBox(height: 20),

          // ── Section: Ürünler & Stok ─────────────────────────────────────────
          _buildSectionHeader('İŞLETME VE KATALOG'),
          _buildRoundedCard([
            _buildCategoryRow(
              title: 'Ürünler ve Stok Listesi',
              subtitle: 'Fiyatları, barkodları ve stok seviyelerini yönetin',
              icon: Icons.inventory_2_rounded,
              color: _kTeal,
              onTap: () => context.push(AppRoutes.products),
            ),
          ]),
          const SizedBox(height: 20),

          // ── Section: Cihaz ve Donanım ──────────────────────────────────────
          _buildSectionHeader('DONANIM VE BAĞLANTILAR'),
          _buildRoundedCard([
            _buildCategoryRow(
              title: 'Yazıcı & Donanım Testi',
              subtitle: 'Yazıcı kuyruğu bağlantısı ve fiş denemeleri',
              icon: Icons.print_rounded,
              color: _kBlue,
              onTap: () => context.push('/settings/hardware_test'),
            ),
            const _Divider(),
            _buildCategoryRow(
              title: 'Tüm Sistem Ayarları',
              subtitle: 'İşletme unvanı, vergi oranları ve fiş şablonları',
              icon: Icons.settings_rounded,
              color: _kTextSecondary,
              onTap: () => context.push('/settings'),
            ),
          ]),
          const SizedBox(height: 20),

          // ── Section: Raporlar ──────────────────────────────────────────────
          _buildSectionHeader('RAPORLAR VE FİNANS'),
          _buildRoundedCard([
            _buildCategoryRow(
              title: 'Finans Hub & Cari Raporlar',
              subtitle: 'Ciro raporu ve KDV analizlerini excel olarak indirin',
              icon: Icons.account_balance_wallet_rounded,
              color: _kGreen,
              onTap: () => context.push(AppRoutes.finance),
            ),
          ]),
          const SizedBox(height: 20),

          // ── Section: Gelişmiş Güvenlik (PIN Korumalı) ──────────────────────
          _buildSectionHeader('SİSTEM GÜVENLİĞİ VE BULUT (PIN KORUMALI)'),
          _buildRoundedCard([
            _buildCategoryRow(
              title: 'Lisans Anahtarı & Paketler',
              subtitle: licStatus.status == 'valid'
                  ? '${licStatus.tierName} — ${licStatus.daysLeft} gün aktif'
                  : '⚠️ Lisans aktif değil',
              icon: Icons.verified_rounded,
              color: _kGreen,
              onTap: () => _runGuardedAction(() {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LicenseManagementPage()));
              }),
            ),
            const _Divider(),
            _buildCategoryRow(
              title: 'Veri Bütünlüğü Check & Repair',
              subtitle: 'Yetim kayıt denetimi, bakiye düzeltme (State Replay)',
              icon: Icons.health_and_safety_rounded,
              color: _kPurple,
              onTap: () =>
                  _runGuardedAction(() => context.push('/settings/db-health')),
            ),
            const _Divider(),
            _buildCategoryRow(
              title: 'Yedekleme & Geri Yükleme',
              subtitle: 'Bulut senkronizasyonu ve yerel veritabanı yedekleri',
              icon: Icons.backup_rounded,
              color: _kTeal,
              onTap: () =>
                  _runGuardedAction(() => context.push('/settings/backup')),
            ),
            const _Divider(),
            _buildCategoryRow(
              title: 'Denetim Merkezi (Audit Center)',
              subtitle: 'Fiyat değişimleri, silmeler ve sistem logları',
              icon: Icons.assignment_turned_in_rounded,
              color: _kBlue,
              onTap: () => _runGuardedAction(() {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AuditCenterPage()));
              }),
            ),
            const _Divider(),
            _buildCategoryRow(
              title: 'Veri Kurtarma Merkezi (Recovery Center)',
              subtitle: 'Silinen ürünleri, müşterileri ve satışları kurtarın',
              icon: Icons.restore_from_trash_rounded,
              color: _kRed,
              onTap: () => _runGuardedAction(() {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RecoveryCenterPage()));
              }),
            ),
            const _Divider(),
            _buildCategoryRow(
              title: 'Admin Kontrol Merkezi',
              subtitle: 'Gelişmiş veri replikasyonu ve telemetri izleme',
              icon: Icons.admin_panel_settings_rounded,
              color: _kAmber,
              onTap: () => _runGuardedAction(() => context.push('/admin')),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildUserWelcomeBanner(AuthUser user, LicenseStatus licStatus) {
    final initials = user.name.isNotEmpty ? user.name[0].toUpperCase() : 'A';
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [_kPurple, _kPurple.withOpacity(0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 22),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _kTextPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Yönetici • ${licStatus.tierName}',
                    style:
                        const TextStyle(color: _kTextSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kPurple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Yönetim',
                style: TextStyle(
                    color: _kPurple, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoundedCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _buildCategoryRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _iOSIconBadge(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: _kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _kTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: _kTextSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iOSIconBadge({required IconData icon, required Color color}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: _kTextSecondary, size: 18),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 16),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: _kTextSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ── Divider Widget ───────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 64),
      height: 0.5,
      color: _kBorderColor,
    );
  }
}
