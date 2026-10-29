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
  /// Strateji: Çökme anında 'SENDING' durumunda takılı kalmış outbox satırları
  /// 'PENDING' durumuna geri alınır; ancak 'attempts' sayacı sıfırlanmaz ve 5 denemeyi
  /// aşmış zehirli kayıtlar (poison pills) doğrudan 'DEAD_LETTER' durumuna çekilir.
  /// 'DEAD_LETTER' veya 'CONFLICT' durumundaki kayıtlar asla canlandırılmaz.
  Future<int> recoverInterruptedSyncJobs() async {
    int replayed = 0;
    try {
      final db = await DatabaseManager.instance.getDatabase();

      // 1. Attempts ceiling: 5 veya daha fazla başarısız denemesi olan satırları
      // DEAD_LETTER durumuna alarak sonsuz döngüleri engelle.
      await db.rawUpdate('''
        UPDATE sync_outbox_v4
        SET state = 'DEAD_LETTER'
        WHERE attempts >= 5 AND state IN ('PENDING', 'SENDING', 'REJECTED', 'FAILED')
      ''');

      // 2. Çökme veya elektrik kesintisi anında 'SENDING' durumunda kalmış satırları
      // 'PENDING' durumuna al, ancak attempts sayacını koru (asla sıfırlama).
      final stuckSending = await db.query(
        'sync_outbox_v4',
        where: "state = 'SENDING' AND attempts < 5",
      );

      if (stuckSending.isNotEmpty) {
        debugPrint(
            '[CrashRecovery] ${stuckSending.length} yarıda kalmış (SENDING) outbox satırı bulundu. PENDING durumuna alınıyor...');
        await db.update(
          'sync_outbox_v4',
          {'state': 'PENDING'},
          where: "state = 'SENDING' AND attempts < 5",
        );
        replayed = stuckSending.length;
      }

      // failed_push_log'daki çözümlenmemiş kayıtları raporla
      final pendingPushLogs = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM failed_push_log WHERE resolved = 0',
      );
      final pendingCount = (pendingPushLogs.first['cnt'] as int?) ?? 0;
      if (pendingCount > 0) {
        debugPrint(
            '[CrashRecovery] failed_push_log’da $pendingCount çözümlenmemiş hata kaydı var.');
      }
    } catch (e) {
      debugPrint('[CrashRecovery] Kurtarma işlemi hata verdi: $e');
    }
    return replayed;
  }
}
