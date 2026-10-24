// core_next/client_core/lib/domain/models/sync_mutation.dart

import 'dart:convert';

/// Çevrimdışı senkronizasyon kuyruğundaki (sync_events) tekil mutasyon modeli.
/// 
/// Sunucu Sync V4 / Protocol 6 sözleşmesiyle tam uyumlu alanları ve nedensel
/// sıralama (causal_sequence) metadata'sını taşır.
class SyncMutation {
  final String eventId;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payload;
  final int baseRevision;
  final int clientTimestamp;
  final String syncState;
  final int attempts;
  final String? lastError;
  final String? groupId;
  final int causalSequence;

  const SyncMutation({
    required this.eventId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    this.baseRevision = 0,
    required this.clientTimestamp,
    this.syncState = 'PENDING',
    this.attempts = 0,
    this.lastError,
    this.groupId,
    this.causalSequence = 0,
  });

  /// SQLite `sync_events` tablosuna yazılacak satır haritası.
  Map<String, dynamic> toDbRow() {
    return {
      'event_id': eventId,
      'entity_type': entityType.toLowerCase(),
      'entity_id': entityId,
      'operation': operation,
      'payload_json': jsonEncode(payload),
      'base_revision': baseRevision,
      'client_timestamp': clientTimestamp,
      'sync_state': syncState,
      'attempts': attempts,
      'last_error': lastError,
      'group_id': groupId,
      'causal_sequence': causalSequence,
    };
  }

  /// SQLite `sync_events` satırından nesne üretir.
  factory SyncMutation.fromDbRow(Map<String, dynamic> row) {
    Map<String, dynamic> parsedPayload;
    final rawPayload = row['payload_json'];
    if (rawPayload is String) {
      try {
        parsedPayload = Map<String, dynamic>.from(jsonDecode(rawPayload) as Map);
      } catch (_) {
        parsedPayload = <String, dynamic>{};
      }
    } else if (rawPayload is Map) {
      parsedPayload = Map<String, dynamic>.from(rawPayload);
    } else {
      parsedPayload = <String, dynamic>{};
    }

    return SyncMutation(
      eventId: row['event_id'] as String,
      entityType: (row['entity_type'] as String).toLowerCase(),
      entityId: row['entity_id'] as String,
      operation: row['operation'] as String,
      payload: parsedPayload,
      baseRevision: (row['base_revision'] as num?)?.toInt() ?? 0,
      clientTimestamp: (row['client_timestamp'] as num).toInt(),
      syncState: row['sync_state'] as String? ?? 'PENDING',
      attempts: (row['attempts'] as num?)?.toInt() ?? 0,
      lastError: row['last_error'] as String?,
      groupId: row['group_id'] as String?,
      causalSequence: (row['causal_sequence'] as num?)?.toInt() ?? 0,
    );
  }

  /// Üretim sunucusu `/api/v4/sync/push` DTO'sunun beklediği mutasyon haritası.
  Map<String, dynamic> toServerMutationDto() {
    return {
      'mutation_id': eventId,
      'entity_type': entityType.toLowerCase(),
      'entity_id': entityId,
      'operation': operation,
      'base_revision': baseRevision,
      'payload': payload,
    };
  }
}
