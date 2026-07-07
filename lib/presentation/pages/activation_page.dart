// lib/presentation/pages/activation_page.dart
import 'dart:math';
import 'dart:io' show File;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/services/password_hash_service.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/config/router.dart';

// Styling constants
const _kPrimary = Color(0xFF10B981); // Emerald Green
const _kPrimaryDark = Color(0xFF059669);
const _kBackground = Color(0xFFFAFAFC); // Sophisticated off-white / light slate grey
const _kCardBg = Colors.white;
const _kTextPrimary = Color(0xFF1E293B); // Slate 900
const _kTextSecondary = Color(0xFF64748B); // Slate 500
const _kBorderColor = Color(0xFFE2E8F0); // Slate 200

class ActivationPage extends ConsumerStatefulWidget {
  const ActivationPage({super.key});

  @override
  ConsumerState<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends ConsumerState<ActivationPage> {
  int _currentStep = 1; // 1: Setup Form, 2: Setup Complete

  // Store & Admin Setup Controllers
  final _setupFormKey = GlobalKey<FormState>();
  final TextEditingController _businessNameCtrl = TextEditingController();
  final TextEditingController _businessPhoneCtrl = TextEditingController();
  final TextEditingController _businessAddressCtrl = TextEditingController();
  final TextEditingController _adminNameCtrl = TextEditingController();
  final TextEditingController _adminEmailCtrl = TextEditingController();
  final TextEditingController _adminPasswordCtrl = TextEditingController();
  final TextEditingController _adminPinCtrl = TextEditingController();
  
  String _generatedRecoveryKey = '';
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _selectedLogoPath;

  @override
  void initState() {
    super.initState();
    _generateRecoveryKeyString();
  }

  void _generateRecoveryKeyString() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    String genPart() => List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
    setState(() {
      _generatedRecoveryKey = 'SRNT-${genPart()}-${genPart()}-${genPart()}';
    });
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _businessPhoneCtrl.dispose();
    _businessAddressCtrl.dispose();
    _adminNameCtrl.dispose();
    _adminEmailCtrl.dispose();
    _adminPasswordCtrl.dispose();
    _adminPinCtrl.dispose();
    super.dispose();
  }

  // Action: Rekey DB, create Settings, Admin user, and log in
  Future<void> _completeSetup() async {
    if (!_setupFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final licenseService = ref.read(licenseServiceProvider);
      final licenseManager = ref.read(licenseManagerProvider);
      final deviceManager = ref.read(deviceManagerProvider);
      final authService = ref.read(authServiceProvider);
      final settingsRepo = await ref.read(settingsRepositoryProvider.future);

      // 1. Automatic License Activation using pre-signed RSA-2048 wildcard token
      const licenseToken = 'eyJtZXJjaGFudElkIjoiQVVUT19NRVJDSEFOVCIsImFsbG93ZWREZXZpY2VzIjpbIioiXSwiZXhwaXJ5RGF0ZSI6IjIwMzYtMTItMzFUMjM6NTk6NTlaIiwidGllciI6IlBST19QTFVTIiwiZmVhdHVyZXMiOlsibXVsdGlfZGV2aWNlIiwiY2xvdWRfc3luYyIsImFkdmFuY2VkX3JlcG9ydHMiXSwic2lnbmF0dXJlIjoicnZMc2tPOHdFZ2pBc2xvRlgrSHVqV1FVc0ZveUZkNHJlVmlYai9yRU5Wa2NiTjloN2l2N3pIZ3A3RUpuWjhtWnRHdWV6a2tkK1cvd0VlenVwS0Y4QXB5RHFZQ1J1U3pzUmJuWHBUQWlkeVp3Z29pZjZFbVpPUG1kV3hlbEpkRVNkT1dhUllhclRPdFp3SFhkMzFSdFhiZkFGZHBNTkhtK2NnMDgvQU1KY3dEOXBCbEVaREd3aEpseDhiam80VmF3emVGUTY3bGRkcis1ZVd2R3VRYUtoTXpYVUxwR1BTMGI5RzljNlpXRnJ0VGloV2p1Y1VhRnoyV08yWnp1NFdIa2pITms2NWU0WGM0N1lRZzNBeHdsZzdLV0ptVThXaHYra1lxdjFCRExIb09FQWxFM3kvUTJ4Nk9hdVB2aDBxWk1hTndYQ2k5eUlDWGRpWndXNXQ1bkJRPT0ifQ==';
      await licenseService.saveLicenseToken(licenseToken);

      // 2. SQLite operations — only on non-Web platforms
      if (!kIsWeb) {
        final dbManager = DatabaseManager();
        await dbManager.changeDatabaseKey(_generatedRecoveryKey);
        await dbManager.close();
        await dbManager.getDatabase();
      }

      // 3. Save Settings
      final settings = Settings(
        businessName: _businessNameCtrl.text.trim(),
        businessPhone: _businessPhoneCtrl.text.trim(),
        businessAddress: _businessAddressCtrl.text.trim(),
        businessLogo: _selectedLogoPath,
      );
      await settingsRepo.updateSettings(settings);

      // 4. Create Super Admin User
      final adminUser = AuthUser(
        id: 'user-admin',
        name: _adminNameCtrl.text.trim(),
        email: _adminEmailCtrl.text.trim().toLowerCase(),
        role: UserRole.admin,
        permissions: AuthService.getPermissionsForRole(UserRole.admin),
        createdAt: DateTime.now(),
      );
      await authService.createUser(adminUser, _adminPasswordCtrl.text);

      // Log setup user creation
      try {
        await ref.read(auditLogServiceProvider).log(
          action: 'user_created',
          details: '{"id":"${adminUser.id}","name":"${adminUser.name}","role":"admin"}',
        );
      } catch (_) {
        // Non-fatal if audit log fails during setup
      }

      // 5. Store Hashed PIN
      final prefs = await SharedPreferences.getInstance();
      final hashedPin = PasswordHashService.hashPassword(_adminPinCtrl.text);
      await prefs.setString('admin_pin_code', hashedPin);

      // 6. Login
      if (kIsWeb) {
        // On Web, directly set the session in AuthNotifier
        await ref.read(authNotifierProvider.notifier).loginWithUser(adminUser);
      } else {
        await authService.login(_adminEmailCtrl.text.trim(), _adminPasswordCtrl.text);
      }

      // Invalidate providers to force load new settings/user state
      ref.invalidate(currentUserProvider);
      ref.invalidate(settingsProvider);

      setState(() {
        _currentStep = 2;
        _isLoading = false;
      });

      // Navigate to Home
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          context.go(AppRoutes.home);
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Kurulum hatası oluştu: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Card(
              color: _kCardBg,
              elevation: 4,
              shadowColor: Colors.black.withOpacity(0.04),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: _kBorderColor, width: 1),
              ),
              child: _currentStep == 1 ? _buildSetupStep() : _buildCompleteStep(),
            ),
          ),
        ),
      ),
    );
  }

  // UI Step: Shop Details & Admin Setup
  Widget _buildSetupStep() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Form(
        key: _setupFormKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.storefront_rounded, size: 48, color: _kPrimary),
            const SizedBox(height: 16),
            const Text(
              'İlk Kurulum Ayarları',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _kTextPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'POS veritabanınızı oluşturmak için işletme ve yönetici hesap bilgilerinizi tanımlayın.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _kTextSecondary),
            ),
            const SizedBox(height: 28),

            // Section: İşletme Bilgileri
            _buildSectionHeader('İŞLETME BİLGİLERİ'),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: () async {
                  try {
                    final picker = ImagePicker();
                    final pickedFile = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 512,
                      maxHeight: 512,
                    );
                    if (pickedFile != null) {
                      setState(() {
                        _selectedLogoPath = pickedFile.path;
                      });
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Logo seçilirken hata: $e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                },
                child: Stack(
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        shape: BoxShape.circle,
                        border: Border.all(color: _kBorderColor, width: 2),
                      ),
                      child: _selectedLogoPath != null &&
                              _selectedLogoPath!.isNotEmpty &&
                              (kIsWeb || File(_selectedLogoPath!).existsSync())
                          ? ClipOval(
                              child: kIsWeb
                                  ? Image.network(
                                      _selectedLogoPath!,
                                      width: 86,
                                      height: 86,
                                      fit: BoxFit.cover,
                                    )
                                  : Image.file(
                                      File(_selectedLogoPath!),
                                      width: 86,
                                      height: 86,
                                      fit: BoxFit.cover,
                                    ),
                            )
                          : const Icon(
                              Icons.add_photo_alternate_rounded,
                              color: _kPrimary,
                              size: 36,
                            ),
                    ),
                    if (_selectedLogoPath != null &&
                        _selectedLogoPath!.isNotEmpty &&
                        (kIsWeb || File(_selectedLogoPath!).existsSync()))
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedLogoPath = null;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.delete_forever_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'İşletme Logosu (Opsiyonel)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: _kTextSecondary),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _businessNameCtrl,
              label: 'İşletme / Market Adı',
              icon: Icons.store_rounded,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'İşletme adı zorunludur.' : null,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _businessPhoneCtrl,
              label: 'İşletme Telefon',
              icon: Icons.phone_rounded,
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Telefon numarası zorunludur.' : null,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _businessAddressCtrl,
              label: 'Adres',
              icon: Icons.location_on_rounded,
              maxLines: 2,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Adres zorunludur.' : null,
            ),
            const SizedBox(height: 28),

            // Section: Yönetici Hesabı
            _buildSectionHeader('YÖNETİCİ HESABI (SUPER ADMIN)'),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _adminNameCtrl,
              label: 'Yönetici Ad Soyad',
              icon: Icons.person_rounded,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Yönetici adı zorunludur.' : null,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _adminEmailCtrl,
              label: 'Yönetici E-posta',
              icon: Icons.email_rounded,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'E-posta zorunludur.';
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v.trim())) {
                  return 'Geçersiz e-posta formatı.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _adminPasswordCtrl,
              label: 'Yönetici Şifre (En az 6 karakter)',
              icon: Icons.lock_rounded,
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: _kTextSecondary),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: (v) => (v == null || v.length < 6) ? 'Şifre en az 6 karakter olmalıdır.' : null,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _adminPinCtrl,
              label: 'Yönetici PIN Kodu (4 Hane)',
              icon: Icons.password_rounded,
              keyboardType: TextInputType.number,
              obscureText: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              validator: (v) => (v == null || v.length != 4) ? 'PIN kodu 4 haneli olmalıdır.' : null,
            ),
            const SizedBox(height: 28),

            // Section: Veritabanı Kurtarma Anahtarı
            _buildSectionHeader('VERİTABANI KURTARMA ANAHTARI (PORTABLE BACKUP KEY)'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB), // soft amber background
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'KRİTİK GÜVENLİK UYARISI',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Veritabanınız bu kurtarma anahtarı ile şifrelenecektir. Yedeklerinizi başka bir cihazda açabilmek için bu şifreyi güvenli bir yere kaydedin!',
                    style: TextStyle(fontSize: 11, color: _kTextSecondary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _generatedRecoveryKey,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: _kTextPrimary,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: _kPrimary, size: 20),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _generatedRecoveryKey));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Kurtarma anahtarı kopyalandı.')),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isLoading ? null : _completeSetup,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)),
                    )
                  : const Text('Kurulumu Tamamla ve Başlat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  // UI Step: Success Screen
  Widget _buildCompleteStep() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 64.0, horizontal: 32.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 72, color: _kPrimary),
          SizedBox(height: 24),
          Text(
            'Kurulum Başarılı!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _kTextPrimary),
          ),
          SizedBox(height: 8),
          Text(
            'Yönetici profili başarıyla oluşturuldu. Yönlendiriliyorsunuz...',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: _kTextSecondary),
          ),
          SizedBox(height: 32),
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(_kPrimary),
          ),
        ],
      ),
    );
  }

  // Textbox helper method for premium styling
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      validator: validator,
      style: const TextStyle(color: _kTextPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kTextSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: _kPrimary, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: _kBackground,
        alignLabelWithHint: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kPrimary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _kPrimary,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}
