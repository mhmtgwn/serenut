import 'dart:convert';

enum PrintDocumentKind { receipt, productLabel, orderLabel }

enum PrinterLanguage { escPos, tspl }

enum PrinterTransportKind { tcp, windowsSpooler, usb, bluetooth, embedded }

enum PrintJobState {
  created,
  queued,
  rendering,
  sending,
  delivered,
  retryWait,
  awaitingUserCheck,
  confirmed,
  rejected,
  failed,
  cancelled,
}

class PrintDesignProfile {
  final String id;
  final String name;
  final PrintDocumentKind kind;
  final int schemaVersion;
  final String rendererVersion;
  final Map<String, Object?> definition;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PrintDesignProfile({
    required this.id,
    required this.name,
    required this.kind,
    required this.schemaVersion,
    required this.rendererVersion,
    required this.definition,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'schema_version': schemaVersion,
        'renderer_version': rendererVersion,
        'definition_json': jsonEncode(definition),
        'is_default': isDefault ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory PrintDesignProfile.fromMap(Map<String, Object?> map) =>
      PrintDesignProfile(
        id: map['id']! as String,
        name: map['name']! as String,
        kind: PrintDocumentKind.values.byName(map['kind']! as String),
        schemaVersion: map['schema_version']! as int,
        rendererVersion: map['renderer_version']! as String,
        definition: Map<String, Object?>.from(
          jsonDecode(map['definition_json']! as String) as Map,
        ),
        isDefault: map['is_default'] == 1,
        createdAt: DateTime.parse(map['created_at']! as String),
        updatedAt: DateTime.parse(map['updated_at']! as String),
      );
}

class PrinterDeviceProfile {
  final String id;
  final String name;
  final PrinterLanguage language;
  final PrinterTransportKind transport;
  final Map<String, Object?> transportConfig;
  final Map<String, Object?> capabilities;
  final bool enabled;
  final DateTime? lastTestedAt;
  final bool? lastTestSucceeded;
  final String? lastTestMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PrinterDeviceProfile({
    required this.id,
    required this.name,
    required this.language,
    required this.transport,
    required this.transportConfig,
    required this.capabilities,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    this.lastTestedAt,
    this.lastTestSucceeded,
    this.lastTestMessage,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'language': language.name,
        'transport': transport.name,
        'transport_config_json': jsonEncode(transportConfig),
        'capabilities_json': jsonEncode(capabilities),
        'enabled': enabled ? 1 : 0,
        'last_tested_at': lastTestedAt?.toIso8601String(),
        'last_test_succeeded':
            lastTestSucceeded == null ? null : (lastTestSucceeded! ? 1 : 0),
        'last_test_message': lastTestMessage,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory PrinterDeviceProfile.fromMap(Map<String, Object?> map) =>
      PrinterDeviceProfile(
        id: map['id']! as String,
        name: map['name']! as String,
        language: PrinterLanguage.values.byName(map['language']! as String),
        transport:
            PrinterTransportKind.values.byName(map['transport']! as String),
        transportConfig: Map<String, Object?>.from(
          jsonDecode(map['transport_config_json']! as String) as Map,
        ),
        capabilities: Map<String, Object?>.from(
          jsonDecode(map['capabilities_json']! as String) as Map,
        ),
        enabled: map['enabled'] == 1,
        lastTestedAt: map['last_tested_at'] == null
            ? null
            : DateTime.parse(map['last_tested_at']! as String),
        lastTestSucceeded: map['last_test_succeeded'] == null
            ? null
            : map['last_test_succeeded'] == 1,
        lastTestMessage: map['last_test_message'] as String?,
        createdAt: DateTime.parse(map['created_at']! as String),
        updatedAt: DateTime.parse(map['updated_at']! as String),
      );
}

class PrinterRoute {
  final PrintDocumentKind kind;
  final String deviceId;
  final String designProfileId;
  final DateTime updatedAt;

  const PrinterRoute({
    required this.kind,
    required this.deviceId,
    required this.designProfileId,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'kind': kind.name,
        'device_id': deviceId,
        'design_profile_id': designProfileId,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory PrinterRoute.fromMap(Map<String, Object?> map) => PrinterRoute(
        kind: PrintDocumentKind.values.byName(map['kind']! as String),
        deviceId: map['device_id']! as String,
        designProfileId: map['design_profile_id']! as String,
        updatedAt: DateTime.parse(map['updated_at']! as String),
      );
}

class PrintJobRecord {
  final String id;
  final PrintDocumentKind kind;
  final String payloadJson;
  final int copies;
  final String designProfileId;
  final String designSnapshotJson;
  final String deviceId;
  final String transportSnapshotJson;
  final String capabilitySnapshotJson;
  final String rendererVersion;
  final PrintJobState state;
  final int attemptCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? nextAttemptAt;
  final String? errorCode;
  final String? errorMessage;
  final String? renderedChecksum;
  final String? deliveryObservationJson;

  const PrintJobRecord({
    required this.id,
    required this.kind,
    required this.payloadJson,
    required this.copies,
    required this.designProfileId,
    required this.designSnapshotJson,
    required this.deviceId,
    required this.transportSnapshotJson,
    required this.capabilitySnapshotJson,
    required this.rendererVersion,
    required this.state,
    required this.attemptCount,
    required this.createdAt,
    required this.updatedAt,
    this.nextAttemptAt,
    this.errorCode,
    this.errorMessage,
    this.renderedChecksum,
    this.deliveryObservationJson,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind.name,
        'payload_json': payloadJson,
        'copies': copies,
        'design_profile_id': designProfileId,
        'design_snapshot_json': designSnapshotJson,
        'device_id': deviceId,
        'transport_snapshot_json': transportSnapshotJson,
        'capability_snapshot_json': capabilitySnapshotJson,
        'renderer_version': rendererVersion,
        'state': state.name,
        'attempt_count': attemptCount,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'next_attempt_at': nextAttemptAt?.toIso8601String(),
        'error_code': errorCode,
        'error_message': errorMessage,
        'rendered_checksum': renderedChecksum,
        'delivery_observation_json': deliveryObservationJson,
      };

  factory PrintJobRecord.fromMap(Map<String, Object?> map) => PrintJobRecord(
        id: map['id']! as String,
        kind: PrintDocumentKind.values.byName(map['kind']! as String),
        payloadJson: map['payload_json']! as String,
        copies: map['copies']! as int,
        designProfileId: map['design_profile_id']! as String,
        designSnapshotJson: map['design_snapshot_json']! as String,
        deviceId: map['device_id']! as String,
        transportSnapshotJson: map['transport_snapshot_json']! as String,
        capabilitySnapshotJson: map['capability_snapshot_json']! as String,
        rendererVersion: map['renderer_version']! as String,
        state: PrintJobState.values.byName(map['state']! as String),
        attemptCount: map['attempt_count']! as int,
        createdAt: DateTime.parse(map['created_at']! as String),
        updatedAt: DateTime.parse(map['updated_at']! as String),
        nextAttemptAt: map['next_attempt_at'] == null
            ? null
            : DateTime.parse(map['next_attempt_at']! as String),
        errorCode: map['error_code'] as String?,
        errorMessage: map['error_message'] as String?,
        renderedChecksum: map['rendered_checksum'] as String?,
        deliveryObservationJson: map['delivery_observation_json'] as String?,
      );
}

class PrintRecoverySummary {
  final int safelyRequeued;
  final int awaitingUserCheck;

  const PrintRecoverySummary({
    required this.safelyRequeued,
    required this.awaitingUserCheck,
  });
}
