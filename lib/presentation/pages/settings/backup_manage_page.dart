// lib/presentation/pages/settings/backup_manage_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/domain/models/permission.dart';

class BackupManagePage extends ConsumerStatefulWidget {
  const BackupManagePage({super.key});

  @override
  ConsumerState<BackupManagePage> createState() => _BackupManagePageState();
}

class _BackupManagePageState extends ConsumerState<BackupManagePage> {
  List<File> _backupFiles = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshBackups();
  }

  Future<void> _refreshBackups() async {
    setState(() => _isLoading = true);
    try {
      final files = await ref.read(backupServiceProvider).getBackupFiles();
      setState(() {
        _backupFiles = files;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yedekler listelenirken hata oluştu: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createBackup() async {
    setState(() => _isLoading = true);
    try {
      final path = await ref.read(backupServiceProvider).backupDatabase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Yeni yedek başarıyla oluşturuldu: ${path.split(Platform.pathSeparator).last}')),
        );
      }
      _refreshBackups();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yedek alınırken hata oluştu: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _restoreBackup(File file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Veritabanını Geri Yükle',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Bu yedek dosyasını geri yüklemek istediğinize emin misiniz? Mevcut tüm verilerinizin üzerine yazılacaktır ve bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal', style: TextStyle(color: kTextSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Geri Yükle'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    requirePermissionAccess(context,
        permission: Permission.settingsDatabase,
        title: 'Yedek Geri Yükleme Yetkisi',
        requirePin: true,
        onGranted: (approvedByUserId, approvedByUserName) async {
      setState(() => _isLoading = true);
      try {
        await ref.read(backupServiceProvider).restoreDatabase(file.path);
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('Başarılı',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              content: const Text(
                  'Veritabanı yedekten başarıyla geri yüklendi. Uygulama güncellendi.'),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  child: const Text('Tamam'),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Geri yükleme başarısız: $e')),
          );
        }
      } finally {
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final hasAccess = currentUser != null &&
        (currentUser.role == UserRole.sysadmin ||
            currentUser.role == UserRole.owner ||
            currentUser.role == UserRole.admin ||
            currentUser.hasPermission(Permission.settingsDatabase.value));

    if (!hasAccess) {
      return const Scaffold(
        body: Center(
          child: Text('Bu sayfaya erişim yetkiniz bulunmuyor.'),
        ),
      );
    }

    return FullScreenSettingsPage(
      title: 'Yedekleme ve Geri Yükleme',
      actions: [
        IconButton(
          icon: const Icon(Icons.add_rounded, color: kGreen),
          tooltip: 'Yeni Yedek Al',
          onPressed: _isLoading ? null : _createBackup,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorderColor),
            ),
            child: const Row(
              children: [
                Icon(Icons.cloud_upload_rounded, color: kGreen, size: 40),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Verilerinizi Güvende Tutun',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: kTextPrimary),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Yerel yedek alabilir, bunları paylaşabilir veya eski bir yedeği geri yükleyebilirsiniz.',
                        style: TextStyle(fontSize: 12, color: kTextSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'YEREL YEDEKLER',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: kTextSecondary,
                letterSpacing: 0.3),
          ),
          const SizedBox(height: 8),
          if (_isLoading && _backupFiles.isEmpty)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(kGreen))))
          else if (_backupFiles.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorderColor),
              ),
              child: Column(
                children: [
                  const Icon(Icons.backup_table_rounded,
                      size: 48, color: kBorderColor),
                  const SizedBox(height: 12),
                  const Text('Kayıtlı yedek bulunamadı.',
                      style: TextStyle(color: kTextSecondary, fontSize: 14)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _createBackup,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Şimdi Yedek Al'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorderColor),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _backupFiles.length,
                separatorBuilder: (context, index) => const IOSDivider(),
                itemBuilder: (context, index) {
                  final file = _backupFiles[index];
                  final name = file.path.split(Platform.pathSeparator).last;
                  final date = file.lastModifiedSync();
                  final sizeKB = (file.lengthSync() / 1024).toStringAsFixed(1);

                  return ListTile(
                    leading: const Icon(Icons.settings_backup_restore_rounded,
                        color: kBlue),
                    title: Text(
                      name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: kTextPrimary),
                    ),
                    subtitle: Text(
                      'Tarih: ${DateFormat('dd.MM.yyyy HH:mm').format(date)} • Boyut: $sizeKB KB',
                      style:
                          const TextStyle(fontSize: 11, color: kTextSecondary),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.share_rounded,
                              color: kGreen, size: 20),
                          tooltip: 'Paylaş',
                          onPressed: () => ref
                              .read(backupServiceProvider)
                              .shareBackup(file.path),
                        ),
                        IconButton(
                          icon: const Icon(Icons.restore_rounded,
                              color: kPink, size: 20),
                          tooltip: 'Geri Yükle',
                          onPressed: () => _restoreBackup(file),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
