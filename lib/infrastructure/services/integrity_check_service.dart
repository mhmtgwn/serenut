// lib/infrastructure/services/integrity_check_service.dart
// Serenut OS — Database & File Integrity Check Service (Sprint 3)

import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../../infrastructure/database/database_provider.dart';

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

      // Verify essential configuration exist in SharedPreferences
      final adminPin = _prefs.getString('admin_pin_code');
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

  /// Attempts database repair from local backup snapshot
  Future<bool> attemptDatabaseRepair() async {
    try {
      final String dbPath = join(await DatabaseManager().getDatabasesPath(), 'serenut_pos.db');
      final String backupPath = join(await DatabaseManager().getDatabasesPath(), 'serenut_pos_upgrade_backup.db');

      final dbFile = File(dbPath);
      final backupFile = File(backupPath);

      if (await backupFile.exists()) {
        // Safe hot-restore: delete corrupted, write back backup file
        if (await dbFile.exists()) {
          await dbFile.delete();
        }
        await backupFile.copy(dbPath);
        
        // Copy auxiliary wal/shm if present
        final walBackup = File('$backupPath-wal');
        if (await walBackup.exists()) {
          await walBackup.copy('$dbPath-wal');
        }

        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
