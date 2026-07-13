import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';
import 'package:serenutos/providers/database_provider.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

import 'package:serenutos/providers/service_providers.dart';

/// Riverpod provider for Settings Repository
final settingsRepositoryProvider = FutureProvider<ISettingsRepository>((ref) async {
  if (kIsWeb) {
    return InMemorySettingsRepository();
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
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateSettings(Settings settings) async {
    state = const AsyncValue.loading();
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.updateSettings(settings);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('serenut_pending_company_patch', true);

      // Sync company profile with backend (fire-and-forget/non-blocking)
      try {
        final gateway = ref.read(dbGatewayProvider);
        final profileRows = await gateway.query('business_profile', limit: 1);
        int expectedVersion = 1;
        if (profileRows.isNotEmpty) {
          expectedVersion = profileRows.first['version'] as int? ?? 1;
        }

        final apiClient = ref.read(apiClientProvider);
        final response = await apiClient.send(
          'PATCH',
          '/api/v1/company',
          body: {
            'expected_version': expectedVersion,
            'name': settings.businessName,
            'phone': settings.businessPhone,
            'address': settings.businessAddress,
            'owner_name': settings.ownerName,
            'type': settings.businessType,
            'city': settings.businessCity,
            'district': settings.businessDistrict,
            'currency': settings.currency,
            'logo_url': settings.businessLogo,
          },
        );
        if (response.isSuccess) {
          final updatedMap = response.json as Map<String, dynamic>;
          final newVersion = updatedMap['version'] as int? ?? (expectedVersion + 1);
          await gateway.update(
            'business_profile',
            {
              'name': updatedMap['name'] ?? settings.businessName,
              'owner_name': updatedMap['owner_name'] ?? settings.ownerName,
              'type': updatedMap['type'] ?? settings.businessType,
              'phone': updatedMap['phone'] ?? settings.businessPhone,
              'email': updatedMap['email'] ?? '',
              'tax_number': updatedMap['tax_number'] ?? '',
              'city': updatedMap['city'] ?? settings.businessCity,
              'district': updatedMap['district'] ?? settings.businessDistrict,
              'currency': updatedMap['currency'] ?? settings.currency,
              'version': newVersion,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [1],
          );
          await prefs.setBool('serenut_pending_company_patch', false);
        }
      } on ApiException catch (e) {
        if (e.statusCode == 409) {
          await prefs.setBool('serenut_pending_company_patch', false);
          debugPrint('[Settings] ⚠️ Company patch version conflict: 409 returned.');
        }
      } catch (e) {
        debugPrint('⚠️ Central business profile sync failed: $e');
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
