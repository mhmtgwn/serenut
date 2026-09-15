// lib/providers/gib_invoice_providers.dart
// Serenut OS — GİB e-Arşiv Riverpod Sağlayıcıları

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/gib_invoice_models.dart';
import 'package:serenutos/domain/services/gib_invoice_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_invoice_repository.dart';
import 'package:serenutos/infrastructure/services/gib_earsiv_client.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';

class GibCredentials {
  final String username;
  final String password;
  final bool isTestMode;
  final double defaultVatRate;

  const GibCredentials({
    this.username = '',
    this.password = '',
    this.isTestMode = false,
    this.defaultVatRate = 20.0,
  });

  bool get isConfigured => username.trim().isNotEmpty && password.trim().isNotEmpty;
}

class GibCredentialsNotifier extends StateNotifier<GibCredentials> {
  final Ref _ref;

  GibCredentialsNotifier(this._ref) : super(const GibCredentials()) {
    _load();
  }

  void _load() {
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      final u = prefs.getString('gib_portal_username') ?? '';
      final p = prefs.getString('gib_portal_password') ?? '';
      final t = prefs.getBool('gib_portal_test_mode') ?? false;
      final v = prefs.getDouble('gib_default_vat_rate') ?? 20.0;
      state = GibCredentials(
        username: u,
        password: p,
        isTestMode: t,
        defaultVatRate: v,
      );
    } catch (_) {}
  }

  Future<void> save({
    required String username,
    required String password,
    required bool isTestMode,
    double defaultVatRate = 20.0,
  }) async {
    final prefs = _ref.read(sharedPreferencesProvider);
    await prefs.setString('gib_portal_username', username.trim());
    await prefs.setString('gib_portal_password', password.trim());
    await prefs.setBool('gib_portal_test_mode', isTestMode);
    await prefs.setDouble('gib_default_vat_rate', defaultVatRate);

    state = GibCredentials(
      username: username.trim(),
      password: password.trim(),
      isTestMode: isTestMode,
      defaultVatRate: defaultVatRate,
    );
  }
}

final gibCredentialsProvider =
    StateNotifierProvider<GibCredentialsNotifier, GibCredentials>((ref) {
  return GibCredentialsNotifier(ref);
});

final gibInvoiceRepositoryProvider = Provider<IGibInvoiceRepository>((ref) {
  final gateway = DbGatewayImpl(DatabaseManager());
  return SqliteInvoiceRepository(gateway);
});

final gibEArsivClientProvider = Provider<GibEArsivClient>((ref) {
  final creds = ref.watch(gibCredentialsProvider);
  return GibEArsivClient(isTestMode: creds.isTestMode);
});

final gibInvoiceServiceProvider = Provider<GibInvoiceService>((ref) {
  final client = ref.watch(gibEArsivClientProvider);
  final repo = ref.watch(gibInvoiceRepositoryProvider);
  return GibInvoiceService(client: client, repository: repo);
});

final gibInvoiceListProvider =
    FutureProvider.autoDispose<List<GibInvoiceRecord>>((ref) async {
  final service = ref.watch(gibInvoiceServiceProvider);
  return service.getInvoices(limit: 100);
});

final saleInvoiceProvider = FutureProvider.autoDispose
    .family<GibInvoiceRecord?, String>((ref, saleId) async {
  final service = ref.watch(gibInvoiceServiceProvider);
  return service.getInvoiceForSale(saleId);
});
