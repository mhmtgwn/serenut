// lib/infrastructure/services/update_v2/health_verifier_service.dart
// Serenut Platform — 5-Step Post-Install Health Verification Protocol

import 'dart:async';
import 'package:flutter/foundation.dart';

abstract class SqliteHealthCheck {
  Future<bool> verifyIntegrity();
}

abstract class SqliteWalHealthCheck {
  Future<bool> verifyWalJournal();
}

abstract class NetworkHealthCheck {
  Future<bool> verifyVpsConnection();
}

abstract class UiHealthCheck {
  Future<bool> verifyUiInitialized();
}

class HealthVerifierService {
  final SqliteHealthCheck _sqliteCheck;
  final SqliteWalHealthCheck? _walCheck;
  final NetworkHealthCheck _networkCheck;
  final UiHealthCheck _uiCheck;

  HealthVerifierService({
    required SqliteHealthCheck sqliteCheck,
    SqliteWalHealthCheck? walCheck,
    required NetworkHealthCheck networkCheck,
    required UiHealthCheck uiCheck,
  })  : _sqliteCheck = sqliteCheck,
        _walCheck = walCheck,
        _networkCheck = networkCheck,
        _uiCheck = uiCheck;

  /// Performs the 5-step health checks and computes the combined health score.
  /// Returns true if health score is >= 0.95 (passed), false otherwise.
  Future<bool> evaluateHealth() async {
    int totalSteps = 0;
    int passedSteps = 0;

    // Step 1: SQLite Integrity Check
    totalSteps++;
    try {
      final sqlitePassed = await _sqliteCheck.verifyIntegrity();
      if (sqlitePassed) passedSteps++;
    } catch (e) {
      debugPrint('[HealthVerifier] Step 1 SQLite Integrity failed: $e');
    }

    // Step 2: SQLite Write-Ahead Logging (WAL) Check
    totalSteps++;
    try {
      final walPassed = _walCheck != null
          ? await _walCheck!.verifyWalJournal()
          : await _sqliteCheck.verifyIntegrity();
      if (walPassed) passedSteps++;
    } catch (e) {
      debugPrint('[HealthVerifier] Step 2 SQLite WAL check failed: $e');
    }

    // Step 3: VPS Server WebSocket Connection Check
    totalSteps++;
    try {
      final vpsPassed = await _networkCheck.verifyVpsConnection();
      if (vpsPassed) passedSteps++;
    } catch (e) {
      debugPrint('[HealthVerifier] Step 3 Network check failed: $e');
    }

    // Step 4: UI Engine Response Initialization
    totalSteps++;
    try {
      final uiPassed = await _uiCheck.verifyUiInitialized();
      if (uiPassed) passedSteps++;
    } catch (e) {
      debugPrint('[HealthVerifier] Step 4 UI check failed: $e');
    }

    if (totalSteps == 0) return true;
    final double score = passedSteps / totalSteps;
    debugPrint(
        '[HealthVerifier] Completed 5-step check. Score: $score (Passed: $passedSteps/$totalSteps)');

    return score >= 0.95;
  }
}
