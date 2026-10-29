// lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart
// Serenut OS — Core Next Bootstrap Migration Coordinator
// Stage 10.9.3: Safe Lifecycle, WAL Checkpoint, Backup Verification, Fail-Closed

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/infrastructure/migration/safe_rollback_coordinator.dart';
import 'package:serenutos/infrastructure/migration/cutoff_maintenance_lock.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/core_next/infrastructure/database/app_database.dart';
import 'package:serenutos/core_next/infrastructure/migration/migration_bridge_engine.dart';

/// Core Next Migration Yaşam Döngüsü Durumları
enum CoreNextMigrationState {
  notStarted,
  backupInProgress,
  migrationInProgress,
  verificationInProgress,
  completed,
  failedRecoverable,
  failedBlocked;

  String get value {
    switch (this) {
      case CoreNextMigrationState.notStarted:
        return 'not_started';
      case CoreNextMigrationState.backupInProgress:
        return 'backup_in_progress';
      case CoreNextMigrationState.migrationInProgress:
        return 'migration_in_progress';
      case CoreNextMigrationState.verificationInProgress:
        return 'verification_in_progress';
      case CoreNextMigrationState.completed:
        return 'completed';
      case CoreNextMigrationState.failedRecoverable:
        return 'failed_recoverable';
      case CoreNextMigrationState.failedBlocked:
        return 'failed_blocked';
    }
  }

  static CoreNextMigrationState fromString(String? val) {
    switch (val) {
      case 'backup_in_progress':
        return CoreNextMigrationState.backupInProgress;
      case 'migration_in_progress':
        return CoreNextMigrationState.migrationInProgress;
      case 'verification_in_progress':
        return CoreNextMigrationState.verificationInProgress;
      case 'completed':
        return CoreNextMigrationState.completed;
      case 'failed_recoverable':
        return CoreNextMigrationState.failedRecoverable;
      case 'failed_blocked':
        return CoreNextMigrationState.failedBlocked;
      case 'not_started':
      default:
        return CoreNextMigrationState.notStarted;
    }
  }
}

/// Koordinatör İşlem Sonucu
class BootstrapCoordinatorResult {
  final bool isSuccess;
  final CoreNextMigrationState state;
  final String? backupPath;
  final dynamic migrationReport;
  final String? errorMessage;
  final String? errorReference;
  final bool isSkipped;
  final bool isAlreadyRunning;

  const BootstrapCoordinatorResult({
    required this.isSuccess,
    required this.state,
    this.backupPath,
    this.migrationReport,
    this.errorMessage,
    this.errorReference,
    this.isSkipped = false,
    this.isAlreadyRunning = false,
  });

  @override
  String toString() =>
      'BootstrapCoordinatorResult(isSuccess: $isSuccess, state: ${state.value}, skipped: $isSkipped, backup: $backupPath, error: $errorMessage)';
}

/// Özel Hata Sınıfları
class BackupVerificationException implements Exception {
  final String message;
  const BackupVerificationException(this.message);
  @override
  String toString() => 'BackupVerificationException: $message';
}

class ReconciliationException implements Exception {
  final String message;
  const ReconciliationException(this.message);
  @override
  String toString() => 'ReconciliationException: $message';
}

class MigrationExecutionException implements Exception {
  final String message;
  const MigrationExecutionException(this.message);
  @override
  String toString() => 'MigrationExecutionException: $message';
}

/// Kullanıcı Onay Kararı (Stage 10.12.17)
enum MigrationConsentDecision {
  approved,
  postponed;
}

/// Kullanıcı Onayı Arayüzü / Callback
typedef MigrationConsentRequester = Future<MigrationConsentDecision> Function();

/// Core Next Migration Aşamaları (Stage 10.12.17)
enum MigrationStage {
  idle,
  backupPreparing,
  sourceVerifying,
  dataMigrating,
  reconciliation,
  integrityChecking,
  completed,
  failed;
}

/// Reaktif İlerleme Durumu Modeli
class MigrationProgress {
  final MigrationStage stage;
  final String stageTitle;
  final String? detail;
  final double progress; // 0.0 to 1.0

  const MigrationProgress({
    required this.stage,
    required this.stageTitle,
    this.detail,
    required this.progress,
  });

  @override
  String toString() =>
      'MigrationProgress(stage: ${stage.name}, title: $stageTitle, progress: ${(progress * 100).toStringAsFixed(1)}%, detail: $detail)';
}

/// İlerleme Bildirim Callback'i
typedef MigrationProgressCallback = void Function(MigrationProgress progress);

/// Core Next Migration Çalıştırıcı Fonksiyon Arayüzü
typedef CoreNextMigrationRunner = Future<dynamic> Function({
  required Database legacyDb,
  required Database targetDb,
  String? legacyFilePath,
  bool fullScope,
});

/// Core Next Migration Kontrol Fonksiyon Arayüzü
typedef CoreNextCompletionChecker = Future<bool> Function(Database targetDb);

/// Core Next Rollback Guard Fonksiyon Arayüzü
typedef CoreNextRollbackGuard = Future<void> Function({
  required Database targetDb,
  required int initialMigrationCutoffTimestamp,
});

/// Core Next Canlı Catch-Up ve Mutabakat Doğrulama Fonksiyon Arayüzü (Stage 10.12.45)
typedef CoreNextCatchUpRunner = Future<bool> Function({
  required Database legacyDb,
  required Database targetDb,
  required String legacyDbPath,
  int? cutoffTimestamp,
});

/// Core Next Bootstrap Coordinator
/// 
/// Sorumluluklar:
/// 1. Migration durumunu SharedPreferences üzerinden yönetmek.
/// 2. Kaynak veritabanının bütünlüğünü doğrulamak.
/// 3. WAL Checkpoint ve doğrulanmış (verified) atomik yedek oluşturmak.
/// 4. Hedef Core Next veritabanını hazırlayıp migration'ı işletmek.
/// 5. Kaynak ve hedef verilerin kuruş bazında temel mutabakatını sağlamak.
/// 6. Hata anında Fail-Closed davranarak legacy sistemi korumak.
/// 7. Eşzamanlı (concurrent) çalıştırmaları engellemek.
class CoreNextBootstrapCoordinator {
  static const String prefKeyMigrationState = 'core_next_bootstrap_migration_state';
  static const String prefKeyCompletedAt = 'core_next_migration_completed_at';
  static const String prefKeyLastError = 'core_next_migration_last_error';
  static const String prefKeyBackupPath = 'core_next_migration_backup_path';

  static bool _isExecutionRunning = false;

  final DatabaseManager? _dbManager;
  final SharedPreferences? _prefs;
  final Database? _customLegacyDb;
  final Database? _customTargetDb;
  final String? _customLegacyFilePath;
  final String? _customBackupDirectory;
  final CoreNextMigrationRunner? _migrationRunner;
  final CoreNextCompletionChecker? _completionChecker;
  final CoreNextRollbackGuard? _rollbackGuard;
  final CoreNextCatchUpRunner? _catchUpRunner;
  final MigrationConsentRequester? _consentRequester;
  final MigrationProgressCallback? _onProgress;
  final bool _autonomousMode;

  CoreNextBootstrapCoordinator({
    DatabaseManager? dbManager,
    SharedPreferences? prefs,
    Database? customLegacyDb,
    Database? customTargetDb,
    String? customLegacyFilePath,
    String? customBackupDirectory,
    CoreNextMigrationRunner? migrationRunner,
    CoreNextCompletionChecker? completionChecker,
    CoreNextRollbackGuard? rollbackGuard,
    CoreNextCatchUpRunner? catchUpRunner,
    MigrationConsentRequester? consentRequester,
    MigrationProgressCallback? onProgress,
    bool autonomousMode = false,
  })  : _dbManager = dbManager,
        _prefs = prefs,
        _customLegacyDb = customLegacyDb,
        _customTargetDb = customTargetDb,
        _customLegacyFilePath = customLegacyFilePath,
        _customBackupDirectory = customBackupDirectory,
        _migrationRunner = migrationRunner,
        _completionChecker = completionChecker,
        _rollbackGuard = rollbackGuard,
        _catchUpRunner = catchUpRunner,
        _consentRequester = consentRequester,
        _onProgress = onProgress,
        _autonomousMode = autonomousMode;

  /// Eşzamanlı kilit durumu (Test amaçlı sorgulama için)
  static bool get isExecutionRunning => _isExecutionRunning;

  /// Test amaçlı kilidi sıfırlama metodu
  @visibleForTesting
  static void resetExecutionLock() {
    _isExecutionRunning = false;
  }

  /// Kalıcı durumu SharedPreferences'tan okur
  Future<CoreNextMigrationState> getPersistentState() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getString(prefKeyMigrationState);
    return CoreNextMigrationState.fromString(raw);
  }

  /// Kalıcı durumu günceller
  Future<void> _setPersistentState(CoreNextMigrationState state, {String? error}) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(prefKeyMigrationState, state.value);
    if (error != null) {
      await prefs.setString(prefKeyLastError, error);
    }
    if (state == CoreNextMigrationState.completed) {
      await prefs.setString(prefKeyCompletedAt, DateTime.now().toIso8601String());
    }
  }

  static String _generateErrorReference(String error) {
    final hash = (error.hashCode.abs() % 0xFFFFFF).toRadixString(16).toUpperCase();
    return 'ERR-${hash.padLeft(6, '0')}';
  }

  /// Tablo kolon isimlerini yardımcı sorgular
  Future<Set<String>> _getTableColumns(Database db, String tableName) async {
    final info = await db.rawQuery('PRAGMA table_info($tableName)');
    return info.map((r) => r['name'].toString()).toSet();
  }

  /// Hedef Core Next veritabanını açar veya temin eder
  Future<Database> _getTargetDatabase() async {
    if (_customTargetDb != null) return _customTargetDb!;
    final dbPath = DatabaseManager.overrideCoreNextDatabasePath ??
        await DatabaseManager.instance.getCoreNextDatabasePath();
    return openDatabase(
      dbPath,
      version: 3,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
        try {
          await db.rawQuery('PRAGMA journal_mode = WAL;');
        } catch (_) {}
      },
    );
  }

  /// Hedef veritabanında migration'ın daha önce tamamlanıp tamamlanmadığını kontrol eder
  Future<bool> _isCompletedOnTarget(Database targetDb) async {
    if (_completionChecker != null) {
      return _completionChecker!(targetDb);
    }
    try {
      final integrity = await targetDb.rawQuery('PRAGMA integrity_check;');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        return false;
      }
      final rows = await targetDb.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['legacy_migration_completed'],
      );
      return rows.isNotEmpty && rows.first['value'] == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Ana Koordinasyon Akışı
  Future<BootstrapCoordinatorResult> coordinate({
    bool forceRetry = false,
    MigrationConsentRequester? consentRequester,
    MigrationProgressCallback? onProgress,
    CoreNextCatchUpRunner? catchUpRunner,
    bool? autonomousMode,
  }) async {
    final effectiveProgress = onProgress ?? _onProgress;
    final effectiveConsentRequester = consentRequester ?? _consentRequester;
    final effectiveCatchUpRunner = catchUpRunner ?? _catchUpRunner;
    final isAutonomous = autonomousMode ?? _autonomousMode;

    if (_isExecutionRunning) {
      final current = await getPersistentState();
      return BootstrapCoordinatorResult(
        isSuccess: false,
        state: current,
        isAlreadyRunning: true,
        errorMessage: 'CoreNextBootstrapCoordinator işlemi şu anda başka bir akış tarafından yürütülüyor.',
      );
    }

    _isExecutionRunning = true;
    try {
      final currentState = await getPersistentState();

      // 1. Zaten başarıyla tamamlanmış mı?
      if (currentState == CoreNextMigrationState.completed && !forceRetry) {
        final targetDb = await _getTargetDatabase();
        final isCompleted = await _isCompletedOnTarget(targetDb);
        if (isCompleted) {
          debugPrint('[CoreNextBootstrapCoordinator] Migration daha önce tamamlanmış. Atlanıyor.');
          effectiveProgress?.call(const MigrationProgress(
            stage: MigrationStage.completed,
            stageTitle: 'İşlem tamamlandı',
            detail: 'Migration daha önce başarıyla tamamlanmış.',
            progress: 1.0,
          ));
          return const BootstrapCoordinatorResult(
            isSuccess: true,
            state: CoreNextMigrationState.completed,
            isSkipped: true,
          );
        }
      }

      // 2. Kalıcı olarak bloklanmış durum (Fail-Closed)
      if (currentState == CoreNextMigrationState.failedBlocked && !forceRetry) {
        effectiveProgress?.call(const MigrationProgress(
          stage: MigrationStage.failed,
          stageTitle: 'İşlem tamamlandı veya hata oluştu',
          detail: 'Önceki migration denemesinde kritik blokaj oluştu. Manuel operatör müdahalesi gerekiyor.',
          progress: 0.0,
        ));
        return const BootstrapCoordinatorResult(
          isSuccess: false,
          state: CoreNextMigrationState.failedBlocked,
          errorMessage: 'Önceki migration denemesinde kritik blokaj oluştu. Manuel operatör müdahalesi gerekiyor.',
        );
      }

      // 3. Yarım kalmış / çökme sonrası kurtarma kontrolü
      if (currentState == CoreNextMigrationState.backupInProgress ||
          currentState == CoreNextMigrationState.migrationInProgress ||
          currentState == CoreNextMigrationState.verificationInProgress) {
        debugPrint('[CoreNextBootstrapCoordinator] ⚠️ Önceki oturumda yarım kalmış işlem tespit edildi (${currentState.value}). Temiz yeniden deneme hazırlanıyor.');
        await _setPersistentState(CoreNextMigrationState.failedRecoverable, error: 'Önceki oturum işlem ortasında sonlandı.');
      }

      // 3.0. Migration Runner Önkoşul Kontrolü (Fail-Closed — Stage 10.12.19)
      if (_migrationRunner == null) {
        const errMsg = 'MigrationRunner enjekte edilmedi. Koordinasyon durduruldu.';
        debugPrint('[CoreNextBootstrapCoordinator] ⛔ $errMsg');
        final persistentState = await getPersistentState();
        return BootstrapCoordinatorResult(
          isSuccess: false,
          state: persistentState,
          isSkipped: true,
          errorMessage: errMsg,
        );
      }

      // 3.1. Kullanıcı Onayı veya Otomatik Geçiş Değerlendirmesi
      MigrationConsentDecision decision = MigrationConsentDecision.approved;
      if (!isAutonomous) {
        if (effectiveConsentRequester == null) {
          const errMsg = 'Kullanıcı onay isteyici (consent requester) tanımlanmamış. Güvenlik gereği fail-closed duruldu.';
          debugPrint('[CoreNextBootstrapCoordinator] ⛔ $errMsg');
          final persistentState = await getPersistentState();
          return BootstrapCoordinatorResult(
            isSuccess: false,
            state: persistentState,
            isSkipped: true,
            errorMessage: errMsg,
          );
        }

        try {
          decision = await effectiveConsentRequester();
        } catch (e) {
          final errMsg = 'Kullanıcı onay isteyici çağrısı sırasında hata oluştu: $e. Güvenlik gereği migration durduruldu.';
          debugPrint('[CoreNextBootstrapCoordinator] ⛔ $errMsg');
          return BootstrapCoordinatorResult(
            isSuccess: false,
            state: CoreNextMigrationState.notStarted,
            isSkipped: true,
            errorMessage: errMsg,
          );
        }

        if (decision != MigrationConsentDecision.approved) {
          debugPrint('[CoreNextBootstrapCoordinator] ⏸️ Kullanıcı geçişi erteledi ("Şimdi Değil"). Migration başlatılmadı.');
          return const BootstrapCoordinatorResult(
            isSuccess: true,
            state: CoreNextMigrationState.notStarted,
            isSkipped: true,
            errorMessage: 'Kullanıcı geçişi erteledi.',
          );
        }
      } else {
        debugPrint('[CoreNextBootstrapCoordinator] ⚡ Otomatik mod aktif: Müşteriye hiçbir işlem yaptırılmadan geçiş otomatik yürütülüyor.');
      }

      final int migrationStartTimestamp = DateTime.now().millisecondsSinceEpoch;

      // 4. Kaynak Veritabanı Doğrulaması (Kaynak veritabanı doğrulanıyor)
      effectiveProgress?.call(const MigrationProgress(
        stage: MigrationStage.sourceVerifying,
        stageTitle: 'Kaynak veritabanı doğrulanıyor',
        detail: 'Kaynak veritabanı (serenut_pos.db) SQLite bütünlük kontrolleri yapılıyor...',
        progress: 0.20,
      ));

      final legacyDb = _customLegacyDb ??
          await (_dbManager?.getDatabase() ?? DatabaseManager.instance.getDatabase());

      final legacyIntegrity = await legacyDb.rawQuery('PRAGMA integrity_check;');
      if (legacyIntegrity.isEmpty || legacyIntegrity.first.values.first != 'ok') {
        const errMsg = 'Kaynak veritabanı (serenut_pos.db) SQLite bütünlük testini geçemedi. Migration durduruldu.';
        await _setPersistentState(CoreNextMigrationState.failedBlocked, error: errMsg);
        effectiveProgress?.call(const MigrationProgress(
          stage: MigrationStage.failed,
          stageTitle: 'İşlem tamamlandı veya hata oluştu',
          detail: errMsg,
          progress: 0.0,
        ));
        return BootstrapCoordinatorResult(
          isSuccess: false,
          state: CoreNextMigrationState.failedBlocked,
          errorMessage: errMsg,
          errorReference: _generateErrorReference(errMsg),
        );
      }

      // 5. WAL Checkpoint ve Doğrulanmış Atomik Yedekleme (Yedek hazırlanıyor)
      effectiveProgress?.call(const MigrationProgress(
        stage: MigrationStage.backupPreparing,
        stageTitle: 'Yedek hazırlanıyor',
        detail: 'Aktif veritabanı yedeği alınıyor ve WAL checkpoint doğrulanıyor...',
        progress: 0.35,
      ));

      await _setPersistentState(CoreNextMigrationState.backupInProgress);
      DatabaseManager.isWriteLocked = true;

      String? verifiedBackupPath;
      try {
        // WAL Flush
        try {
          await legacyDb.execute('PRAGMA wal_checkpoint(TRUNCATE);');
        } catch (_) {
          // Bellek içi veya platform fallback
        }

        final String backupDirectoryPath;
        if (_customBackupDirectory != null) {
          backupDirectoryPath = _customBackupDirectory!;
        } else {
          final docs = await getApplicationDocumentsDirectory();
          backupDirectoryPath = p.join(docs.path, 'SerenutBackups');
        }

        final backupDir = Directory(backupDirectoryPath);
        if (!await backupDir.exists()) {
          await backupDir.create(recursive: true);
        }

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final backupFileName = 'serenut_pos_migration_backup_$timestamp.db';
        final backupFilePath = p.join(backupDirectoryPath, backupFileName);

        // A) Atomik VACUUM INTO veya güvenli dosya kopyası
        bool vacuumSucceeded = false;
        try {
          await legacyDb.execute('VACUUM INTO ?', [backupFilePath]);
          vacuumSucceeded = true;
        } catch (_) {
          // VACUUM INTO desteklenmiyorsa disk fallback
        }

        if (!vacuumSucceeded) {
          final legacyPath = _customLegacyFilePath ??
              DatabaseManager.overrideDatabasePath ??
              await DatabaseManager.instance.getLegacyDatabasePath();
          final srcFile = File(legacyPath);
          if (await srcFile.exists()) {
            await srcFile.copy(backupFilePath);
            final wal = File('$legacyPath-wal');
            if (await wal.exists()) await wal.copy('$backupFilePath-wal');
            final shm = File('$legacyPath-shm');
            if (await shm.exists()) await shm.copy('$backupFilePath-shm');
          } else {
            throw const BackupVerificationException('Aktif kaynak veritabanı dosyası bulunamadı.');
          }
        }

        // B) Yedeğin Açılabilirliği ve Bütünlük Doğrulaması (PRAGMA integrity_check)
        final backupFile = File(backupFilePath);
        if (!await backupFile.exists()) {
          throw const BackupVerificationException('Yedek dosyası fiziksel olarak oluşturulamadı.');
        }

        final verifyDb = await openDatabase(backupFilePath,
            readOnly: true, singleInstance: false);
        try {
          final backupIntegrity = await verifyDb.rawQuery('PRAGMA integrity_check;');
          if (backupIntegrity.isEmpty || backupIntegrity.first.values.first != 'ok') {
            throw BackupVerificationException(
                'Yedek dosyasının bütünlük doğrulaması başarısız: ${backupIntegrity.first.values.first}');
          }
        } finally {
          await verifyDb.close();
        }

        verifiedBackupPath = backupFilePath;
        final prefs = _prefs ?? await SharedPreferences.getInstance();
        await prefs.setString(prefKeyBackupPath, verifiedBackupPath);
        debugPrint('[CoreNextBootstrapCoordinator] ✅ Yedekleme ve PRAGMA doğrulaması başarılı: $verifiedBackupPath');
      } catch (e) {
        DatabaseManager.isWriteLocked = false;
        final errMsg = 'Yedekleme ve doğrulama aşamasında hata: $e';
        await _setPersistentState(CoreNextMigrationState.failedRecoverable, error: errMsg);
        effectiveProgress?.call(MigrationProgress(
          stage: MigrationStage.failed,
          stageTitle: 'İşlem tamamlandı veya hata oluştu',
          detail: errMsg,
          progress: 0.0,
        ));
        return BootstrapCoordinatorResult(
          isSuccess: false,
          state: CoreNextMigrationState.failedRecoverable,
          errorMessage: errMsg,
          errorReference: _generateErrorReference(errMsg),
        );
      }

      // 6. Hedef Core Next Veritabanı ve Migration İşletimi (Veriler aktarılıyor)
      await _setPersistentState(CoreNextMigrationState.migrationInProgress);
      final targetDb = await _getTargetDatabase();

      effectiveProgress?.call(const MigrationProgress(
        stage: MigrationStage.dataMigrating,
        stageTitle: 'Veriler aktarılıyor',
        detail: 'Katalog, müşteri hesapları ve satış kayıtları aktarılıyor...',
        progress: 0.50,
      ));

      dynamic report;
      if (_migrationRunner != null) {
        try {
          report = await (_migrationRunner as dynamic)(
            legacyDb: legacyDb,
            targetDb: targetDb,
            legacyFilePath: verifiedBackupPath,
            fullScope: true,
            onProgress: (String subStage, double pct, String? detail) {
              effectiveProgress?.call(MigrationProgress(
                stage: MigrationStage.dataMigrating,
                stageTitle: 'Veriler aktarılıyor',
                detail: detail ?? subStage,
                progress: pct,
              ));
            },
          );
        } on NoSuchMethodError {
          report = await _migrationRunner!(
            legacyDb: legacyDb,
            targetDb: targetDb,
            legacyFilePath: verifiedBackupPath,
            fullScope: true,
          );
        }
      } else {
        throw const MigrationExecutionException('MigrationRunner enjekte edilmedi.');
      }

      final bool isSuccess = (report is bool)
          ? report
          : (report?.isSuccess == true);

      if (!isSuccess) {
        DatabaseManager.isWriteLocked = false;
        final errMsg = 'Migration motoru aktarım hatası: ${report?.errorMessage ?? 'Başarısız'}';
        await _setPersistentState(CoreNextMigrationState.failedRecoverable, error: errMsg);
        effectiveProgress?.call(MigrationProgress(
          stage: MigrationStage.failed,
          stageTitle: 'İşlem tamamlandı veya hata oluştu',
          detail: errMsg,
          progress: 0.0,
        ));
        return BootstrapCoordinatorResult(
          isSuccess: false,
          state: CoreNextMigrationState.failedRecoverable,
          backupPath: verifiedBackupPath,
          migrationReport: report,
          errorMessage: errMsg,
          errorReference: _generateErrorReference(errMsg),
        );
      }

      // 6.1. Canlı Catch-Up Senkronizasyonu (Stage 10.12.45 Entegrasyonu)
      if (effectiveCatchUpRunner != null) {
        effectiveProgress?.call(const MigrationProgress(
          stage: MigrationStage.reconciliation,
          stageTitle: 'Canlı veriler eşitleniyor ve mutabakat yapılıyor',
          detail: 'İlk aktarım sırasında veya sonrasında oluşan yeni hareketler yakalanıyor...',
          progress: 0.82,
        ));

        final catchUpPassed = await effectiveCatchUpRunner(
          legacyDb: legacyDb,
          targetDb: targetDb,
          legacyDbPath: verifiedBackupPath,
          cutoffTimestamp: migrationStartTimestamp,
        );

        if (!catchUpPassed) {
          throw const ReconciliationException(
            'Canlı işlem catch-up ve mutabakat doğrulaması başarısız. Cutover engellendi.',
          );
        }
      }

      // 7. Post-Migration Veri Mutabakatı (Finans ve stok mutabakatı yapılıyor)
      effectiveProgress?.call(const MigrationProgress(
        stage: MigrationStage.reconciliation,
        stageTitle: 'Finans ve stok mutabakatı yapılıyor',
        detail: 'Stok miktarları ve müşteri bakiyeleri kuruş duyarlılığında karşılaştırılıyor...',
        progress: 0.85,
      ));

      await _setPersistentState(CoreNextMigrationState.verificationInProgress);

      // A) Ürün Sayısı ve Stok Miktarı
      final legacyProdRows = await legacyDb.rawQuery('SELECT COUNT(*) as cnt FROM products;');
      final legacyProdCount = (legacyProdRows.first['cnt'] as num?)?.toInt() ?? 0;
      final coreProdRows = await targetDb.rawQuery('SELECT COUNT(*) as cnt FROM products;');
      final coreProdCount = (coreProdRows.first['cnt'] as num?)?.toInt() ?? 0;
      if (coreProdCount < legacyProdCount) {
        throw ReconciliationException('Ürün mutabakat sapması: Hedef ($coreProdCount) < Kaynak ($legacyProdCount)');
      }

      final legacyProdCols = await _getTableColumns(legacyDb, 'products');
      final double expectedStockTotal;
      if (legacyProdCols.contains('stock_quantity')) {
        final res = await legacyDb.rawQuery('SELECT COALESCE(SUM(stock_quantity), 0) as total FROM products;');
        expectedStockTotal = (res.first['total'] as num?)?.toDouble() ?? 0.0;
      } else if (legacyProdCols.contains('quantity')) {
        final res = await legacyDb.rawQuery('SELECT COALESCE(SUM(quantity), 0) as total FROM products;');
        expectedStockTotal = (res.first['total'] as num?)?.toDouble() ?? 0.0;
      } else {
        expectedStockTotal = 0.0;
      }
      final coreStockRows = await targetDb.rawQuery('SELECT COALESCE(SUM(stock_quantity), 0) as total FROM products;');
      final actualStockTotal = (coreStockRows.first['total'] as num?)?.toDouble() ?? 0.0;
      if ((actualStockTotal - expectedStockTotal).abs() > 0.001) {
        throw ReconciliationException('Stok miktar mutabakat sapması: Hedef ($actualStockTotal) != Kaynak ($expectedStockTotal)');
      }

      // Detaylı ürün bazlı stok sapma kontrolü (Toplam eşit olsa dahi birebir ürün sapmasını yakalama)
      final legacyProds = await legacyDb.rawQuery(
        'SELECT id, ${legacyProdCols.contains('stock_quantity') ? 'stock_quantity' : 'quantity'} as qty FROM products;'
      );
      final coreProds = await targetDb.rawQuery('SELECT id, stock_quantity FROM products;');
      final coreStockMap = {
        for (var r in coreProds) r['id'] as String: (r['stock_quantity'] as num?)?.toDouble() ?? 0.0
      };
      for (final lp in legacyProds) {
        final id = lp['id'] as String;
        final expectedQty = (lp['qty'] as num?)?.toDouble() ?? 0.0;
        final actualQty = coreStockMap[id];
        if (actualQty == null || (actualQty - expectedQty).abs() > 0.001) {
          throw ReconciliationException(
            'Ürün bazlı stok sapması: Ürün $id için Hedef ($actualQty) != Kaynak ($expectedQty)',
          );
        }
      }

      // B) Müşteri Sayısı ve Bakiye Toplamı
      final legacyCustRows = await legacyDb.rawQuery('SELECT COUNT(*) as cnt FROM customers;');
      final legacyCustCount = (legacyCustRows.first['cnt'] as num?)?.toInt() ?? 0;
      final coreCustRows = await targetDb.rawQuery('SELECT COUNT(*) as cnt FROM customers;');
      final coreCustCount = (coreCustRows.first['cnt'] as num?)?.toInt() ?? 0;
      if (coreCustCount < legacyCustCount) {
        throw ReconciliationException('Müşteri mutabakat sapması: Hedef ($coreCustCount) < Kaynak ($legacyCustCount)');
      }

      final legacyCustCols = await _getTableColumns(legacyDb, 'customers');
      final int expectedCustBalCents;
      if (legacyCustCols.contains('balance')) {
        final res = await legacyDb.rawQuery('SELECT COALESCE(SUM(balance), 0.0) as total FROM customers;');
        expectedCustBalCents = (((res.first['total'] as num?)?.toDouble() ?? 0.0) * 100).round();
      } else if (legacyCustCols.contains('balance_minor')) {
        final res = await legacyDb.rawQuery('SELECT COALESCE(SUM(balance_minor), 0) as total FROM customers;');
        expectedCustBalCents = (res.first['total'] as num?)?.toInt() ?? 0;
      } else {
        expectedCustBalCents = 0;
      }
      final coreCustBalRows = await targetDb.rawQuery('SELECT COALESCE(SUM(balance_cents), 0) as total FROM customers;');
      final actualCustBalCents = (coreCustBalRows.first['total'] as num?)?.toInt() ?? 0;
      if (actualCustBalCents != expectedCustBalCents) {
        throw ReconciliationException('Müşteri bakiye mutabakat sapması: Hedef ($actualCustBalCents kuruş) != Kaynak ($expectedCustBalCents kuruş)');
      }

      // Detaylı müşteri bazlı bakiye sapma kontrolü (Toplam eşit olsa dahi hesap sapmasını yakalama)
      final legacyCusts = await legacyDb.rawQuery(
        'SELECT id, ${legacyCustCols.contains('balance') ? 'balance' : 'balance_minor'} as bal FROM customers;'
      );
      final coreCusts = await targetDb.rawQuery('SELECT id, balance_cents FROM customers;');
      final coreCustMap = {
        for (var r in coreCusts) r['id'] as String: (r['balance_cents'] as num?)?.toInt() ?? 0
      };
      for (final lc in legacyCusts) {
        final rawId = (lc['id'] as String?)?.trim() ?? '';
        final effectiveId = rawId.isEmpty ? 'customer-pesin-default' : rawId;
        final expectedBal = legacyCustCols.contains('balance')
            ? (((lc['bal'] as num?)?.toDouble() ?? 0.0) * 100).round()
            : ((lc['bal'] as num?)?.toInt() ?? 0);
        final actualBal = coreCustMap[effectiveId];
        if (actualBal == null || actualBal != expectedBal) {
          throw ReconciliationException(
            'Müşteri bazlı bakiye sapması: Müşteri $effectiveId için Hedef ($actualBal kuruş) != Kaynak ($expectedBal kuruş)',
          );
        }
      }

      // C) Satış Sayısı ve Tutar Toplamı
      final legacySaleRows = await legacyDb.rawQuery('SELECT COUNT(*) as cnt FROM sales;');
      final legacySaleCount = (legacySaleRows.first['cnt'] as num?)?.toInt() ?? 0;
      final coreSaleRows = await targetDb.rawQuery('SELECT COUNT(*) as cnt FROM sales;');
      final coreSaleCount = (coreSaleRows.first['cnt'] as num?)?.toInt() ?? 0;
      if (coreSaleCount != legacySaleCount) {
        throw ReconciliationException('Satış adet mutabakat sapması: Hedef ($coreSaleCount) != Kaynak ($legacySaleCount)');
      }

      final legacyCols = await _getTableColumns(legacyDb, 'sales');
      final int expectedTotalCents;
      if (legacyCols.contains('total_amount_minor')) {
        final res = await legacyDb.rawQuery('SELECT COALESCE(SUM(total_amount_minor), 0) as total FROM sales;');
        expectedTotalCents = (res.first['total'] as num?)?.toInt() ?? 0;
      } else {
        final res = await legacyDb.rawQuery('SELECT COALESCE(SUM(total_amount), 0.0) as total FROM sales;');
        expectedTotalCents = (((res.first['total'] as num?)?.toDouble() ?? 0.0) * 100).round();
      }

      final coreTotalRows = await targetDb.rawQuery('SELECT COALESCE(SUM(total_cents), 0) as total FROM sales;');
      final actualTotalCents = (coreTotalRows.first['total'] as num?)?.toInt() ?? 0;
      if (actualTotalCents != expectedTotalCents) {
        throw ReconciliationException('Satış tutar mutabakat sapması: Hedef ($actualTotalCents kuruş) != Kaynak ($expectedTotalCents kuruş)');
      }

      // D) Ödeme Kalemleri Tutarlılığı (sale_payments toplamı satış toplamına eşit olmalıdır)
      final targetTables = await targetDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='sale_payments'");
      if (targetTables.isNotEmpty) {
        final corePayRows = await targetDb.rawQuery('SELECT COALESCE(SUM(amount_cents), 0) as total FROM sale_payments;');
        final actualPayCents = (corePayRows.first['total'] as num?)?.toInt() ?? 0;
        if (actualPayCents != expectedTotalCents) {
          throw ReconciliationException('Ödeme tutar mutabakat sapması: Hedef ödemeler ($actualPayCents kuruş) != Satış toplamı ($expectedTotalCents kuruş)');
        }
      }

      // 8. Hedef SQLite PRAGMA Bütünlüğü (Son bütünlük kontrolleri yapılıyor)
      effectiveProgress?.call(const MigrationProgress(
        stage: MigrationStage.integrityChecking,
        stageTitle: 'Son bütünlük kontrolleri yapılıyor',
        detail: 'Hedef veritabanı PRAGMA ve yabancı anahtar kontrolleri tamamlanıyor...',
        progress: 0.95,
      ));

      final coreIntegrity = await targetDb.rawQuery('PRAGMA integrity_check;');
      if (coreIntegrity.isEmpty || coreIntegrity.first.values.first != 'ok') {
        throw ReconciliationException('Hedef veritabanı PRAGMA integrity_check başarısız: ${coreIntegrity.first.values.first}');
      }
      final coreFk = await targetDb.rawQuery('PRAGMA foreign_key_check;');
      if (coreFk.isNotEmpty) {
        throw ReconciliationException('Hedef veritabanında ${coreFk.length} adet yabancı anahtar ihlali tespit edildi.');
      }



      // 9. Kalıcı Başarı Durumunu Onayla (İşlem tamamlandı)
      await _setPersistentState(CoreNextMigrationState.completed);
      DatabaseManager.isWriteLocked = false;

      effectiveProgress?.call(const MigrationProgress(
        stage: MigrationStage.completed,
        stageTitle: 'İşlem tamamlandı',
        detail: 'Core Next veritabanı başarıyla hazırlandı ve yönlendirildi.',
        progress: 1.0,
      ));

      debugPrint('[CoreNextBootstrapCoordinator] 🎉 Migration ve mutabakat başarıyla tamamlandı. Durum: completed');
      return BootstrapCoordinatorResult(
        isSuccess: true,
        state: CoreNextMigrationState.completed,
        backupPath: verifiedBackupPath,
        migrationReport: report,
      );
    } catch (e, st) {
      DatabaseManager.isWriteLocked = false;
      final rawError = e.toString();
      final refCode = _generateErrorReference(rawError);

      effectiveProgress?.call(MigrationProgress(
        stage: MigrationStage.failed,
        stageTitle: 'İşlem tamamlandı veya hata oluştu',
        detail: rawError,
        progress: 0.0,
      ));

      try {
        unawaited(TelemetryService().logError(
          e,
          st,
          context: 'core_next_bootstrap_coordinator_failure',
          correlationId: refCode,
        ));
      } catch (_) {
        // Telemetry hatası akışı bozmaz
      }

      final CoreNextMigrationState failedState = (e is BackupVerificationException || e is ReconciliationException)
          ? CoreNextMigrationState.failedRecoverable
          : CoreNextMigrationState.failedRecoverable;

      await _setPersistentState(failedState, error: rawError);

      return BootstrapCoordinatorResult(
        isSuccess: false,
        state: failedState,
        errorMessage: rawError,
        errorReference: refCode,
      );
    } finally {
      _isExecutionRunning = false;
    }
  }

  /// Güvenli Rollback Denetimi ve Geri Dönüş
  /// 
  /// Eğer hedef veritabanında migration kesme anından (cutoff) sonra yeni bir satış
  /// veya finansal hareket oluşmuşsa, [assertSafeRollback] fırlatılır ve sessiz geri dönüş
  /// KESİNLİKLE ENGELLENİR.
  /// 
  /// Eğer yeni satış yoksa, hedefteki `legacy_migration_completed` bayrağı `'rolled_back'`
  /// yapılır, migration state `failedRecoverable` olarak güncellenir ve legacy fallback'e
  /// güvenli izin verilir.
  Future<BootstrapCoordinatorResult> rollbackToLegacy({
    int? initialCutoffTimestamp,
    CoreNextRollbackGuard? customRollbackGuard,
    Database? customLegacyDb,
    CutoffMaintenanceLock? cutoffLock,
    String? tenantId,
    SafeRollbackRunner? customRollbackRunner,
  }) async {
    final targetDb = await _getTargetDatabase();
    final cutoff = initialCutoffTimestamp ?? 0;
    final guard = customRollbackGuard ?? _rollbackGuard;
    final prefs = _prefs ?? await SharedPreferences.getInstance();

    try {
      if (guard != null) {
        await guard(
          targetDb: targetDb,
          initialMigrationCutoffTimestamp: cutoff,
        );
      }

      final runner = customRollbackRunner ?? PilotCutoverGate.safeRollbackRunner;
      Database? legacyDb = customLegacyDb ?? _customLegacyDb;
      if (legacyDb == null) {
        try {
          legacyDb = await (_dbManager?.getDatabase() ?? DatabaseManager.instance.getDatabase());
        } catch (_) {
          // Test ortamı veya legacy DB henüz açılmamışsa null kalabilir
        }
      }

      if (runner != null && legacyDb != null) {
        final effectiveTenantId = tenantId ?? prefs.getString('tenant_id') ?? 'nutopia';
        final effectiveCutoff = cutoffLock ?? DatabaseManager.cutoffMaintenanceLock;

        final safeResult = await runner(
          legacyDb: legacyDb,
          coreDb: targetDb,
          prefs: prefs,
          tenantId: effectiveTenantId,
          cutoffLock: effectiveCutoff,
        );

        if (!safeResult.isSuccess) {
          final errMsg = safeResult.errorMessage ?? 'Güvenli geri dönüş motoru başarısız oldu.';
          await _setPersistentState(
            CoreNextMigrationState.failedBlocked,
            error: errMsg,
          );
          return BootstrapCoordinatorResult(
            isSuccess: false,
            state: CoreNextMigrationState.failedBlocked,
            errorMessage: errMsg,
            errorReference: _generateErrorReference(errMsg),
          );
        }
      }

      // Güvenli rollback: hedefteki `legacy_migration_completed` bayrağı `'rolled_back'` yapılır
      final targetTables = (await targetDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='app_settings'",
      )).toList();
      if (targetTables.isNotEmpty) {
        await targetDb.insert(
          'app_settings',
          {
            'key': 'legacy_migration_completed',
            'value': 'rolled_back',
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await _setPersistentState(
        CoreNextMigrationState.failedRecoverable,
        error: 'Güvenli rollback uygulandı: Legacy veritabanına dönüldü.',
      );

      return const BootstrapCoordinatorResult(
        isSuccess: true,
        state: CoreNextMigrationState.failedRecoverable,
        errorMessage: 'Güvenli rollback başarıyla uygulandı.',
      );
    } catch (e) {
      final rawError = e.toString();
      await _setPersistentState(
        CoreNextMigrationState.failedBlocked,
        error: rawError,
      );
      return BootstrapCoordinatorResult(
        isSuccess: false,
        state: CoreNextMigrationState.failedBlocked,
        errorMessage: rawError,
        errorReference: _generateErrorReference(rawError),
      );
    }
  }
}

/// Core Next Migration Runner Provider
final coreNextMigrationRunnerProvider = Provider<CoreNextMigrationRunner?>((ref) {
  return ({
    required Database legacyDb,
    required Database targetDb,
    String? legacyFilePath,
    bool fullScope = false,
  }) async {
    final coreAppDb = CoreAppDatabase(targetDb);
    final engine = MigrationBridgeEngine(coreAppDb);
    return await engine.migrateFromLegacy(
      legacyDb,
      legacyFilePath: legacyFilePath,
      fullScope: fullScope,
    );
  };
});

/// Core Next Rollback Guard Provider (Varsayılan: null)
final coreNextRollbackGuardProvider = Provider<CoreNextRollbackGuard?>((ref) => null);

/// Core Next Catch-Up Runner Provider (Varsayılan: null — Stage 10.12.45)
final coreNextCatchUpRunnerProvider = Provider<CoreNextCatchUpRunner?>((ref) => null);

/// Core Next Migration Reaktif İlerleme Durumu Provider'ı
final coreNextMigrationProgressProvider = StateProvider<MigrationProgress?>((ref) => null);

/// Core Next Kullanıcı Onay İsteyici Provider'ı (Varsayılan: null — Güvenli kontrol)
final coreNextConsentRequesterProvider = Provider<MigrationConsentRequester?>((ref) => null);

/// Riverpod Sağlayıcısı
final coreNextBootstrapCoordinatorProvider = Provider<CoreNextBootstrapCoordinator>((ref) {
  final runner = ref.watch(coreNextMigrationRunnerProvider);
  final rollbackGuard = ref.watch(coreNextRollbackGuardProvider);
  final catchUpRunner = ref.watch(coreNextCatchUpRunnerProvider);
  final consentRequester = ref.watch(coreNextConsentRequesterProvider);
  return CoreNextBootstrapCoordinator(
    dbManager: DatabaseManager.instance,
    migrationRunner: runner,
    rollbackGuard: rollbackGuard,
    catchUpRunner: catchUpRunner,
    consentRequester: consentRequester,
    onProgress: (progress) {
      ref.read(coreNextMigrationProgressProvider.notifier).state = progress;
    },
  );
});

/// Aktif kullanıcı onay talebini tutan model (Stage 10.12.19)
class MigrationConsentRequest {
  final Completer<MigrationConsentDecision> completer;
  final String? sourceDbPath;
  final String? targetDbPath;
  final int? estimatedProductCount;
  final int? estimatedCustomerCount;

  const MigrationConsentRequest({
    required this.completer,
    this.sourceDbPath,
    this.targetDbPath,
    this.estimatedProductCount,
    this.estimatedCustomerCount,
  });
}

/// UI üzerinde bekleyen onay talebini dinleyen StateProvider (Stage 10.12.19)
final coreNextConsentRequestProvider = StateProvider<MigrationConsentRequest?>((ref) => null);

/// UI tabanlı kontrollü onay isteyici üreteci (Stage 10.12.19)
///
/// Riverpod Ref veya ProviderContainer kabul eder.
/// Aynı oturumda çift diyalog açılmasını engeller, onay talebini
/// [coreNextConsentRequestProvider] üzerinden UI overlay'ine iletir
/// ve kullanıcının kararını bekler.
MigrationConsentRequester createUiConsentRequester(
  dynamic refOrContainer, {
  String? sourceDbPath,
  String? targetDbPath,
  int? estimatedProductCount,
  int? estimatedCustomerCount,
}) {
  bool promptedInSession = false;
  return () async {
    if (promptedInSession) {
      debugPrint('[ConsentRequester] Bu oturumda zaten onay istendi. Çift diyalog engellendi.');
      return MigrationConsentDecision.postponed;
    }
    promptedInSession = true;

    final completer = Completer<MigrationConsentDecision>();
    final request = MigrationConsentRequest(
      completer: completer,
      sourceDbPath: sourceDbPath,
      targetDbPath: targetDbPath,
      estimatedProductCount: estimatedProductCount,
      estimatedCustomerCount: estimatedCustomerCount,
    );

    try {
      if (refOrContainer is ProviderContainer) {
        refOrContainer.read(coreNextConsentRequestProvider.notifier).state = request;
      } else {
        refOrContainer.read(coreNextConsentRequestProvider.notifier).state = request;
      }

      final decision = await completer.future;
      return decision;
    } catch (e) {
      debugPrint('[ConsentRequester] Onay bekleme sırasında hata: $e');
      return MigrationConsentDecision.postponed;
    } finally {
      if (refOrContainer is ProviderContainer) {
        refOrContainer.read(coreNextConsentRequestProvider.notifier).state = null;
      } else {
        refOrContainer.read(coreNextConsentRequestProvider.notifier).state = null;
      }
    }
  };
}

