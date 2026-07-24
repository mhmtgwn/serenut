import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/services/version_checker.dart';
import 'package:serenutos/infrastructure/services/release_manager_service.dart';
import 'package:serenutos/presentation/widgets/update_dialog.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/service_providers.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  bool _checking = false;
  String? _lastResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Uygulama Hakkında'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 0,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.storefront_rounded,
                          size: 56, color: Color(0xFF16A34A)),
                      const SizedBox(height: 12),
                      const Text(
                        'Serenut OS',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Sürüm ${VersionChecker.currentVersion}',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                      if (_lastResult != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _lastResult!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: Colors.white,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const Icon(Icons.system_update_rounded,
                      color: Color(0xFF3B82F6)),
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
        ),
      ),
    );
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
        deviceId: null,
      );
    } catch (error) {
      if (mounted) setState(() => _lastResult = 'Kontrol başarısız: $error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }
}
