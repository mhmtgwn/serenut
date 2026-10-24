// lib/infrastructure/services/telemetry_upload_service.dart
// Serenut OS — Client Telemetry buffering service (Sprint 9)
// Renamed from TelemetryService to TelemetryUploadService to avoid class
// name collision with domain/services/telemetry_service.dart (LocalLoggingService).

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../infrastructure/database/database_provider.dart';
import '../../infrastructure/database/db_gateway.dart';
import '../../infrastructure/network/api_client.dart';

class TelemetryUploadService {
  final ApiClient _apiClient;
  final DbGateway? _gateway;
  bool _isRecording = false;

  TelemetryUploadService(this._apiClient, [this._gateway]);

  /// Buffer metric record into local SQLite database
  Future<void> recordMetric(String name, double value,
      {Object? metadata}) async {
    if (_isRecording) return;
    _isRecording = true;
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
      // to prevent using a closing/aborted transaction executor.
      await runZoned(() async {
        final db = await DatabaseManager.instance.getDatabase();
        await db.insert('client_telemetry_logs', payload);
      }, zoneValues: {#sqlite_txn: null});
      debugPrint('[TelemetryUpload] Recorded local metric: $name = $value');
    } catch (e) {
      debugPrint('[TelemetryUpload] Failed to record local metric: $e');
    } finally {
      _isRecording = false;
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
