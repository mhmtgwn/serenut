import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/services/version_checker.dart';
import 'package:serenutos/infrastructure/services/release_manager_service.dart';
import 'package:serenutos/presentation/widgets/update_dialog.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart';
import 'package:serenutos/presentation/widgets/serenut_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  bool _checking = false;
  String? _lastResult;

  @override
  void initState() {
    super.initState();
    VersionChecker.getAppVersion().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final licenseService = ref.watch(licenseServiceProvider);
    final licenseInfo = licenseService.getLicenseInfo();
    final licenseStatus = licenseService.checkLicenseStatus();
    final remainingDays = licenseService.getRemainingDays();

    return FullScreenSettingsPage(
      title: 'Uygulama Hakkında',
      useScrollView: false,
      child: ListView(
        children: [
          SerenutSurface(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                const Icon(Icons.storefront_rounded,
                    size: 52, color: POSColors.green),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Serenut OS',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Sürüm ${VersionChecker.currentVersion}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (_lastResult != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _lastResult!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SerenutSurface(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _licenseColor(licenseStatus).withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: Icon(
                    Icons.verified_user_outlined,
                    color: _licenseColor(licenseStatus),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lisans Durumu',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _licenseDescription(
                          licenseStatus,
                          licenseInfo?.tier.name,
                          remainingDays,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final uri = Uri.parse('https://serenut.com/pricing');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Lisansı Uzat / Yenile'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: POSColors.green,
                          side: const BorderSide(color: POSColors.green),
                        ),
                      ),
                    ],
                  ),
                ),
                SerenutStatusBadge(
                  label: _licenseLabel(licenseStatus),
                  color: _licenseColor(licenseStatus),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SerenutSurface(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.all(AppSpacing.md),
              leading: const Icon(
                Icons.system_update_rounded,
                color: POSColors.green,
              ),
              title: const Text(
                'Güncellemeleri denetle',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Kararlı kanaldaki en son sürümü kontrol eder.',
              ),
              trailing: _checking
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _checking ? null : _checkForUpdate,
            ),
          ),
        ],
      ),
    );
  }

  String _licenseLabel(String status) => switch (status) {
        'valid' || 'active' => 'Aktif',
        'trial' => 'Deneme',
        'expired' => 'Süresi doldu',
        'tampered' => 'Güvenlik uyarısı',
        _ => 'Bulunamadı',
      };

  Color _licenseColor(String status) => switch (status) {
        'valid' || 'active' => POSColors.green,
        'trial' => POSColors.blue,
        'expired' || 'tampered' => POSColors.red,
        _ => POSColors.amberDark,
      };

  String _licenseDescription(String status, String? tier, int days) {
    return switch (status) {
      'valid' ||
      'active' =>
        '${tier ?? 'Standart'} paket • $days gün kullanım süresi kaldı.',
      'trial' => 'Deneme kullanımı aktif • $days gün kaldı.',
      'expired' => 'Lisans süresi dolmuş. Destek ekibiyle iletişime geçin.',
      'tampered' =>
        '${tier ?? 'Mevcut'} lisans bulundu; cihaz saati yeniden doğrulanmalı.',
      _ => 'Bu cihazda doğrulanmış lisans bilgisi bulunamadı.',
    };
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _checking = true;
      _lastResult = null;
    });
    try {
      final checker = VersionChecker(apiClient: ref.read(apiClientProvider));
      final info = await checker.getVersionInfo();
      if (!mounted) return;
      if (info == null) {
        setState(() => _lastResult =
            'Güncelleme sunucusuna ulaşılamadı. Daha sonra tekrar deneyin.');
        return;
      }
      final hasUpdate = VersionChecker.isVersionOlder(
        VersionChecker.currentVersion,
        info.latestVersion,
      );
      if (!hasUpdate) {
        setState(() => _lastResult = 'Uygulamanız güncel.');
        return;
      }
      await showUpdateDialog(
        context: context,
        updateInfo: UpdateInfo(
          hasUpdate: true,
          isForceUpdate: info.isForceUpdate,
          latestVersion: info.latestVersion,
          minRequiredVersion: info.minRequiredVersion,
          downloadUrl: info.downloadUrl,
          sha256Hash: info.sha256Hash,
          signature: info.signature,
          fileSizeBytes: info.fileSizeBytes,
          releaseNotes: info.releaseNotes,
          channel: 'stable',
        ),
        releaseManager: ref.read(releaseManagerServiceProvider),
        platform: Platform.isAndroid ? 'android' : 'windows',
        jwtToken: ref.read(authServiceProvider).getJwtToken(),
        deviceId:
            ref.read(licenseServiceProvider).getLicenseInfo()?.activationId,
      );
    } catch (error) {
      if (mounted) setState(() => _lastResult = 'Kontrol başarısız: $error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }
}
