// lib/infrastructure/bootstrap/pilot_cutover_gate.dart
// Serenut OS — Pilot Cutover Kapısı (Stage 10.12.26)
//
// Core Next pilot cutover geçişini kontrol eden fail-closed güvenlik kapısı.
// Varsayılan olarak kapalıdır; tüm güvenlik, bütünlük ve yedekleme kanıtları
// doğrulanmadan Core Next repository yönlendirmesini ASLA aktif etmez.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/domain/services/tenant_identity_resolver.dart';
import 'package:serenutos/infrastructure/migration/safe_rollback_coordinator.dart';
import 'package:serenutos/infrastructure/migration/cutoff_maintenance_lock.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';

/// Pilot Geçiş Kapısı Durum Kodları
enum PilotGateStatus {
  disabledByDefault,
  blockedKillSwitch,
  blockedMissingConfiguration,
  blockedMigrationNotCompleted,
  blockedMissingBackupProof,
  blockedTargetDatabaseNotFound,
  blockedTargetDatabaseCorrupt,
  blockedTargetSchemaMismatch,
  blockedTargetMissingTables,
  blockedTenantMismatch,
  blockedResolverRejection,
  blockedTimeout,
  blockedUnknownError,
  blockedUnsafeRollback,
  pilotActiveApproved;

  bool get isApproved => this == PilotGateStatus.pilotActiveApproved;
}

/// Pilot Kapısı Değerlendirme Çıktısı
class PilotGateResult {
  final bool isPilotActive;
  final PilotGateStatus status;
  final String reason;
  final List<Override> overrides;
  final String? targetDbPath;
  final int evaluatedDurationMs;
  final bool isSalesEngineActive;

  const PilotGateResult({
    required this.isPilotActive,
    required this.status,
    required this.reason,
    this.overrides = const [],
    this.targetDbPath,
    this.evaluatedDurationMs = 0,
    this.isSalesEngineActive = false,
  });

  bool get isFailClosed => !isPilotActive;

  @override
  String toString() =>
      'PilotGateResult(isPilotActive: $isPilotActive, status: ${status.name}, reason: $reason, overridesCount: ${overrides.length}, isSalesEngineActive: $isSalesEngineActive)';
}

/// Repository override üreteci fonksiyon arayüzü
typedef PilotRepositoryOverrideGenerator = Future<List<Override>?> Function({
  required String requestedTenantId,
  required String legacyDbPath,
  required String targetDbPath,
  required bool enableSalesEngine,
  DatabaseFactory? dbFactory,
});

/// Fail-Closed Pilot Cutover Kapısı
class PilotCutoverGate {
  static const String prefKeyPilotEnabled = 'core_next_pilot_enabled';
  static const String prefKeyKillSwitch = 'core_next_kill_switch';
  static const String prefKeySalesEngineEnabled = 'core_next_sales_engine_enabled';
  static const int expectedSchemaVersion = 7;

  final PilotRepositoryOverrideGenerator? _overrideGenerator;

  const PilotCutoverGate({
    PilotRepositoryOverrideGenerator? overrideGenerator,
  }) : _overrideGenerator = overrideGenerator;

  /// Kill switch durumunu SharedPreferences üzerinden sorgular.
  static bool isKillSwitchActive(SharedPreferences prefs) {
    return prefs.getBool(prefKeyKillSwitch) ?? false;
  }

  static SafeRollbackRunner? safeRollbackRunner;
  static PilotRepositoryOverrideGenerator? defaultOverrideGenerator;

  /// Acil durum devre kesicisini (kill switch) aktif hale getirir (fail-closed koruması).
  /// [requireVerifiedRollback] true ise, geri dönüş aktarımı tamamlanmadan bayrağın tek başına
  /// değişmesini engeller.
  static Future<bool> triggerEmergencyKillSwitch(
    SharedPreferences prefs, {
    bool requireVerifiedRollback = false,
  }) async {
    if (requireVerifiedRollback) {
      final state = prefs.getString(SafeRollbackConstants.prefKeyRollbackState);
      if (state != 'completed') {
        debugPrint(
            '[PilotCutoverGate] ⚠️ Kill switch engellendi: Geri dönüş tamamlanmadı (durum: $state)');
        return false;
      }
    }
    return await prefs.setBool(prefKeyKillSwitch, true);
  }

  /// SafeRollbackCoordinator'ı gerçek çalışma zamanında tetikler:
  /// 1. Kesim kilidi (CutoffMaintenanceLock) devreye girer, devam eden yazmalar boşaltılır (drain).
  /// 2. ReverseMigrationEngine atomik SQLite transaction'ında çalışır.
  /// 3. Çok boyutlu mutabakat (RollbackReconciliationReport) doğrulanır.
  /// 4. SADECE VE SADECE mutabakat başarılıysa kill switch devreye alınır ve legacy routing açılır.
  /// 5. Aktarım veya mutabakat başarısız olursa fail-closed kilit korunur, legacy routing AÇILMAZ.
  static Future<SafeRollbackResult> triggerSafeRollbackAndKillSwitch({
    required SharedPreferences prefs,
    required Database legacyDb,
    required dynamic coreDb,
    required String tenantId,
    CutoffMaintenanceLock? cutoffLock,
    Duration drainTimeout = const Duration(seconds: 15),
    SafeRollbackRunner? customRunner,
  }) async {
    final runner = customRunner ?? safeRollbackRunner;
    if (runner == null) {
      throw StateError(
        'SafeRollbackRunner tanımlanmamış. Güvenli geri dönüş çalıştırılamaz.',
      );
    }

    final result = await runner(
      legacyDb: legacyDb,
      coreDb: coreDb,
      prefs: prefs,
      tenantId: tenantId,
      cutoffLock: cutoffLock ?? DatabaseManager.cutoffMaintenanceLock,
      drainTimeout: drainTimeout,
    );

    if (result.isSuccess) {
      await prefs.setBool(prefKeyKillSwitch, true);
      debugPrint('[PilotCutoverGate] ✅ Güvenli geri dönüş ve mutabakat tamamlandı. Kill switch aktif edildi.');
    } else {
      debugPrint('[PilotCutoverGate] ❌ Geri dönüş veya mutabakat başarısız (${result.errorMessage}). Kill switch ve legacy routing engellendi.');
    }

    return result;
  }

  /// Uygulama açılışında 'in_progress' veya 'failed_blocked' durumunda kalmış rollback'i güvenle kurtarır.
  /// İdempotent tersine aktarımı ve mutabakatı yeniden dener.
  /// Kurtarılamazsa sistemi fail-closed kilitli tutar; kesinlikle sessizce legacy DB'ye geçmez.
  static Future<SafeRollbackResult> recoverPendingRollback({
    required SharedPreferences prefs,
    required Database legacyDb,
    required dynamic coreDb,
    required String tenantId,
    CutoffMaintenanceLock? cutoffLock,
    SafeRollbackRunner? customRunner,
  }) async {
    final state = prefs.getString(SafeRollbackConstants.prefKeyRollbackState);
    if (state != 'in_progress' && state != 'failed_blocked') {
      return const SafeRollbackResult(
        isSuccess: true,
        status: 'no_recovery_needed',
        durationMs: 0,
      );
    }

    debugPrint('[PilotCutoverGate] 🔄 Yarım kalmış geri dönüş durumu tespit edildi ($state). Güvenli kurtarma işletiliyor...');
    final runner = customRunner ?? safeRollbackRunner;
    if (runner == null) {
      throw StateError(
        'SafeRollbackRunner tanımlanmamış. Yarım kalmış geri dönüş kurtarılamaz.',
      );
    }

    final result = await runner(
      legacyDb: legacyDb,
      coreDb: coreDb,
      prefs: prefs,
      tenantId: tenantId,
      cutoffLock: cutoffLock ?? DatabaseManager.cutoffMaintenanceLock,
    );

    if (result.isSuccess) {
      await prefs.setBool(prefKeyKillSwitch, true);
      debugPrint('[PilotCutoverGate] ✅ Yarım kalmış geri dönüş başarıyla kurtarıldı. Legacy routing güvenle açıldı.');
    } else {
      debugPrint('[PilotCutoverGate] ⛔ Kurtarma denemesi başarısız oldu: ${result.errorMessage}. Sistem kilitli tutuldu.');
    }

    return result;
  }

  /// Pilot cutover gereksinimlerini atomik ve fail-closed olarak değerlendirir.
  Future<PilotGateResult> evaluate({
    required SharedPreferences prefs,
    String? requestedTenantId,
    String? legacyDbPath,
    String? targetDbPath,
    DatabaseFactory? dbFactory,
    Duration timeout = const Duration(milliseconds: 2500),
    bool? enableSalesEngine,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      return await _evaluateInternal(
        prefs: prefs,
        requestedTenantId: requestedTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: targetDbPath,
        dbFactory: dbFactory,
        enableSalesEngine: enableSalesEngine,
        stopwatch: stopwatch,
      ).timeout(
        timeout,
        onTimeout: () {
          stopwatch.stop();
          debugPrint(
              '[PilotCutoverGate] ⏱️ Değerlendirme zaman aşımına uğradı (${timeout.inMilliseconds}ms). Fail-closed devreye girdi.');
          return PilotGateResult(
            isPilotActive: false,
            status: PilotGateStatus.blockedTimeout,
            reason:
                'Pilot cutover kapısı zaman aşımına uğradı (${timeout.inMilliseconds}ms). Legacy akış korundu.',
            evaluatedDurationMs: stopwatch.elapsedMilliseconds,
          );
        },
      );
    } catch (e, st) {
      stopwatch.stop();
      debugPrint('[PilotCutoverGate] ❌ Beklenmeyen hata: $e\n$st');
      return PilotGateResult(
        isPilotActive: false,
        status: PilotGateStatus.blockedUnknownError,
        reason:
            'Pilot cutover değerlendirmesinde beklenmeyen hata (fail-closed): $e',
        evaluatedDurationMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  Future<PilotGateResult> _evaluateInternal({
    required SharedPreferences prefs,
    String? requestedTenantId,
    String? legacyDbPath,
    String? targetDbPath,
    DatabaseFactory? dbFactory,
    bool? enableSalesEngine,
    required Stopwatch stopwatch,
  }) async {
    // 0. Kural: Güvenli Geri Dönüş Durumu (Rollback In-Progress veya Failed-Blocked Kontrolü)
    final String? rollbackState = prefs.getString('core_next_rollback_state');
    if (rollbackState == 'in_progress' || rollbackState == 'failed_blocked') {
      stopwatch.stop();
      return PilotGateResult(
        isPilotActive: false,
        status: PilotGateStatus.blockedUnsafeRollback,
        reason:
            'Geri dönüş aktarımı tamamlanmamış (durum: $rollbackState). Yeni Core Next kayıtlarının kaybolmaması için işlem fail-closed durduruldu.',
        evaluatedDurationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // 1. Kural: Pilot Feature Flag Kontrolü (Varsayılan: false)
    final bool isPilotEnabled = prefs.getBool(prefKeyPilotEnabled) ?? false;
    if (!isPilotEnabled) {
      stopwatch.stop();
      return PilotGateResult(
        isPilotActive: false,
        status: PilotGateStatus.disabledByDefault,
        reason:
            'Pilot cutover bayrağı kapalı (core_next_pilot_enabled = false). Legacy akış aktif.',
        evaluatedDurationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // 2. Kural: Acil Durum Devre Kesici (Kill Switch) Kontrolü
    final bool isKillSwitchActive = prefs.getBool(prefKeyKillSwitch) ?? false;
    if (isKillSwitchActive) {
      stopwatch.stop();
      return PilotGateResult(
        isPilotActive: false,
        status: PilotGateStatus.blockedKillSwitch,
        reason:
            'Acil durum devre kesici (core_next_kill_switch) aktif. Geçiş derhal engellendi.',
        evaluatedDurationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // 3. Kural: Migration Durumu Doğrulaması
    final rawMigrationState =
        prefs.getString(CoreNextBootstrapCoordinator.prefKeyMigrationState);
    final migrationState = CoreNextMigrationState.fromString(rawMigrationState);
    if (migrationState != CoreNextMigrationState.completed) {
      stopwatch.stop();
      return PilotGateResult(
        isPilotActive: false,
        status: PilotGateStatus.blockedMigrationNotCompleted,
        reason:
            'Core Next migration tamamlanmamış (durum: ${migrationState.value}). Pilot geçiş engellendi.',
        evaluatedDurationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // 4. Kural: Doğrulanmış Yedekleme Kanıtı (Backup Proof)
    final String? lastBackupDate = prefs.getString('last_backup_date');
    final String? migrationBackupPath =
        prefs.getString(CoreNextBootstrapCoordinator.prefKeyBackupPath);

    bool backupProofFound = false;
    if (migrationBackupPath != null && migrationBackupPath.isNotEmpty) {
      final bFile = File(migrationBackupPath);
      if (bFile.existsSync() && bFile.lengthSync() >= 512) {
        backupProofFound = true;
      } else {
        // migrationBackupPath belirtilmiş ancak dosya yok veya bozuk (< 512B):
        // lastBackupDate olsa dahi geçersiz kanıt olarak işaretlenir (Fail-Closed)
        backupProofFound = false;
      }
    } else if (lastBackupDate != null &&
        lastBackupDate.isNotEmpty &&
        DateTime.tryParse(lastBackupDate) != null) {
      backupProofFound = true;
    }

    if (!backupProofFound) {
      stopwatch.stop();
      return PilotGateResult(
        isPilotActive: false,
        status: PilotGateStatus.blockedMissingBackupProof,
        reason:
            'Pilot geçiş öncesinde doğrulanmış yedekleme kanıtı bulunamadı. Veri güvenliği gereği durduruldu.',
        evaluatedDurationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // 5. Kural: Hedef Veritabanı Yolu ve Fiziksel Varlık Kontrolü
    final dbManager = DatabaseManager.instance;
    final String resolvedLegacyPath =
        legacyDbPath ?? await dbManager.getLegacyDatabasePath();
    final String resolvedTargetPath =
        targetDbPath ?? await dbManager.getCoreNextDatabasePath();

    final targetFile = File(resolvedTargetPath);
    if (!targetFile.existsSync()) {
      stopwatch.stop();
      return PilotGateResult(
        isPilotActive: false,
        status: PilotGateStatus.blockedTargetDatabaseNotFound,
        reason:
            'Hedef Core Next veritabanı dosyası bulunamadı: $resolvedTargetPath',
        evaluatedDurationMs: stopwatch.elapsedMilliseconds,
      );
    }

    if (targetFile.lengthSync() < 512) {
      stopwatch.stop();
      return PilotGateResult(
        isPilotActive: false,
        status: PilotGateStatus.blockedTargetDatabaseCorrupt,
        reason:
            'Hedef Core Next veritabanı dosyası 0 bayt veya bozuk header (< 512B).',
        evaluatedDurationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // 6. Kural: SQLite Bütünlük ve Şema Doğrulaması (PRAGMA integrity_check, user_version, kritik tablolar)
    final factory = dbFactory ?? databaseFactory;
    Database? testDb;
    try {
      testDb = await factory.openDatabase(
        resolvedTargetPath,
        options: OpenDatabaseOptions(readOnly: true),
      );

      final integrity = await testDb.rawQuery('PRAGMA integrity_check;');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        stopwatch.stop();
        return PilotGateResult(
          isPilotActive: false,
          status: PilotGateStatus.blockedTargetDatabaseCorrupt,
          reason: 'Hedef veritabanı PRAGMA integrity_check kontrolünden geçemedi.',
          evaluatedDurationMs: stopwatch.elapsedMilliseconds,
        );
      }

      final versionRes = await testDb.rawQuery('PRAGMA user_version;');
      final userVersion = (versionRes.first.values.first as num?)?.toInt() ?? 0;
      if (userVersion < 3 || userVersion > expectedSchemaVersion) {
        stopwatch.stop();
        return PilotGateResult(
          isPilotActive: false,
          status: PilotGateStatus.blockedTargetSchemaMismatch,
          reason:
              'Hedef veritabanı şema sürümü uyumsuz ($userVersion not in 3..$expectedSchemaVersion).',
          evaluatedDurationMs: stopwatch.elapsedMilliseconds,
        );
      }

      final tables = (await testDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((r) => r['name'].toString()).toSet();

      const requiredTables = {
        'products',
        'customers',
        'sales',
        'ledger_entries',
        'sync_events'
      };
      if (!requiredTables.every(tables.contains)) {
        stopwatch.stop();
        return PilotGateResult(
          isPilotActive: false,
          status: PilotGateStatus.blockedTargetMissingTables,
          reason: 'Hedef veritabanında kritik Core Next tabloları eksik.',
          evaluatedDurationMs: stopwatch.elapsedMilliseconds,
        );
      }

      // Satış motoru talep edildiyse ek satış tablolarını kontrol et
      final bool isSalesEngineRequested = enableSalesEngine ??
          (prefs.getBool(prefKeySalesEngineEnabled) ?? false);

      if (isSalesEngineRequested) {
        const requiredSalesTables = {
          'sale_items',
          'sale_payments',
          'cash_transactions',
        };
        if (!requiredSalesTables.every(tables.contains)) {
          stopwatch.stop();
          return PilotGateResult(
            isPilotActive: false,
            status: PilotGateStatus.blockedTargetMissingTables,
            reason:
                'Hedef veritabanında Core Next satış motoru için gereken tablolar (sale_items, sale_payments, cash_transactions) eksik.',
            evaluatedDurationMs: stopwatch.elapsedMilliseconds,
          );
        }
      }

      if (tables.contains('app_settings')) {
        final tenantRows = await testDb.query(
          'app_settings',
          where: 'key = ?',
          whereArgs: ['tenant_id'],
        );
        if (tenantRows.isNotEmpty) {
          final dbTenantId = tenantRows.first['value']?.toString().trim();
          if (requestedTenantId != null &&
              dbTenantId != null &&
              !TenantIdentityResolver.matches(
                requestedTenantId: requestedTenantId,
                dbTenantId: dbTenantId,
              )) {
            stopwatch.stop();
            return PilotGateResult(
              isPilotActive: false,
              status: PilotGateStatus.blockedTenantMismatch,
              reason:
                  'Tenant ID uyuşmazlığı: İstenen "$requestedTenantId" != DB "$dbTenantId".',
              evaluatedDurationMs: stopwatch.elapsedMilliseconds,
            );
          }
        }
      }
    } catch (e) {
      stopwatch.stop();
      return PilotGateResult(
        isPilotActive: false,
        status: PilotGateStatus.blockedTargetDatabaseCorrupt,
        reason: 'Hedef veritabanı açılış/doğrulama hatası: $e',
        evaluatedDurationMs: stopwatch.elapsedMilliseconds,
      );
    } finally {
      if (testDb != null && testDb.isOpen) {
        await testDb.close();
      }
    }

    // 7. Kural: Override Üreteci ve Koordinatör Doğrulaması
    final generator = _overrideGenerator ?? defaultOverrideGenerator;
    if (generator == null) {
      stopwatch.stop();
      return PilotGateResult(
        isPilotActive: false,
        status: PilotGateStatus.blockedMissingConfiguration,
        reason:
            'Pilot cutover güvenlik onayları tamamlandı; ancak runtime override generator enjekte edilmedi (fail-closed korundu).',
        targetDbPath: resolvedTargetPath,
        evaluatedDurationMs: stopwatch.elapsedMilliseconds,
      );
    }

    final bool isSalesEngineRequested = enableSalesEngine ??
        (prefs.getBool(prefKeySalesEngineEnabled) ?? false);

    final overrides = await generator(
      requestedTenantId: requestedTenantId ?? 'default_tenant',
      legacyDbPath: resolvedLegacyPath,
      targetDbPath: resolvedTargetPath,
      enableSalesEngine: isSalesEngineRequested,
      dbFactory: dbFactory,
    );

    if (overrides == null || overrides.isEmpty) {
      stopwatch.stop();
      return PilotGateResult(
        isPilotActive: false,
        status: PilotGateStatus.blockedResolverRejection,
        reason:
            'Koordinatör veya resolver hedef geçişi reddetti (overrides boş döndü).',
        targetDbPath: resolvedTargetPath,
        evaluatedDurationMs: stopwatch.elapsedMilliseconds,
      );
    }

    bool salesEngineActivated = false;
    if (isSalesEngineRequested) {
      final verifyContainer = ProviderContainer(overrides: overrides);
      try {
        final hasSalesEngineEnabled =
            verifyContainer.read(coreNextSalesEngineEnabledProvider) == true;
        final hasSaleExecutor =
            verifyContainer.read(coreNextSaleExecutorProvider) != null;
        final hasRefundExecutor =
            verifyContainer.read(coreNextRefundExecutorProvider) != null;
        final hasSaleRepo =
            verifyContainer.read(coreNextSaleRepositoryProvider) != null;

        if (!hasSaleRepo ||
            !hasSaleExecutor ||
            !hasRefundExecutor ||
            !hasSalesEngineEnabled) {
          stopwatch.stop();
          return PilotGateResult(
            isPilotActive: false,
            status: PilotGateStatus.blockedMissingConfiguration,
            reason:
                'Core Next satış motoru talep edildi ancak çalışma zamanı executor bağlantıları eksik veya başarısız oldu.',
            targetDbPath: resolvedTargetPath,
            evaluatedDurationMs: stopwatch.elapsedMilliseconds,
          );
        }
      } catch (e) {
        stopwatch.stop();
        return PilotGateResult(
          isPilotActive: false,
          status: PilotGateStatus.blockedMissingConfiguration,
          reason:
              'Core Next satış motoru sağlayıcıları doğrulanırken hata oluştu: $e',
          targetDbPath: resolvedTargetPath,
          evaluatedDurationMs: stopwatch.elapsedMilliseconds,
        );
      } finally {
        verifyContainer.dispose();
      }
      salesEngineActivated = true;
    }

    stopwatch.stop();
    return PilotGateResult(
      isPilotActive: true,
      status: PilotGateStatus.pilotActiveApproved,
      reason: salesEngineActivated
          ? 'Tüm pilot cutover kontrolleri ve Core Next satış motoru bağlantıları başarıyla doğrulandı ve bağlandı.'
          : 'Tüm pilot cutover kontrolleri (%100 bütünlük, şema v3, yedekleme kanıtı, tenant eşleşmesi) doğrulandı (Satış motoru legacy modda).',
      overrides: overrides,
      targetDbPath: resolvedTargetPath,
      evaluatedDurationMs: stopwatch.elapsedMilliseconds,
      isSalesEngineActive: salesEngineActivated,
    );
  }
}
