// lib/presentation/pages/register_page.dart
// Serenut OS — Hesap Oluştur (Web Sitesiyle Uyumlu Açık Tema)
// Fiş bilgileri: İşletme adı, telefon, şehir/ilçe, vergi no → ZORUNLU
// Logo: opsiyonel (boş = Serenut varsayılan logosu)
// Web portalıyla tutarlı: e-posta + kullanıcı adı zorunlu

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/domain/models/business_profile.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_business_profile_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_settings_repository.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/providers/database_provider.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/config/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sayfa
// ─────────────────────────────────────────────────────────────────────────────

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();
  int _step = 0; // 0 = Hesap bilgileri, 1 = İşletme bilgileri

  // ── Sayfa 0: Hesap ──
  final _emailCtrl      = TextEditingController();
  final _usernameCtrl   = TextEditingController();
  final _passwordCtrl   = TextEditingController();
  final _password2Ctrl  = TextEditingController();
  bool _obscurePass  = true;
  bool _obscurePass2 = true;

  // ── Sayfa 1: İşletme (fiş bilgileri) ──
  final _bizNameCtrl    = TextEditingController();
  final _ownerNameCtrl  = TextEditingController();
  final _phoneCtrl      = TextEditingController();
  final _taxNoCtrl      = TextEditingController();

  String? _selectedCity;
  String? _selectedDistrict;
  String? _selectedType;
  String? _logoPath; // null = varsayılan Serenut logosu

  Map<String, List<String>> _cityMap = {};
  List<String> _cities = [];
  List<String> _districts = [];
  bool _citiesLoaded = false;

  bool _saving = false;
  String? _error;

  static const _businessTypes = [
    'Market', 'Kafe', 'Restoran', 'Kuruyemişçi', 'Pastane',
    'Büfe', 'Kasap', 'Manav', 'Eczane', 'Diğer',
  ];

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _password2Ctrl.dispose();
    _bizNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _phoneCtrl.dispose();
    _taxNoCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadCities() async {
    try {
      final raw  = await rootBundle.loadString('assets/data/cities.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final countries = json['countries'] as List<dynamic>;
      final tr = countries.firstWhere(
        (c) => (c as Map<String, dynamic>)['code'] == 'TR',
        orElse: () => null,
      );
      if (tr != null) {
        final cityList = (tr as Map<String, dynamic>)['cities'] as List<dynamic>;
        final Map<String, List<String>> map = {};
        for (final c in cityList) {
          final name      = (c as Map<String, dynamic>)['name'] as String;
          final districts = (c['districts'] as List<dynamic>).cast<String>();
          map[name]       = districts;
        }
        if (mounted) {
          setState(() {
            _cityMap      = map;
            _cities       = map.keys.toList()..sort();
            _citiesLoaded = true;
          });
        }
      }
    } catch (_) {}
  }

  // ── Adım 0 doğrulama ve geçiş ──
  void _goToStep1() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _step = 1);
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  // ── Kayıt tamamla ──
  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedCity == null) {
      setState(() => _error = 'Lütfen şehir seçin.');
      return;
    }

    setState(() { _saving = true; _error = null; });

    try {
      final gateway    = ref.read(dbGatewayProvider);
      final authService = ref.read(authServiceProvider);
      final prefs      = ref.read(sharedPreferencesProvider);

      // 1. Admin kullanıcı oluştur
      final adminUser = AuthUser(
        id:          const Uuid().v4(),
        name:        _ownerNameCtrl.text.trim(),
        email:       _emailCtrl.text.trim(),
        role:        UserRole.admin,
        permissions: AuthService.getPermissionsForRole(UserRole.admin),
        createdAt:   DateTime.now(),
      );
      await authService.createUser(adminUser, _passwordCtrl.text);
      await prefs.setString('admin_username', _usernameCtrl.text.trim());
      await prefs.setString('admin_full_name', _ownerNameCtrl.text.trim());

      // 2. İşletme profilini kaydet
      final profileRepo = SqliteBusinessProfileRepository(gateway);
      final profile = BusinessProfile(
        name:       _bizNameCtrl.text.trim(),
        ownerName:  _ownerNameCtrl.text.trim(),
        type:       _selectedType ?? '',
        phone:      _phoneCtrl.text.trim(),
        email:      _emailCtrl.text.trim(),
        taxNumber:  _taxNoCtrl.text.trim(),
        city:       _selectedCity ?? '',
        district:   _selectedDistrict ?? '',
        logoPath:   _logoPath, // null = varsayılan logo
        createdAt:  DateTime.now(),
      );
      await profileRepo.saveProfile(profile);

      // 3. Settings tablosuna da yaz (fişte kullanılır)
      final settingsRepo = SqliteSettingsRepository(gateway);
      await settingsRepo.updateSettings(Settings(
        businessName:    _bizNameCtrl.text.trim(),
        businessPhone:   _phoneCtrl.text.trim(),
        businessAddress: '${_selectedDistrict ?? ''}, ${_selectedCity ?? ''}',
        businessTaxId:   _taxNoCtrl.text.trim(),
        businessLogo:    _logoPath,
        ownerName:       _ownerNameCtrl.text.trim(),
        businessEmail:   _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        businessCity:    _selectedCity ?? '',
        businessDistrict: _selectedDistrict ?? '',
        businessType:    _selectedType ?? '',
        createdAt:       DateTime.now(),
      ));

      // 4. Backend'e kayıt (opsiyonel — network yoksa silent fail)
      try {
        final apiClient = ref.read(apiClientProvider);
        await apiClient.post('/auth/register', {
          'company_name': _bizNameCtrl.text.trim(),
          'name':         _ownerNameCtrl.text.trim(),
          'username':     _usernameCtrl.text.trim(),
          'email':        _emailCtrl.text.trim(),
          'password':     _passwordCtrl.text,
          'phone':        _phoneCtrl.text.trim(),
        });
      } catch (_) {
        // Network yoksa local'e devam
      }

      // 5. Onboarding tamamlandı + 30 gün deneme
      await prefs.setBool('serenut_onboarding_completed_v2', true);
      final trialManager = ref.read(trialManagerProvider);
      await trialManager.startTrial(DateTime.now());

      if (mounted) context.go(AppRoutes.home);
    } catch (e) {
      setState(() {
        _saving = false;
        _error  = 'Kayıt sırasında hata oluştu: $e';
      });
    }
  }

  // ── Logo seç ──
  Future<void> _pickLogo() async {
    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (img != null && mounted) {
        setState(() => _logoPath = img.path);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final size   = MediaQuery.sizeOf(context);
    final isWide = size.width > 600;

    if (_saving) {
      return Scaffold(
        backgroundColor: POSColors.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: POSColors.green),
              const SizedBox(height: 20),
              Text(
                'Hesabınız oluşturuluyor…',
                style: GoogleFonts.inter(color: POSColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: POSColors.surface,
      appBar: AppBar(
        backgroundColor: POSColors.card,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: POSColors.text, size: 18),
          onPressed: () {
            if (_step == 1) {
              setState(() => _step = 0);
              _pageController.animateToPage(0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut);
            } else {
              context.go('/login');
            }
          },
        ),
        title: Text(
          _step == 0 ? 'Hesap Oluştur' : 'İşletme Bilgileri',
          style: GoogleFonts.inter(color: POSColors.text, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: _StepBar(current: _step, total: 2),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // ─── Adım 0: Hesap Bilgileri ───
              _buildAccountStep(isWide, size),
              // ─── Adım 1: İşletme / Fiş Bilgileri ───
              _buildBusinessStep(isWide, size),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Adım 0 ───────────────────────────────────────────────────
  Widget _buildAccountStep(bool isWide, Size size) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? size.width * 0.2 : 24,
        vertical: 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionCard(
            title: 'Hesap Bilgileri',
            icon: Icons.manage_accounts_rounded,
            children: [
              _LightFormField(
                controller: _emailCtrl,
                label: 'E-posta *',
                hint: 'ahmet@market.com',
                icon: Icons.email_outlined,
                keyboard: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'E-posta zorunludur';
                  if (!v.contains('@')) return 'Geçerli bir e-posta girin';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              _LightFormField(
                controller: _usernameCtrl,
                label: 'Kullanıcı Adı *',
                hint: 'kullanici_adi',
                icon: Icons.person_outline_rounded,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Kullanıcı adı zorunludur';
                  if (v.trim().length < 3) return 'En az 3 karakter olmalı';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              _LightFormField(
                controller: _passwordCtrl,
                label: 'Şifre *',
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePass,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: POSColors.textSecondary, size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Şifre zorunludur';
                  if (v.length < 6) return 'En az 6 karakter olmalı';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              _LightFormField(
                controller: _password2Ctrl,
                label: 'Şifre Tekrar *',
                hint: '••••••••',
                icon: Icons.lock_rounded,
                obscureText: _obscurePass2,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePass2 ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: POSColors.textSecondary, size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePass2 = !_obscurePass2),
                ),
                validator: (v) {
                  if (v != _passwordCtrl.text) return 'Şifreler eşleşmiyor';
                  return null;
                },
              ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            _ErrorBox(message: _error!),
          ],

          const SizedBox(height: 28),
          _GreenButton(
            label: 'İleri — İşletme Bilgileri',
            icon: Icons.arrow_forward_rounded,
            onTap: _goToStep1,
          ),
          const SizedBox(height: 20),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Hesabınız var mı? ',
                    style: GoogleFonts.inter(color: POSColors.textSecondary, fontSize: 13)),
                GestureDetector(
                  onTap: () => context.go('/login/form'),
                  child: Text('Giriş Yap',
                      style: GoogleFonts.inter(
                        color: POSColors.green, fontSize: 13,
                        fontWeight: FontWeight.w700,
                      )),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Adım 1 ───────────────────────────────────────────────────
  Widget _buildBusinessStep(bool isWide, Size size) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? size.width * 0.2 : 24,
        vertical: 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Fiş zorunlu bilgiler ──
          _SectionCard(
            title: 'Fiş Bilgileri (Zorunlu)',
            icon: Icons.receipt_long_rounded,
            subtitle: 'Bu bilgiler fişe yazılır.',
            children: [
              _LightFormField(
                controller: _bizNameCtrl,
                label: 'İşletme Adı *',
                hint: 'ABC Market',
                icon: Icons.storefront_rounded,
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'İşletme adı zorunludur' : null,
              ),
              const SizedBox(height: 14),
              _LightFormField(
                controller: _ownerNameCtrl,
                label: 'Yetkili Adı Soyadı *',
                hint: 'Ahmet Yılmaz',
                icon: Icons.person_rounded,
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Ad Soyad zorunludur' : null,
              ),
              const SizedBox(height: 14),
              _LightFormField(
                controller: _phoneCtrl,
                label: 'Telefon *',
                hint: '0532 xxx xx xx',
                icon: Icons.phone_rounded,
                keyboard: TextInputType.phone,
                validator: (v) {
                  if (v?.trim().isEmpty ?? true) return 'Telefon zorunludur';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              _LightFormField(
                controller: _taxNoCtrl,
                label: 'Vergi No *',
                hint: '1234567890',
                icon: Icons.badge_rounded,
                keyboard: TextInputType.number,
                validator: (v) {
                  if (v?.trim().isEmpty ?? true) return 'Vergi no zorunludur';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              // Şehir
              if (_citiesLoaded)
                _LightDropdown<String>(
                  label: 'Şehir *',
                  icon: Icons.location_city_rounded,
                  value: _selectedCity,
                  hint: 'Şehir seçin',
                  items: _cities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() {
                    _selectedCity     = v;
                    _selectedDistrict = null;
                    _districts = v != null ? (_cityMap[v] ?? []) : [];
                  }),
                  validator: (v) => v == null ? 'Şehir seçin' : null,
                )
              else
                const _LoadingField(label: 'Şehir yükleniyor…'),
              if (_districts.isNotEmpty) ...[
                const SizedBox(height: 14),
                _LightDropdown<String>(
                  label: 'İlçe *',
                  icon: Icons.map_outlined,
                  value: _selectedDistrict,
                  hint: 'İlçe seçin',
                  items: _districts.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (v) => setState(() => _selectedDistrict = v),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // ── İşletme türü ──
          _SectionCard(
            title: 'İşletme Türü',
            icon: Icons.category_rounded,
            subtitle: 'Opsiyonel — stok şablonu için kullanılır',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _businessTypes.map((type) {
                  final sel = _selectedType == type;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedType = sel ? null : type),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? POSColors.green : POSColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? POSColors.green : POSColors.border,
                        ),
                      ),
                      child: Text(
                        type,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : POSColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Logo ──
          _SectionCard(
            title: 'Logo',
            icon: Icons.image_rounded,
            subtitle: 'Opsiyonel — boş bırakırsanız Serenut logosu kullanılır',
            children: [
              Row(
                children: [
                  // Önizleme
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: POSColors.surface,
                      border: Border.all(color: POSColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _logoPath != null
                        ? Image.file(File(_logoPath!), fit: BoxFit.cover)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.storefront_rounded,
                                  color: POSColors.green, size: 28),
                              const SizedBox(height: 4),
                              Text('Varsayılan',
                                  style: GoogleFonts.inter(
                                      fontSize: 9, color: POSColors.textDisabled, fontWeight: FontWeight.w500)),
                            ],
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickLogo,
                          icon: const Icon(Icons.upload_rounded, size: 18),
                          label: const Text('Logo Seç'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: POSColors.green,
                            side: const BorderSide(color: POSColors.border),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        if (_logoPath != null) ...[
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => setState(() => _logoPath = null),
                            child: Text('Kaldır (varsayılan kullan)',
                                style: GoogleFonts.inter(
                                    fontSize: 12, color: POSColors.red, fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            _ErrorBox(message: _error!),
          ],

          const SizedBox(height: 28),
          _GreenButton(
            label: 'Hesabı Oluştur — 30 Gün Ücretsiz Başla',
            icon: Icons.rocket_launch_rounded,
            onTap: _submit,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Yardımcı Widget'lar
// ─────────────────────────────────────────────────────────────────────────────

class _StepBar extends StatelessWidget {
  final int current;
  final int total;
  const _StepBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final active = i <= current;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 3,
            margin: EdgeInsets.only(right: i < total - 1 ? 2 : 0),
            color: active ? POSColors.green : POSColors.border,
          ),
        );
      }),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: POSColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: POSColors.greenLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: POSColors.green),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.inter(
                            color: POSColors.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: GoogleFonts.inter(
                              color: POSColors.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _LightFormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboard;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _LightFormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboard,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscureText,
      validator: validator,
      style: GoogleFonts.inter(color: POSColors.text, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: POSColors.textDisabled, fontSize: 13),
        labelStyle: GoogleFonts.inter(color: POSColors.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: POSColors.textSecondary, size: 19),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: POSColors.card,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: POSColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: POSColors.green, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: POSColors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: POSColors.red, width: 1.5),
        ),
        errorStyle: GoogleFonts.inter(color: POSColors.red, fontSize: 12, fontWeight: FontWeight.w500),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

class _LightDropdown<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?) onChanged;
  final String? Function(T?)? validator;

  const _LightDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
      dropdownColor: POSColors.card,
      style: GoogleFonts.inter(color: POSColors.text, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: POSColors.textDisabled, fontSize: 13),
        labelStyle: GoogleFonts.inter(color: POSColors.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: POSColors.textSecondary, size: 19),
        filled: true,
        fillColor: POSColors.card,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: POSColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: POSColors.green, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: POSColors.red),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

class _LoadingField extends StatelessWidget {
  final String label;
  const _LoadingField({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: POSColors.border),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: POSColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: GoogleFonts.inter(color: POSColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _GreenButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _GreenButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [POSColors.green, POSColors.greenDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: POSColors.green.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: POSColors.redLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: POSColors.red.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: POSColors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(color: POSColors.red, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
