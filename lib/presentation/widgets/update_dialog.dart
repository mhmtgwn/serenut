// lib/presentation/widgets/update_dialog.dart
// Serenut Platform — OTA Update Dialog (Sprint 6)
// Three modes: force update blocker, optional update offer, download progress screen.
// Created: 04 Jul 2026

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:serenutos/infrastructure/services/release_manager_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/providers/service_providers.dart';

enum _DialogState { offer, downloading, verifying, done, error }

/// Shows the update dialog to the user.
///
/// For forced updates, the dialog cannot be dismissed.
/// For optional updates, a 'Sonraya Bırak' button is shown.
///
/// Returns true if the update was installed, false if skipped/dismissed.
Future<bool> showUpdateDialog({
  required BuildContext context,
  required UpdateInfo updateInfo,
  required ReleaseManagerService releaseManager,
  required String platform,
  required String? jwtToken,
  required String? deviceId,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false, // Always non-dismissible via tap outside
        builder: (_) => _UpdateDialog(
          updateInfo: updateInfo,
          releaseManager: releaseManager,
          platform: platform,
          jwtToken: jwtToken,
          deviceId: deviceId,
        ),
      ) ??
      false;
}

class _UpdateDialog extends ConsumerStatefulWidget {
  final UpdateInfo updateInfo;
  final ReleaseManagerService releaseManager;
  final String platform;
  final String? jwtToken;
  final String? deviceId;

  const _UpdateDialog({
    required this.updateInfo,
    required this.releaseManager,
    required this.platform,
    required this.jwtToken,
    required this.deviceId,
  });

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> with SingleTickerProviderStateMixin {
  _DialogState _state = _DialogState.offer;
  double _progress = 0.0;
  String _progressText = '';
  String? _errorMessage;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _startDownload() async {
    setState(() {
      _state = _DialogState.verifying;
      _progress = 0.0;
      _progressText = 'Sistem gereksinimleri kontrol ediliyor...';
    });

    final rollback = ref.read(rollbackManagerProvider);
    final specResult = await rollback.verifyInstallationSpecs();
    if (!specResult.isAllPass) {
      setState(() {
        _state = _DialogState.error;
        _errorMessage = 'Sistem gereksinimleri karşılanamadı:\n${specResult.issues.join('\n')}';
      });
      return;
    }

    setState(() {
      _progressText = 'Mevcut sürüm yedekleniyor...';
    });
    final backupSuccess = await rollback.backupCurrentVersion();
    if (!backupSuccess) {
      setState(() {
        _state = _DialogState.error;
        _errorMessage = 'Mevcut sürüm yedeklenemedi. Güncelleme güvenliğiniz için iptal edildi.';
      });
      return;
    }

    setState(() {
      _state = _DialogState.downloading;
      _progress = 0.0;
      _progressText = 'İndiriliyor...';
    });

    File? downloadedFile;

    try {
      // Stream download progress
      await for (final progress in widget.releaseManager.downloadUpdate(
        updateInfo: widget.updateInfo,
        platform: widget.platform,
        jwtToken: widget.jwtToken,
        deviceId: widget.deviceId,
      )) {
        if (!mounted) return;
        final totalMB = progress.totalBytes != null ? (progress.totalBytes! / 1024 / 1024).toStringAsFixed(1) : '?';
        final downloadedMB = (progress.bytesDownloaded / 1024 / 1024).toStringAsFixed(1);
        setState(() {
          _progress = progress.percentage;
          _progressText = '$downloadedMB MB / $totalMB MB';
        });
      }

      // Get downloaded file
      downloadedFile = await widget.releaseManager.getDownloadedFile(
        widget.updateInfo.latestVersion,
        widget.platform,
      );

      if (downloadedFile == null) {
        throw Exception('İndirilen dosya bulunamadı.');
      }

      // SHA-256 verification
      setState(() {
        _state = _DialogState.verifying;
        _progressText = 'SHA-256 doğrulanıyor...';
      });

      bool verified = true;
      if (widget.updateInfo.sha256Hash != null) {
        verified = await widget.releaseManager.verifyDownload(
          downloadedFile,
          widget.updateInfo.sha256Hash!,
          widget.updateInfo.signature ?? '',
        );
      }

      if (!verified) {
        if (await downloadedFile.exists()) {
          await downloadedFile.delete();
        }
        setState(() {
          _state = _DialogState.error;
          _errorMessage = 'Dosya bütünlüğü veya dijital imza doğrulanamadı. Güvenlik nedeniyle kurulum iptal edildi.';
        });
        return;
      }

      // Install
      setState(() {
        _state = _DialogState.done;
        _progressText = 'Kurulum başlatılıyor...';
      });

      final result = await widget.releaseManager.installUpdate(downloadedFile, widget.platform);

      if (result == InstallResult.success) {
        if (mounted) Navigator.of(context).pop(true);
      } else {
        // Trigger automated rollback
        await rollback.triggerRollback();
        setState(() {
          _state = _DialogState.error;
          _errorMessage = 'Kurulum başlatılamadı (${result.name}). Sistem önceki stabil sürüme geri döndürüldü (Rollback).';
        });
      }
    } catch (e) {
      if (!mounted) return;
      // Trigger automated rollback on unexpected exceptions during setup
      await rollback.triggerRollback();
      setState(() {
        _state = _DialogState.error;
        _errorMessage = 'Güncelleme hatası: ${e.toString()}. Sistem geri döndürüldü (Rollback).';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final info = widget.updateInfo;

    return FadeTransition(
      opacity: _fadeAnim,
      child: AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: info.isForceUpdate ? Colors.red.withOpacity(0.15) : Colors.blue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                info.isForceUpdate ? Icons.system_update_alt_rounded : Icons.system_update_rounded,
                color: info.isForceUpdate ? Colors.red : Colors.blue,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.isForceUpdate ? 'Zorunlu Güncelleme' : 'Güncelleme Mevcut',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: info.isForceUpdate ? Colors.red : null,
                    ),
                  ),
                  Text(
                    'v${info.latestVersion}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: _buildContent(context, info),
        ),
        actions: _buildActions(context, info),
      ),
    );
  }

  Widget _buildContent(BuildContext context, UpdateInfo info) {
    switch (_state) {
      case _DialogState.offer:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            if (info.isForceUpdate)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu güncelleme zorunludur. Güncellemeden uygulamaya devam edilemez.',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (info.releaseNotes != null && info.releaseNotes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Yenilikler',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
            if (info.fileSizeBytes != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.file_download_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Dosya boyutu: ${(info.fileSizeBytes! / 1024 / 1024).toStringAsFixed(1)} MB',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ],
        );

      case _DialogState.downloading:
      case _DialogState.verifying:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            _AnimatedProgressBar(value: _progress),
            const SizedBox(height: 12),
            Text(
              _state == _DialogState.verifying ? '🔐 SHA-256 doğrulanıyor...' : _progressText,
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (_state == _DialogState.downloading)
              Text(
                '${(_progress * 100).toInt()}%',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
            if (_state == _DialogState.verifying)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        );

      case _DialogState.done:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 16),
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 56),
            SizedBox(height: 8),
            Text('Güncelleme hazır! Kurulum başlatılıyor...', textAlign: TextAlign.center),
          ],
        );

      case _DialogState.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 8),
                Text('Güncelleme başarısız', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Bilinmeyen hata oluştu.',
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        );
    }
  }

  List<Widget> _buildActions(BuildContext context, UpdateInfo info) {
    switch (_state) {
      case _DialogState.offer:
        return [
          if (!info.isForceUpdate)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Sonraya Bırak'),
            ),
          ElevatedButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Güncelle'),
            style: ElevatedButton.styleFrom(
              backgroundColor: info.isForceUpdate ? Colors.red : Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 4),
        ];

      case _DialogState.downloading:
      case _DialogState.verifying:
      case _DialogState.done:
        return [
          const Padding(
            padding: EdgeInsets.only(right: 16, bottom: 8),
            child: Text('Lütfen bekleyin...', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        ];

      case _DialogState.error:
        return [
          if (!info.isForceUpdate)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Kapat'),
            ),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _state = _DialogState.offer;
              });
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar Dene'),
          ),
          const SizedBox(width: 4),
        ];
    }
  }
}

/// Animated progress bar with gradient fill.
class _AnimatedProgressBar extends StatelessWidget {
  final double value; // 0.0 - 1.0

  const _AnimatedProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 12,
        child: LinearProgressIndicator(
          value: value,
          backgroundColor: Colors.grey.withOpacity(0.2),
          valueColor: AlwaysStoppedAnimation<Color>(
            value < 0.5 ? Colors.blue : (value < 0.9 ? Colors.cyan : Colors.green),
          ),
        ),
      ),
    );
  }
}
