// lib/infrastructure/services/update_v2/update_coordinator.dart
// Serenut Platform — Client Update Coordinator Orchestrator

import 'package:serenutos/domain/models/update_v2/release_manifest.dart';
import 'package:serenutos/domain/services/update_v2/policy_engine.dart';
import 'package:serenutos/infrastructure/services/update_v2/update_lock_provider.dart';
import 'package:serenutos/infrastructure/services/update_v2/manifest_parser_service.dart';

class CoordinatorCheckResult {
  final bool hasUpdate;
  final ReleaseManifest? manifest;
  final String? errorCode; // e.g. UPD-001, UPD-005
  final String? errorMessage;

  CoordinatorCheckResult({
    required this.hasUpdate,
    this.manifest,
    this.errorCode,
    this.errorMessage,
  });

  factory CoordinatorCheckResult.success(ReleaseManifest manifest) =>
      CoordinatorCheckResult(hasUpdate: true, manifest: manifest);
}

class UpdateCoordinator {
  final UpdateLockProvider _lockProvider;
  final PolicyEngine _policyEngine;
  final ManifestParserService _manifestParser;

  UpdateCoordinator({
    required UpdateLockProvider lockProvider,
    required PolicyEngine policyEngine,
    required ManifestParserService manifestParser,
  })  : _lockProvider = lockProvider,
        _policyEngine = policyEngine,
        _manifestParser = manifestParser;

  /// Runs the full update check, manifest parsing, signature checking, and policy evaluation lifecycle.
  /// Locks globally via UpdateLockProvider.
  Future<CoordinatorCheckResult> runUpdateWorkflow({
    required String correlationId,
    required String rawManifestContent,
    required String signature,
    required bool isSalesCheckoutActive,
    String? publicKeyOverride,
  }) async {
    // 1. Acquire Concurrency Lock
    final lockAcquired = await _lockProvider.acquire(correlationId);
    if (!lockAcquired) {
      return CoordinatorCheckResult(
        hasUpdate: false,
        errorCode: 'UPD-005',
        errorMessage: 'Concurrent update check already running.',
      );
    }

    try {
      // 2. Parse & Verify Manifest (Integrity & Digital Signature)
      final parseResult = await _manifestParser.parseAndVerify(
        rawManifestContent: rawManifestContent,
        signature: signature,
        publicKeyOverride: publicKeyOverride,
      );

      if (!parseResult.isValid || parseResult.manifest == null) {
        final errCode = parseResult.errorMessage != null &&
                parseResult.errorMessage!.contains('signature')
            ? 'UPD-002'
            : 'UPD-001';
        return CoordinatorCheckResult(
          hasUpdate: false,
          errorCode: errCode,
          errorMessage: parseResult.errorMessage ?? 'Manifest parse failed.',
        );
      }

      final manifest = parseResult.manifest!;

      // 3. Evaluate Policy Engine constraints (Disk, RAM, OS, Checkout Active status)
      final policyResult = await _policyEngine.evaluate(
        rules: manifest.rules,
        isSalesCheckoutActive: isSalesCheckoutActive,
      );

      if (!policyResult.isPassed) {
        return CoordinatorCheckResult(
          hasUpdate: false,
          errorCode: policyResult.errorCode ?? 'UPD-005',
          errorMessage: policyResult.reason ?? 'Policy constraints check failed.',
        );
      }

      return CoordinatorCheckResult(hasUpdate: true, manifest: manifest);
    } finally {
      // 4. Safe Lock Release
      _lockProvider.release(correlationId);
    }
  }
}
