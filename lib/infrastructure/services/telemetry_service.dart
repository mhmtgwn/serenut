// lib/infrastructure/services/telemetry_service.dart
// Serenut OS — Client Telemetry buffering service (Sprint 9)

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../infrastructure/database/database_provider.dart';
import '../../infrastructure/network/api_client.dart';
import 'package:flutter/foundation.dart';

class TelemetryService {
  final ApiClient _apiClient;

  TelemetryService(this._apiClient);

  /// Buffer metric record into local SQLite database
  Future<void> recordMetric(String name, double value, {String? metadata}) async {
    try {
      final db = await DatabaseManager().getDatabase();
      await db.insert('client_telemetry_logs', {
        'metric_name': name,
        'metric_value': value,
        'timestamp': DateTime.now().toIso8601String(),
        'metadata': metadata ?? '',
      });
      debugPrint('[Telemetry] Recorded local metric: $name = $value');
    } catch (e) {
      debugPrint('[Telemetry] Failed to record local metric: $e');
    }
  }

  /// Query buffer rows and post them in a batch transaction payload
  Future<void> uploadMetricsBatch() async {
    try {
      final db = await DatabaseManager().getDatabase();
      final List<Map<String, dynamic>> records = await db.query(
        'client_telemetry_logs',
        orderBy: 'id ASC',
        limit: 100, // Batch limit of 100 to prevent payload limits
      );

      if (records.isEmpty) return;

      final payload = records.map((r) => {
        'metric_name': r['metric_name'],
        'metric_value': r['metric_value'],
        'timestamp': r['timestamp'],
        'metadata': r['metadata'],
      }).toList();

      final response = await _apiClient.post(
        '/api/v1/telemetry/upload',
        {'metrics': payload},
      );

      if (response.statusCode == 200) {
        // Clear successfully processed telemetry batches
        final List<int> ids = records.map((r) => r['id'] as int).toList();
        await db.delete(
          'client_telemetry_logs',
          where: 'id IN (${ids.join(",")})',
        );
        debugPrint('[Telemetry] Batch batch-uploaded ${ids.length} metrics to SaaS platform.');
      } else {
        debugPrint('[Telemetry] Failed to upload batch: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[Telemetry] Error uploading telemetry batch: $e');
    }
  }
}
