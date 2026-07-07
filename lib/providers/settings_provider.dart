import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';
import 'package:serenutos/providers/database_provider.dart';


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
      // Reload settings to update state
      final updated = await repo.getSettings();
      state = AsyncValue.data(updated);
      
      // Also invalidate settingsProvider so anything watching it gets the updated settings
      ref.invalidate(settingsProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// Provider for SettingsNotifier
final settingsNotifierProvider =
    StateNotifierProvider<SettingsNotifier, AsyncValue<Settings>>(
  (ref) => SettingsNotifier(ref),
);
