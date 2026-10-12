// lib/presentation/pages/onboarding/onboarding_wizard_page.dart
// Serenut OS — Ana Onboarding Wizard Konteyner
// Sub-route tabanlı wizard: /onboarding → /onboarding/business → /onboarding/admin → /onboarding/success

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/pages/onboarding/onboarding_state.dart';
import 'package:serenutos/presentation/pages/onboarding/steps/step1_business_info.dart';
import 'package:serenutos/presentation/pages/onboarding/steps/step2_admin_account.dart';
import 'package:serenutos/presentation/pages/onboarding/steps/step3_success.dart';
import 'package:serenutos/presentation/pages/onboarding/license_activation_flow.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/presentation/controllers/onboarding_controller.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';

import 'package:serenutos/presentation/widgets/app_notification_host.dart';
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

  void _onComplete(BusinessInfo info, InitialDataSetup initialSetup) {
    final updated = _state.copyWith(business: info, initialData: initialSetup);
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
      initialSetup: _state.initialData,
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
  String _savingStatus = 'Kurulum tamamlanıyor...';

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
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Kodları Kopyala'),
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: recoveryCodes.join('\n')));
                AppNotificationHost.show(
                  const SnackBar(
                    content: Text('Kurtarma kodları panoya kopyalandı!'),
                    backgroundColor: POSColors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Kodları Kaydettim ve Devam Et'),
            ),
          ],
        ),
      );

      if (mounted) context.go('/onboarding/success');
    } catch (e) {
      if (mounted) {
        AppNotificationHost.show(
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

  void _setSavingStatus(String status) {
    if (mounted) setState(() => _savingStatus = status);
  }

  Future<List<String>> _saveOnboardingData(OnboardingState state) async {
    final recoveryCodes = await ref
        .read(onboardingControllerProvider.notifier)
        .saveOnboardingData(
          onboardingState: state,
          onStatusUpdate: _setSavingStatus,
        );
    _setSavingStatus('Kurulum tamamlanıyor...');
    await _persistence.markCompleted();
    return recoveryCodes;
  }

  @override
  Widget build(BuildContext context) {
    if (_saving) {
      return Scaffold(
        backgroundColor: POSColors.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: POSColors.green),
              const SizedBox(height: 20),
              Text(_savingStatus,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
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
