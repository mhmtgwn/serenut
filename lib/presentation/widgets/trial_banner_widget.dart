// lib/presentation/widgets/trial_banner_widget.dart
// Serenut OS — Trial/License Countdown Banner
// Backend: LicenseService.getRemainingDays() + checkLicenseStatus() — sıfır değişiklik
// Created: Phase 4 — 01 Jul 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/providers/service_providers.dart';

// ── Design Constants ──────────────────────────────────────────────────────────
const _kAmber = Color(0xFFF59E0B);
const _kRed = Color(0xFFEF4444);
const _kGreen = Color(0xFF10B981);

// ── License Status Provider ───────────────────────────────────────────────────

final licenseStatusProvider = Provider<LicenseStatus>((ref) {
  final service = ref.watch(licenseServiceProvider);
  final trialManager = ref.watch(trialManagerProvider);

  final isTrialActive = trialManager.isTrialActive();
  final isCommercialActive = trialManager.isCommercialActive();
  final remainingDays = trialManager.getRemainingDays();

  if (isTrialActive) {
    return LicenseStatus(
      status: 'trial',
      daysLeft: remainingDays,
      tierName: 'DENEME',
      expiryDate: null,
      deviceUuid: service.getDeviceUuid(),
    );
  }

  if (isCommercialActive) {
    return LicenseStatus(
      status: 'active',
      daysLeft: remainingDays,
      tierName: 'TİCARİ LİSANS',
      expiryDate: null,
      deviceUuid: service.getDeviceUuid(),
    );
  }

  final status = service.checkLicenseStatus();
  final info = service.getLicenseInfo();
  final daysLeft = service.getRemainingDays();
  final deviceUuid = service.getDeviceUuid();

  return LicenseStatus(
    status: status,
    daysLeft: daysLeft,
    tierName: info?.tier.name ?? 'UNLICENSED',
    expiryDate: info?.expiryDate,
    deviceUuid: deviceUuid,
  );
});

class LicenseStatus {
  final String status;
  final int daysLeft;
  final String tierName;
  final DateTime? expiryDate;
  final String deviceUuid;

  const LicenseStatus({
    required this.status,
    required this.daysLeft,
    required this.tierName,
    this.expiryDate,
    required this.deviceUuid,
  });
}

// ── Trial Banner Widget ───────────────────────────────────────────────────────

/// Shows a persistent warning banner when:
/// - License is expired
/// - License is tampered (clock manipulation detected)
/// - Less than 14 days remaining
///
/// Returns SizedBox.shrink() when license is healthy.
class TrialBannerWidget extends ConsumerWidget {
  const TrialBannerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licStatus = ref.watch(licenseStatusProvider);

    // Active commercial license (e.g. 364 days remaining)
    if (licStatus.status == 'active') {
      if (licStatus.daysLeft > 14) {
        return const SizedBox
            .shrink(); // Healthy commercial license — NO BANNER
      }
      final isLow = licStatus.daysLeft <= 3;
      return _Banner(
        icon: Icons.verified_user_rounded,
        color: isLow ? _kRed : _kAmber,
        title: 'Lisans Süreniz Doluyor',
        subtitle:
            'Ticari lisansınızın bitmesine ${licStatus.daysLeft} gün kaldı.',
        actionLabel: 'Yenile',
        onAction: () => context.push(AppRoutes.license),
        isCritical: isLow,
      );
    }

    // Active trial countdown
    if (licStatus.status == 'trial') {
      final isLow = licStatus.daysLeft <= 7;
      return _Banner(
        icon: Icons.timer_rounded,
        color: isLow ? _kAmber : _kGreen,
        title: 'Deneme Sürümü Aktif',
        subtitle: 'Deneme sürenizin bitmesine ${licStatus.daysLeft} gün kaldı.',
        actionLabel: 'Lisans Gir',
        onAction: () => context.push(AppRoutes.license),
        isCritical: false,
      );
    }

    // Tampered clock — blocker level
    if (licStatus.status == 'tampered') {
      return _Banner(
        icon: Icons.security_rounded,
        color: _kRed,
        title: 'Sistem Saati Manipülasyonu Tespit Edildi',
        subtitle:
            'Lütfen cihazınızın saatini kontrol edin ve desteğe başvurun.',
        actionLabel: 'Destek Al',
        onAction: () => context.push('/settings'),
        isCritical: true,
      );
    }

    // Expired license
    if (licStatus.status == 'expired') {
      return _Banner(
        icon: Icons.lock_clock_rounded,
        color: _kRed,
        title: 'Lisansınız Sona Erdi',
        subtitle:
            'Sistem kısıtlı modda çalışıyor. Lisansı yenilemek için tıklayın.',
        actionLabel: 'Yenile',
        onAction: () => context.push(AppRoutes.license),
        isCritical: true,
      );
    }

    // Unlicensed — no license at all
    if (licStatus.status == 'unlicensed') {
      return _Banner(
        icon: Icons.warning_amber_rounded,
        color: _kAmber,
        title: 'Lisans Bulunamadı',
        subtitle: 'Geçerli bir lisans anahtarı girin veya destek alın.',
        actionLabel: 'Lisans Gir',
        onAction: () => context.push(AppRoutes.license),
        isCritical: false,
      );
    }

    // Valid but expiring soon (< 14 days)
    if (licStatus.status == 'valid' && licStatus.daysLeft < 14) {
      final urgency = licStatus.daysLeft <= 3;
      return _Banner(
        icon: Icons.timer_rounded,
        color: urgency ? _kRed : _kAmber,
        title: urgency
            ? '⚠️ Lisansınızın dolmasına ${licStatus.daysLeft} gün kaldı!'
            : 'Lisansınızın dolmasına ${licStatus.daysLeft} gün kaldı',
        subtitle: 'Kesintisiz kullanım için lisansı yenileyin.',
        actionLabel: 'Yenile',
        onAction: () => context.push(AppRoutes.license),
        isCritical: urgency,
      );
    }

    // All good — no banner
    return const SizedBox.shrink();
  }
}

// ── Banner Implementation ─────────────────────────────────────────────────────

class _Banner extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final bool isCritical;

  const _Banner({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    required this.isCritical,
  });

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    if (widget.isCritical) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 2),
      )..repeat(reverse: true);
    } else {
      _pulse = AnimationController(vsync: this);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed && !widget.isCritical) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final alpha = widget.isCritical ? (0.06 + _pulse.value * 0.04) : 0.06;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: alpha),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: widget.color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: widget.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        color: widget.color.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onAction,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.actionLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (!widget.isCritical) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() => _dismissed = true),
                  child: Icon(Icons.close_rounded,
                      size: 16, color: widget.color.withValues(alpha: 0.6)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
