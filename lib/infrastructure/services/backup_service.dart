// lib/infrastructure/services/backup_service.dart
// Serenut OS — Dual Database Backup Integration & Resilience Service
// Stage 10.12.26: Atomic Snapshot, SHA-256 Verification, Manifest, Fail-Closed

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:serenutos/domain/models/audit_event.dart';
import 'package:serenutos/domain/services/i_backup_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_audit_repository.dart';

export 'package:serenutos/domain/services/i_backup_service.dart'
    show BackupEntryInfo, DualDatabaseBackupResult;

class BackupService implements IBackupService {
  static const String _lastBackupKey = 'last_backup_date';
  final SharedPreferences? _prefs;

  BackupService({SharedPreferences? prefs}) : _prefs = prefs;

  /// Tekil veritabanı yedeğini atomik olarak alır, doğrular ve SHA-256 hash'ini hesaplar.
  Future<BackupEntryInfo> _backupSingleDatabase({
    required Database activeDb,
    required String sourcePath,
    required String targetBackupPath,
    required String dbIdentifier,
  }) async {
    // 1. Kaynak veritabanının bütünlük doğrulaması
    final List<Map<String, dynamic>> integrityResult =
        await activeDb.rawQuery('PRAGMA integrity_check');
    if (integrityResult.isEmpty ||
        integrityResult.first.values.first != 'ok') {
      throw Exception(
          'Kaynak $dbIdentifier veritabanı bütünlük doğrulaması başarısız. Yedekleme iptal edildi.');
    }

    final tempBackupPath = '$targetBackupPath.tmp';
    final tempFile = File(tempBackupPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    // 2. Modern atomik SQLite snapshot: VACUUM INTO
    bool vacuumSucceeded = false;
    try {
      await activeDb.execute('VACUUM INTO ?', [tempBackupPath]);
      vacuumSucceeded = true;
    } catch (_) {
      vacuumSucceeded = false;
    }

    if (!vacuumSucceeded) {
      // Fallback: WAL checkpoint TRUNCATE ve dosya kopyalama
      try {
        await activeDb.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (e) {
        debugPrint('[BackupService] wal_checkpoint(TRUNCATE) non-fatal error: $e');
      }

      final srcFile = File(sourcePath);
      if (!await srcFile.exists()) {
        throw Exception('Aktif kaynak $dbIdentifier dosyası bulunamadı: $sourcePath');
      }
      await srcFile.copy(tempBackupPath);
    }

    // 3. Oluşturulan geçici dosyanın fiziksel varlığı ve boyutu
    if (!await tempFile.exists() || await tempFile.length() < 512) {
      throw Exception('Yedek dosyası fiziksel olarak oluşturulamadı veya boş.');
    }

    // 4. Geçici dosyanın SQLite bütünlüğünü ve açılabilirliğini test et
    Database? verifyDb;
    try {
      verifyDb = await openDatabase(tempBackupPath,
          readOnly: true, singleInstance: false);
      final testIntegrity = await verifyDb.rawQuery('PRAGMA integrity_check');
      if (testIntegrity.isEmpty || testIntegrity.first.values.first != 'ok') {
        throw Exception('Yedek dosyasının SQLite bütünlük doğrulaması başarısız oldu.');
      }
    } finally {
      if (verifyDb != null && verifyDb.isOpen) {
        await verifyDb.close();
      }
    }

    // 5. SHA-256 Hesaplama
    final sha256Digest = await sha256.bind(tempFile.openRead()).first;
    final sha256Hex = sha256Digest.toString();

    // 6. Hedef dosya mevcutsa temizle ve geçici dosyayı atomik olarak taşı
    final finalFile = File(targetBackupPath);
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tempFile.rename(targetBackupPath);

    final finalLength = await finalFile.length();

    return BackupEntryInfo(
      dbIdentifier: dbIdentifier,
      originalPath: sourcePath,
      backupPath: targetBackupPath,
      fileSizeBytes: finalLength,
      sha256Hash: sha256Hex,
      integrityVerified: true,
      backedUpAt: DateTime.now(),
    );
  }

  /// Çift Veritabanı Yedekleme (Legacy + Core Next)
  ///
  /// Kurallar:
  /// 1. Her iki veritabanının da yolunu güvenli çözer.
  /// 2. Biri veya ikisi mevcutsa ayrı, izole ve doğrulanmış dosyalar oluşturur.
  /// 3. Geçici dosya üzerinden atomik geçiş yapar; hata durumunda yarım dosyaları siler.
  /// 4. Başarısızlık anında fail-closed davranır, hangi aşamanın çöktüğünü raporlar.
  /// 5. Her yedek için dosya boyutu, SHA-256 ve SQLite bütünlüğünü kanıtlar.
  @override
  Future<DualDatabaseBackupResult> backupDualDatabases({
    String? customBackupDir,
    bool requireBoth = false,
  }) async {
    DatabaseManager.isWriteLocked = true;
    final List<File> temporaryFilesToCleanup = [];

    try {
      // 1. Hedef dizin kontrolü ve oluşturma
      final Directory backupsDir;
      if (customBackupDir != null) {
        backupsDir = Directory(customBackupDir);
      } else {
        final docsDir = await getApplicationDocumentsDirectory();
        backupsDir = Directory(join(docsDir.path, 'SerenutBackups'));
      }

      try {
        if (!await backupsDir.exists()) {
          await backupsDir.create(recursive: true);
        }
      } catch (dirErr) {
        return DualDatabaseBackupResult(
          isSuccess: false,
          errorMessage: 'Yedek dizinine erişilemedi veya oluşturulamadı: $dirErr',
          failedStep: 'directory_write_check',
        );
      }

      // 2. Veritabanı yollarının çözümlenmesi
      final dbManager = DatabaseManager.instance;
      final legacyPath = await dbManager.getLegacyDatabasePath();
      final coreNextPath = await dbManager.getCoreNextDatabasePath();

      final legacyFile = File(legacyPath);
      final coreNextFile = File(coreNextPath);

      final bool legacyExists = await legacyFile.exists() ||
          (DatabaseManager.overrideDatabasePath != null &&
              await File(DatabaseManager.overrideDatabasePath!).exists());
      final bool coreNextExists = await coreNextFile.exists();

      if (!legacyExists && !coreNextExists) {
        return const DualDatabaseBackupResult(
          isSuccess: false,
          errorMessage: 'Hiçbir aktif veritabanı dosyası (legacy veya Core Next) bulunamadı.',
          failedStep: 'presence_check',
        );
      }

      if (requireBoth && (!legacyExists || !coreNextExists)) {
        return DualDatabaseBackupResult(
          isSuccess: false,
          errorMessage: 'Her iki veritabanı yedeği zorunlu kılındı ancak '
              '${!legacyExists ? 'Legacy' : 'Core Next'} veritabanı bulunamadı.',
          failedStep: 'presence_check',
        );
      }

      final String timestamp =
          DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

      BackupEntryInfo? legacyInfo;
      BackupEntryInfo? coreNextInfo;

      // 3. Legacy Veritabanı Yedeği
      if (legacyExists) {
        final legacyBackupFileName = 'serenut_pos_backup_$timestamp.db';
        final legacyBackupPath = join(backupsDir.path, legacyBackupFileName);
        temporaryFilesToCleanup.add(File('$legacyBackupPath.tmp'));

        try {
          final Database legacyDb = await dbManager.getDatabase();
          legacyInfo = await _backupSingleDatabase(
            activeDb: legacyDb,
            sourcePath: legacyPath,
            targetBackupPath: legacyBackupPath,
            dbIdentifier: 'legacy',
          );
        } catch (e) {
          return DualDatabaseBackupResult(
            isSuccess: false,
            errorMessage: 'Legacy veritabanı yedeği başarısız: $e',
            failedDatabase: 'legacy',
            failedStep: 'legacy_backup_execution',
          );
        }
      }

      // 4. Core Next Veritabanı Yedeği
      if (coreNextExists) {
        final coreNextBackupFileName = 'serenut_core_v2_backup_$timestamp.db';
        final coreNextBackupPath = join(backupsDir.path, coreNextBackupFileName);
        temporaryFilesToCleanup.add(File('$coreNextBackupPath.tmp'));

        Database? coreDb;
        try {
          coreDb = await openDatabase(coreNextPath);
          coreNextInfo = await _backupSingleDatabase(
            activeDb: coreDb,
            sourcePath: coreNextPath,
            targetBackupPath: coreNextBackupPath,
            dbIdentifier: 'core_next',
          );
        } catch (e) {
          return DualDatabaseBackupResult(
            isSuccess: false,
            errorMessage: 'Core Next veritabanı yedeği başarısız: $e',
            failedDatabase: 'core_next',
            failedStep: 'core_next_backup_execution',
          );
        } finally {
          if (coreDb != null && coreDb.isOpen) {
            await coreDb.close();
          }
        }
      }

      // 5. Çift Yedekleme Manifest Dosyası Oluşturma
      String? manifestPath;
      if (legacyInfo != null && coreNextInfo != null) {
        final manifestFileName = 'serenut_dual_backup_manifest_$timestamp.json';
        manifestPath = join(backupsDir.path, manifestFileName);
        final manifestMap = {
          'manifestVersion': 1,
          'timestamp': DateTime.now().toIso8601String(),
          'legacyBackup': legacyInfo.toJson(),
          'coreNextBackup': coreNextInfo.toJson(),
          'atomicityLimitationNotice':
              'Each database backup is internally consistent via SQLite VACUUM INTO / WAL checkpoint. '
              'Cross-database atomicity between independent SQLite database files is not guaranteed by SQLite.',
        };
        await File(manifestPath).writeAsString(
          const JsonEncoder.withIndent('  ').convert(manifestMap),
        );
      }

      // 6. Tarihçeyi SharedPreferences'a Kaydetme
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setString(_lastBackupKey, now.toIso8601String());
      await prefs.setString('last_backup_date', now.toIso8601String());

      // 7. Audit Log Kaydı
      DatabaseManager.isWriteLocked = false;
      try {
        final auditRepo = SqliteAuditRepository(dbManager);
        await auditRepo.logEvent(AuditEvent(
          id: const Uuid().v4(),
          eventType: 'system_backup',
          entityType: 'system',
          notes: 'Çift veritabanı yedeği başarıyla alındı. '
              'Legacy: ${legacyInfo?.backupPath != null ? basename(legacyInfo!.backupPath) : "YOK"}, '
              'CoreNext: ${coreNextInfo?.backupPath != null ? basename(coreNextInfo!.backupPath) : "YOK"}',
          timestamp: DateTime.now(),
        ));
      } catch (e, stackTrace) {
        developer.log('Yedekleme audit olayı kaydedilemedi',
            error: e, stackTrace: stackTrace);
      }

      return DualDatabaseBackupResult(
        isSuccess: true,
        legacyBackup: legacyInfo,
        coreNextBackup: coreNextInfo,
        manifestPath: manifestPath,
      );
    } catch (e) {
      return DualDatabaseBackupResult(
        isSuccess: false,
        errorMessage: 'Beklenmeyen yedekleme hatası: $e',
        failedStep: 'unhandled_exception',
      );
    } finally {
      DatabaseManager.isWriteLocked = false;
      for (final tmp in temporaryFilesToCleanup) {
        try {
          if (await tmp.exists()) {
            await tmp.delete();
          }
        } catch (e) {
          debugPrint('[BackupService] Cleanup temp file error: $e');
        }
      }
    }
  }

  /// Geriye dönük uyumlu standart yedekleme metodu.
  /// Çift veritabanı yedekleme motorunu çağırır ve birincil yedek dosyasının yolunu döner.
  @override
  Future<String> backupDatabase() async {
    final result = await backupDualDatabases(requireBoth: false);
    if (!result.isSuccess) {
      throw Exception(result.errorMessage ?? 'Veritabanı yedeği oluşturulamadı.');
    }
    return result.legacyBackup?.backupPath ?? result.coreNextBackup!.backupPath;
  }

  /// Triggers auto backup if it hasn't been done today
  @override
  Future<void> autoBackupIfNeeded() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final lastBackupStr = prefs.getString(_lastBackupKey);
    if (lastBackupStr != null) {
      final lastBackup = DateTime.tryParse(lastBackupStr);
      if (lastBackup != null) {
        final now = DateTime.now();
        if (lastBackup.year == now.year &&
            lastBackup.month == now.month &&
            lastBackup.day == now.day) {
          return;
        }
      }
    }
    await backupDatabase();
  }

  /// Share a backup file via native share sheets
  @override
  Future<void> shareBackup(String backupPath) async {
    final file = File(backupPath);
    if (!await file.exists()) {
      throw Exception('Yedek dosyası bulunamadı.');
    }
    await Share.shareXFiles(
      [XFile(backupPath)],
      subject: 'Serenut OS Veritabanı Yedeği',
      text:
          'Serenut OS veritabanı yedeğidir. Dosya adı: ${basename(backupPath)}',
    );
  }

  /// Get list of local backups (Legacy, Core Next)
  @override
  Future<List<File>> getBackupFiles() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final backupsDir = Directory(join(docsDir.path, 'SerenutBackups'));
    if (!await backupsDir.exists()) return [];

    final list = backupsDir.listSync();
    final files = list
        .whereType<File>()
        .where((file) {
          final name = basename(file.path);
          return (name.startsWith('serenut_pos_backup_') ||
                  name.startsWith('serenut_core_v2_backup_')) &&
              file.path.endsWith('.db');
        })
        .toList();

    // Sort by modified date descending
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  /// Restore database from a backup path.
  ///
  /// Akıllı algılama:
  /// - Yedek dosyası Core Next (user_version = 3 veya Core Next tabloları) ise
  ///   hedef Core Next veritabanı yoluna (`serenut_core_v2.db`) geri yükler.
  /// - Yedek dosyası Legacy (`settings`, `sales`, `products`) ise
  ///   hedef Legacy veritabanı yoluna (`serenut_pos.db`) geri yükler.
  /// - Yazma hatasında `.bak` geçici kopyaları ile tam otomatik rollback uygular.
  @override
  Future<bool> restoreDatabase(String backupPath, [String? recoveryKey]) async {
    final file = File(backupPath);
    if (!await file.exists()) {
      throw Exception('Geri yüklenecek yedek dosyası bulunamadı.');
    }

    DatabaseManager.isWriteLocked = true;
    try {
      final dbManager = DatabaseManager.instance;

    // 1. Dosya şema ve tip kontrolü
    Database? tempDb;
    bool isCoreNextBackup = false;
    try {
      tempDb = await dbManager.openDatabaseConnection(
        backupPath,
        readOnly: true,
      );
      final tables = await tempDb
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tables.map((t) => t['name'] as String).toSet();

      final versionResult = await tempDb.rawQuery('PRAGMA user_version');
      final userVersion =
          (versionResult.first.values.first as num?)?.toInt() ?? 0;

      if ((userVersion >= 3 && userVersion <= 10) ||
          (tableNames.contains('app_settings') &&
              tableNames.contains('ledger_entries'))) {
        isCoreNextBackup = true;
      } else if (tableNames.contains('settings') &&
          tableNames.contains('sales') &&
          tableNames.contains('products')) {
        isCoreNextBackup = false;
      } else {
        throw Exception(
            'Geçersiz yedek dosyası. Ne Legacy ne de Core Next şeması tespit edilemedi.');
      }
    } catch (e) {
      throw Exception('Yedek dosyası doğrulanamadı: $e');
    } finally {
      if (tempDb != null) {
        await tempDb.close();
      }
    }

    // 2. Hedef dosya yolunu belirle
    final String targetDbPath = isCoreNextBackup
        ? await dbManager.getCoreNextDatabasePath()
        : await dbManager.getLegacyDatabasePath();

    try {
      final db = await dbManager.getDatabase();
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // Ignored if DB was not yet initialized
    }
    await dbManager.close();

    // 3. Atomik dosya takası ve .bak kurtarma
    final walPath = '$targetDbPath-wal';
    final shmPath = '$targetDbPath-shm';

    final targetFile = File(targetDbPath);
    final walFile = File(walPath);
    final shmFile = File(shmPath);

    final tempBackupDbPath = '$targetDbPath.bak';
    final tempBackupWalPath = '$walPath.bak';
    final tempBackupShmPath = '$shmPath.bak';

    final tempBackupDbFile = File(tempBackupDbPath);
    final tempBackupWalFile = File(tempBackupWalPath);
    final tempBackupShmFile = File(tempBackupShmPath);

    if (await tempBackupDbFile.exists()) await tempBackupDbFile.delete();
    if (await tempBackupWalFile.exists()) await tempBackupWalFile.delete();
    if (await tempBackupShmFile.exists()) await tempBackupShmFile.delete();

    if (await targetFile.exists()) await targetFile.rename(tempBackupDbPath);
    if (await walFile.exists()) await walFile.rename(tempBackupWalPath);
    if (await shmFile.exists()) await shmFile.rename(tempBackupShmPath);

    try {
      await file.copy(targetDbPath);

      Database? testRestoredDb;
      try {
        testRestoredDb = await openDatabase(targetDbPath,
            readOnly: true, singleInstance: false);
        final integrity = await testRestoredDb.rawQuery('PRAGMA integrity_check');
        if (integrity.isEmpty || integrity.first.values.first != 'ok') {
          throw Exception('Geri yüklenen dosya bütünlük testini geçemedi.');
        }
      } finally {
        if (testRestoredDb != null && testRestoredDb.isOpen) {
          await testRestoredDb.close();
        }
      }

      if (await tempBackupDbFile.exists()) await tempBackupDbFile.delete();
      if (await tempBackupWalFile.exists()) await tempBackupWalFile.delete();
      if (await tempBackupShmFile.exists()) await tempBackupShmFile.delete();
    } catch (e) {
      if (await targetFile.exists()) await targetFile.delete();
      if (await walFile.exists()) await walFile.delete();
      if (await shmFile.exists()) await shmFile.delete();

      if (await tempBackupDbFile.exists()) {
        await tempBackupDbFile.rename(targetDbPath);
      }
      if (await tempBackupWalFile.exists()) {
        await tempBackupWalFile.rename(walPath);
      }
      if (await tempBackupShmFile.exists()) {
        await tempBackupShmFile.rename(shmPath);
      }

      throw Exception(
          'Veritabanı geri yükleme hatası, değişiklikler geri alındı: $e');
    }

    if (!isCoreNextBackup) {
      await dbManager.getDatabase();
    }

    try {
      final auditRepo = SqliteAuditRepository(dbManager);
      await auditRepo.logEvent(AuditEvent(
        id: const Uuid().v4(),
        eventType: 'system_restore',
        entityType: 'system',
        notes: 'Veritabanı (${isCoreNextBackup ? "Core Next" : "Legacy"}) yedekten geri yüklendi: ${basename(backupPath)}',
        timestamp: DateTime.now(),
      ));
    } catch (e) {
      debugPrint('[BackupService] Telemetry audit log error after restore: $e');
    }

    return true;
    } finally {
      DatabaseManager.isWriteLocked = false;
    }
  }

  @override
  Future<void> clearAllBackups() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final backupsDir = Directory(join(docsDir.path, 'SerenutBackups'));
    if (await backupsDir.exists()) {
      await backupsDir.delete(recursive: true);
    }
  }
}
