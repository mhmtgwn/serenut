// lib/infrastructure/migration/safe_rollback_coordinator.dart
// SERENUT OS — STAGE 10.12.80
// GÜVENLİ VE ATOMİK GERİ DÖNÜŞ SÖZLEŞMESİ (SAFE ROLLBACK CONTRACT)

import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'cutoff_maintenance_lock.dart';

/// Geri dönüş sonuç modeli
class SafeRollbackResult {
  final bool isSuccess;
  final String status;
  final String? errorMessage;
  final dynamic migrationReport;
  final dynamic reconciliationReport;
  final int durationMs;

  const SafeRollbackResult({
    required this.isSuccess,
    required this.status,
    this.errorMessage,
    this.migrationReport,
    this.reconciliationReport,
    required this.durationMs,
  });
}

/// Geri dönüş sabitleri
class SafeRollbackConstants {
  static const String prefKeyRollbackState = 'core_next_rollback_state';
  static const String prefKeyRollbackStartedAt = 'core_next_rollback_started_at';
  static const String prefKeyRollbackCompletedAt = 'core_next_rollback_completed_at';
  static const String prefKeyRollbackLastError = 'core_next_rollback_last_error';
  static const String prefKeyRollbackReport = 'core_next_rollback_report';
}

/// Geri dönüş çalıştırıcı fonksiyon türü
typedef SafeRollbackRunner = Future<SafeRollbackResult> Function({
  required Database legacyDb,
  required dynamic coreDb,
  required SharedPreferences prefs,
  required String tenantId,
  CutoffMaintenanceLock? cutoffLock,
  Duration drainTimeout,
});
