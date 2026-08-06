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
        debugPrint(
            '[CrashRecovery] Alert: Interrupted crash detected from last session.');
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
        debugPrint(
            '[CrashRecovery] App shut down cleanly. Session lock released.');
      }
    } catch (e) {
      debugPrint('[CrashRecovery] Failed to clear session lock: $e');
    }
  }

  /// Crash sonras\u0131 yar\u0131da kalan sync i\u015flemlerini kurtarır.
  ///
  /// Strateji: sync_outbox_v4 tablosunda FAILED durumunda s\u0131k\u0131\u015f\u0131p kalm\u0131\u015f
  /// sat\u0131rlar PENDING'e s\u0131f\u0131rlan\u0131r; bu sayede sync engine bunlar\u0131 yeniden
  /// göndermeye \u00e7al\u0131\u015f\u0131r. failed_push_log tablosu \u00f6zel yap\u0131s\u0131 nedeniyle bu
  /// i\u015flem i\u00e7in uygun de\u011fildir (payload/entity_type sütunu yok).
  Future<int> recoverInterruptedSyncJobs() async {
    int replayed = 0;
    try {
      final db = await DatabaseManager().getDatabase();

      // sync_outbox_v4'te FAILED veya \u00e7ok uzun s\u00fcre PENDING kalm\u0131\u015f sat\u0131rlar\u0131
      // bul (birden fazla deneme yap\u0131lm\u0131\u015f ama hi\u00e7 tamamlanmam\u0131\u015f).
      final List<Map<String, dynamic>> stuckEntries = await db.query(
        'sync_outbox_v4',
        where: "state IN ('FAILED', 'PENDING') AND attempts > 0",
      );

      if (stuckEntries.isNotEmpty) {
        debugPrint(
            '[CrashRecovery] ${stuckEntries.length} yar\u0131da kalm\u0131\u015f outbox sat\u0131r\u0131 bulundu. PENDING\u2019e s\u0131f\u0131rlan\u0131yor...');
        await db.update(
          'sync_outbox_v4',
          {
            'state': 'PENDING',
            'attempts': 0,
          },
          where: "state IN ('FAILED', 'PENDING') AND attempts > 0",
        );
        replayed = stuckEntries.length;
      }

      // failed_push_log'daki \u00e7\u00f6z\u00fcmlenmemi\u015f kay\u0131tlar\u0131 raporla (schema s\u0131n\u0131rlamas\u0131
      // nedeniyle direkt replay yap\u0131lm\u0131yor, ancak op say\u0131s\u0131 loglan\u0131yor).
      final pendingPushLogs = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM failed_push_log WHERE resolved = 0',
      );
      final pendingCount = (pendingPushLogs.first['cnt'] as int?) ?? 0;
      if (pendingCount > 0) {
        debugPrint(
            '[CrashRecovery] failed_push_log\u2019da $pendingCount \u00e7\u00f6z\u00fcmlenmemi\u015f hata kayd\u0131 var.');
      }
    } catch (e) {
      debugPrint('[CrashRecovery] Kurtarma i\u015flemi hata verdi: $e');
    }
    return replayed;
  }
}
