// lib/presentation/pages/paywall_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/repository_providers.dart';
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
  LicenseTier _selectedTier = LicenseTier.pro; // Default selection
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

  Future<void> _purchaseSubscription() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final billingRepo = ref.read(billingRepositoryProvider);
      
      // Determine plan code
      final planId = _selectedTier == LicenseTier.basic 
          ? 'plan-basic' 
          : (_selectedTier == LicenseTier.pro ? 'plan-pro' : 'plan-enterprise');

      // Request checkout session URL from Server
      final checkoutUrl = await billingRepo.startSubscription(planId);
      
      // Launch webview sim
      final uri = Uri.parse('https://serenut.com$checkoutUrl');
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        setState(() {
          _successMessage = 'Ödeme sayfası tarayıcınızda açıldı. Ödemeyi tamamladıktan sonra lisansınız otomatik aktif olacaktır.';
        });
      } else {
        throw Exception('Ödeme sayfası açılamadı.');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Ödeme başlatma hatası: $e';
      });
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
                                    ? 'Deneme Süreniz Sona Erdi! Devam etmek için lisans anahtarınızı girin veya satın alın.'
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

                      // Packages Selection Header
                      const Text(
                        'İşletmeniz İçin Koruma Planı Seçin',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Nutoplano Serenut OS ile veri kayıplarını ve finansal riskleri sıfıra indirin.',
                        style: TextStyle(
                          color: _kTextMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Package Cards
                      _buildPackageCard(
                        tier: LicenseTier.basic,
                        title: 'BASIC (Temel POS - 450 TL/Ay)',
                        desc: 'Günlük perakende satış ve stok takibi',
                        features: [
                          'Temel veresiye & nakit satışı',
                          'Müşteri & ürün katalog yönetimi',
                          'Maksimum 2 aktif cihaz desteği',
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildPackageCard(
                        tier: LicenseTier.pro,
                        title: 'PRO (Ledger Bütünlüğü - 950 TL/Ay)',
                        desc: 'Finansal risk koruması ve resmi raporlama',
                        features: [
                          'Drift korumalı bank-grade ledger bütünlüğü',
                          'Resmi PDF banka ekstresi & Excel çıktıları',
                          'Müşterilere otomatik SMS bakiye bildirimleri',
                          'Maksimum 5 aktif cihaz desteği',
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildPackageCard(
                        tier: LicenseTier.proPlus,
                        title: 'ENTERPRISE (Sınırsız - 2450 TL/Ay)',
                        desc: 'Tam kontrol, izleme ve kurtarma araçları',
                        features: [
                          'Multi-device otomatik bulut senkronizasyonu',
                          'Çakışma çözümleme paneli (conflict resolution)',
                          'Yazıcı ve SMS kuyruğu arka plan denetimleri',
                          'Sistem observability telemetrisi & audit logs',
                          'Maksimum 99 aktif cihaz desteği',
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Purchase Button
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _purchaseSubscription,
                        icon: const Icon(Icons.credit_card_rounded),
                        label: const Text('Kredi Kartı ile Satın Al / Yenile'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 24),

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

  Widget _buildPackageCard({
    required LicenseTier tier,
    required String title,
    required String desc,
    required List<String> features,
  }) {
    final isSelected = _selectedTier == tier;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTier = tier;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F2D24) : const Color(0xFF0F172A),
          border: Border.all(
            color: isSelected ? _kPrimary : const Color(0xFF1E293B),
            width: isSelected ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      style: const TextStyle(
                        color: _kTextMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isSelected ? _kPrimary : _kTextMuted,
                  size: 20,
                ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF1E293B), height: 1),
              const SizedBox(height: 10),
              ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: _kPrimary, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }
}
