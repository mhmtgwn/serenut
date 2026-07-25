import 'dart:convert';
import 'package:http/http.dart' as http;
import '../local/outbox_dao.dart';
import 'metrics_collector.dart';

class PushManager {
  final OutboxDao outboxDao;
  final String serverBaseUrl;
  final String authToken;
  final SyncMetricsCollector metrics;

  PushManager({
    required this.outboxDao,
    required this.serverBaseUrl,
    required this.authToken,
    required this.metrics,
  });

  /// Executes push task for pending outbox batch (up to batchSize items).
  Future<bool> executePushBatch({int batchSize = 100}) async {
    final pendingBatch = await outboxDao.getPendingBatch(batchSize);
    if (pendingBatch.isEmpty) {
      return true;
    }

    metrics.updateQueueDepth(pendingBatch.length);

    final ids = pendingBatch.map((m) => m.id!).toList();
    await outboxDao.markSending(ids);

    final mutationsPayload = pendingBatch.map((m) {
      return {
        'client_mutation_id': m.clientMutationId,
        'tenant_id': m.tenantId,
        'device_id': m.deviceId,
        'domain': m.domain,
        'entity_type': m.entityType,
        'entity_id': m.entityId,
        'op_type': m.opType,
        'payload': jsonDecode(m.payload),
        'client_timestamp': m.clientTimestamp,
        'base_revision': m.baseRevision,
      };
    }).toList();

    try {
      final startTime = DateTime.now().millisecondsSinceEpoch;
      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/v2/sync/push'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
          'x-device-id': pendingBatch.first.deviceId,
        },
        body: jsonEncode({
          'tenant_id': pendingBatch.first.tenantId,
          'device_id': pendingBatch.first.deviceId,
          'mutations': mutationsPayload,
        }),
      );

      metrics.recordSyncDuration(DateTime.now().millisecondsSinceEpoch - startTime);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          // Delete successfully processed mutations from Outbox
          await outboxDao.deleteByIds(ids);
          metrics.recordPush();
          return true;
        }
      }

      // If failed, revert status to PENDING
      for (final id in ids) {
        await outboxDao.markFailed(id, 'HTTP ${response.statusCode}: ${response.body}');
      }
      return false;
    } catch (e) {
      for (final id in ids) {
        await outboxDao.markFailed(id, e.toString());
      }
      return false;
    }
  }
}
