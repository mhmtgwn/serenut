// lib/infrastructure/services/telemetry_upload_service.dart
// Serenut OS — Client Telemetry buffering service (Sprint 9)
// Renamed from TelemetryService to TelemetryUploadService to avoid class
// name collision with domain/services/telemetry_service.dart (LocalLoggingService).

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../infrastructure/database/database_provider.dart';
import '../../infrastructure/database/db_gateway.dart';
import '../../infrastructure/network/api_client.dart';

class TelemetryUploadService {
  final ApiClient _apiClient;
  final DbGateway? _gateway;
  static Future<void> _writeQueue = Future.value();
  static const int maxTelemetryQueueSize = 5000;

  TelemetryUploadService(this._apiClient, [this._gateway]);

  /// Buffer metric record into local SQLite database
  Future<void> recordMetric(String name, double value,
      {Object? metadata}) {
    // If called inside an active SQLite transaction zone, never block the caller
    // waiting for a detached database connection write (which would deadlock sqflite).
    if (Zone.current[#sqlite_txn] != null) {
      Zone.root.run(() {
        Future<void>.delayed(Duration.zero, () {
          _writeQueue = _writeQueue.then((_) async {
            try {
              await _recordMetricInternal(name, value, metadata: metadata);
            } catch (e) {
              debugPrint('[TelemetryUpload] Zone record metric error: $e');
            }
          });
        });
      });
      return Future<void>.value();
    }

    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _recordMetricInternal(name, value, metadata: metadata);
        completer.complete();
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> _recordMetricInternal(String name, double value,
      {Object? metadata}) async {
    try {
      final cutoff = DatabaseManager.cutoffMaintenanceLock;
      if (cutoff != null && !cutoff.state.isWritePermitted) {
        cutoff.assertWritePermitted(operation: 'TelemetryUploadService.recordMetric');
      }

      final payload = {
        'metric_name': name,
        'metric_value': value,
        'timestamp': DateTime.now().toIso8601String(),
        'metadata':
            metadata is String ? metadata : jsonEncode(metadata ?? const {}),
      };

      // Always execute detached from any ongoing SQLite transaction zone
      // and serialized via DbGatewayImpl so telemetry writes never collide
      // with active Database.transaction locks.
      await runZoned(() async {
        final gateway = _gateway ?? DbGatewayImpl(DatabaseManager.instance);
        await gateway.insert('client_telemetry_logs', payload);

        // FIFO eviction: maintain local queue under 5,000 records
        final rows = await gateway.rawQuery(
          'SELECT COUNT(*) as cnt FROM client_telemetry_logs',
        );
        final count = Sqflite.firstIntValue(rows) ?? 0;
        if (count > maxTelemetryQueueSize) {
          final excess = count - maxTelemetryQueueSize;
          await gateway.rawDelete('''
            DELETE FROM client_telemetry_logs WHERE id IN (
              SELECT id FROM client_telemetry_logs ORDER BY id ASC LIMIT ?
            )
          ''', [excess]);
        }
      }, zoneValues: {#sqlite_txn: null});
      debugPrint('[TelemetryUpload] Recorded local metric: $name = $value');
    } catch (e) {
      debugPrint('[TelemetryUpload] Failed to record local metric: $e');
    }
  }

  /// Query buffer rows and post them in a batch transaction payload
  Future<void> uploadMetricsBatch() async {
    try {
      final cutoff = DatabaseManager.cutoffMaintenanceLock;
      if (cutoff != null && !cutoff.state.isWritePermitted) {
        return;
      }

      final gateway = _gateway;
      final List<Map<String, dynamic>> records;
      if (gateway != null) {
        records = await gateway.query(
          'client_telemetry_logs',
          orderBy: 'id ASC',
          limit: 100,
        );
      } else {
        final db = await DatabaseManager.instance.getDatabase();
        records = await db.query(
          'client_telemetry_logs',
          orderBy: 'id ASC',
          limit: 100, // Batch limit of 100 to prevent payload limits
        );
      }

      if (records.isEmpty) return;

      final payload = records
          .map((r) => {
                'metric_name': r['metric_name'],
                'metric_value': r['metric_value'],
                'timestamp': r['timestamp'],
                'metadata': r['metadata'],
              })
          .toList();

      final response = await _apiClient.post(
        '/api/v1/telemetry/upload',
        {'metrics': payload},
      );

      if (response.statusCode == 200) {
        // Clear successfully processed telemetry batches
        final List<int> ids = records.map((r) => r['id'] as int).toList();
        if (gateway != null) {
          await gateway.delete(
            'client_telemetry_logs',
            where: 'id IN (${ids.join(",")})',
          );
        } else {
          final db = await DatabaseManager.instance.getDatabase();
          await db.delete(
            'client_telemetry_logs',
            where: 'id IN (${ids.join(",")})',
          );
        }
        debugPrint(
            '[TelemetryUpload] Batch-uploaded ${ids.length} metrics to SaaS platform.');
      } else {
        debugPrint(
            '[TelemetryUpload] Failed to upload batch: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[TelemetryUpload] Error uploading telemetry batch: $e');
    }
  }
}
