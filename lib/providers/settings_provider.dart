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
              'tax_included': 1,
              'version': map['version'] ?? 1,
              'created_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

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
      await repo.updateSettings(settings);

      // Tenant-wide profile fields are picked up by SyncV4. Keeping this write
      // local-first also lets image files be resized and converted into a
      // portable logo before they are sent to the company profile endpoint.
      if (companyProfileChanged) {
        debugPrint('[Settings] Company profile queued for SyncV4.');
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
