// lib/infrastructure/services/update_v2/update_trigger_manager.dart
// Serenut Platform — Unified Update Trigger Manager

import 'package:flutter/foundation.dart';
import 'package:serenutos/infrastructure/services/update_v2/update_coordinator.dart';

enum TriggerSource { startup, timer, manual, adminPush }

class UpdateTriggerManager {
  final UpdateCoordinator _coordinator;

  UpdateTriggerManager({
    required UpdateCoordinator coordinator,
  }) : _coordinator = coordinator;

  /// Entry point to trigger update checks from different parts of the application.
  Future<CoordinatorCheckResult> triggerUpdateCheck({
    required TriggerSource source,
    required String rawManifestContent,
    required String signature,
    required bool isSalesCheckoutActive,
    String? publicKeyOverride,
  }) async {
    final correlationId = 'upd-trig-${source.name}-${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('[UpdateTriggerManager] Triggered update check via ${source.name} (Correlation: $correlationId)');
    
    return await _coordinator.runUpdateWorkflow(
      correlationId: correlationId,
      rawManifestContent: rawManifestContent,
      signature: signature,
      isSalesCheckoutActive: isSalesCheckoutActive,
      publicKeyOverride: publicKeyOverride,
    );
  }
}
