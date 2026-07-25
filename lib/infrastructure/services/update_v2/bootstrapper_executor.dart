// lib/infrastructure/services/update_v2/bootstrapper_executor.dart
// Serenut Platform — Client Bootstrapper Replacement Core Executor

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

enum BootstrapperResult {
  success(0),
  lockTimeout(10),
  invalidSignature(20),
  hashMismatch(30),
  installFailed(40),
  rollbackCompleted(50),
  rollbackFailed(60);

  final int exitCode;
  const BootstrapperResult(this.exitCode);
}

class BootstrapperExecutor {
  /// Waits for the parent application process (PID) to exit, checking for file locks.
  Future<bool> waitForProcessExit(int pid, Duration timeout) async {
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime) < timeout) {
      final isRunning = await _isProcessRunning(pid);
      if (!isRunning) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  /// Verifies if a file is currently locked or can be opened for writing.
  Future<bool> isFileLocked(File file) async {
    if (!await file.exists()) return false;
    try {
      // Attempt to open the file in write mode to detect sharing violations
      final raf = await file.open(mode: FileMode.writeOnlyAppend);
      await raf.close();
      return false;
    } catch (_) {
      return true;
    }
  }

  /// Executes atomic binary replacement.
  Future<BootstrapperResult> executeReplacement({
    required File targetFile,
    required File newFile,
    required File backupFile,
    int? parentPid,
    Duration waitTimeout = const Duration(seconds: 90),
  }) async {
    // 1. Wait for main process exit if PID is supplied
    if (parentPid != null && parentPid > 0) {
      final exited = await waitForProcessExit(parentPid, waitTimeout);
      if (!exited) {
        debugPrint('[Bootstrapper] Error: Parent application process (PID $parentPid) did not exit within timeout.');
        return BootstrapperResult.lockTimeout;
      }
    }

    // 2. Lock Detection
    if (await isFileLocked(targetFile)) {
      debugPrint('[Bootstrapper] Error: Target file is locked by another process (DLL or sharing violation).');
      return BootstrapperResult.lockTimeout;
    }

    // Self-Protection check: make sure newFile path is not the same as targetFile or current executable path
    if (targetFile.path == Platform.script.toFilePath()) {
      debugPrint('[Bootstrapper] Error: Self-protection triggered. Cannot overwrite the current updater instance.');
      return BootstrapperResult.installFailed;
    }

    // 3. Rename existing target to backup (Atomic preparation)
    try {
      if (await targetFile.exists()) {
        if (await backupFile.exists()) {
          await backupFile.delete();
        }
        await targetFile.rename(backupFile.path);
      }
    } catch (e) {
      debugPrint('[Bootstrapper] Error: Failed to rename target file to backup: $e');
      return BootstrapperResult.installFailed;
    }

    // 4. Verify Backup Validation (Check backup executable size and existence)
    if (!await backupFile.exists() || await backupFile.length() == 0) {
      debugPrint('[Bootstrapper] Error: Backup executable verification failed. Aborting installation.');
      return BootstrapperResult.installFailed;
    }

    // 5. Copy new file to target location
    try {
      await newFile.copy(targetFile.path);
    } catch (e) {
      debugPrint('[Bootstrapper] Error: Failed to copy new executable. Initiating rollback. Exception: $e');
      // Rollback: Restore backup file
      try {
        if (await backupFile.exists()) {
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          await backupFile.rename(targetFile.path);
          return BootstrapperResult.rollbackCompleted;
        }
      } catch (rollbackErr) {
        debugPrint('[Bootstrapper] Critical: Rollback failed! Target executable is missing/corrupted: $rollbackErr');
        return BootstrapperResult.rollbackFailed;
      }
      return BootstrapperResult.installFailed;
    }

    // 6. Cleanup Backup on Success
    try {
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } catch (_) {
      // Soft-pass on backup deletion cleanup failure
    }

    return BootstrapperResult.success;
  }

  Future<bool> _isProcessRunning(int pid) async {
    try {
      if (Platform.isWindows) {
        final res = await Process.run('tasklist', ['/FI', 'PID eq $pid']);
        return res.stdout.toString().contains('$pid');
      } else {
        final res = await Process.run('kill', ['-0', '$pid']);
        return res.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }
}
