// lib/infrastructure/sync_v4/sync_v4_dtos.dart
// Serenut OS — Strongly-typed DTOs for Sync V4 API Boundaries

import 'dart:convert';

int _parseSyncCursor(Object? value, {required int fallback}) {
  if (value == null) return fallback;
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
  }
  throw const FormatException('Sync cursor must be an integer.');
}

/// Acknowledged push mutation result from server
class SyncPushAckResult {
  final String mutationId;
  final int revision;

  const SyncPushAckResult({
    required this.mutationId,
    required this.revision,
  });

  factory SyncPushAckResult.fromJson(Map<String, dynamic> json) {
    return SyncPushAckResult(
      mutationId: json['mutation_id']?.toString() ?? '',
      revision: (json['revision'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Conflict response when local revision is superseded on server
class SyncPushConflict {
  final String mutationId;
  final String entityType;
  final String entityId;
  final int serverRevision;

  const SyncPushConflict({
    required this.mutationId,
    required this.entityType,
    required this.entityId,
    required this.serverRevision,
  });

  factory SyncPushConflict.fromJson(Map<String, dynamic> json) {
    return SyncPushConflict(
      mutationId: json['mutation_id']?.toString() ?? '',
      entityType: json['entity_type']?.toString() ?? '',
      entityId: json['entity_id']?.toString() ?? '',
      serverRevision: (json['server_revision'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toDbRow() {
    return {
      'mutation_id': mutationId,
      'entity_type': entityType,
      'entity_id': entityId,
      'server_revision': serverRevision,
      'detected_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

/// Rejected mutation entry from push response
class SyncPushRejected {
  final String? mutationId;
  final String error;

  const SyncPushRejected({
    this.mutationId,
    required this.error,
  });

  factory SyncPushRejected.fromJson(Map<String, dynamic> json) {
    return SyncPushRejected(
      mutationId: json['mutation_id']?.toString(),
      error: json['error']?.toString() ?? 'rejected',
    );
  }
}

/// Strongly typed container for /api/v4/sync/push response
class SyncPushResponseDto {
  final List<SyncPushAckResult> results;
  final List<SyncPushConflict> conflicts;
  final List<SyncPushRejected> rejected;

  const SyncPushResponseDto({
    this.results = const [],
    this.conflicts = const [],
    this.rejected = const [],
  });

  factory SyncPushResponseDto.fromJson(Map<String, dynamic> json) {
    final resList = (json['results'] as List?)
            ?.whereType<Map>()
            .map(
                (r) => SyncPushAckResult.fromJson(Map<String, dynamic>.from(r)))
            .toList() ??
        const [];
    final confList = (json['conflicts'] as List?)
            ?.whereType<Map>()
            .map((r) => SyncPushConflict.fromJson(Map<String, dynamic>.from(r)))
            .toList() ??
        const [];
    final rejList = (json['rejected'] as List?)
            ?.whereType<Map>()
            .map((r) => SyncPushRejected.fromJson(Map<String, dynamic>.from(r)))
            .toList() ??
        const [];
    return SyncPushResponseDto(
      results: resList,
      conflicts: confList,
      rejected: rejList,
    );
  }
}

/// Single change event received from /api/v4/sync/pull
class SyncPullChangeDto {
  final int revision;
  final String mutationId;
  final String deviceId;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payload;
  final String createdAt;

  const SyncPullChangeDto({
    required this.revision,
    required this.mutationId,
    required this.deviceId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.createdAt,
  });

  factory SyncPullChangeDto.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    Map<String, dynamic> parsedPayload;
    if (rawPayload is Map) {
      parsedPayload = Map<String, dynamic>.from(rawPayload);
    } else if (rawPayload is String) {
      try {
        parsedPayload =
            Map<String, dynamic>.from(jsonDecode(rawPayload) as Map);
      } catch (_) {
        parsedPayload = const {};
      }
    } else {
      parsedPayload = const {};
    }

    return SyncPullChangeDto(
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      mutationId: json['mutation_id']?.toString() ?? '',
      deviceId: json['device_id']?.toString() ?? '',
      entityType: json['entity_type']?.toString() ?? '',
      entityId: json['entity_id']?.toString() ?? '',
      operation: json['operation']?.toString() ?? 'UPSERT',
      payload: parsedPayload,
      createdAt: json['created_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'revision': revision,
      'mutation_id': mutationId,
      'device_id': deviceId,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation,
      'payload': payload,
      'created_at': createdAt,
    };
  }
}

/// Strongly typed container for /api/v4/sync/pull response
class SyncPullResponseDto {
  final List<SyncPullChangeDto> changes;
  final int nextCursor;

  const SyncPullResponseDto({
    this.changes = const [],
    this.nextCursor = 0,
  });

  factory SyncPullResponseDto.fromJson(Map<String, dynamic> json,
      [int fallbackCursor = 0]) {
    final changesList = (json['changes'] as List?)
            ?.whereType<Map>()
            .map(
                (c) => SyncPullChangeDto.fromJson(Map<String, dynamic>.from(c)))
            .toList() ??
        const [];
    final next = _parseSyncCursor(
      json['next_cursor'],
      fallback: fallbackCursor,
    );
    return SyncPullResponseDto(
      changes: changesList,
      nextCursor: next,
    );
  }
}

/// Canonical tenant snapshot returned to a device without a local cursor.
class SyncBootstrapResponseDto {
  final List<SyncPullChangeDto> changes;
  final int nextCursor;

  const SyncBootstrapResponseDto({
    this.changes = const [],
    this.nextCursor = 0,
  });

  factory SyncBootstrapResponseDto.fromJson(Map<String, dynamic> json) {
    final rawChanges = json['changes'];
    if (rawChanges != null && rawChanges is! List) {
      throw const FormatException('Sync bootstrap changes must be a list.');
    }
    final changes = (rawChanges as List? ?? const []).map((value) {
      if (value is! Map) {
        throw const FormatException('Sync bootstrap change must be an object.');
      }
      return SyncPullChangeDto.fromJson(Map<String, dynamic>.from(value));
    }).toList(growable: false);
    return SyncBootstrapResponseDto(
      changes: changes,
      nextCursor: _parseSyncCursor(json['next_cursor'], fallback: 0),
    );
  }
}
