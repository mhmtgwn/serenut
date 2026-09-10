import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_settings_repository.dart';
import 'package:serenutos/providers/database_provider.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart'
    show sharedPreferencesProvider;

import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Riverpod provider for Settings Repository
final settingsRepositoryProvider =
    FutureProvider<ISettingsRepository>((ref) async {
  if (kIsWeb) {
    final prefs = ref.watch(sharedPreferencesProvider);
    return SharedPreferencesSettingsRepository(prefs);
  }
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteSettingsRepository(gateway);
});

/// Future provider of application Settings
final settingsProvider = FutureProvider<Settings>((ref) async {
  final repo = await ref.watch(settingsRepositoryProvider.future);
  return repo.getSettings();
});

/// StateNotifier to manage reactive Settings state changes
class SettingsNotifier extends StateNotifier<AsyncValue<Settings>> {
  final Ref ref;

  SettingsNotifier(this.ref) : super(const AsyncValue.loading()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      final settings = await repo.getSettings();
      state = AsyncValue.data(settings);

      // Automatically sync company details from server if logged in
      syncCompanyFromServer();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<String?> _encodePortableLogo(String? value) async {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('data:image/')) {
      return trimmed;
    }
    try {
      final file = File(trimmed);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      final lower = trimmed.toLowerCase();
      final mime = (lower.endsWith('.png'))
          ? 'image/png'
          : (lower.endsWith('.webp'))
              ? 'image/webp'
              : 'image/jpeg';
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (e) {
      debugPrint('[SettingsNotifier] Logo encode failed: $e');
      return null;
    }
  }

  /// Explicitly pushes the local company settings to the server via PATCH /api/v1/company.
  /// Handles 409 conflict retry and updates version/dirty flags upon success.
  Future<bool> pushCompanyToServer(Settings settings, {bool force = true}) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      if (apiClient.jwtToken == null || apiClient.jwtToken!.isEmpty) {
        debugPrint('[SettingsNotifier] No active session token to push company profile.');
        return false;
      }

      final res = await apiClient.get('/api/v1/company');
      if (!res.isSuccess || res.json == null) {
        debugPrint('[SettingsNotifier] Cannot reach server company endpoint (${res.statusCode}). Keeping local dirty state.');
        return false;
      }

      final remote = Map<String, dynamic>.from(res.json as Map);
      final remoteVersion = remote['version'] is int
          ? remote['version'] as int
          : int.tryParse(remote['version']?.toString() ?? '1') ?? 1;

      final portableLogo = await _encodePortableLogo(settings.businessLogo);

      final body = <String, dynamic>{
        'expected_version': remoteVersion,
        'force': force,
        'name': settings.businessName,
        'address': settings.businessAddress,
        'phone': settings.businessPhone,
        'email': settings.businessEmail,
        'tax_number': settings.businessTaxId,
        'owner_name': settings.ownerName,
        'type': settings.businessType,
        'city': settings.businessCity,
        'district': settings.businessDistrict,
        'currency': settings.currency,
        'logo_url': portableLogo,
      };

      ApiResponse? patch;
      try {
        patch = await apiClient.send('PATCH', '/api/v1/company', body: body);
      } on ApiException catch (e) {
        if (e.statusCode == 409) {
          debugPrint('[SettingsNotifier] 409 conflict during company PATCH; retrying with fresh version...');
          final retryRes = await apiClient.get('/api/v1/company');
          if (retryRes.isSuccess && retryRes.json != null) {
            final retryRemote = Map<String, dynamic>.from(retryRes.json as Map);
            final retryVer = retryRemote['version'] is int
                ? retryRemote['version'] as int
                : int.tryParse(retryRemote['version']?.toString() ?? '') ?? (remoteVersion + 1);
            body['expected_version'] = retryVer;
            try {
              patch = await apiClient.send('PATCH', '/api/v1/company', body: body);
            } catch (retryErr) {
              debugPrint('[SettingsNotifier] Retry PATCH failed: $retryErr');
            }
          }
        } else {
          debugPrint('[SettingsNotifier] Company PATCH failed with status ${e.statusCode}: ${e.message}');
          return false;
        }
      }

      if (patch != null && patch.isSuccess && patch.json != null) {
        final patched = Map<String, dynamic>.from(patch.json as Map);
        final newVer = patched['version'] is int
            ? patched['version'] as int
            : int.tryParse(patched['version']?.toString() ?? '') ?? (remoteVersion + 1);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('sync_v4_company_version', newVer);
        await prefs.setString('sync_v4_company_synced_at', DateTime.now().toUtc().toIso8601String());
        await prefs.setBool('sync_v4_company_dirty', false);
        debugPrint('[SettingsNotifier] Successfully synced company info to server v$newVer.');
        return true;
      }
    } catch (e) {
      debugPrint('[SettingsNotifier] Remote company update network error: $e');
    }
    return false;
  }

  Future<void> syncCompanyFromServer() async {
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      final current = await repo.getSettings();
      final prefs = await SharedPreferences.getInstance();
      final isDirty = prefs.getBool('sync_v4_company_dirty') ?? false;

      // If user has unpushed local changes, push them to server instead of pulling!
      if (isDirty) {
        debugPrint('[SettingsNotifier] Local changes are dirty. Pushing to server instead of pulling.');
        await pushCompanyToServer(current, force: true);
        return;
      }

      final apiClient = ref.read(apiClientProvider);
      if (apiClient.jwtToken == null || apiClient.jwtToken!.isEmpty) return;

      final response = await apiClient.get('/api/v1/company');
      if (response.isSuccess && response.json != null) {
        final map = response.json as Map<String, dynamic>;
        final companyName = (map['name'] as String? ?? '').trim();
        final knownVersion = prefs.getInt('sync_v4_company_version') ?? 0;
        final remoteVersion = map['version'] is int
            ? map['version'] as int
            : int.tryParse(map['version']?.toString() ?? '') ?? 0;

        final localIsDefault = (current.businessName.isEmpty || current.businessName == 'Serenut OS');

        // If local is customized, DO NOT overwrite unless remote is strictly newer AND knownVersion > 0
        if (!localIsDefault) {
          if (remoteVersion <= knownVersion || knownVersion == 0) {
            // Keep local customized values
            if (remoteVersion > 0 && knownVersion == 0) {
              await prefs.setInt('sync_v4_company_version', remoteVersion);
            }
            return;
          }
        }

        // Helper to pick remote if non-empty string, else preserve local
        String pick(dynamic remoteVal, String localVal) {
          final r = remoteVal?.toString().trim();
          if (r != null && r.isNotEmpty) return r;
          return localVal;
        }

        // Prevent server from reverting user's local edits if local is customized
        final resolvedName = (companyName.isEmpty || companyName == 'Serenut OS') &&
                !localIsDefault
            ? current.businessName
            : (companyName.isNotEmpty ? companyName : current.businessName);

        final updated = current.copyWith(
          businessName: resolvedName,
          businessPhone: pick(map['phone'], current.businessPhone),
          businessAddress: pick(map['address'], current.businessAddress),
          businessTaxId: pick(map['tax_number'], current.businessTaxId ?? ''),
          ownerName: pick(map['owner_name'], current.ownerName),
          businessEmail: pick(map['email'], current.businessEmail ?? ''),
          businessCity: pick(map['city'], current.businessCity),
          businessDistrict: pick(map['district'], current.businessDistrict),
          businessType: pick(map['type'], current.businessType),
          businessLogo: pick(map['logo_url'], current.businessLogo ?? ''),
        );

        await repo.updateSettings(updated);

        final gateway = ref.read(dbGatewayProvider);
        await gateway.insert(
          'business_profile',
          {
            'id': 1,
            'name': updated.businessName,
            'owner_name': updated.ownerName,
            'type': updated.businessType,
            'phone': updated.businessPhone,
            'email': updated.businessEmail ?? '',
            'tax_number': updated.businessTaxId ?? '',
            'city': updated.businessCity,
            'district': updated.businessDistrict,
            'currency': map['currency'] ?? updated.currency,
            'logo_path': updated.businessLogo,
            'tax_included': 1,
            'version': remoteVersion,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        if (remoteVersion > 0) {
          await prefs.setInt('sync_v4_company_version', remoteVersion);
        }
        await prefs.setBool('sync_v4_company_dirty', false);
        state = AsyncValue.data(updated);
      }
    } catch (e) {
      debugPrint('[SettingsNotifier] ⚠️ Company sync from server skipped: $e');
    }
  }

  Future<void> updateSettings(Settings settings) async {
    state = const AsyncValue.loading();
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      final previous = await repo.getSettings();
      final companyProfileChanged =
          previous.businessName != settings.businessName ||
              previous.businessPhone != settings.businessPhone ||
              previous.businessAddress != settings.businessAddress ||
              previous.businessTaxId != settings.businessTaxId ||
              previous.businessLogo != settings.businessLogo ||
              previous.ownerName != settings.ownerName ||
              previous.businessEmail != settings.businessEmail ||
              previous.businessCity != settings.businessCity ||
              previous.businessDistrict != settings.businessDistrict ||
              previous.businessType != settings.businessType ||
              previous.currency != settings.currency;

      // 1. Local SQLite settings update (offline-first: local always wins immediately)
      await repo.updateSettings(settings);

      // 2. Local SQLite business_profile update & dirty flag
      if (companyProfileChanged) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('sync_v4_company_dirty', true);

        try {
          final gateway = ref.read(dbGatewayProvider);
          await gateway.insert(
            'business_profile',
            {
              'id': 1,
              'name': settings.businessName,
              'owner_name': settings.ownerName,
              'type': settings.businessType,
              'phone': settings.businessPhone,
              'email': settings.businessEmail ?? '',
              'tax_number': settings.businessTaxId ?? '',
              'city': settings.businessCity,
              'district': settings.businessDistrict,
              'currency': settings.currency,
              'logo_path': settings.businessLogo,
              'tax_included': 1,
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } catch (e) {
          debugPrint('[SettingsNotifier] business_profile update skipped: $e');
        }

        // 3. Immediate remote API update if server is reachable
        await pushCompanyToServer(settings, force: true);
      }

      // Reload settings to update state
      final updated = await repo.getSettings();
      state = AsyncValue.data(updated);

      // Also invalidate settingsProvider so anything watching it gets the updated settings
      ref.invalidate(settingsProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> incrementSmsCounter() async {
    final current = state.value;
    if (current == null) return;

    final now = DateTime.now();
    int newSent = current.smsSentThisMonth + 1;
    int? currentResetMonth = current.smsLimitResetMonth;

    if (currentResetMonth != now.month) {
      newSent = 1;
      currentResetMonth = now.month;
    }

    final updated = current.copyWith(
      smsSentThisMonth: newSent,
      smsLimitResetMonth: currentResetMonth,
    );
    await updateSettings(updated);
  }
}

/// Provider for SettingsNotifier
final settingsNotifierProvider =
    StateNotifierProvider<SettingsNotifier, AsyncValue<Settings>>(
  (ref) => SettingsNotifier(ref),
);
