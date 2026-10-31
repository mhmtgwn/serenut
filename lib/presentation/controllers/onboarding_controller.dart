// lib/presentation/controllers/onboarding_controller.dart
// Serenut OS — Onboarding Business Logic Controller (Phase 5 Layer Boundary)

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/business_profile.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/services/demo_data_seeder.dart';
import 'package:serenutos/presentation/pages/onboarding/onboarding_state.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';

String _hashPin(String pin) {
  final bytes = utf8.encode(pin);
  return sha256.convert(bytes).toString();
}

class OnboardingController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  OnboardingController(this._ref) : super(const AsyncValue.data(null));

  Future<List<String>> saveOnboardingData({
    required OnboardingState onboardingState,
    required void Function(String status) onStatusUpdate,
  }) async {
    state = const AsyncValue.loading();
    final prefs = _ref.read(sharedPreferencesProvider);

    onStatusUpdate('Hesabınız oluşturuluyor...');
    final rawPassword = onboardingState.admin.password;
    final apiClient = _ref.read(apiClientProvider);
    final registration = await apiClient.post('/auth/register', {
      'company_name': onboardingState.business.businessName,
      'name': onboardingState.admin.adminFullName,
      'email': onboardingState.admin.username,
      'password': rawPassword,
      'phone': onboardingState.business.phone,
      'tax_number': onboardingState.business.taxNumber,
      'city': onboardingState.business.city,
      'district': onboardingState.business.district,
      'address': '${onboardingState.business.district}, ${onboardingState.business.city}',
      'accept_terms': true,
      'accept_privacy': true,
      'accept_kvkk': true,
      'accept_marketing': false,
    });
    if (!registration.isSuccess) {
      throw Exception(
        registration.json['error']?['message'] ?? 'Sunucu kayıt hatası.',
      );
    }
    final recoveryCodes =
        (registration.json['recovery_codes'] as List<dynamic>? ?? const [])
            .map((code) => code.toString())
            .toList(growable: false);
    if (recoveryCodes.length != 10) {
      throw StateError(
          'Kurtarma kodları oluşturulamadı. Kayıt güvenle tamamlanamadı.');
    }

    await _ref.read(authNotifierProvider.notifier).login(
          onboardingState.admin.username,
          rawPassword,
        );
    debugPrint('Onboarding: Sunucu kaydı ve cihaz aktivasyonu başarılı');

    // 1. Admin kimlik bilgileri
    onStatusUpdate('Yerel ayarlar kaydediliyor...');
    final pinHash = _hashPin(onboardingState.admin.pin);
    await prefs.setString('admin_username', onboardingState.admin.username);
    await prefs.setString('admin_full_name', onboardingState.admin.adminFullName);

    // 2. İşletme profili
    final profileRepo = _ref.read(businessProfileRepositoryProvider);
    final profile = BusinessProfile(
      name: onboardingState.business.businessName,
      ownerName: onboardingState.business.ownerName,
      type: onboardingState.business.businessType,
      phone: onboardingState.business.phone,
      email: onboardingState.business.email.isEmpty ? null : onboardingState.business.email,
      taxNumber:
          onboardingState.business.taxNumber.isEmpty ? null : onboardingState.business.taxNumber,
      city: onboardingState.business.city,
      district: onboardingState.business.district,
      currency: onboardingState.business.currency,
      taxIncluded: onboardingState.business.taxIncluded,
      logoPath: onboardingState.business.logoPath,
      createdAt: DateTime.now(),
    );
    await profileRepo.saveProfile(profile);

    // 3. Settings tablosu
    final settingsRepo = await _ref.read(settingsRepositoryProvider.future);
    await settingsRepo.updateSettings(Settings(
      adminPinCode: pinHash,
      businessName: onboardingState.business.businessName,
      businessPhone: onboardingState.business.phone,
      businessAddress: '${onboardingState.business.district}, ${onboardingState.business.city}',
      businessTaxId:
          onboardingState.business.taxNumber.isEmpty ? null : onboardingState.business.taxNumber,
      businessLogo: onboardingState.business.logoPath,
      ownerName: onboardingState.business.ownerName,
      businessEmail: onboardingState.business.email.isEmpty ? null : onboardingState.business.email,
      businessCity: onboardingState.business.city,
      businessDistrict: onboardingState.business.district,
      businessType: onboardingState.business.businessType,
      currency: onboardingState.business.currency,
      createdAt: DateTime.now(),
    ));

    // 4. Demo kurulum
    onStatusUpdate('Kurulum modu uygulanıyor...');
    if (onboardingState.initialData.isDemo) {
      await DemoDataSeeder(
        productRepository: await _ref.read(productRepositoryProvider.future),
        customerRepository: await _ref.read(customerRepositoryProvider.future),
        orderRepository: await _ref.read(orderRepositoryProvider.future),
        saleRepository: await _ref.read(saleRepositoryProvider.future),
      ).seed(businessType: onboardingState.business.businessType);
    }

    state = const AsyncValue.data(null);
    return recoveryCodes;
  }

  Future<void> performBootstrapSync(void Function(double progress, String status) onProgress) async {
    final bootstrapService = _ref.read(bootstrapSyncServiceProvider);
    await bootstrapService.runBootstrap(onProgress);
  }
}

final onboardingControllerProvider =
    StateNotifierProvider<OnboardingController, AsyncValue<void>>((ref) {
  return OnboardingController(ref);
});
