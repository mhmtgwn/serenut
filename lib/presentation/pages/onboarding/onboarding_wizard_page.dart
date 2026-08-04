// lib/presentation/pages/onboarding/onboarding_wizard_page.dart
// Serenut OS — Ana Onboarding Wizard Konteyner
// Sub-route tabanlı wizard: /onboarding → /onboarding/business → /onboarding/admin → /onboarding/success

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/models/business_profile.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_business_profile_repository.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_settings_repository.dart';
import 'package:serenutos/presentation/pages/onboarding/onboarding_state.dart';
import 'package:serenutos/presentation/pages/onboarding/steps/step1_business_info.dart';
import 'package:serenutos/presentation/pages/onboarding/steps/step2_admin_account.dart';
import 'package:serenutos/presentation/pages/onboarding/steps/step3_success.dart';
import 'package:serenutos/presentation/pages/onboarding/license_activation_flow.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:serenutos/domain/models/industry_template.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Step wrappers — GoRouter route builder'larında kullanılan widget'lar
// ─────────────────────────────────────────────────────────────────────────────

/// İşletme bilgileri adımı
class OnboardingStep1Page extends ConsumerStatefulWidget {
  const OnboardingStep1Page({super.key});

  @override
  ConsumerState<OnboardingStep1Page> createState() =>
      _OnboardingStep1PageState();
}

class _OnboardingStep1PageState extends ConsumerState<OnboardingStep1Page> {
  OnboardingState _state = const OnboardingState();
  late OnboardingPersistence _persistence;
  bool _loading = true; // Sunucudan veri çekiliyor

  @override
  void initState() {
    super.initState();
    _loadAndMaybeSkip();
  }

  Future<void> _loadAndMaybeSkip() async {
    final prefs = ref.read(sharedPreferencesProvider);
    _persistence = OnboardingPersistence(prefs);
    var loadedState = _persistence.loadState();

    // VPS'ten şirket bilgisini çek
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.get('/api/v1/company');
      if (response.isSuccess && response.json != null) {
        final map = response.json as Map<String, dynamic>;
        final serverName = map['name'] as String? ?? '';
        if (serverName.trim().isNotEmpty) {
          // Şirket bilgileri VPS'te kayıtlı → state'i doldur
          final serverBusiness = BusinessInfo(
            businessName: serverName,
            ownerName: map['owner_name'] as String? ?? '',
            phone: map['phone'] as String? ?? '',
            taxNumber: map['tax_number'] as String? ?? '',
            email: map['email'] as String? ?? '',
            city: map['city'] as String? ?? '',
            district: map['district'] as String? ?? '',
            businessType: map['type'] as String? ?? '',
          );
          loadedState = loadedState.copyWith(business: serverBusiness);
          _persistence.saveState(loadedState);
          _persistence.saveStep(2);

          // Adımı atla — kullanıcının tekrar girmesine gerek yok
          if (mounted) context.go('/onboarding/admin');
          return;
        }
      }
    } catch (_) {
      // Çevrimdışı veya hata: kullanıcı manuel girer
    }

    if (mounted) {
      setState(() {
        _state = loadedState;
        _loading = false;
      });
    }
  }

  void _onComplete(BusinessInfo info) {
    final updated = _state.copyWith(business: info);
    _persistence.saveState(updated);
    _persistence.saveStep(2);
    context.go('/onboarding/admin');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Step1BusinessInfo(
      initialData: _state.business,
      onComplete: _onComplete,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Admin hesabı adımı

// ─────────────────────────────────────────────────────────────────────────────
class OnboardingStep2Page extends ConsumerStatefulWidget {
  const OnboardingStep2Page({super.key});

  @override
  ConsumerState<OnboardingStep2Page> createState() =>
      _OnboardingStep2PageState();
}

class _OnboardingStep2PageState extends ConsumerState<OnboardingStep2Page> {
  OnboardingState _state = const OnboardingState();
  late OnboardingPersistence _persistence;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final prefs = ref.read(sharedPreferencesProvider);
    _persistence = OnboardingPersistence(prefs);
    setState(() => _state = _persistence.loadState());
  }

  Future<void> _onComplete(AdminInfo adminInfo) async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final updated = _state.copyWith(admin: adminInfo);
      _persistence.saveState(updated);
      _persistence.saveStep(3);

      final recoveryCodes = await _saveOnboardingData(updated);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Kurtarma kodlarınızı saklayın'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Bu kodlar yalnızca şimdi gösterilir ve her biri tek kullanımlıktır.'),
                const SizedBox(height: 12),
                SelectableText(recoveryCodes.join('\n')),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Kodları Kaydettim'),
            ),
          ],
        ),
      );

      if (mounted) context.go('/onboarding/success');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kayıt hatası: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<List<String>> _saveOnboardingData(OnboardingState state) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final dbManager = DatabaseManager();
    final gateway = DbGatewayImpl(dbManager);

    // The server owns account, tenant and device entitlement creation.  Do this
    // before persisting a local business so a failed registration cannot leave a
    // device that looks configured but has no tenant to sync with.
    final rawPassword = state.admin.password;
    final apiClient = ref.read(apiClientProvider);
    final registration = await apiClient.post('/auth/register', {
      'company_name': state.business.businessName,
      'name': state.admin.adminFullName,
      'email': state.admin.username,
      'password': rawPassword,
      'phone': state.business.phone,
      'tax_number': state.business.taxNumber,
      'city': state.business.city,
      'district': state.business.district,
      'address': '${state.business.district}, ${state.business.city}',
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

    // Login establishes the authenticated session, subscription cache and the
    // canonical device activation through /auth/session-bootstrap.
    await ref.read(authServiceProvider).login(
          state.admin.username,
          rawPassword,
        );
    debugPrint('Onboarding: Sunucu kaydı ve cihaz aktivasyonu başarılı');

    // 1. Admin kimlik bilgilerini kaydet
    // PIN: SQLite settings tablosuna yaz (tek kaynak)
    final pinHash = _hashPin(state.admin.pin);
    // Write admin PIN to SQLite settings table (single source of truth)
    final db = await dbManager.getDatabase();
    final existingSettings = await db.query('settings', limit: 1);
    if (existingSettings.isNotEmpty) {
      await db.update('settings', {
        'admin_pin_code': pinHash,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
    await prefs.setString('admin_username', state.admin.username);
    await prefs.setString('admin_full_name', state.admin.adminFullName);
    // Güvenlik Düzeltmesi: admin_password_hash SharedPreferences'a SHA-256 olarak kaydedilmez.

    // 2. İşletme profilini DB'ye kaydet
    final profileRepo = SqliteBusinessProfileRepository(gateway);
    final profile = BusinessProfile(
      name: state.business.businessName,
      ownerName: state.business.ownerName,
      type: state.business.businessType,
      phone: state.business.phone,
      email: state.business.email.isEmpty ? null : state.business.email,
      taxNumber:
          state.business.taxNumber.isEmpty ? null : state.business.taxNumber,
      city: state.business.city,
      district: state.business.district,
      currency: state.business.currency,
      taxIncluded: state.business.taxIncluded,
      logoPath: state.business.logoPath,
      createdAt: DateTime.now(),
    );
    await profileRepo.saveProfile(profile);

    // 3. Settings tablosuna kaydet
    final settingsRepo = SqliteSettingsRepository(gateway);
    await settingsRepo.updateSettings(Settings(
      businessName: state.business.businessName,
      businessPhone: state.business.phone,
      businessAddress: '${state.business.district}, ${state.business.city}',
      businessTaxId:
          state.business.taxNumber.isEmpty ? null : state.business.taxNumber,
      businessLogo: state.business.logoPath,
      ownerName: state.business.ownerName,
      businessEmail: state.business.email.isEmpty ? null : state.business.email,
      businessCity: state.business.city,
      businessDistrict: state.business.district,
      businessType: state.business.businessType,
      currency: state.business.currency,
      createdAt: DateTime.now(),
    ));
    // 4. Sektör şablonundaki ürünleri SQLite'a tohumla (seed)
    final template =
        IndustryTemplateRegistry.getTemplate(state.business.businessType);
    if (template != null) {
      final productRepo = SqliteProductRepository(gateway);
      for (final p in template.products) {
        final barcode = p.barcode ?? 'BAR-${p.name.hashCode.abs()}';
        await productRepo.create(ProductEntity(
          id: barcode,
          name: p.name,
          description: '${p.category} kategorisinden hazır ürün.',
          price: p.price,
          quantity: 100,
          category: p.category,
          vat: p.vatRate.toInt(),
        ));
      }
    }

    // 5. Onboarding tamamlandı
    await _persistence.markCompleted();
    return recoveryCodes;
  }

  /// Basit PIN hash'leme (HMAC-SHA256)
  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_saving) {
      return const Scaffold(
        backgroundColor: POSColors.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: POSColors.green),
              SizedBox(height: 20),
              Text('Kurulum tamamlanıyor...',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: POSColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    return Step2AdminAccount(
      initialData: _state.admin,
      onComplete: _onComplete,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Başarı ekranı
// ─────────────────────────────────────────────────────────────────────────────
class OnboardingSuccessPage extends ConsumerStatefulWidget {
  const OnboardingSuccessPage({super.key});

  @override
  ConsumerState<OnboardingSuccessPage> createState() =>
      _OnboardingSuccessPageState();
}

class _OnboardingSuccessPageState extends ConsumerState<OnboardingSuccessPage> {
  OnboardingState _state = const OnboardingState();
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final persistence = OnboardingPersistence(prefs);
    final trialManager = ref.read(trialManagerProvider);
    final expiry = await trialManager.getExpiryDate() ??
        DateTime.now().add(const Duration(days: 30));
    if (mounted) {
      setState(() {
        _state = persistence.loadState();
        _expiryDate = expiry;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Step3Success(
      state: _state,
      trialExpiryDate: _expiryDate,
      appVersion: '1.0.0',
      onLaunch: () => context.go('/onboarding/bootstrap'),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Lisans aktivasyon sayfası (onboarding içinden)
// ─────────────────────────────────────────────────────────────────────────────
class OnboardingLicensePage extends StatelessWidget {
  const OnboardingLicensePage({super.key});

  @override
  Widget build(BuildContext context) {
    return LicenseActivationFlow(
      onLicenseActivated: (key, type) {
        context.go('/onboarding/business');
      },
    );
  }
}
