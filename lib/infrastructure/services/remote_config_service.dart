// lib/infrastructure/services/remote_config_service.dart
// Serenut OS — Remote Config & Feature Flags Service (Sprint 8)

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../infrastructure/network/api_client.dart';
import 'package:flutter/foundation.dart';

class RemoteConfigService {
  final SharedPreferences _prefs;
  final ApiClient _apiClient;
  
  static const String _configKey = 'cached_remote_config';

  RemoteConfigService(this._prefs, this._apiClient);

  /// Fetch remote config from SaaS API and cache locally
  Future<void> fetchAndActivate() async {
    try {
      final response = await _apiClient.get('/api/v1/remote-config');
      if (response.statusCode == 200) {
        final body = response.body;
        await _prefs.setString(_configKey, body);
        debugPrint('[RemoteConfig] Successfully synced configurations from server.');
      }
    } catch (e) {
      debugPrint('[RemoteConfig] Sync failed, using cached config. Error: $e');
    }
  }

  Map<String, dynamic> _getConfigMap() {
    final cached = _prefs.getString(_configKey);
    if (cached == null || cached.isEmpty) {
      // Default fallback specifications
      return {
        'kill_switch': false,
        'sync_interval_seconds': 300,
        'log_level': 'info',
        'telemetry_interval_seconds': 600,
        'enable_payment_retry': true
      };
    }
    try {
      return jsonDecode(cached) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  bool isKillSwitchActive() {
    return _getConfigMap()['kill_switch'] as bool? ?? false;
  }

  int getSyncIntervalSeconds() {
    return _getConfigMap()['sync_interval_seconds'] as int? ?? 300;
  }

  String getLogLevel() {
    return _getConfigMap()['log_level'] as String? ?? 'info';
  }

  int getTelemetryIntervalSeconds() {
    return _getConfigMap()['telemetry_interval_seconds'] as int? ?? 600;
  }

  bool isPaymentRetryEnabled() {
    return _getConfigMap()['enable_payment_retry'] as bool? ?? true;
  }
}
