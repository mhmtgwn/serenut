// Serenut OS — Canonical initial synchronization service.
//
// There is deliberately no module-by-module bootstrap fallback here. Every
// production installation hydrates through Sync V4 so first sync and routine
// sync apply the exact same authorization and data contract.

import 'dart:convert';

import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_v4_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BootstrapSyncService {
  static const _completedKey = 'serenut_v4_bootstrap_completed';
  static const _indexKey = 'serenut_v4_bootstrap_index';

  final SharedPreferences _prefs;
  final ApiClient _apiClient;
  final String? _scopeId;

  BootstrapSyncService(this._prefs, this._apiClient, {String? scopeId})
      : _scopeId = scopeId;

  String _scopedKey(String base) {
    var scope = _scopeId?.trim();
    if (scope == null || scope.isEmpty) {
      final storedUser = _prefs.getString('auth_user_json');
      if (storedUser != null && storedUser.isNotEmpty) {
        try {
          final user = jsonDecode(storedUser) as Map<String, dynamic>;
          scope = (user['companyId'] ?? user['company_id'])?.toString();
        } catch (_) {
          // An invalid cached session must not prevent a fresh V4 bootstrap.
        }
      }
    }
    return scope == null || scope.isEmpty ? base : '${base}_$scope';
  }

  bool isCompleted() => _prefs.getBool(_scopedKey(_completedKey)) ?? false;

  Future<void> resetBootstrap() async {
    await _prefs.remove(_scopedKey(_completedKey));
    await _prefs.remove(_scopedKey(_indexKey));
  }

  Future<void> runBootstrap(
    void Function(double progress, String statusText) onProgress,
  ) async {
    onProgress(10, 'Yetkili ilk senkronizasyon başlatılıyor...');
    final result = await SyncV4Service(_apiClient).sync();
    if (!result.success) {
      throw Exception(
        result.errors.isEmpty
            ? 'İlk senkronizasyon tamamlanamadı.'
            : result.errors.join('\n'),
      );
    }

    await _prefs.setBool(_scopedKey(_completedKey), true);
    await _prefs.setInt(_scopedKey(_indexKey), 0);
    onProgress(100, 'Tüm veriler güvenli olarak eşitlendi');
  }
}
