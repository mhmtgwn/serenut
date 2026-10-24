// core_next/client_core/lib/domain/models/sync_dtos.dart

import 'dart:convert';

/// Sunucu `/api/v4/sync/push` yanıtında onaylanan mutasyon sonucu
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

/// Sunucu revizyonu yerel revizyondan ileri olduğunda dönen çakışma kaydı
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
}

/// Sunucu tarafından reddedilen mutasyon kaydı
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

/// `/api/v4/sync/push` yanıt konteyneri
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
    final rawResults = (json['results'] as List?)
            ?.whereType<Map>()
            .map((r) => SyncPushAckResult.fromJson(Map<String, dynamic>.from(r)))
            .toList() ??
        const [];
    final rawConflicts = (json['conflicts'] as List?)
            ?.whereType<Map>()
            .map((c) => SyncPushConflict.fromJson(Map<String, dynamic>.from(c)))
            .toList() ??
        const [];
    final rawRejected = (json['rejected'] as List?)
            ?.whereType<Map>()
            .map((rej) => SyncPushRejected.fromJson(Map<String, dynamic>.from(rej)))
            .toList() ??
        const [];

    return SyncPushResponseDto(
      results: rawResults,
      conflicts: rawConflicts,
      rejected: rawRejected,
    );
  }
}

/// `/api/v4/sync/pull` değişikliği
class SyncPullChange {
  final int revision;
  final String mutationId;
  final String deviceId;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payload;
  final String createdAt;

  const SyncPullChange({
    required this.revision,
    required this.mutationId,
    required this.deviceId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.createdAt,
  });

  factory SyncPullChange.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    Map<String, dynamic> parsedPayload;
    if (rawPayload is Map) {
      parsedPayload = Map<String, dynamic>.from(rawPayload);
    } else if (rawPayload is String) {
      try {
        parsedPayload = Map<String, dynamic>.from(jsonDecode(rawPayload) as Map);
      } catch (_) {
        parsedPayload = const {};
      }
    } else {
      parsedPayload = const {};
    }

    return SyncPullChange(
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
}

/// `/api/v4/sync/pull` yanıt konteyneri
class SyncPullResponseDto {
  final List<SyncPullChange> changes;
  final int nextCursor;

  const SyncPullResponseDto({
    this.changes = const [],
    this.nextCursor = 0,
  });

  factory SyncPullResponseDto.fromJson(Map<String, dynamic> json) {
    final rawChanges = (json['changes'] as List?)
            ?.whereType<Map>()
            .map((c) => SyncPullChange.fromJson(Map<String, dynamic>.from(c)))
            .toList() ??
        const [];
    final next = (json['next_cursor'] as num?)?.toInt() ?? 0;

    return SyncPullResponseDto(
      changes: rawChanges,
      nextCursor: next,
    );
  }
}

/// `/api/v4/sync/bootstrap` anlık görüntü yanıtı
class SyncBootstrapResponseDto {
  final List<SyncPullChange> changes;
  final int nextCursor;

  const SyncBootstrapResponseDto({
    this.changes = const [],
    this.nextCursor = 0,
  });

  factory SyncBootstrapResponseDto.fromJson(Map<String, dynamic> json) {
    final rawChanges = (json['changes'] as List?)
            ?.whereType<Map>()
            .map((c) => SyncPullChange.fromJson(Map<String, dynamic>.from(c)))
            .toList() ??
        const [];
    final next = (json['next_cursor'] as num?)?.toInt() ?? 0;

    return SyncBootstrapResponseDto(
      changes: rawChanges,
      nextCursor: next,
    );
  }
}

// ── Senkronizasyon Hata Tipleri ──────────────────────────────────────────────

abstract class SyncException implements Exception {
  final String message;
  final int? statusCode;

  const SyncException(this.message, [this.statusCode]);

  @override
  String toString() => '$runtimeType: $message (status: $statusCode)';
}

class SyncProtocolUpgradeRequiredException extends SyncException {
  final int requiredVersion;
  const SyncProtocolUpgradeRequiredException({
    required this.requiredVersion,
    String message = 'Senkronizasyon protokolü güncel değil (HTTP 426).',
  }) : super(message, 426);
}

class SyncUnauthorizedException extends SyncException {
  const SyncUnauthorizedException([String message = 'Yetkisiz erişim (HTTP 401).'])
      : super(message, 401);
}

class SyncForbiddenException extends SyncException {
  const SyncForbiddenException([String message = 'Erişim reddedildi / Geçersiz cihaz (HTTP 403).'])
      : super(message, 403);
}

class SyncBadRequestException extends SyncException {
  const SyncBadRequestException(String message) : super(message, 400);
}

class SyncConflictException extends SyncException {
  final String? errorCode;
  const SyncConflictException(String message, {this.errorCode}) : super(message, 409);
}

class SyncServerException extends SyncException {
  const SyncServerException(String message, [int statusCode = 500])
      : super(message, statusCode);
}

class SyncTimeoutException extends SyncException {
  const SyncTimeoutException([String message = 'Sunucu bağlantısı zaman aşımına uğradı.'])
      : super(message, null);
}

class SyncNetworkException extends SyncException {
  const SyncNetworkException(String message) : super(message, null);
}

class SyncFormatException extends SyncException {
  const SyncFormatException(String message) : super(message, null);
}
