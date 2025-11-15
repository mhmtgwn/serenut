import 'dart:io';
import 'package:flutter/material.dart';
// import 'package:file_picker/file_picker.dart'; // Paket kurulumu gerekli
import '../services/backup_service.dart';
import '../utils/error_handler.dart';
import '../widgets/custom_app_bar.dart';

/// Yedekleme ve geri yükleme ayarları sayfası
class BackupSettingsPage extends StatefulWidget {
  const BackupSettingsPage({Key? key}) : super(key: key);

  @override
  State<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends State<BackupSettingsPage> {
  final BackupService _backupService = BackupService();
  List<File> _backupFiles = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadBackupFiles();
  }

  /// Yedekleme dosyalarını yükle
  Future<void> _loadBackupFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final files = await _backupService.getBackupFiles();
      setState(() {
        _backupFiles = files;
      });
    } catch (e) {
      ErrorHandler.reportError(
        'Yedekleme Listesi Hatası',
        'Yedekleme dosyaları yüklenirken bir sorun oluştu.',
        details: e.toString(),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Yeni yedekleme oluştur
  Future<void> _createBackup() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final backupPath = await _backupService.createFullBackup();
      if (backupPath != null) {
        await _loadBackupFiles(); // Listeyi yenile
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Yedekleme dosyasından geri yükle
  Future<void> _restoreFromFile() async {
    try {
      // FilePicker paketi kurulumu gerekli
      ErrorHandler.reportError(
        'Dosya Seçici Özelliği',
        'Dosya seçici özelliği için file_picker paketi kurulumu gerekli.',
      );
      
      // Paket kurulduktan sonra aşağıdaki kod kullanılabilir:
      /*
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final filePath = result.files.first.path;
        if (filePath != null) {
          // Onay dialog'u göster
          final confirmed = await _showRestoreConfirmation();
          if (confirmed) {
            setState(() {
              _isLoading = true;
            });

            final success = await _backupService.restoreFromBackup(filePath);
            if (success) {
              await _loadBackupFiles(); // Listeyi yenile
            }

            setState(() {
              _isLoading = false;
            });
          }
        }
      }
      */
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ErrorHandler.reportError(
        'Dosya Seçme Hatası',
        'Geri yükleme dosyası seçilirken bir sorun oluştu.',
        details: e.toString(),
      );
    }
  }

  /// Mevcut yedeklemeden geri yükle
  Future<void> _restoreFromBackup(String backupPath) async {
    final confirmed = await _showRestoreConfirmation();
    if (!confirmed) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _backupService.restoreFromBackup(backupPath);
      if (success) {
        await _loadBackupFiles(); // Listeyi yenile
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Geri yükleme onay dialog'u
  Future<bool> _showRestoreConfirmation() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Geri Yükleme Onayı'),
        content: const Text(
          'Bu işlem mevcut tüm verileri silecek ve yedekleme dosyasındaki verilerle değiştirecektir. '
          'Bu işlem geri alınamaz. Devam etmek istediğinizden emin misiniz?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Geri Yükle'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// Yedekleme dosyasını sil
  Future<void> _deleteBackup(String backupPath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yedekleme Silme Onayı'),
        content: const Text('Bu yedekleme dosyasını silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _backupService.deleteBackup(backupPath);
      if (success) {
        await _loadBackupFiles(); // Listeyi yenile
      }
    }
  }

  /// Yedekleme dosyasını paylaş
  Future<void> _shareBackup(String backupPath) async {
    try {
      await _backupService.shareBackup(backupPath);
    } catch (e) {
      // share_plus paketi eksik olduğu için hata verecek
      ErrorHandler.reportError(
        'Paylaşım Özelliği',
        'Paylaşım özelliği için ek paket kurulumu gerekli.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Yedekleme & Geri Yükleme',
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Yedekleme oluşturma bölümü
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.backup,
                                color: Theme.of(context).primaryColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Yedekleme Oluştur',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Tüm verilerinizin yedeğini oluşturun. Bu işlem müşteriler, ürünler, siparişler ve ayarları içerir.',
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _createBackup,
                              icon: const Icon(Icons.save),
                              label: const Text('Yeni Yedekleme Oluştur'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Geri yükleme bölümü
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.restore,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Geri Yükleme',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Yedekleme dosyasından verilerinizi geri yükleyin. Bu işlem mevcut verileri siler.',
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _restoreFromFile,
                              icon: const Icon(Icons.file_upload),
                              label: const Text('Dosyadan Geri Yükle'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Mevcut yedeklemeler
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.folder,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Mevcut Yedeklemeler',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          if (_backupFiles.isEmpty)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.folder_open,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Henüz yedekleme dosyası yok',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _backupFiles.length,
                              itemBuilder: (context, index) {
                                final file = _backupFiles[index];
                                final fileName = file.path.split('/').last;
                                final stats = file.statSync();
                                
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: const Icon(Icons.file_present),
                                    title: Text(fileName),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Tarih: ${_formatDate(stats.modified)}'),
                                        Text('Boyut: ${_formatFileSize(stats.size)}'),
                                      ],
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) {
                                        switch (value) {
                                          case 'restore':
                                            _restoreFromBackup(file.path);
                                            break;
                                          case 'share':
                                            _shareBackup(file.path);
                                            break;
                                          case 'delete':
                                            _deleteBackup(file.path);
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'restore',
                                          child: Row(
                                            children: [
                                              Icon(Icons.restore),
                                              SizedBox(width: 8),
                                              Text('Geri Yükle'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'share',
                                          child: Row(
                                            children: [
                                              Icon(Icons.share),
                                              SizedBox(width: 8),
                                              Text('Paylaş'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete, color: Colors.red),
                                              SizedBox(width: 8),
                                              Text('Sil', style: TextStyle(color: Colors.red)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// Tarihi formatla
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.'
           '${date.month.toString().padLeft(2, '0')}.'
           '${date.year} '
           '${date.hour.toString().padLeft(2, '0')}:'
           '${date.minute.toString().padLeft(2, '0')}';
  }

  /// Dosya boyutunu formatla
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
