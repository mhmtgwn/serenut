// lib/presentation/pages/paywall_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:url_launcher/url_launcher.dart';

const _kPrimary = Color(0xFF10B981); // Emerald Green
const _kBackground = Color(0xFF0F172A); // Slate 900
const _kCardBg = Color(0xFF1E293B); // Slate 800
const _kTextMuted = Color(0xFF94A3B8); // Slate 400

class PaywallPage extends ConsumerStatefulWidget {
  const PaywallPage({super.key});

  @override
  ConsumerState<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends ConsumerState<PaywallPage> {
  final _tokenCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _activateLicense() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final licenseService = ref.read(licenseServiceProvider);
      final token = _tokenCtrl.text.trim();
      
      final isValid = licenseService.verifyLicenseToken(token);
      if (!isValid) {
        throw Exception('Geçersiz lisans anahtarı.');
      }

      // Save to local storage
      await licenseService.saveLicenseToken(token);

      setState(() {
        _successMessage = 'Lisans başarıyla etkinleştirildi! Yönlendiriliyorsunuz...';
      });

      // Delay briefly to show success state then route to login
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        context.go('/login');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _launchWebUrl(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Tarayıcı açılamadı.');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Bağlantı açılamadı: $e';
      });
    }
  }

  Future<void> _handleLogout() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).logout();
      if (mounted) {
        context.go('/login');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Çıkış yapılırken hata oluştu.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceId = ref.watch(deviceManagerProvider).getDeviceId();
    final remainingDays = ref.watch(trialManagerProvider).getRemainingDays();
    final isTrialExpired = remainingDays <= 0;

    return Scaffold(
      backgroundColor: _kBackground,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              color: _kCardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
                side: const BorderSide(color: Color(0xFF334155), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Logo
                      const Center(
                        child: Text(
                          '🌿 SERENUT OS',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _kPrimary,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Status Alert Banner
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isTrialExpired
                              ? const Color(0xFF7F1D1D)
                              : const Color(0xFF064E3B),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isTrialExpired ? Icons.warning : Icons.info,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                isTrialExpired
                                    ? 'Deneme Süreniz Sona Erdi! Devam etmek için lisans anahtarınızı girin veya web sitemizden satın alın.'
                                    : 'Deneme Süreniz Aktif ($remainingDays gün kaldı).',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Website Information Text
                      const Text(
                        'Lisans ve Abonelik İşlemleri',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Lisans satın alma, yenileme ve hesap yönetimi işlemleri güvenliğiniz için Serenut web sitesi üzerinden gerçekleştirilmektedir.',
                        style: TextStyle(
                          color: _kTextMuted,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Web site actions
                      ElevatedButton.icon(
                        onPressed: () => _launchWebUrl('https://serenut.com/portal/'),
                        icon: const Icon(Icons.shopping_bag_rounded),
                        label: const Text('Lisans Satın Al / Yenile (Web)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Secondary actions on Web
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _launchWebUrl('https://serenut.com/portal/#register'),
                              icon: const Icon(Icons.person_add_rounded, size: 18),
                              label: const Text('Kayıt Ol'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Color(0xFF475569)),
                                padding: const EdgeInsets.symmetric(vertical: 12.0),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _launchWebUrl('https://serenut.com/portal/#reset'),
                              icon: const Icon(Icons.lock_reset_rounded, size: 18),
                              label: const Text('Şifremi Unuttum'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Color(0xFF475569)),
                                padding: const EdgeInsets.symmetric(vertical: 12.0),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(color: Color(0xFF334155)),
                      const SizedBox(height: 16),

                      // Activation Token Input
                      const Text(
                        'Lisans Anahtarı Etkinleştirme',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _tokenCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Örn: PRO-XXXX-XXXX-XXXX',
                          hintStyle: const TextStyle(color: _kTextMuted),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: const BorderSide(color: Color(0xFF475569)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Lütfen lisans anahtarını girin.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Error message display
                      if (_errorMessage != null) ...[
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Success message display
                      if (_successMessage != null) ...[
                        Text(
                          _successMessage!,
                          style: const TextStyle(color: _kPrimary, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Submit Button
                      ElevatedButton(
                        onPressed: _isLoading ? null : _activateLicense,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Lisansı Etkinleştir',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                      ),
                      const SizedBox(height: 16),

                      // Local logout / Switch account button
                      TextButton.icon(
                        onPressed: _isLoading ? null : _handleLogout,
                        icon: const Icon(Icons.exit_to_app_rounded, size: 18),
                        label: const Text('Farklı Hesapla Giriş Yap (Çıkış Yap)'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Footer Device ID
                      Center(
                        child: SelectableText(
                          'Cihaz ID: $deviceId',
                          style: const TextStyle(
                            color: _kTextMuted,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
