// core_next/client_core/lib/infrastructure/sync/sync_v4_outbox_processor.dart

import '../../domain/models/sync_dtos.dart';
import '../../domain/models/sync_mutation.dart';
import '../database/app_database.dart';
import 'sync_v4_http_client.dart';

/// Outbox kuyruğu işleme sonucu özeti
class OutboxProcessResult {
  final int totalProcessed;
  final int syncedCount;
  final int conflictCount;
  final int rejectedCount;
  final int transientErrorCount;
  final String? fatalError;

  const OutboxProcessResult({
    this.totalProcessed = 0,
    this.syncedCount = 0,
    this.conflictCount = 0,
    this.rejectedCount = 0,
    this.transientErrorCount = 0,
    this.fatalError,
  });

  bool get hasErrors => (rejectedCount + transientErrorCount > 0) || fatalError != null;
}

/// Kalıcı doğrulama ve sunucu kural hataları (yeniden denenmesi anlamsız olanlar)
const Set<String> nonRetryableServerErrors = {
  'invalid_mutation',
  'invalid_sale',
  'invalid_sale_item',
  'sale_total_mismatch',
  'invalid_credit_payment',
  'invalid_full_payment',
  'invalid_customer',
  'immutable_sale',
  'immutable_refund',
  'stale_before_operational_reset',
  'invalid_device_activation',
  'sale_payload_conflict',
  'mutation_payload_conflict',
  'refund_actor_required',
};

/// Çevrimdışı `sync_events` kuyruğunu tüketip HTTP istemcisine ileten işlemci.
class SyncV4OutboxProcessor {
  /// Bir mutasyonun geçici hata alarak en fazla kaç kez denenebileceği üst sınırı.
  /// Bu sınırı aşan mutasyonlar REJECTED (Dead Letter) yapılarak kuyruğun kilitlenmesi engellenir.
  static const int maxTransientAttempts = 25;

  final CoreAppDatabase db;
  final SyncV4HttpClient httpClient;

  SyncV4OutboxProcessor({
    required this.db,
    required this.httpClient,
  });

  /// Kuyrukta bekleyen veya geçici hata almış mutasyonları sıralı tüketir.
  Future<OutboxProcessResult> processOutbox({int batchSize = 100}) async {
    // 1. Bekleyen mutasyonları nedensel sırayla (causal_sequence) ve zamana göre oku
    final rows = await db.query(
      'sync_events',
      where: "sync_state IN ('PENDING', 'TRANSIENT_ERROR')",
      orderBy: '''
        CASE WHEN group_id IS NOT NULL 
             THEN (SELECT MIN(s2.client_timestamp) FROM sync_events s2 WHERE s2.group_id = sync_events.group_id) 
             ELSE client_timestamp 
        END ASC,
        COALESCE(group_id, event_id) ASC,
        causal_sequence ASC,
        client_timestamp ASC
      ''',
      limit: batchSize,
    );

    if (rows.isEmpty) {
      return const OutboxProcessResult();
    }

    final mutations = rows.map((r) => SyncMutation.fromDbRow(r)).toList();

    try {
      // 2. HTTP İstemcisi ile sunucuya push et
      final response = await httpClient.push(mutations);

      // 3. Yanıtı her mutasyon için bağımsız olarak tek bir veritabanı transaction'ında işle
      return await db.transaction<OutboxProcessResult>((txn) async {
        int synced = 0;
        int conflicts = 0;
        int rejected = 0;
        int transient = 0;

        final ackedIds = response.results.map((r) => r.mutationId).toSet();
        final ackMap = {for (var r in response.results) r.mutationId: r.revision};
        final conflictMap = {for (var c in response.conflicts) c.mutationId: c};
        final rejectedMap = {
          for (var r in response.rejected)
            if (r.mutationId != null) r.mutationId!: r.error
        };

        for (final m in mutations) {
          final ackKey = ackedIds.contains(m.eventId)
              ? m.eventId
              : (ackedIds.contains(m.serverMutationId) ? m.serverMutationId : null);
          final conflictKey = conflictMap.containsKey(m.eventId)
              ? m.eventId
              : (conflictMap.containsKey(m.serverMutationId) ? m.serverMutationId : null);
          final rejectedKey = rejectedMap.containsKey(m.eventId)
              ? m.eventId
              : (rejectedMap.containsKey(m.serverMutationId) ? m.serverMutationId : null);

          if (ackKey != null) {
            // Başarılı: Yalnızca sunucu tarafından onaylanan mutasyon SYNCED olur
            final ackRev = ackMap[ackKey] ?? 0;
            await txn.update(
              'sync_events',
              {
                'sync_state': 'SYNCED',
                'base_revision': ackRev > 0 ? ackRev : m.baseRevision,
                'last_error': null,
              },
              where: 'event_id = ?',
              whereArgs: [m.eventId],
            );
            synced++;
          } else if (conflictKey != null) {
            // Çatışma: LWW / Conflict tablosuna kaydedildi
            final conf = conflictMap[conflictKey]!;
            final targetRev = conf.serverRevision > 0 ? conf.serverRevision : m.baseRevision;
            await txn.update(
              'sync_events',
              {
                'sync_state': 'CONFLICT',
                'base_revision': targetRev,
                'last_error': 'Sunucu revizyonu ile çakışma (rev: ${conf.serverRevision})',
              },
              where: 'event_id = ?',
              whereArgs: [m.eventId],
            );
            conflicts++;
          } else if (rejectedKey != null) {
            // Ret: Kalıcı 4xx veya sunucu doğrulama hatası ayrımı
            final error = rejectedMap[rejectedKey]!;
            final isNonRetryable = nonRetryableServerErrors.contains(error);
            final newAttempts = m.attempts + 1;
            final isMaxAttemptsExceeded = newAttempts >= maxTransientAttempts;
            final state = (isNonRetryable || isMaxAttemptsExceeded) ? 'REJECTED' : 'TRANSIENT_ERROR';
            final lastErr = isMaxAttemptsExceeded ? 'max_attempts_exceeded: $error' : error;

            await txn.update(
              'sync_events',
              {
                'sync_state': state,
                'attempts': newAttempts,
                'last_error': lastErr,
              },
              where: 'event_id = ?',
              whereArgs: [m.eventId],
            );

            if (isNonRetryable || isMaxAttemptsExceeded) {
              rejected++;
            } else {
              transient++;
            }
          } else {
            // Sunucu yanıtı bir mutasyonun işlendiğini kesin olarak doğrulamıyorsa onu başarılı kabul etme!
            // Yanıtta ne ack, ne conflict, ne de rejected olarak dönmeyen mutasyon geçici hata sayılır.
            final newAttempts = m.attempts + 1;
            final isMaxAttemptsExceeded = newAttempts >= maxTransientAttempts;
            await txn.update(
              'sync_events',
              {
                'sync_state': isMaxAttemptsExceeded ? 'REJECTED' : 'TRANSIENT_ERROR',
                'attempts': newAttempts,
                'last_error': isMaxAttemptsExceeded
                    ? 'max_attempts_exceeded: unacknowledged_by_server'
                    : 'unacknowledged_by_server',
              },
              where: 'event_id = ?',
              whereArgs: [m.eventId],
            );
            if (isMaxAttemptsExceeded) {
              rejected++;
            } else {
              transient++;
            }
          }
        }

        return OutboxProcessResult(
          totalProcessed: mutations.length,
          syncedCount: synced,
          conflictCount: conflicts,
          rejectedCount: rejected,
          transientErrorCount: transient,
        );
      });
    } on SyncProtocolUpgradeRequiredException catch (e) {
      // Protokol yükseltme zorunlu (HTTP 426): Durumu koru, hata kaydet
      await _recordBatchTransientError(mutations, e.message);
      return OutboxProcessResult(
        totalProcessed: mutations.length,
        transientErrorCount: mutations.length,
        fatalError: e.message,
      );
    } on SyncBadRequestException catch (e) {
      // Tüm batch istek düzeyinde reddedildi (HTTP 400)
      await _recordBatchFatalError(mutations, e.message);
      return OutboxProcessResult(
        totalProcessed: mutations.length,
        rejectedCount: mutations.length,
        fatalError: e.message,
      );
    } on SyncConflictException catch (e) {
      // HTTP 409 Çatışma Ayrımı: Doğrulanmış sunucu çatışma kodu ise terminal REJECTED,
      // bilinmeyen veya kodsuz HTTP 409 ise körlemesine reddetme, güvenli geçici kabul et.
      final isNonRetryable = e.errorCode != null && nonRetryableServerErrors.contains(e.errorCode);
      if (isNonRetryable) {
        await _recordBatchFatalError(mutations, e.errorCode ?? e.message);
        return OutboxProcessResult(
          totalProcessed: mutations.length,
          rejectedCount: mutations.length,
          fatalError: e.message,
        );
      } else {
        await _recordBatchTransientError(mutations, e.message);
        return OutboxProcessResult(
          totalProcessed: mutations.length,
          transientErrorCount: mutations.length,
          fatalError: e.message,
        );
      }
    } on SyncException catch (e) {
      // Ağ hatası, zaman aşımı veya 5xx sunucu hatası (geçici)
      await _recordBatchTransientError(mutations, e.message);
      return OutboxProcessResult(
        totalProcessed: mutations.length,
        transientErrorCount: mutations.length,
        fatalError: e.message,
      );
    } catch (e) {
      // Beklenmeyen hata
      await _recordBatchTransientError(mutations, e.toString());
      return OutboxProcessResult(
        totalProcessed: mutations.length,
        transientErrorCount: mutations.length,
        fatalError: e.toString(),
      );
    }
  }

  /// Tüm batch geçici ağ veya sunucu hatası aldığında kayıtları günceller.
  Future<void> _recordBatchTransientError(List<SyncMutation> list, String message) async {
    await db.transaction((txn) async {
      for (final m in list) {
        final newAttempts = m.attempts + 1;
        final isDeadLetter = newAttempts >= maxTransientAttempts;
        await txn.update(
          'sync_events',
          {
            'sync_state': isDeadLetter ? 'REJECTED' : 'TRANSIENT_ERROR',
            'attempts': newAttempts,
            'last_error': isDeadLetter ? 'max_attempts_exceeded: $message' : message,
          },
          where: 'event_id = ?',
          whereArgs: [m.eventId],
        );
      }
    });
  }

  /// Tüm batch geçersiz istek formatı nedeniyle reddedildiğinde günceller.
  Future<void> _recordBatchFatalError(List<SyncMutation> list, String message) async {
    await db.transaction((txn) async {
      for (final m in list) {
        await txn.update(
          'sync_events',
          {
            'sync_state': 'REJECTED',
            'attempts': m.attempts + 1,
            'last_error': message,
          },
          where: 'event_id = ?',
          whereArgs: [m.eventId],
        );
      }
    });
  }

  /// Kullanıcı ve yönetim arayüzü için reddedilen mutasyonları listeler
  Future<List<SyncMutation>> getRejectedMutations() async {
    final rows = await db.query(
      'sync_events',
      where: "sync_state = 'REJECTED'",
      orderBy: 'client_timestamp DESC',
    );
    return rows.map((r) => SyncMutation.fromDbRow(r)).toList();
  }

  /// Çakışma masasına ayrılmış mutasyonları listeler
  Future<List<SyncMutation>> getConflictMutations() async {
    final rows = await db.query(
      'sync_events',
      where: "sync_state = 'CONFLICT'",
      orderBy: 'client_timestamp DESC',
    );
    return rows.map((r) => SyncMutation.fromDbRow(r)).toList();
  }

  /// Düzeltilen veya incelenen bir mutasyonu yeniden kuyruğa alır (REJECTED -> PENDING)
  Future<void> retryRejectedMutation(String eventId) async {
    await db.transaction((txn) async {
      await txn.update(
        'sync_events',
        {
          'sync_state': 'PENDING',
          'attempts': 0,
          'last_error': null,
        },
        where: 'event_id = ?',
        whereArgs: [eventId],
      );
    });
  }

  /// Çakışmaya düşmüş bir mutasyonun base_revision değerini güncelleyerek yeniden kuyruğa (PENDING) alır.
  Future<void> rebaseConflictMutation(String eventId, {int? newRevision}) async {
    await db.transaction((txn) async {
      final updateData = <String, dynamic>{
        'sync_state': 'PENDING',
        'attempts': 0,
        'last_error': null,
      };
      if (newRevision != null && newRevision > 0) {
        updateData['base_revision'] = newRevision;
      }
      await txn.update(
        'sync_events',
        updateData,
        where: 'event_id = ?',
        whereArgs: [eventId],
      );
    });
  }

  /// Belirli bir varlık tip ve ID'si için çakışmadaki tüm mutasyonları güncel revizyonla rebase eder.
  Future<int> rebaseAllConflictsForEntity(String entityType, String entityId, int newRevision) async {
    return await db.transaction<int>((txn) async {
      return await txn.update(
        'sync_events',
        {
          'sync_state': 'PENDING',
          'base_revision': newRevision,
          'attempts': 0,
          'last_error': null,
        },
        where: "entity_type = ? AND entity_id = ? AND sync_state = 'CONFLICT'",
        whereArgs: [entityType, entityId],
      );
    });
  }
}

