// lib/domain/services/sync_client.dart
// Serenut Platform — Cloud Sync Client Service
// Manages cloud synchronization operations, health checks, and sync queue routing.
// Created: 04 Jul 2026

import 'package:serenutos/infrastructure/network/api_client.dart';

abstract class SyncClient {
  Future<bool> checkHealth();
  Future<Map<String, dynamic>> push(List<Map<String, dynamic>> queueItems);
  Future<Map<String, dynamic>> pull(int lastSyncTimestamp);
  Future<bool> retry(String itemId);
  Future<void> resolveConflict(
      String itemId, Map<String, dynamic> resolvedData);
}

class RealSyncClient implements SyncClient {
  final ApiClient _apiClient;

  RealSyncClient(this._apiClient);

  @override
  Future<bool> checkHealth() async {
    try {
      final response = await _apiClient.get('/health');
      return response.isSuccess && response.json['status'] == 'healthy';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> push(
      List<Map<String, dynamic>> queueItems) async {
    // Backend expects 'items' rather than 'queue'
    final response = await _apiClient.post('/sync/push', {
      'items': queueItems,
    });
    return response.json as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> pull(int lastSyncTimestamp) async {
    // Backend expects 'last_timestamp' rather than 'last_modified'
    final response =
        await _apiClient.get('/sync/pull?last_timestamp=$lastSyncTimestamp');
    return response.json as Map<String, dynamic>;
  }

  @override
  Future<bool> retry(String itemId) async {
    try {
      final response = await _apiClient.post('/sync/retry', {
        'id': itemId,
      });
      return response.isSuccess && response.json['retried'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> resolveConflict(
      String itemId, Map<String, dynamic> resolvedData) async {
    await _apiClient.post('/sync/conflict/resolve', {
      'id': itemId,
      'resolution': resolvedData,
    });
  }
}
