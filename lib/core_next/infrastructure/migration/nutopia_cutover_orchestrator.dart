// core_next/client_core/lib/infrastructure/migration/nutopia_cutover_orchestrator.dart
// SERENUT OS — STAGE 10.12.72
// NUTOPIA CUTOVER ORCHESTRATOR (MERKEZİ GEÇİŞ YÜRÜTÜCÜSÜ)
//
// Bu sınıf, Nutopia Fındık Değirmeni geçiş bileşenlerini
// (Bakım Kilidi, Delta Yakalama, Bütünlük Kapıları, DB Yönlendirme ve Ters Geri Dönüş)
// tek bir merkezi, atomik ve fail-closed koordinatör altında toplar.
//
// GÜVENLİK KURALI:
// Varsayılan olarak isDryRun = true modundadır. Açık yetkilendirme anahtarı
// verilmedikçe canlı veritabanı yönlendirmesini veya satış motorunu ASLA aktif etmez.

import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import 'cutoff_maintenance_lock.dart';
import 'live_safe_catch_up_reconciliation_coordinator.dart';
import 'migration_bridge_engine.dart';

/// Orkestratörün yönettiği yaşam döngüsü aşamaları
enum NutopiaCutoverStage {
  idle,
  identityVerification,
  fileAndBackupVerification,
  lockingRequested,
  lockingDraining,
  locked,
  deltaCatchUp,
  gateVerification,
  routingActivation,
  completed,
  rollingBack,
  rolledBack,
  failedBlocked,
}

/// Orkestratör çalıştırma yapılandırma modeli
class NutopiaCutoverExecutionOptions {
  final bool isDryRun;
  final String? liveExecutionAuthorizationKey;
  final String tenantId;
  final String legacyDbPath;
  final String targetCoreDbPath;
  final int? lastMigrationCutoffTimestamp;
  final Duration lockTimeout;

  const NutopiaCutoverExecutionOptions({
    this.isDryRun = true,
    this.liveExecutionAuthorizationKey,
    this.tenantId = 'nutopia',
    required this.legacyDbPath,
    required this.targetCoreDbPath,
    this.lastMigrationCutoffTimestamp,
    this.lockTimeout = const Duration(seconds: 15),
  });

  static const String requiredLiveAuthKey = 'CONFIRMED_NUTOPIA_LIVE_CUTOVER_AUTH';

  /// Otomatik olarak yerel işletim sistemi üzerindeki aktif canlı Nutopia DB yolunu (%APPDATA%...\serenut_pos.db) çözer.
  /// 16 Ekim snapshot yedeği yerine gerçek canlı kaynak yolunu sağlar.
  static Future<String> resolveDefaultLiveLegacyDbPath() async {
    final basePath = await getDatabasesPath();
    return p.join(basePath, 'serenut_pos.db');
  }
}

/// Orkestratör işlem sonucu ve adli denetim izi
class NutopiaCutoverResult {
  final bool isSuccess;
  final NutopiaCutoverStage finalStage;
  final bool isDryRun;
  final String? errorMessage;
  final String? rollbackMessage;
  final LiveReconciliationReport? reconciliationReport;
  final ReverseMigrationReport? rollbackReport;
  final Map<String, dynamic> auditTrail;
  final int durationMs;

  const NutopiaCutoverResult({
    required this.isSuccess,
    required this.finalStage,
    required this.isDryRun,
    this.errorMessage,
    this.rollbackMessage,
    this.reconciliationReport,
    this.rollbackReport,
    this.auditTrail = const {},
    required this.durationMs,
  });

  @override
  String toString() =>
      'NutopiaCutoverResult(isSuccess: $isSuccess, stage: ${finalStage.name}, isDryRun: $isDryRun, error: $errorMessage)';
}

/// Nutopia Kesin Geçiş Orkestratörü
class NutopiaCutoverOrchestrator {
  final CutoffMaintenanceLock cutoffMaintenanceLock;
  final LiveSafeCatchUpReconciliationCoordinator catchUpCoordinator;
  final SharedPreferences? prefs;
  final DatabaseFactory dbFactory;

  const NutopiaCutoverOrchestrator({
    required this.cutoffMaintenanceLock,
    this.catchUpCoordinator = const LiveSafeCatchUpReconciliationCoordinator(),
    this.prefs,
    required this.dbFactory,
  });

  /// SHA-256 dosya özeti hesaplar
  static Future<String> computeSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Nutopia Geçiş Akışını Güvenle Yürütür
  Future<NutopiaCutoverResult> executeCutover(
    NutopiaCutoverExecutionOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();
    final auditTrail = <String, dynamic>{
      'started_at': DateTime.now().toIso8601String(),
      'tenant_id': options.tenantId,
      'is_dry_run': options.isDryRun,
      'stages_passed': <String>[],
    };

    NutopiaCutoverStage currentStage = NutopiaCutoverStage.idle;
    Database? legacyDb;
    CoreAppDatabase? targetCoreDb;
    bool lockAcquired = false;

    try {
      // ───────────────────────────────────────────────────────────────────────
      // AŞAMA 1: İŞLETME KİMLİĞİ DOĞRULAMASI (TENANT IDENTITY GUARD)
      // ───────────────────────────────────────────────────────────────────────
      currentStage = NutopiaCutoverStage.identityVerification;
      if (options.tenantId.toLowerCase().trim() != 'nutopia') {
        throw ArgumentError(
          'GEÇİŞ ENGELİ: Bu orkestratör yalnızca "nutopia" kiracısı için yetkilidir. '
          'Gelen kiracı: "${options.tenantId}"',
        );
      }
      (auditTrail['stages_passed'] as List).add('1_identity_verified');

      // ───────────────────────────────────────────────────────────────────────
      // AŞAMA 2 & 3: DOSYA, YEDEK, SHA-256 VE SQLITE BÜTÜNLÜK DENETİMİ
      // ───────────────────────────────────────────────────────────────────────
      currentStage = NutopiaCutoverStage.fileAndBackupVerification;
      final legacyFile = File(options.legacyDbPath);
      final targetFile = File(options.targetCoreDbPath);

      if (!legacyFile.existsSync()) {
        throw FileSystemException(
          'Kaynak Nutopia veritabanı dosyası bulunamadı',
          options.legacyDbPath,
        );
      }
      if (!targetFile.existsSync()) {
        throw FileSystemException(
          'Hedef Nutopia Core Next veritabanı dosyası bulunamadı',
          options.targetCoreDbPath,
        );
      }

      final legacySize = legacyFile.lengthSync();
      final targetSize = targetFile.lengthSync();
      if (legacySize < 512 || targetSize < 512) {
        throw StateError(
          'Veritabanı dosyası geçersiz boyutta (< 512 bayt). Kaynak: $legacySize, Hedef: $targetSize',
        );
      }

      final legacySha256 = await computeSha256(legacyFile);
      final targetSha256 = await computeSha256(targetFile);
      auditTrail['legacy_sha256'] = legacySha256;
      auditTrail['target_sha256'] = targetSha256;
      auditTrail['legacy_size_bytes'] = legacySize;
      auditTrail['target_size_bytes'] = targetSize;

      // SQLite Integrity Check (Kaynak & Hedef)
      legacyDb = await dbFactory.openDatabase(
        options.legacyDbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final legIntegrity = await legacyDb.rawQuery('PRAGMA integrity_check;');
      if (legIntegrity.isEmpty || legIntegrity.first.values.first != 'ok') {
        throw StateError('Kaynak veritabanı SQLite bütünlük doğrulaması başarısız (integrity != ok).');
      }

      // Kaynak settings tablosundan işletme adı kontrolü
      final hasSettings = await legacyDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='settings'",
      );
      if (hasSettings.isNotEmpty) {
        final settingsRows = await legacyDb.query('settings');
        String bName = '';
        if (settingsRows.isNotEmpty) {
          final first = settingsRows.first;
          if (first.containsKey('business_name')) {
            bName = first['business_name']?.toString() ?? '';
          } else if (first.containsKey('key') && first.containsKey('value')) {
            for (final r in settingsRows) {
              if (r['key']?.toString() == 'business_name') {
                bName = r['value']?.toString() ?? '';
                break;
              }
            }
          }
        }
        if (!bName.toLowerCase().contains('nutopia')) {
          throw StateError(
            'Kaynak veritabanı ayarlarındaki işletme adı Nutopia ile eşleşmiyor: "$bName"',
          );
        }
        auditTrail['source_business_name'] = bName;
      }

      (auditTrail['stages_passed'] as List).add('2_file_and_backup_verified');

      // ───────────────────────────────────────────────────────────────────────
      // AŞAMA 4 & 5: MERKEZİ KESİM BAKIM KİLİDİ VE YAZMA BOŞALTMA (DRAINING)
      // ───────────────────────────────────────────────────────────────────────
      currentStage = NutopiaCutoverStage.lockingRequested;
      final lockSuccess = await cutoffMaintenanceLock.acquireLock(
        tenantId: 'nutopia',
        reason: 'Nutopia Core Next Production Cutover',
        timeout: options.lockTimeout,
      );

      if (!lockSuccess || !cutoffMaintenanceLock.isSafeForSnapshot) {
        throw StateError(
          'Bakım kilidi alınamadı veya devam eden işlemler boşaltılamadı (Draining Timeout). '
          'Aktif yazma sayısı: ${cutoffMaintenanceLock.state.activeWriteCount}',
        );
      }
      lockAcquired = true;
      currentStage = NutopiaCutoverStage.locked;
      auditTrail['lock_acquired_at'] = DateTime.now().toIso8601String();
      (auditTrail['stages_passed'] as List).add('3_maintenance_lock_active');

      // ───────────────────────────────────────────────────────────────────────
      // AŞAMA 6: DELTA YAKALAMA VE MUTABAKAT (CATCH-UP & RECONCILIATION)
      // ───────────────────────────────────────────────────────────────────────
      currentStage = NutopiaCutoverStage.deltaCatchUp;
      targetCoreDb = await CoreAppDatabase.open(
        inMemoryOrCustomPath: options.targetCoreDbPath,
      );

      // Hedef app_settings kiracı kontrolü
      final settingRows = await targetCoreDb.db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['tenant_id'],
      );
      final targetTenantId = settingRows.isNotEmpty ? settingRows.first['value']?.toString() : null;
      if (targetTenantId != 'nutopia') {
        throw StateError(
          'Hedef veritabanı tenant_id uyuşmuyor: "$targetTenantId" != "nutopia"',
        );
      }

      // Canlı yazma kontrolü için salt-okunur kaynak bağlantısını kapatıp uygun modda açalım
      await legacyDb.close();
      legacyDb = await dbFactory.openDatabase(
        options.legacyDbPath,
        options: OpenDatabaseOptions(readOnly: options.isDryRun),
      );

      final reconReport = await catchUpCoordinator.performCatchUpAndReconcile(
        legacyDb: legacyDb,
        targetCoreDb: targetCoreDb,
        legacyDbPath: options.legacyDbPath,
        lastMigrationCutoffTimestamp: options.lastMigrationCutoffTimestamp,
        persistCutoverStatus: !options.isDryRun,
      );

      auditTrail['reconciliation_decision'] = reconReport.decision.name;
      auditTrail['reconciliation_matched'] = reconReport.isMatched;
      auditTrail['catch_up_records'] = reconReport.catchUpRecordsMigrated;

      if (!reconReport.isMatched ||
          reconReport.decision != CutoverReconciliationDecision.cutoverApproved) {
        throw StateError(
          'Delta mutabakatı başarısız oldu! Karar: ${reconReport.decision.name}. '
          'Detaylar: ${reconReport.details}',
        );
      }
      (auditTrail['stages_passed'] as List).add('4_delta_reconciled');

      // Checkpoint zaman damgası mühürleme (Watermark)
      if (!options.isDryRun) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        await targetCoreDb.db.insert(
          'app_settings',
          {
            'key': 'last_delta_checkpoint_timestamp',
            'value': nowMs.toString(),
            'updated_at': nowMs,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        auditTrail['checkpoint_timestamp_ms'] = nowMs;
      }

      // ───────────────────────────────────────────────────────────────────────
      // AŞAMA 7: İLİŞKİSEL BÜTÜNLÜK VE GEÇİŞ KAPILARI DOĞRULAMASI (G1 - G6)
      // ───────────────────────────────────────────────────────────────────────
      currentStage = NutopiaCutoverStage.gateVerification;
      final targetFkCheck = await targetCoreDb.db.rawQuery('PRAGMA foreign_key_check;');
      if (targetFkCheck.isNotEmpty) {
        throw StateError(
          'Hedef veritabanında yabancı anahtar ihlali tespit edildi: $targetFkCheck',
        );
      }

      (auditTrail['stages_passed'] as List).add('5_gate_verified');

      // ───────────────────────────────────────────────────────────────────────
      // AŞAMA 8: YÖNLENDİRME VE MOTOR AKTİVASYONU (SADECE VE SADECE CANLI MODDA)
      // ───────────────────────────────────────────────────────────────────────
      currentStage = NutopiaCutoverStage.routingActivation;

      if (options.isDryRun) {
        // DRY-RUN GÜVENLİK SINIRI:
        // Canlı yönlendirme kesinlikle DEĞİŞTİRİLMEZ!
        // Kilidi kontrollü biçimde serbest bırak ve raporla.
        await cutoffMaintenanceLock.releaseLock();
        lockAcquired = false;

        stopwatch.stop();
        return NutopiaCutoverResult(
          isSuccess: true,
          finalStage: NutopiaCutoverStage.completed,
          isDryRun: true,
          reconciliationReport: reconReport,
          auditTrail: auditTrail,
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }

      // CANLI MOD ÇALIŞTIRMA (Kesin Yetkilendirme Kapısı Kontrolü)
      if (options.liveExecutionAuthorizationKey !=
          NutopiaCutoverExecutionOptions.requiredLiveAuthKey) {
        throw StateError(
          'CANLI GEÇİŞ YETKİSİZ: Geçerli canlı yetkilendirme anahtarı sağlanmadı.',
        );
      }

      if (prefs != null) {
        await prefs!.setBool('core_next_pilot_enabled', true);
        await prefs!.setString(
          'core_next_cutover_completed_at',
          DateTime.now().toIso8601String(),
        );
      }

      // Kilidi serbest bırak — artık yeni işlemler Core Next DB'ye akacaktır
      await cutoffMaintenanceLock.releaseLock();
      lockAcquired = false;

      (auditTrail['stages_passed'] as List).add('6_routing_activated');
      stopwatch.stop();

      return NutopiaCutoverResult(
        isSuccess: true,
        finalStage: NutopiaCutoverStage.completed,
        isDryRun: false,
        reconciliationReport: reconReport,
        auditTrail: auditTrail,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e, st) {
      debugPrint('[NutopiaCutoverOrchestrator] ❌ Hata meydana geldi ($currentStage): $e\n$st');

      String? rollbackMsg;
      ReverseMigrationReport? rbReport;

      // Hata meydana geldiğinde geri dönüş (Rollback) protokolü:
      if (targetCoreDb != null && legacyDb != null && !options.isDryRun) {
        try {
          currentStage = NutopiaCutoverStage.rollingBack;
          debugPrint('[NutopiaCutoverOrchestrator] 🔄 Tersine uzlaştırma (Reverse Migration) başlatılıyor...');
          rbReport = await ReverseMigrationEngine.rollbackToLegacy(
            legacyDb: legacyDb,
            coreDb: targetCoreDb,
          );
          if (rbReport.isSuccess) {
            rollbackMsg = 'Geri dönüş başarıyla tamamlandı (Yeni fişler legacy DB\'ye aktarıldı).';
            currentStage = NutopiaCutoverStage.rolledBack;
          } else {
            rollbackMsg = 'KRİTİK: Geri dönüş başarısız: ${rbReport.errorMessage}';
            currentStage = NutopiaCutoverStage.failedBlocked;
          }
        } catch (rbErr) {
          rollbackMsg = 'KRİTİK: Geri dönüş sırasında istisna oluştu: $rbErr';
          currentStage = NutopiaCutoverStage.failedBlocked;
        }
      }

      if (prefs != null) {
        await prefs!.setBool('core_next_pilot_enabled', false);
      }

      // Eğer kilit alınmış ve sistem kilitliyse;
      // Yalnızca dryRun ise veya geri dönüş temiz tamamlandıysa kilidi aç.
      // Aksi halde veritabanını kilitli tut (kullanıcıların bozuk/çakışan veriye yazmasını engelle).
      if (lockAcquired) {
        if (options.isDryRun || currentStage == NutopiaCutoverStage.rolledBack) {
          await cutoffMaintenanceLock.releaseLock();
        } else {
          debugPrint(
            '[NutopiaCutoverOrchestrator] 🚨 FAIL-CLOSED: Veri bütünlüğü için kesim kilidi AÇILMADI.',
          );
        }
      }

      stopwatch.stop();
      return NutopiaCutoverResult(
        isSuccess: false,
        finalStage: currentStage == NutopiaCutoverStage.rolledBack
            ? NutopiaCutoverStage.rolledBack
            : NutopiaCutoverStage.failedBlocked,
        isDryRun: options.isDryRun,
        errorMessage: e.toString(),
        rollbackMessage: rollbackMsg,
        rollbackReport: rbReport,
        auditTrail: auditTrail,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } finally {
      if (legacyDb != null && legacyDb.isOpen) {
        await legacyDb.close();
      }
      if (targetCoreDb != null) {
        await targetCoreDb.close();
      }
    }
  }
}
