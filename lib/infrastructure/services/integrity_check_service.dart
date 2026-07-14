// lib/infrastructure/services/integrity_check_service.dart
// Serenut OS — Database & File Integrity Check Service (Sprint 3)

import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../../infrastructure/database/database_provider.dart';
import '../../domain/services/telemetry_service.dart';

class IntegrityReport {
  final bool isDatabaseHealthy;
  final bool isFileSystemHealthy;
  final List<String> issues;
  final String logs;

  IntegrityReport({
    required this.isDatabaseHealthy,
    required this.isFileSystemHealthy,
    required this.issues,
    required this.logs,
  });

  bool get isAllPass => isDatabaseHealthy && isFileSystemHealthy;
}

class IntegrityCheckService {
  final SharedPreferences _prefs;

  IntegrityCheckService(this._prefs);

  /// Scans all local resources and returns an IntegrityReport
  Future<IntegrityReport> runDiagnostics() async {
    final issues = <String>[];
    final logBuffer = StringBuffer();
    bool dbHealthy = true;
    bool fsHealthy = true;

    logBuffer.writeln('=== START DIAGNOSTICS: ${DateTime.now().toIso8601String()} ===');

    // 1. SQLite Database Checks
    try {
      final db = await DatabaseManager().getDatabase();
      
      // PRAGMA integrity_check
      final List<Map<String, dynamic>> integrityRes = await db.rawQuery('PRAGMA integrity_check');
      if (integrityRes.isEmpty || integrityRes.first.values.first != 'ok') {
        dbHealthy = false;
        final details = integrityRes.isNotEmpty ? integrityRes.first.values.first.toString() : 'Empty result';
        issues.add('Database integrity check failed: $details');
        logBuffer.writeln('❌ DB Integrity Fail: $details');
      } else {
        logBuffer.writeln('✅ DB Integrity Check: PASS');
      }

      // PRAGMA foreign_key_check
      final List<Map<String, dynamic>> fkRes = await db.rawQuery('PRAGMA foreign_key_check');
      if (fkRes.isNotEmpty) {
        dbHealthy = false;
        issues.add('Foreign key integrity anomalies detected: ${fkRes.length} row violations');
        logBuffer.writeln('❌ DB Foreign Key Check: FAIL (${fkRes.length} violations)');
      } else {
        logBuffer.writeln('✅ DB Foreign Key Check: PASS');
      }

      // Verify ledger_bypass_flag is active = 0 (ledger immutability safety check)
      final List<Map<String, dynamic>> bypassRes = await db.rawQuery('SELECT active FROM ledger_bypass_flag LIMIT 1');
      if (bypassRes.isNotEmpty && bypassRes.first['active'] == 1) {
        // Safe correction
        await db.rawUpdate('UPDATE ledger_bypass_flag SET active = 0');
        issues.add('Ledger bypass flag was left active (1). Automatically restored to 0 for security.');
        logBuffer.writeln('⚠️ Security Check: Ledger bypass flag was stuck at 1. Automatically repaired to 0.');
        try {
          await TelemetryService().logStructured(
            event: 'ledger_bypass_flag_repaired',
            level: LogLevel.critical,
            metadata: {
              'timestamp': DateTime.now().toIso8601String(),
              'message': 'Bypass flag was stuck at 1 on startup; reset to 0.',
            },
          );
        } catch (_) {}
      } else {
        logBuffer.writeln('✅ Security Check: Ledger bypass flag is disabled: PASS');
      }
    } catch (e) {
      dbHealthy = false;
      issues.add('Could not open or read database: $e');
      logBuffer.writeln('❌ DB Open Exception: $e');
    }

    // 2. Directory & Files Checks
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final cacheDir = await getTemporaryDirectory();
      
      // Check crucial folders
      if (!Directory(appSupportDir.path).existsSync()) {
        fsHealthy = false;
        issues.add('App support directory is missing');
      }
      if (!Directory(cacheDir.path).existsSync()) {
        fsHealthy = false;
        issues.add('Temporary cache directory is missing');
      }

      // Verify essential configuration exists in SQLite settings (single source of truth)
      final dbForPin = await DatabaseManager().getDatabase();
      final pinRows = await dbForPin.query('settings', columns: ['admin_pin_code'], limit: 1);
      final adminPin = pinRows.isNotEmpty ? pinRows.first['admin_pin_code'] as String? : null;
      if (adminPin == null || adminPin.isEmpty) {
        // Warning level only
        logBuffer.writeln('⚠️ Warning: Admin PIN config is not set (first launch onboarding state)');
      } else {
        logBuffer.writeln('✅ Config Verification: PASS');
      }
    } catch (e) {
      fsHealthy = false;
      issues.add('File system diagnostics check failed: $e');
      logBuffer.writeln('❌ File System Exception: $e');
    }

    logBuffer.writeln('=== END DIAGNOSTICS: ${dbHealthy && fsHealthy ? "PASS" : "FAIL"} ===');

    return IntegrityReport(
      isDatabaseHealthy: dbHealthy,
      isFileSystemHealthy: fsHealthy,
      issues: issues,
      logs: logBuffer.toString(),
    );
  }

  /// Attempts database repair from the most recent valid backup.
  ///
  /// KRİTİK E DÜZELTMESİ: Repair sırası:
  ///   1. SerenutBackups/ klasöründeki en son kullanıcı backup'ı (tarih/saate göre)
  ///   2. Yok ise: migration upgrade backup dosyası (serenut_pos_upgrade_backup.db)
  ///   3. İkisi de yoksa: false döner.
  ///
  /// Güvenlik: hedef DB silinmeden önce temp backup alınır; kopya başarısız
  /// olursa temp backup geri yüklenir.
  Future<bool> attemptDatabaseRepair() async {
    try {
      final dbDir = await DatabaseManager().getDatabasesPath();
      final String dbPath = join(dbDir, 'serenut_pos.db');

      // 1. En son kullanıcı backup'ını bul (SerenutBackups/ klasörü)
      File? latestBackupFile;
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        final backupsDir = Directory(join(docsDir.path, 'SerenutBackups'));
        if (await backupsDir.exists()) {
          final files = backupsDir
              .listSync()
              .whereType<File>()
              .where((f) =>
                  basename(f.path).startsWith('serenut_pos_backup_') &&
                  f.path.endsWith('.db'))
              .toList();
          if (files.isNotEmpty) {
            files.sort((a, b) =>
                b.lastModifiedSync().compareTo(a.lastModifiedSync()));
            latestBackupFile = files.first;
          }
        }
      } catch (e) {
        // Backup klasörü okunamazsa logla ama işlemi durdurma
        debugPrint('[IntegrityCheckService] SerenutBackups taraması başarısız: $e');
      }

      // 2. Fallback: upgrade backup
      final String upgradePath = join(dbDir, 'serenut_pos_upgrade_backup.db');
      final File upgradeBackup = File(upgradePath);

      final File? sourceFile = latestBackupFile ??
          (await upgradeBackup.exists() ? upgradeBackup : null);

      if (sourceFile == null) {
        debugPrint('[IntegrityCheckService] attemptDatabaseRepair: kullanılabilir backup yok.');
        return false;
      }

      debugPrint('[IntegrityCheckService] Repair kaynağı: ${sourceFile.path}');

      final dbFile = File(dbPath);

      // 3. Mevcut DB'yi temp'e yedekle (rollback garantisi)
      final tempPath = '$dbPath.repair_bak';
      final tempFile = File(tempPath);
      if (await tempFile.exists()) await tempFile.delete();
      if (await dbFile.exists()) {
        await dbFile.copy(tempPath);
      }

      try {
        if (await dbFile.exists()) await dbFile.delete();
        await sourceFile.copy(dbPath);

        // WAL sidecar varsa onu da kopyala
        final walSource = File('${sourceFile.path}-wal');
        if (await walSource.exists()) {
          await walSource.copy('$dbPath-wal');
        }

        // Geri yüklenen dosyayı hızlı doğrula
        final db = await DatabaseManager().getDatabase();
        final res = await db.rawQuery('PRAGMA integrity_check');
        if (res.isEmpty || res.first.values.first != 'ok') {
          throw Exception('Geri yüklenen DB integrity check başarısız.');
        }

        // Başarılı — temp backup'ı sil
        if (await tempFile.exists()) await tempFile.delete();
        debugPrint('[IntegrityCheckService] Repair başarılı: ${basename(sourceFile.path)}');
        return true;
      } catch (e) {
        debugPrint('[IntegrityCheckService] Repair başarısız, rollback yapılıyor: $e');
        // Rollback: temp backup'ı geri yükle
        if (await dbFile.exists()) await dbFile.delete();
        if (await tempFile.exists()) await tempFile.rename(dbPath);
        return false;
      }
    } catch (e) {
      debugPrint('[IntegrityCheckService] attemptDatabaseRepair genel hata: $e');
      return false;
    }
  }
}
