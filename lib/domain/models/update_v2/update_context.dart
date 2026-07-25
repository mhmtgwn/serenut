// lib/domain/models/update_v2/update_context.dart
// Serenut Platform — Client Update State Context

import 'package:serenutos/domain/models/update_v2/release_manifest.dart';
import 'package:serenutos/domain/models/update_v2/update_telemetry_event.dart';
import 'package:serenutos/domain/services/update_v2/policy_engine.dart';
import 'package:serenutos/infrastructure/services/update_v2/update_trigger_manager.dart';

enum UpdateState {
  idle,
  checking,
  precheck,
  downloading,
  verifying,
  draining,
  handshake,
  postInstall,
  healthCheck,
  completed,
  failed,
  rollback
}

extension UpdateStateExtension on UpdateState {
  String toSchemaString() {
    return name.toUpperCase();
  }
}

class UpdateContext {
  final String correlationId;
  final TriggerSource triggerSource;
  final DateTime startedAt;

  UpdateState currentState;
  ReleaseManifest? manifest;
  PolicyEvaluationResult? policyResult;
  int retryCount;
  String? errorCode;
  String? errorMessage;

  UpdateContext({
    required this.correlationId,
    required this.triggerSource,
    this.currentState = UpdateState.idle,
    this.manifest,
    this.policyResult,
    this.retryCount = 0,
    this.errorCode,
    this.errorMessage,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  UpdateContext copy() {
    return UpdateContext(
      correlationId: correlationId,
      triggerSource: triggerSource,
      currentState: currentState,
      manifest: manifest,
      policyResult: policyResult,
      retryCount: retryCount,
      errorCode: errorCode,
      errorMessage: errorMessage,
      startedAt: startedAt,
    );
  }
}
