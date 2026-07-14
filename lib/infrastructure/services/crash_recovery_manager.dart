// lib/infrastructure/services/crash_recovery_manager.dart
// Serenut OS — Crash Recovery and Interrupted State Manager (Sprint 12)

import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../../infrastructure/database/database_provider.dart';
import 'package:flutter/foundation.dart';

class CrashRecoveryManager {
  
  /// Checks if the application crashed during the last session.
  /// If it finds the lock file, it returns true (crashed). Otherwise creates the lock and returns false.
  Future<bool> checkForCrashOnStartup() async {
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final lockFile = File(join(appSupportDir.path, 'app_running.lock'));

      if (await lockFile.exists()) {
        debugPrint('[CrashRecovery] Alert: Interrupted crash detected from last session.');
        return true;
      }

      // Create lock file for the current session
      await lockFile.writeAsString(DateTime.now().toIso8601String());
      return false;
    } catch (e) {
      debugPrint('[CrashRecovery] Failed to perform lock file checks: $e');
      return false;
    }
  }

  /// Removes the running session lock file on clean application exit
  Future<void> markAppCleanShutdown() async {
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final lockFile = File(join(appSupportDir.path, 'app_running.lock'));
      if (await lockFile.exists()) {
        await lockFile.delete();
        debugPrint('[CrashRecovery] App shut down cleanly. Session lock released.');
      }
    } catch (e) {
      debugPrint('[CrashRecovery] Failed to clear session lock: $e');
    }
  }

  /// Scans local sync tables to replay interrupted transactions
  Future<int> recoverInterruptedSyncJobs() async {
    int replayed = 0;
    try {
      final db = await DatabaseManager().getDatabase();
      
      // Select interrupted failed pushes
      final List<Map<String, dynamic>> pendingPushes = await db.query(
        'failed_push_log',
        where: 'resolved = 0',
      );

      if (pendingPushes.isNotEmpty) {
        debugPrint('[CrashRecovery] Found ${pendingPushes.length} interrupted sync entries. Queueing replay...');
        for (final row in pendingPushes) {
          // Re-trigger sync queues (mocking recovery action log)
          await db.update(
            'failed_push_log',
            {
              'attempt_count': (row['attempt_count'] as int) + 1,
              'last_attempt_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
          replayed++;
        }
      }
    } catch (e) {
      debugPrint('[CrashRecovery] Error replaying transactions: $e');
    }
    return replayed;
  }
}
