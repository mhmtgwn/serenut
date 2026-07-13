// lib/presentation/pages/license_page.dart
// Serenut POS — Lisans Yönetim Ekranı
// NOTE: Named LicenseManagementPage to avoid conflict with Flutter Material's LicensePage
// Created: Phase 6 — 01 Jul 2026

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/presentation/widgets/trial_banner_widget.dart';

// ── Design Constants ──────────────────────────────────────────────────────────
const _kBgColor       = Color(0xFFF8FAFC);
const _kCardBg        = Colors.white;
const _kBorderColor   = Color(0xFFE2E8F0);
const _kTextPrimary   = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kGreen         = Color(0xFF10B981);
const _kRed           = Color(0xFFEF4444);
const _kAmber         = Color(0xFFF59E0B);
const _kBlue          = Color(0xFF3B82F6);
const _kPurple        = Color(0xFF8B5CF6);

// ── Page ──────────────────────────────────────────────────────────────────────

class LicenseManagementPage extends ConsumerStatefulWidget {
  const LicenseManagementPage({super.key});

  @override
  ConsumerState<LicenseManagementPage> createState() => _LicenseManagementPageState();
}

class _LicenseManagementPageState extends ConsumerState<LicenseManagementPage> {
  final _tokenController = TextEditingController();
  bool _isValidating = false;
  String? _validationError;
  bool _tokenVisible = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final licenseService = ref.watch(licenseServiceProvider);
    final status         = licenseService.checkLicenseStatus();
    final info           = licenseService.getLicenseInfo();
    final daysLeft       = licenseService.getRemainingDays();
    final deviceUuid     = licenseService.getDeviceUuid();

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Lisans Yönetimi',
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
          // ── Current License Status Card ─────────────────────────────────
          _buildStatusHero(status, info, daysLeft),
          const SizedBox(height: 16),

          // ── License Details ─────────────────────────────────────────────
          if (info != null) ...[
            _buildSectionHeader('LİSANS DETAYLARI'),
            const SizedBox(height: 8),
            _buildDetailsCard(info, daysLeft),
            const SizedBox(height: 16),
          ],

          // ── Feature Matrix ──────────────────────────────────────────────
          _buildSectionHeader('ÖZELLİK MATRİSİ'),
          const SizedBox(height: 8),
          _buildFeatureMatrix(info?.tier ?? LicenseTier.basic),
          const SizedBox(height: 16),



          // ── Device UUID ─────────────────────────────────────────────────
          _buildSectionHeader('CİHAZ KİMLİĞİ'),
          const SizedBox(height: 8),
          _buildDeviceCard(deviceUuid),
          const SizedBox(height: 16),

          // ── Support ─────────────────────────────────────────────────────
          _buildSupportCard(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Status Hero ───────────────────────────────────────────────────────────

  Widget _buildStatusHero(String status, dynamic info, int daysLeft) {
    final (gradient, icon, title, subtitle, chipLabel, chipColor) = switch (status) {
      'valid' => (
        [const Color(0xFF059669), const Color(0xFF10B981)],
        Icons.verified_rounded,
        'Lisans Aktif',
        info != null ? '${(info as dynamic).tier.name} Paketi' : 'Aktif',
        '$daysLeft gün kaldı',
        _kGreen,
      ),
      'expired' => (
        [const Color(0xFFDC2626), const Color(0xFFEF4444)],
        Icons.lock_clock_rounded,
        'Lisans Sona Erdi',
        'Sistem kısıtlı modda',
        'Süresi Doldu',
        _kRed,
      ),
      'tampered' => (
        [const Color(0xFFB91C1C), const Color(0xFFDC2626)],
        Icons.security_rounded,
        'Güvenlik Uyarısı',
        'Saat manipülasyonu tespit edildi',
        'Kilitli',
        _kRed,
      ),
      _ => (
        [const Color(0xFFB45309), const Color(0xFFF59E0B)],
        Icons.warning_amber_rounded,
        'Lisans Bulunamadı',
        'Sistem deneme modunda',
        'Lisanssız',
        _kAmber,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient.cast<Color>(),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        )),
                    Text(subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 13,
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  chipLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Details Card ─────────────────────────────────────────────────────────

  Widget _buildDetailsCard(dynamic info, int daysLeft) {
    final expiryDate = info.expiryDate as DateTime;
    final tier       = info.tier as LicenseTier;
    final devices    = info.allowedDevices as List<String>;
    final isWildcard = devices.contains('*');

    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        children: [
          _DetailRow(
            icon: Icons.workspace_premium_rounded,
            color: _kPurple,
            label: 'Plan',
            value: tier.name,
          ),
          const Divider(height: 1, color: _kBorderColor),
          _DetailRow(
            icon: Icons.calendar_today_rounded,
            color: _kBlue,
            label: 'Bitiş Tarihi',
            value: DateFormat('dd MMMM yyyy', 'tr_TR').format(expiryDate),
          ),
          const Divider(height: 1, color: _kBorderColor),
          _DetailRow(
            icon: Icons.timer_rounded,
            color: daysLeft > 30 ? _kGreen : daysLeft > 7 ? _kAmber : _kRed,
            label: 'Kalan Süre',
            value: '$daysLeft gün',
          ),
          const Divider(height: 1, color: _kBorderColor),
          _DetailRow(
            icon: Icons.devices_rounded,
            color: _kTeal,
            label: 'Cihaz Limiti',
            value: isWildcard ? 'Sınırsız (*)' : '${devices.length}/${tier.deviceLimit}',
          ),
        ],
      ),
    );
  }

  // ── Feature Matrix ────────────────────────────────────────────────────────

  Widget _buildFeatureMatrix(LicenseTier currentTier) {
    final features = [
      ('Temel Satış (POS)', true, true, true),
      ('Cari Hesap Yönetimi', true, true, true),
      ('SMS Bildirimleri', false, true, true),
      ('Raporlar & Exportlar', false, true, true),
      ('Çoklu Cihaz', false, false, true),
      ('Bulut Senkronizasyon', false, false, true),
      ('Gelişmiş Raporlar', false, false, true),
      ('Öncelikli Destek', false, false, true),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Expanded(child: SizedBox()),
                ...LicenseTier.values.map((tier) => SizedBox(
                  width: 64,
                  child: Column(
                    children: [
                      Text(
                        tier.name,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: tier == currentTier ? _kGreen : _kTextSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (tier == currentTier)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: _kGreen,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Aktif',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                )),
              ],
            ),
          ),
          const Divider(height: 1, color: _kBorderColor),
          ...features.asMap().entries.map((entry) {
            final feat = entry.value;
            final isLast = entry.key == features.length - 1;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(feat.$1,
                            style: const TextStyle(
                                color: _kTextPrimary, fontSize: 12)),
                      ),
                      _TierCell(included: feat.$2, isActive: currentTier == LicenseTier.basic),
                      _TierCell(included: feat.$3, isActive: currentTier == LicenseTier.pro),
                      _TierCell(included: feat.$4, isActive: currentTier == LicenseTier.proPlus),
                    ],
                  ),
                ),
                if (!isLast) const Divider(height: 1, indent: 16, color: _kBorderColor),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ── Token Entry Card ──────────────────────────────────────────────────────

  Widget _buildTokenEntryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lisans anahtarınızı girin:',
            style: TextStyle(
              color: _kTextSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _tokenController,
            obscureText: !_tokenVisible,
            maxLines: _tokenVisible ? 3 : 1,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: _kTextPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'eyJtZXJjaGFudElk...',
              hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kBorderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kBlue),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _tokenVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: _kTextSecondary,
                  size: 18,
                ),
                onPressed: () => setState(() => _tokenVisible = !_tokenVisible),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          if (_validationError != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: _kRed, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _validationError!,
                    style: const TextStyle(color: _kRed, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _tokenController.clear();
                    setState(() => _validationError = null);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kTextSecondary,
                    side: const BorderSide(color: _kBorderColor),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Temizle'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _isValidating ? null : _validateAndSave,
                  icon: _isValidating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.verified_rounded, size: 18),
                  label: Text(_isValidating ? 'Doğrulanıyor...' : 'Anahtarı Doğrula & Kaydet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Device Card ───────────────────────────────────────────────────────────

  Widget _buildDeviceCard(String uuid) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Destek veya lisans yenileme için bu UUID\'yi paylaşın:',
            style: TextStyle(color: _kTextSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: uuid));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cihaz kimliği kopyalandı'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Kopyala'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kBlue,
                side: const BorderSide(color: _kBlue),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Support Card ──────────────────────────────────────────────────────────

  Widget _buildSupportCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kBlue.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBlue.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.support_agent_rounded, color: _kBlue, size: 28),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Destek Hattı',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _kTextPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Lisans sorunları için destek ekibimize ulaşın.',
                  style: TextStyle(color: _kTextSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Destek Al',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _validateAndSave() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _validationError = 'Lütfen bir lisans anahtarı girin.');
      return;
    }

    setState(() { _isValidating = true; _validationError = null; });

    try {
      final service = ref.read(licenseServiceProvider);
      final saved = await service.saveLicenseToken(token);

      if (!mounted) return;

      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Lisans başarıyla doğrulandı ve kaydedildi.'),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _tokenController.clear();
        // Invalidate license status providers
        ref.invalidate(licenseStatusProvider);
      } else {
        setState(() => _validationError =
            'Geçersiz lisans anahtarı. RSA imzası doğrulanamadı veya cihaz kimliği uyuşmuyor.');
      }
    } catch (e) {
      setState(() => _validationError = 'Doğrulama hatası: $e');
    } finally {
      if (mounted) setState(() => _isValidating = false);
    }
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
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ── Helper Widgets ────────────────────────────────────────────────────────────

const _kTeal = Color(0xFF0D9488);

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(color: _kTextSecondary, fontSize: 13)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: _kTextPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ],
      ),
    );
  }
}

class _TierCell extends StatelessWidget {
  final bool included;
  final bool isActive;

  const _TierCell({required this.included, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Center(
        child: Icon(
          included ? Icons.check_circle_rounded : Icons.remove_rounded,
          size: 18,
          color: included
              ? (isActive ? _kGreen : const Color(0xFFA7F3D0))
              : _kBorderColor,
        ),
      ),
    );
  }
}
