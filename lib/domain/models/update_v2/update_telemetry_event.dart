// lib/domain/models/update_v2/update_telemetry_event.dart
// Serenut Platform — Update Telemetry Event DTO (schemaVersion = 1)

import 'package:flutter/foundation.dart';
import 'package:serenutos/domain/models/update_v2/release_manifest.dart';

enum UpdateEventType {
  checkStarted,
  manifestVerified,
  precheckPassed,
  precheckFailed,
  downloadStarted,
  downloadCompleted,
  verificationFailed,
  drainStarted,
  bootstrapperLaunched,
  postInstallStarted,
  healthCheckPassed,
  healthCheckFailed,
  installSuccess,
  installFailed,
  rollbackExecuted,
}

extension UpdateEventTypeExtension on UpdateEventType {
  String toSchemaString() {
    switch (this) {
      case UpdateEventType.checkStarted:
        return 'CHECK_STARTED';
      case UpdateEventType.manifestVerified:
        return 'MANIFEST_VERIFIED';
      case UpdateEventType.precheckPassed:
        return 'PRECHECK_PASSED';
      case UpdateEventType.precheckFailed:
        return 'PRECHECK_FAILED';
      case UpdateEventType.downloadStarted:
        return 'DOWNLOAD_STARTED';
      case UpdateEventType.downloadCompleted:
        return 'DOWNLOAD_COMPLETED';
      case UpdateEventType.verificationFailed:
        return 'VERIFICATION_FAILED';
      case UpdateEventType.drainStarted:
        return 'DRAIN_STARTED';
      case UpdateEventType.bootstrapperLaunched:
        return 'BOOTSTRAPPER_LAUNCHED';
      case UpdateEventType.postInstallStarted:
        return 'POST_INSTALL_STARTED';
      case UpdateEventType.healthCheckPassed:
        return 'HEALTH_CHECK_PASSED';
      case UpdateEventType.healthCheckFailed:
        return 'HEALTH_CHECK_FAILED';
      case UpdateEventType.installSuccess:
        return 'INSTALL_SUCCESS';
      case UpdateEventType.installFailed:
        return 'INSTALL_FAILED';
      case UpdateEventType.rollbackExecuted:
        return 'ROLLBACK_EXECUTED';
    }
  }

  static UpdateEventType fromSchemaString(String raw) {
    switch (raw.toUpperCase()) {
      case 'CHECK_STARTED':
        return UpdateEventType.checkStarted;
      case 'MANIFEST_VERIFIED':
        return UpdateEventType.manifestVerified;
      case 'PRECHECK_PASSED':
        return UpdateEventType.precheckPassed;
      case 'PRECHECK_FAILED':
        return UpdateEventType.precheckFailed;
      case 'DOWNLOAD_STARTED':
        return UpdateEventType.downloadStarted;
      case 'DOWNLOAD_COMPLETED':
        return UpdateEventType.downloadCompleted;
      case 'VERIFICATION_FAILED':
        return UpdateEventType.verificationFailed;
      case 'DRAIN_STARTED':
        return UpdateEventType.drainStarted;
      case 'BOOTSTRAPPER_LAUNCHED':
        return UpdateEventType.bootstrapperLaunched;
      case 'POST_INSTALL_STARTED':
        return UpdateEventType.postInstallStarted;
      case 'HEALTH_CHECK_PASSED':
        return UpdateEventType.healthCheckPassed;
      case 'HEALTH_CHECK_FAILED':
        return UpdateEventType.healthCheckFailed;
      case 'INSTALL_SUCCESS':
        return UpdateEventType.installSuccess;
      case 'INSTALL_FAILED':
        return UpdateEventType.installFailed;
      case 'ROLLBACK_EXECUTED':
        return UpdateEventType.rollbackExecuted;
      default:
        throw InvalidManifestException('Unknown UpdateEventType: $raw');
    }
  }
}

@immutable
class UpdateTelemetryEvent {
  static const int currentSupportedSchemaVersion = 1;

  final int schemaVersion;
  final String correlationId;
  final String deviceId;
  final String? companyId;
  final String fromVersion;
  final String toVersion;
  final UpdateEventType eventType;
  final String? errorCode;
  final String? errorMessage;
  final Map<String, dynamic>? systemSpecs;
  final String timestamp;

  const UpdateTelemetryEvent({
    required this.schemaVersion,
    required this.correlationId,
    required this.deviceId,
    this.companyId,
    required this.fromVersion,
    required this.toVersion,
    required this.eventType,
    this.errorCode,
    this.errorMessage,
    this.systemSpecs,
    required this.timestamp,
  });

  factory UpdateTelemetryEvent.fromJson(Map<String, dynamic> json) {
    final schemaVer = json['schemaVersion'] as int?;
    if (schemaVer == null) {
      throw InvalidManifestException(
          'Missing schemaVersion in telemetry event.');
    }
    if (schemaVer > currentSupportedSchemaVersion) {
      throw UnsupportedSchemaException(
        receivedVersion: schemaVer,
        supportedVersion: currentSupportedSchemaVersion,
      );
    }

    return UpdateTelemetryEvent(
      schemaVersion: schemaVer,
      correlationId: json['correlationId'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      companyId: json['companyId'] as String?,
      fromVersion: json['fromVersion'] as String? ?? '',
      toVersion: json['toVersion'] as String? ?? '',
      eventType: UpdateEventTypeExtension.fromSchemaString(
          json['eventType'] as String? ?? ''),
      errorCode: json['errorCode'] as String?,
      errorMessage: json['errorMessage'] as String?,
      systemSpecs: json['systemSpecs'] as Map<String, dynamic>?,
      timestamp:
          json['timestamp'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'correlationId': correlationId,
        'deviceId': deviceId,
        'companyId': companyId,
        'fromVersion': fromVersion,
        'toVersion': toVersion,
        'eventType': eventType.toSchemaString(),
        'errorCode': errorCode,
        'errorMessage': errorMessage,
        'systemSpecs': systemSpecs,
        'timestamp': timestamp,
      };
}
