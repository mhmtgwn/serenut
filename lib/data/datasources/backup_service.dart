import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'package:share_plus/share_plus.dart'; // Paket kurulumu gerekli
import 'database_service.dart';
import 'customer_service.dart';
import 'product_service.dart';
import 'order_service.dart';
import '../../shared/utils/error_handler.dart';

/// Veritabanı yedekleme ve geri yükleme servisi
class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  final DatabaseService _dbService = DatabaseService.instance;

  /// Veritabanının tam yedeğini oluştur
  Future<String?> createFullBackup() async {
    try {
      // Depolama izni kontrol et
      final storagePermission = await Permission.storage.request();
      if (!storagePermission.isGranted) {
        ErrorHandler.reportError(
          'İzin Hatası',
          'Yedekleme için depolama izni gerekli.',
        );
        return null;
      }

      final db = await _dbService.database;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      // Yedekleme verilerini topla
      final backupData = <String, dynamic>{
        'version': 1,
        'timestamp': timestamp,
        'created_at': DateTime.now().toIso8601String(),
        'tables': <String, List<Map<String, dynamic>>>{},
      };

      // Tüm tabloları yedekle
      final tables = [
        'customers',
        'products', 
        'orders',
        'order_items',
        'payments',
        'expenses',
        'devices',
        'printer_assignments',
        'business_profile',
        'receipt_settings',
      ];

      for (final tableName in tables) {
        try {
          final tableData = await db.query(tableName);
          backupData['tables'][tableName] = tableData;
          debugPrint('Tablo yedeklendi: $tableName (${tableData.length} kayıt)');
        } catch (e) {
          debugPrint('Tablo yedekleme hatası ($tableName): $e');
          // Tablo yoksa devam et
        }
      }

      // JSON formatına dönüştür
      final jsonString = jsonEncode(backupData);
      
      // Dosya yolunu belirle
      final directory = await getApplicationDocumentsDirectory();
      final backupFileName = 'shaman_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      final backupFile = File('${directory.path}/$backupFileName');
      
      // Dosyayı kaydet
      await backupFile.writeAsString(jsonString);
      
      ErrorHandler.showSuccess('Yedekleme başarıyla oluşturuldu');
      debugPrint('Yedekleme dosyası: ${backupFile.path}');
      
      return backupFile.path;
    } catch (e) {
      ErrorHandler.reportError(
        'Yedekleme Hatası',
        'Veritabanı yedeklenirken bir sorun oluştu.',
        details: e.toString(),
      );
      return null;
    }
  }

  /// Yedekleme dosyasından veritabanını geri yükle
  Future<bool> restoreFromBackup(String backupFilePath) async {
    try {
      final backupFile = File(backupFilePath);
      
      if (!await backupFile.exists()) {
        ErrorHandler.reportError(
          'Dosya Bulunamadı',
          'Yedekleme dosyası bulunamadı.',
        );
        return false;
      }

      // Yedekleme dosyasını oku
      final jsonString = await backupFile.readAsString();
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;
      
      // Yedekleme formatını kontrol et
      if (!_validateBackupFormat(backupData)) {
        ErrorHandler.reportError(
          'Geçersiz Yedekleme',
          'Yedekleme dosyası geçersiz veya bozuk.',
        );
        return false;
      }

      final db = await _dbService.database;
      
      // Transaction içinde geri yükleme işlemi
      await db.transaction((txn) async {
        final tables = backupData['tables'] as Map<String, dynamic>;
        
        for (final entry in tables.entries) {
          final tableName = entry.key;
          final tableData = entry.value as List<dynamic>;
          
          try {
            // Tabloyu temizle
            await txn.delete(tableName);
            debugPrint('Tablo temizlendi: $tableName');
            
            // Verileri geri yükle
            for (final row in tableData) {
              final rowData = row as Map<String, dynamic>;
              await txn.insert(tableName, rowData);
            }
            
            debugPrint('Tablo geri yüklendi: $tableName (${tableData.length} kayıt)');
          } catch (e) {
            debugPrint('Tablo geri yükleme hatası ($tableName): $e');
            // Hata durumunda transaction rollback olacak
            rethrow;
          }
        }
      });

      ErrorHandler.showSuccess('Veritabanı başarıyla geri yüklendi');
      return true;
    } catch (e) {
      ErrorHandler.reportError(
        'Geri Yükleme Hatası',
        'Veritabanı geri yüklenirken bir sorun oluştu.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Yedekleme dosyasını paylaş
  Future<void> shareBackup(String backupFilePath) async {
    try {
      final backupFile = File(backupFilePath);
      
      if (!await backupFile.exists()) {
        ErrorHandler.reportError(
          'Dosya Bulunamadı',
          'Paylaşılacak yedekleme dosyası bulunamadı.',
        );
        return;
      }

      // share_plus paketi kurulumu gerekli
      // await Share.shareXFiles(
      //   [XFile(backupFilePath)],
      //   text: 'Shaman POS Yedekleme Dosyası',
      //   subject: 'Veritabanı Yedekleme',
      // );
      
      ErrorHandler.reportError(
        'Paylaşım Özelliği',
        'Paylaşım özelliği için share_plus paketi kurulumu gerekli.',
      );
    } catch (e) {
      ErrorHandler.reportError(
        'Paylaşım Hatası',
        'Yedekleme dosyası paylaşılırken bir sorun oluştu.',
        details: e.toString(),
      );
    }
  }

  /// Otomatik yedekleme oluştur
  Future<void> createAutoBackup() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final autoBackupDir = Directory('${directory.path}/auto_backups');
      
      // Otomatik yedekleme klasörünü oluştur
      if (!await autoBackupDir.exists()) {
        await autoBackupDir.create(recursive: true);
      }

      // Eski otomatik yedeklemeleri temizle (5'ten fazla varsa)
      await _cleanupOldBackups(autoBackupDir);

      // Yeni yedekleme oluştur
      final backupPath = await createFullBackup();
      
      if (backupPath != null) {
        // Yedeklemeyi otomatik yedekleme klasörüne kopyala
        final backupFile = File(backupPath);
        final autoBackupFileName = 'auto_backup_${DateTime.now().millisecondsSinceEpoch}.json';
        final autoBackupFile = File('${autoBackupDir.path}/$autoBackupFileName');
        
        await backupFile.copy(autoBackupFile.path);
        await backupFile.delete(); // Orijinal dosyayı sil
        
        debugPrint('Otomatik yedekleme oluşturuldu: ${autoBackupFile.path}');
      }
    } catch (e) {
      debugPrint('Otomatik yedekleme hatası: $e');
      // Otomatik yedekleme hatalarında kullanıcıyı rahatsız etme
    }
  }

  /// Mevcut yedekleme dosyalarını listele
  Future<List<File>> getBackupFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final backupFiles = <File>[];
      
      // Ana dizindeki yedekleme dosyaları
      final mainDirFiles = await directory.list().toList();
      for (final entity in mainDirFiles) {
        if (entity is File && 
            entity.path.contains('shaman_backup_') && 
            entity.path.endsWith('.json')) {
          backupFiles.add(entity);
        }
      }
      
      // Otomatik yedekleme klasöründeki dosyalar
      final autoBackupDir = Directory('${directory.path}/auto_backups');
      if (await autoBackupDir.exists()) {
        final autoDirFiles = await autoBackupDir.list().toList();
        for (final entity in autoDirFiles) {
          if (entity is File && 
              entity.path.contains('auto_backup_') && 
              entity.path.endsWith('.json')) {
            backupFiles.add(entity);
          }
        }
      }
      
      // Tarihe göre sırala (en yeni önce)
      backupFiles.sort((a, b) {
        final aStats = a.statSync();
        final bStats = b.statSync();
        return bStats.modified.compareTo(aStats.modified);
      });
      
      return backupFiles;
    } catch (e) {
      ErrorHandler.reportError(
        'Yedekleme Listesi Hatası',
        'Yedekleme dosyaları listelenirken bir sorun oluştu.',
        details: e.toString(),
      );
      return [];
    }
  }

  /// Yedekleme dosyasını sil
  Future<bool> deleteBackup(String backupFilePath) async {
    try {
      final backupFile = File(backupFilePath);
      
      if (await backupFile.exists()) {
        await backupFile.delete();
        ErrorHandler.showSuccess('Yedekleme dosyası silindi');
        return true;
      } else {
        ErrorHandler.reportError(
          'Dosya Bulunamadı',
          'Silinecek yedekleme dosyası bulunamadı.',
        );
        return false;
      }
    } catch (e) {
      ErrorHandler.reportError(
        'Silme Hatası',
        'Yedekleme dosyası silinirken bir sorun oluştu.',
        details: e.toString(),
      );
      return false;
    }
  }

  /// Yedekleme formatını doğrula
  bool _validateBackupFormat(Map<String, dynamic> backupData) {
    try {
      // Gerekli alanları kontrol et
      if (!backupData.containsKey('version') ||
          !backupData.containsKey('timestamp') ||
          !backupData.containsKey('tables')) {
        return false;
      }

      // Version kontrolü
      final version = backupData['version'] as int?;
      if (version == null || version < 1) {
        return false;
      }

      // Tables kontrolü
      final tables = backupData['tables'];
      if (tables is! Map<String, dynamic>) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Eski yedekleme dosyalarını temizle
  Future<void> _cleanupOldBackups(Directory backupDir) async {
    try {
      final files = await backupDir.list().toList();
      final backupFiles = files
          .where((file) => file.path.endsWith('.json'))
          .toList();

      // Tarihe göre sırala (en eski önce)
      backupFiles.sort((a, b) {
        final aStats = a.statSync();
        final bStats = b.statSync();
        return aStats.modified.compareTo(bStats.modified);
      });

      // 5'ten fazla varsa eski olanları sil
      if (backupFiles.length > 5) {
        final filesToDelete = backupFiles.take(backupFiles.length - 5);
        for (final file in filesToDelete) {
          await file.delete();
          debugPrint('Eski yedekleme silindi: ${file.path}');
        }
      }
    } catch (e) {
      debugPrint('Eski yedekleme temizleme hatası: $e');
    }
  }

  /// Yedekleme dosyası bilgilerini getir
  Future<Map<String, dynamic>?> getBackupInfo(String backupFilePath) async {
    try {
      final backupFile = File(backupFilePath);
      
      if (!await backupFile.exists()) {
        return null;
      }

      final jsonString = await backupFile.readAsString();
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;
      
      if (!_validateBackupFormat(backupData)) {
        return null;
      }

      final tables = backupData['tables'] as Map<String, dynamic>;
      int totalRecords = 0;
      
      for (final tableData in tables.values) {
        if (tableData is List) {
          totalRecords += tableData.length;
        }
      }

      return {
        'version': backupData['version'],
        'timestamp': backupData['timestamp'],
        'created_at': backupData['created_at'],
        'file_size': await backupFile.length(),
        'table_count': tables.length,
        'total_records': totalRecords,
        'file_path': backupFilePath,
      };
    } catch (e) {
      debugPrint('Yedekleme bilgisi alma hatası: $e');
      return null;
    }
  }
}
