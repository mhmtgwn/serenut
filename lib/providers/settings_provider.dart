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

  Future<void> syncCompanyFromServer() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.get('/api/v1/company');
      if (response.isSuccess && response.json != null) {
        final map = response.json as Map<String, dynamic>;
        final companyName = map['name'] as String? ?? '';
        if (companyName.trim().isNotEmpty) {
          final gateway = ref.read(dbGatewayProvider);
          final repo = await ref.read(settingsRepositoryProvider.future);
          final current = await repo.getSettings();

          final prefs = await SharedPreferences.getInstance();
          final knownVersion = prefs.getInt('sync_v4_company_version') ?? 0;
          final remoteVersion = map['version'] is int
              ? map['version'] as int
              : int.tryParse(map['version']?.toString() ?? '') ?? 0;

          // Prevent server from reverting user's local edits if local is customized
          if (current.businessName.isNotEmpty &&
              current.businessName != 'Serenut OS' &&
              (companyName.isEmpty ||
                  companyName == 'Serenut OS' ||
                  remoteVersion <= knownVersion ||
                  current.businessName != companyName)) {
            debugPrint(
                '[SettingsNotifier] Preserving local company profile: "${current.businessName}" (server: "$companyName", v$remoteVersion <= v$knownVersion)');
            if (current.businessName != companyName &&
                companyName.isNotEmpty &&
                remoteVersion <= knownVersion) {
              // Remote has older name; push local to server
              updateSettings(current);
            }
            return;
          }

          final updated = current.copyWith(
            businessName: companyName,
            businessPhone: (map['phone'] as String?)?.isNotEmpty == true
                ? map['phone'] as String
                : current.businessPhone,
            businessAddress: (map['address'] as String?)?.isNotEmpty == true
                ? map['address'] as String
                : current.businessAddress,
            businessTaxId: (map['tax_number'] as String?)?.isNotEmpty == true
                ? map['tax_number'] as String
                : current.businessTaxId,
            ownerName: (map['owner_name'] as String?)?.isNotEmpty == true
                ? map['owner_name'] as String
                : current.ownerName,
            businessEmail: (map['email'] as String?)?.isNotEmpty == true
                ? map['email'] as String
                : current.businessEmail,
            businessCity: (map['city'] as String?)?.isNotEmpty == true
                ? map['city'] as String
                : current.businessCity,
            businessDistrict: (map['district'] as String?)?.isNotEmpty == true
                ? map['district'] as String
                : current.businessDistrict,
            businessType: (map['type'] as String?)?.isNotEmpty == true
                ? map['type'] as String
                : current.businessType,
            businessLogo: (map['logo_url'] as String?)?.isNotEmpty == true
                ? map['logo_url'] as String
                : current.businessLogo,
          );

          await repo.updateSettings(updated);

          await gateway.insert(
            'business_profile',
            {
              'id': 1,
              'name': companyName,
              'owner_name': map['owner_name'] ?? '',
              'type': map['type'] ?? '',
              'phone': map['phone'] ?? '',
              'email': map['email'] ?? '',
              'tax_number': map['tax_number'] ?? '',
              'city': map['city'] ?? '',
              'district': map['district'] ?? '',
              'currency': map['currency'] ?? '₺',
              'logo_path': map['logo_url'],
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
          state = AsyncValue.data(updated);
        }
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

      // 1. Local SQLite settings update
      await repo.updateSettings(settings);

      // 2. Local SQLite business_profile update
      if (companyProfileChanged) {
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
        try {
          final apiClient = ref.read(apiClientProvider);
          final res = await apiClient.get('/api/v1/company');
          if (res.isSuccess && res.json != null) {
            final remote = Map<String, dynamic>.from(res.json as Map);
            final remoteVersion = remote['version'] is int
                ? remote['version'] as int
                : int.tryParse(remote['version']?.toString() ?? '1') ?? 1;

            var patch = await apiClient.send('PATCH', '/api/v1/company', body: {
              'expected_version': remoteVersion,
              'force': true,
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
              'logo_url': settings.businessLogo,
            });

            // If 409 conflict, retry once with fresh version
            if (patch.statusCode == 409) {
              final retryRes = await apiClient.get('/api/v1/company');
              if (retryRes.isSuccess && retryRes.json != null) {
                final retryRemote = Map<String, dynamic>.from(retryRes.json as Map);
                final retryVer = retryRemote['version'] is int
                    ? retryRemote['version'] as int
                    : int.tryParse(retryRemote['version']?.toString() ?? '') ?? (remoteVersion + 1);
                patch = await apiClient.send('PATCH', '/api/v1/company', body: {
                  'expected_version': retryVer,
                  'force': true,
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
                  'logo_url': settings.businessLogo,
                });
              }
            }

            if (patch.isSuccess && patch.json != null) {
              final patched = Map<String, dynamic>.from(patch.json as Map);
              final newVer = patched['version'] is int
                  ? patched['version'] as int
                  : int.tryParse(patched['version']?.toString() ?? '') ?? (remoteVersion + 1);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt('sync_v4_company_version', newVer);
              await prefs.setString('sync_v4_company_synced_at', DateTime.now().toUtc().toIso8601String());
              debugPrint('[SettingsNotifier] Successfully synced company info to server v$newVer.');
            } else {
              debugPrint('[SettingsNotifier] Company profile patch response: ${patch.statusCode} ${patch.body}');
            }
          }
        } catch (e) {
          debugPrint('[SettingsNotifier] Remote company update network error: $e');
        }
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
