// lib/infrastructure/services/client_health_service.dart
// Serenut OS — Consolidated Client Health Diagnostics Service (Sprint 11)

import '../../infrastructure/database/database_provider.dart';
import '../../infrastructure/network/api_client.dart';
import '../../domain/services/license_service.dart';
import 'package:flutter/foundation.dart';

class ClientHealthService {
  final ApiClient _apiClient;
  final LicenseService _licenseService;

  ClientHealthService(this._apiClient, this._licenseService);

  /// Performs checks across system dependencies and returns consolidated status map
  Future<Map<String, String>> checkServicesHealth() async {
    final report = <String, String>{};

    // 1. Database check
    try {
      final db = await DatabaseManager().getDatabase();
      final res = await db.rawQuery('SELECT 1');
      if (res.isNotEmpty) {
        report['database'] = 'up';
      } else {
        report['database'] = 'degraded';
      }
    } catch (_) {
      report['database'] = 'down';
    }

    // 2. License check
    try {
      final status = _licenseService.checkLicenseStatus();
      report['license'] = status;
    } catch (_) {
      report['license'] = 'unknown';
    }

    // 3. Network check
    try {
      final pingRes = await _apiClient.get('/health');
      if (pingRes.statusCode == 200) {
        report['network'] = 'online';
      } else {
        report['network'] = 'degraded';
      }
    } catch (_) {
      report['network'] = 'offline';
    }

    // 4. Printer check (mocked details fallback)
    report['printer'] = 'configured';

    return report;
  }

  /// Sends diagnostic report to cloud orchestrator
  Future<bool> reportHealthToServer({required String deviceId}) async {
    try {
      final services = await checkServicesHealth();

      // Determine overall status
      final isHealthy = services['database'] == 'up' &&
          services['license'] == 'valid' &&
          services['network'] == 'online';

      final response = await _apiClient.post(
        '/api/v1/health/report',
        {
          'device_id': deviceId,
          'status': isHealthy ? 'healthy' : 'unhealthy',
          'services': services,
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[ClientHealth] Failed to upload diagnostics report: $e');
      return false;
    }
  }
}
