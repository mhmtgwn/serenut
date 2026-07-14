// lib/presentation/pages/onboarding/steps/step1_business_info.dart
// Adım 1 — İşletme Bilgileri + İşletme Türü (3-adımlı akışın ilk adımı)
// Premium kart bazlı tasarım, JSON'dan il/ilçe yükleme, işletme türü grid

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/pages/onboarding/onboarding_state.dart';
import 'package:serenutos/presentation/pages/onboarding/widgets/step_indicator.dart';

// İşletme türleri
const List<_BusinessType> _businessTypes = [
  _BusinessType(icon: Icons.store_rounded, label: 'Market'),
  _BusinessType(icon: Icons.coffee_rounded, label: 'Kafe'),
  _BusinessType(icon: Icons.grass_rounded, label: 'Kuruyemişçi'),
];

class _BusinessType {
  final IconData icon;
  final String label;
  const _BusinessType({required this.icon, required this.label});
}

class Step1BusinessInfo extends StatefulWidget {
  final BusinessInfo initialData;
  final void Function(BusinessInfo data) onComplete;

  const Step1BusinessInfo({
    super.key,
    required this.initialData,
    required this.onComplete,
  });

  @override
  State<Step1BusinessInfo> createState() => _Step1BusinessInfoState();
}

class _Step1BusinessInfoState extends State<Step1BusinessInfo> {
  final _formKey = GlobalKey<FormState>();
  late BusinessInfo _data;

  // Controllers
  late final TextEditingController _businessNameCtrl;
  late final TextEditingController _ownerNameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _taxNoCtrl;
  late final TextEditingController _emailCtrl;

  List<String> _cities = [];
  List<String> _districts = [];
  bool _citiesLoaded = false;
  Map<String, List<String>> _cityMap = {};

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;
    _businessNameCtrl = TextEditingController(text: _data.businessName);
    _ownerNameCtrl = TextEditingController(text: _data.ownerName);
    _phoneCtrl = TextEditingController(text: _data.phone);
    _taxNoCtrl = TextEditingController(text: _data.taxNumber);
    _emailCtrl = TextEditingController(text: _data.email);
    _loadCities();
  }

  Future<void> _loadCities() async {
    try {
      final raw = await rootBundle.loadString('assets/data/cities.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final countries = json['countries'] as List<dynamic>;
      final tr = countries.firstWhere(
        (c) => (c as Map<String, dynamic>)['code'] == 'TR',
        orElse: () => null,
      );
      if (tr != null) {
        final cityList =
            (tr as Map<String, dynamic>)['cities'] as List<dynamic>;
        final Map<String, List<String>> cityMap = {};
        for (final c in cityList) {
          final name = (c as Map<String, dynamic>)['name'] as String;
          final districts = (c['districts'] as List<dynamic>).cast<String>();
          cityMap[name] = districts;
        }
        setState(() {
          _cityMap = cityMap;
          _cities = cityMap.keys.toList()..sort();
          _citiesLoaded = true;
          // Eğer önceden seçilmiş şehir varsa ilçeleri yükle
          if (_data.city.isNotEmpty && cityMap.containsKey(_data.city)) {
            _districts = cityMap[_data.city]!;
          }
        });
      }
    } catch (e) {
      debugPrint('Şehir verisi yüklenemedi: $e');
    }
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _phoneCtrl.dispose();
    _taxNoCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _onCityChanged(String? city) {
    if (city == null) return;
    setState(() {
      _data = _data.copyWith(city: city, district: '');
      _districts = _cityMap[city] ?? [];
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_data.businessType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen işletme türünü seçin'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    widget.onComplete(_data.copyWith(
      businessName: _businessNameCtrl.text.trim(),
      ownerName: _ownerNameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      taxNumber: _taxNoCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 600;

    return Scaffold(
      backgroundColor: POSColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────
            _OnboardingHeader(
              title: 'İşletme Bilgileri',
              stepLabel: 'Adım 1 / 3',
              currentStep: 0,
              onBack: () => context.go('/onboarding'),
            ),

            // ── Content ──────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? size.width * 0.15 : 20,
                  vertical: 8,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // İşletme Bilgileri Kartı
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionTitle(
                                icon: Icons.business_rounded,
                                text: 'İşletme Bilgileri'),
                            const SizedBox(height: 16),
                            _Field(
                              controller: _businessNameCtrl,
                              label: 'İşletme Adı',
                              hint: 'örn. Seren Market',
                              icon: Icons.store_rounded,
                              required: true,
                              validator: (v) => (v?.trim().isEmpty ?? true)
                                  ? 'İşletme adı gerekli'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            _Field(
                              controller: _ownerNameCtrl,
                              label: 'Yetkili Adı Soyadı',
                              hint: 'Ad Soyad',
                              icon: Icons.person_rounded,
                              required: true,
                              validator: (v) => (v?.trim().isEmpty ?? true)
                                  ? 'Yetkili adı gerekli'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            _Field(
                              controller: _phoneCtrl,
                              label: 'Telefon',
                              hint: '0(5XX) XXX XX XX',
                              icon: Icons.phone_rounded,
                              required: true,
                              keyboard: TextInputType.phone,
                              validator: (v) {
                                if (v?.trim().isEmpty ?? true)
                                  return 'Telefon gerekli';
                                if ((v?.trim().length ?? 0) < 10)
                                  return 'Geçerli bir numara girin';
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            _Field(
                              controller: _taxNoCtrl,
                              label: 'Vergi No',
                              hint: '1234567890',
                              icon: Icons.badge_rounded,
                              required: true,
                              keyboard: TextInputType.number,
                              validator: (v) => (v?.trim().isEmpty ?? true)
                                  ? 'Vergi no gerekli (fişe yazılır)'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            _Field(
                              controller: _emailCtrl,
                              label: 'E-posta (isteğe bağlı)',
                              hint: 'ornek@isletme.com',
                              icon: Icons.email_outlined,
                              keyboard: TextInputType.emailAddress,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Konum Kartı
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionTitle(
                                icon: Icons.location_on_rounded, text: 'Konum'),
                            const SizedBox(height: 16),
                            // İl dropdown
                            _DropdownField<String>(
                              label: 'İl',
                              icon: Icons.map_rounded,
                              value: _data.city.isEmpty ? null : _data.city,
                              items: _cities
                                  .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c)))
                                  .toList(),
                              onChanged: _onCityChanged,
                              hint:
                                  _citiesLoaded ? 'İl seçin' : 'Yükleniyor...',
                            ),
                            const SizedBox(height: 12),
                            // İlçe dropdown
                            _DropdownField<String>(
                              label: 'İlçe',
                              icon: Icons.location_city_rounded,
                              value: _data.district.isEmpty
                                  ? null
                                  : _data.district,
                              items: _districts
                                  .map((d) => DropdownMenuItem(
                                      value: d, child: Text(d)))
                                  .toList(),
                              onChanged: _districts.isEmpty
                                  ? null
                                  : (d) => setState(() =>
                                      _data = _data.copyWith(district: d)),
                              hint: _data.city.isEmpty
                                  ? 'Önce il seçin'
                                  : 'İlçe seçin',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Para & KDV Kartı
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionTitle(
                                icon: Icons.payments_rounded,
                                text: 'Para & Fiyatlandırma'),
                            const SizedBox(height: 16),
                            _DropdownField<String>(
                              label: 'Para Birimi',
                              icon: Icons.currency_exchange_rounded,
                              value: _data.currency,
                              items: const [
                                DropdownMenuItem(
                                    value: '₺', child: Text('₺ — Türk Lirası')),
                                DropdownMenuItem(
                                    value: '\$', child: Text('\$ — Dolar')),
                                DropdownMenuItem(
                                    value: '€', child: Text('€ — Euro')),
                                DropdownMenuItem(
                                    value: '£', child: Text('£ — Sterlin')),
                              ],
                              onChanged: (v) => setState(
                                  () => _data = _data.copyWith(currency: v)),
                            ),
                            const SizedBox(height: 12),
                            _SwitchTile(
                              icon: Icons.receipt_long_rounded,
                              title: 'Vergi Dahil Fiyat',
                              subtitle: 'Ürün fiyatları KDV dahil gösterilsin',
                              value: _data.taxIncluded,
                              onChanged: (v) => setState(
                                  () => _data = _data.copyWith(taxIncluded: v)),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // İşletme Türü Kartı
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionTitle(
                                icon: Icons.category_rounded,
                                text: 'İşletme Türü'),
                            const SizedBox(height: 4),
                            Text('İşletmenizi en iyi tanımlayan türü seçin',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: POSColors.textSecondary)),
                            const SizedBox(height: 16),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 1.0,
                              ),
                              itemCount: _businessTypes.length,
                              itemBuilder: (_, i) {
                                final bt = _businessTypes[i];
                                final selected = _data.businessType == bt.label;
                                return _BusinessTypeCard(
                                  icon: bt.icon,
                                  label: bt.label,
                                  selected: selected,
                                  onTap: () => setState(
                                    () => _data =
                                        _data.copyWith(businessType: bt.label),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ),

            // ── Sonraki Butonu ────────────────────────────────────────────
            _BottomButton(label: 'Sonraki', onTap: _submit),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// İşletme türü kartı
// ─────────────────────────────────────────────────────────────────────────────
class _BusinessTypeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BusinessTypeCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: selected ? POSColors.green : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? POSColors.green : POSColors.border,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: POSColors.green.withValues(alpha: 0.2),
                      blurRadius: 8,
                      spreadRadius: 1)
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 28,
                color: selected ? Colors.white : POSColors.textSecondary),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : POSColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ortak widget'lar (bu dosyaya özgü)
// ─────────────────────────────────────────────────────────────────────────────

class _OnboardingHeader extends StatelessWidget {
  final String title;
  final String stepLabel;
  final int currentStep;
  final VoidCallback? onBack;

  const _OnboardingHeader({
    required this.title,
    required this.stepLabel,
    required this.currentStep,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: [
          Row(
            children: [
              if (onBack != null)
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  color: POSColors.text,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              else
                const SizedBox(width: 24),
              const Spacer(),
              Text(stepLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    color: POSColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  )),
              const Spacer(),
              const SizedBox(width: 24),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: StepIndicator(totalSteps: 3, currentStep: currentStep),
          ),
          const SizedBox(height: 14),
          Text(title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800, color: POSColors.text)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: POSColors.border),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionTitle({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: POSColors.greenLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 17, color: POSColors.green),
        ),
        const SizedBox(width: 10),
        Text(text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: POSColors.text,
            )),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool required;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.required = false,
    this.keyboard,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      validator: validator,
      style: const TextStyle(fontSize: 15, color: POSColors.text),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: POSColors.textSecondary),
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?)? onChanged;
  final String? hint;

  const _DropdownField({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      style: const TextStyle(fontSize: 15, color: POSColors.text),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: POSColors.textSecondary),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: POSColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: POSColors.text)),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 12, color: POSColors.textSecondary)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _BottomButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _BottomButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: POSColors.green,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
