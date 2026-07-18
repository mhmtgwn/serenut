import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/domain/services/i_backup_service.dart';
import 'package:serenutos/domain/models/audit_event.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_audit_repository.dart';
import 'package:uuid/uuid.dart';

class BackupService implements IBackupService {
  static const String _lastBackupKey = 'last_backup_date';

  /// Performs database backup using VACUUM INTO or WAL Checkpoint
  /// Returns the absolute path of the backup file if successful
  @override
  Future<String> backupDatabase() async {
    DatabaseManager.isWriteLocked = true;

    try {
      // Target directory: Application Documents
      final docsDir = await getApplicationDocumentsDirectory();
      final backupsDir = Directory(join(docsDir.path, 'SerenutBackups'));
      if (!await backupsDir.exists()) {
        await backupsDir.create(recursive: true);
      }

      final String timestamp =
          DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final backupFileName = 'serenut_pos_backup_$timestamp.db';
      final backupPath = join(backupsDir.path, backupFileName);

      final Database db = await DatabaseManager().getDatabase();

      // Verify database integrity before creating a backup copy
      final List<Map<String, dynamic>> integrityResult =
          await db.rawQuery('PRAGMA integrity_check');
      if (integrityResult.isEmpty ||
          integrityResult.first.values.first != 'ok') {
        throw Exception(
            'Veritabanı bütünlük doğrulaması başarısız oldu. Yedekleme iptal edildi.');
      }

      try {
        // 1. Try modern atomic SQLite backup via VACUUM INTO.
        // This creates a fully checkpointed, locked/atomic snapshot.
        await db.execute('VACUUM INTO ?', [backupPath]);
      } catch (e) {
        // 2. Fallback: Force a full WAL checkpoint to flush all WAL changes to main .db file
        await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');

        final dbPath = DatabaseManager.overrideDatabasePath ??
            join(await DatabaseManager().getDatabasesPath(), 'serenut_pos.db');
        final dbFile = File(dbPath);

        if (!await dbFile.exists()) {
          throw Exception('Active database file not found.');
        }
        await dbFile.copy(backupPath);
      }

      // Save timestamp
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setString(_lastBackupKey, now.toIso8601String());
      await prefs.setString('last_backup_date', now.toIso8601String());

      final maxTimeStr = prefs.getString('max_timestamp_seen');
      if (maxTimeStr != null) {
        final currentMax = DateTime.tryParse(maxTimeStr);
        if (currentMax != null && now.isAfter(currentMax)) {
          await prefs.setString('max_timestamp_seen', now.toIso8601String());
        }
      } else {
        await prefs.setString('max_timestamp_seen', now.toIso8601String());
      }

      try {
        final auditRepo = SqliteAuditRepository(DatabaseManager());
        await auditRepo.logEvent(AuditEvent(
          id: const Uuid().v4(),
          eventType: 'system_backup',
          entityType: 'system',
          notes: 'Veritabanı yedeği alındı: ${basename(backupPath)}',
          timestamp: DateTime.now(),
        ));
      } catch (_) {}

      return backupPath;
    } finally {
      DatabaseManager.isWriteLocked = false;
    }
  }

  /// Triggers auto backup if it hasn't been done today
  @override
  Future<void> autoBackupIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final lastBackupStr = prefs.getString(_lastBackupKey);
    if (lastBackupStr != null) {
      final lastBackup = DateTime.tryParse(lastBackupStr);
      if (lastBackup != null) {
        final now = DateTime.now();
        if (lastBackup.year == now.year &&
            lastBackup.month == now.month &&
            lastBackup.day == now.day) {
          // Already backed up today
          return;
        }
      }
    }
    // Perform backup
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

  /// Get list of local backups
  @override
  Future<List<File>> getBackupFiles() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final backupsDir = Directory(join(docsDir.path, 'SerenutBackups'));
    if (!await backupsDir.exists()) return [];

    final list = backupsDir.listSync();
    final files = list
        .whereType<File>()
        .where((file) =>
            basename(file.path).startsWith('serenut_pos_backup_') &&
            file.path.endsWith('.db'))
        .toList();

    // Sort by modified date descending
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  /// Restore database from a backup path
  /// Performs schema/table integrity checks and deletes sidecar files safely.
  /// Decouples encryption checks using optional recoveryKey parameter.
  @override
  Future<bool> restoreDatabase(String backupPath, [String? recoveryKey]) async {
    final file = File(backupPath);
    if (!await file.exists()) {
      throw Exception('Geri yüklenecek yedek dosyası bulunamadı.');
    }

    final dbManager = DatabaseManager();

    // Verify it is a valid sqlite file and can be opened
    Database? tempDb;
    try {
      tempDb = await dbManager.openDatabaseConnection(
        backupPath,
        readOnly: true,
      );
      final tables = await tempDb
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tables.map((t) => t['name'] as String).toList();

      // Basic validation checks
      if (!tableNames.contains('settings') ||
          !tableNames.contains('sales') ||
          !tableNames.contains('products')) {
        throw Exception(
            'Geçersiz yedek dosyası. Gerekli Serenut OS tabloları bulunamadı.');
      }
    } catch (e) {
      throw Exception('Yedek dosyası doğrulanamadı: $e');
    } finally {
      if (tempDb != null) {
        await tempDb.close();
      }
    }

    // 2. Close active database connection to prevent locking
    await dbManager.close();

    // 3. Overwrite current DB file and delete active WAL/SHM sidecars safely
    final dbDir = await dbManager.getDatabasesPath();
    final dbPath =
        DatabaseManager.overrideDatabasePath ?? join(dbDir, 'serenut_pos.db');
    final walPath = '$dbPath-wal';
    final shmPath = '$dbPath-shm';

    final dbFile = File(dbPath);
    final walFile = File(walPath);
    final shmFile = File(shmPath);

    // Keep temporary backups of existing db file to recover on write failure
    final tempBackupDbPath = '$dbPath.bak';
    final tempBackupWalPath = '$walPath.bak';
    final tempBackupShmPath = '$shmPath.bak';

    final tempBackupDbFile = File(tempBackupDbPath);
    final tempBackupWalFile = File(tempBackupWalPath);
    final tempBackupShmFile = File(tempBackupShmPath);

    if (await tempBackupDbFile.exists()) await tempBackupDbFile.delete();
    if (await tempBackupWalFile.exists()) await tempBackupWalFile.delete();
    if (await tempBackupShmFile.exists()) await tempBackupShmFile.delete();

    // Rename current database files to temp backup
    if (await dbFile.exists()) await dbFile.rename(tempBackupDbPath);
    if (await walFile.exists()) await walFile.rename(tempBackupWalPath);
    if (await shmFile.exists()) await shmFile.rename(tempBackupShmPath);

    try {
      // Overwrite DB file
      await file.copy(dbPath);

      // Verify that the restored file can be opened and is intact
      Database? testRestoredDb;
      try {
        testRestoredDb = await dbManager.openDatabaseConnection(
          dbPath,
          readOnly: true,
        );
        await testRestoredDb
            .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      } finally {
        if (testRestoredDb != null) {
          await testRestoredDb.close();
        }
      }

      // If we got here, write was successful. We can safely delete backup temp files.
      if (await tempBackupDbFile.exists()) await tempBackupDbFile.delete();
      if (await tempBackupWalFile.exists()) await tempBackupWalFile.delete();
      if (await tempBackupShmFile.exists()) await tempBackupShmFile.delete();
    } catch (e) {
      // Restore failed, roll back original files!
      if (await dbFile.exists()) await dbFile.delete();
      if (await walFile.exists()) await walFile.delete();
      if (await shmFile.exists()) await shmFile.delete();

      if (await tempBackupDbFile.exists())
        await tempBackupDbFile.rename(dbPath);
      if (await tempBackupWalFile.exists())
        await tempBackupWalFile.rename(walPath);
      if (await tempBackupShmFile.exists())
        await tempBackupShmFile.rename(shmPath);

      throw Exception(
          'Veritabanı geri yükleme yazma hatası, değişiklikler geri alındı: $e');
    }

    // 4. Force re-initialization of DatabaseManager
    await dbManager.getDatabase();

    try {
      final auditRepo = SqliteAuditRepository(dbManager);
      await auditRepo.logEvent(AuditEvent(
        id: const Uuid().v4(),
        eventType: 'system_restore',
        entityType: 'system',
        notes: 'Veritabanı yedekten geri yüklendi: ${basename(backupPath)}',
        timestamp: DateTime.now(),
      ));
    } catch (_) {}

    return true;
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
