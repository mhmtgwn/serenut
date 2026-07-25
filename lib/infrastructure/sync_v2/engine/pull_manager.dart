import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../local/sync_state_dao.dart';
import '../local/inbox_dao.dart';
import 'metrics_collector.dart';

class PullManager {
  final Database db;
  final SyncStateDao syncStateDao;
  final InboxDao inboxDao;
  final String serverBaseUrl;
  final String authToken;
  final SyncMetricsCollector metrics;

  PullManager({
    required this.db,
    required this.syncStateDao,
    required this.inboxDao,
    required this.serverBaseUrl,
    required this.authToken,
    required this.metrics,
  });

  /// Executes smart vector delta pull for lagging domains.
  Future<bool> executeDeltaPull(String tenantId) async {
    final clientVectors = await syncStateDao.getAllVectors();

    try {
      final startTime = DateTime.now().millisecondsSinceEpoch;
      final response = await http.post(
        Uri.parse('$serverBaseUrl/api/v2/sync/delta'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'tenant_id': tenantId,
          'client_vectors': clientVectors,
          'max_batch_size': 500,
        }),
      );

      metrics.recordSyncDuration(DateTime.now().millisecondsSinceEpoch - startTime);

      if (response.statusCode != 200) {
        return false;
      }

      final body = jsonDecode(response.body);
      if (body['success'] != true) {
        return false;
      }

      final deltas = body['deltas'] as List<dynamic>;
      final headVectors = Map<String, int>.from(
        (body['head_vectors'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toInt())),
      );

      // Apply incoming delta revisions inside SQLite transaction
      await db.transaction((txn) async {
        for (final item in deltas) {
          final clientMutationId = item['client_mutation_id'] as String;

          // Idempotency check against Inbox
          if (await inboxDao.isProcessed(clientMutationId)) {
            continue;
          }

          final domain = item['domain'] as String;
          final revision = (item['revision'] as num).toInt();

          // Mark processed in Inbox and update SyncState Vector
          await inboxDao.markProcessed(clientMutationId, txn: txn);
          await syncStateDao.setVector(domain, revision, txn: txn);
        }

        // Update remaining head vectors
        for (final entry in headVectors.entries) {
          await syncStateDao.setVector(entry.key, entry.value, txn: txn);
        }
      });

      metrics.recordPull();
      return true;
    } catch (e) {
      return false;
    }
  }
}
