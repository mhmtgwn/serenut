// lib/infrastructure/services/rollback_manager.dart
// Serenut OS — Safe Update Installation & Rollback Manager (Sprint 6)

import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class SystemSpecCheckResult {
  final bool hasRequiredSpace;
  final bool hasRequiredRam;
  final bool hasAdminPrivileges;
  final double freeSpaceGb;
  final List<String> issues;

  SystemSpecCheckResult({
    required this.hasRequiredSpace,
    required this.hasRequiredRam,
    required this.hasAdminPrivileges,
    required this.freeSpaceGb,
    required this.issues,
  });

  // Serenut OS is installed per-user (`PrivilegesRequired=lowest` on Windows),
  // so an elevated process is not an installation requirement.
  bool get isAllPass => hasRequiredSpace && hasRequiredRam;
}

class RollbackManager {
  /// Run diagnostic specs checks before launching updates setup
  Future<SystemSpecCheckResult> verifyInstallationSpecs() async {
    bool hasSpace = true;
    bool hasRam = true;
    const bool hasAdmin = true;
    double freeGb = 1.0; // Fallback default
    final issues = <String>[];

    // The Windows installer targets {userappdata}; elevation is neither needed
    // nor desirable. Keep this compatibility field true for existing callers.

    // 2. Check Disk Space (Requesting min 300MB)
    try {
      if (Platform.isWindows) {
        final res = await Process.run('powershell',
            ['-Command', '(Get-Volume -DriveLetter C).SizeRemaining']);
        if (res.exitCode == 0) {
          final bytes = int.tryParse(res.stdout.toString().trim()) ?? 0;
          freeGb = bytes / (1024 * 1024 * 1024);
          if (freeGb < 0.3) {
            hasSpace = false;
            issues.add('Yetersiz disk alanı. En az 300MB boş alan gereklidir.');
          }
        }
      } else {
        // Fallback for Android (usually system installer handles this)
        freeGb = 2.0;
      }
    } catch (_) {
      freeGb = 2.0; // Fallback safe
    }

    // 3. Check RAM memory limits (Requesting min 2GB for POS cache buffers)
    try {
      if (Platform.isWindows) {
        final res = await Process.run(
            'wmic', ['computersystem', 'get', 'TotalPhysicalMemory']);
        if (res.exitCode == 0) {
          final lines = res.stdout.toString().split('\n');
          if (lines.length > 1) {
            final rawBytes = int.tryParse(lines[1].trim()) ?? 0;
            final double ramGb = rawBytes / (1024 * 1024 * 1024);
            if (ramGb < 2.0) {
              hasRam = false;
              issues.add('Yetersiz RAM kapasitesi. En az 2GB RAM gereklidir.');
            }
          }
        }
      }
    } catch (_) {
      hasRam = true; // Fallback soft check
    }

    return SystemSpecCheckResult(
      hasRequiredSpace: hasSpace,
      hasRequiredRam: hasRam,
      hasAdminPrivileges: hasAdmin,
      freeSpaceGb: freeGb,
      issues: issues,
    );
  }

  /// Backup current running binary and local configuration
  Future<bool> backupCurrentVersion() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final backupDir = Directory(join(appDir.path, 'update_backups'))
        ..createSync(recursive: true);

      // 1. Backup current executable (Windows case)
      if (Platform.isWindows) {
        final currentExe = File(Platform.resolvedExecutable);
        if (await currentExe.exists()) {
          final targetBackup =
              File(join(backupDir.path, 'serenut_running.exe.bak'));
          await currentExe.copy(targetBackup.path);
        }
      }

      // 2. Backup sqlite database
      final String dbPath = join(await getDatabasesPath(), 'serenut_pos.db');
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        final targetDbBackup = File(join(backupDir.path, 'serenut_pos.db.bak'));
        await dbFile.copy(targetDbBackup.path);
      }

      debugPrint(
          '[RollbackManager] Current version backup completed successfully.');
      return true;
    } catch (e) {
      debugPrint('[RollbackManager] Version backup failed: $e');
      return false;
    }
  }

  /// Triggers automated restore rollback from backup files
  Future<bool> triggerRollback() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final backupDir = Directory(join(appDir.path, 'update_backups'));
      if (!await backupDir.exists()) return false;

      // 1. Rollback Windows executable
      if (Platform.isWindows) {
        final backupExe = File(join(backupDir.path, 'serenut_running.exe.bak'));
        if (await backupExe.exists()) {
          final targetExe = File(Platform.resolvedExecutable);
          await backupExe.copy(targetExe.path);
        }
      }

      // 2. Rollback sqlite database
      final backupDb = File(join(backupDir.path, 'serenut_pos.db.bak'));
      if (await backupDb.exists()) {
        final String dbPath = join(await getDatabasesPath(), 'serenut_pos.db');
        final targetDb = File(dbPath);
        if (await targetDb.exists()) {
          await targetDb.delete();
        }
        await backupDb.copy(targetDb.path);
      }

      debugPrint(
          '[RollbackManager] Automated rollback restore completed successfully.');
      return true;
    } catch (e) {
      debugPrint('[RollbackManager] Rollback attempt failed: $e');
      return false;
    }
  }

  Future<String> getDatabasesPath() async {
    final appSupportDir = await getApplicationSupportDirectory();
    return join(appSupportDir.path, 'databases');
  }
}
