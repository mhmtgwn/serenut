// lib/presentation/pages/login_page.dart
// PHASE 1 - Login Screen with Advanced Local Recovery
// Generated: 02 Jul 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/domain/models/permission.dart' show UserRole;
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_business_profile_repository.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Kullanıcı adı ve şifre zorunludur');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authNotifierProvider.notifier).login(
        _usernameController.text,
        _passwordController.text,
      );

      // Check if login was successful
      final authState = ref.read(authNotifierProvider);
      authState.when(
        success: (user) {
          context.go(AppRoutes.home);
        },
        loading: () {},
        error: (error) {
          setState(() => _errorMessage = error.userMessage);
        },
      );
    } catch (e) {
      setState(() => _errorMessage = 'Giriş hatası: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showForgotPasswordDialog() {
    final usernameController = TextEditingController();
    final phoneController = TextEditingController();
    final newPasswordController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) {
        bool isResetting = false;
        String? dialogError;
        String? dialogSuccess;
        
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Şifre / PIN Sıfırlama'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Güvenlik nedeniyle personel hesaplarının şifreleri sadece yönetici (admin) tarafından Ayarlar > Kullanıcı Yönetimi ekranından sıfırlanabilir.\n\nYönetici (admin) şifrenizi sıfırlamak için kurulumda kaydettiğiniz işletme telefon numarasını girmeniz gerekmektedir.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    if (dialogError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(dialogError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                      ),
                    if (dialogSuccess != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(dialogSuccess!, style: const TextStyle(color: Colors.green, fontSize: 13)),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Kullanıcı Adı',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !isResetting && dialogSuccess == null,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(
                        labelText: 'İşletme Telefon Numarası',
                        hintText: '5XXXXXXXXX',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      enabled: !isResetting && dialogSuccess == null,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Yeni Şifre / PIN',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !isResetting && dialogSuccess == null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kapat'),
                ),
                if (dialogSuccess == null)
                  ElevatedButton(
                    onPressed: isResetting
                        ? null
                        : () async {
                            final username = usernameController.text.trim();
                            final phone = phoneController.text.trim();
                            final newPassword = newPasswordController.text.trim();
                            
                            if (username.isEmpty || phone.isEmpty || newPassword.isEmpty) {
                              setDialogState(() {
                                dialogError = 'Lütfen tüm alanları doldurun.';
                              });
                              return;
                            }
                            if (newPassword.length < 4) {
                              setDialogState(() {
                                dialogError = 'Yeni şifre/PIN en az 4 karakter olmalıdır.';
                              });
                              return;
                            }
                            
                            setDialogState(() {
                              isResetting = true;
                              dialogError = null;
                            });
                            
                            try {
                              final userRepo = ref.read(userRepositoryProvider);
                              final user = await userRepo.findByUsername(username);
                              if (user == null) {
                                throw 'Kullanıcı bulunamadı.';
                              }
                              
                              if (user.role != UserRole.admin) {
                                throw 'Güvenlik nedeniyle personel şifreleri sadece yönetici (admin) tarafından sıfırlanabilir.';
                              }
                              
                              // Check phone number
                              final dbManager = DatabaseManager();
                              final gateway = DbGatewayImpl(dbManager);
                              final profileRepo = SqliteBusinessProfileRepository(gateway);
                              final profile = await profileRepo.getProfile();
                              
                              final enteredPhoneClean = phone.replaceAll(RegExp(r'\D'), '');
                              final dbPhoneClean = (profile?.phone ?? '').replaceAll(RegExp(r'\D'), '');
                              
                              if (enteredPhoneClean.isEmpty || enteredPhoneClean != dbPhoneClean) {
                                throw 'Girdiğiniz telefon numarası işletme profili ile uyuşmuyor!';
                              }
                              
                              // Success! Update password
                              final authService = ref.read(authServiceProvider);
                              await authService.updateUser(user, password: newPassword);
                              
                              // Update SharedPreferences
                              final hashService = ref.read(hashServiceProvider);
                              final prefs = ref.read(sharedPreferencesProvider);
                              final pinHash = hashService.hashPassword(newPassword);
                              await prefs.setString('admin_pin_code', pinHash);
                              await prefs.setString('admin_password_hash', pinHash);
                              
                              setDialogState(() {
                                dialogSuccess = 'Şifreniz başarıyla güncellendi!';
                                isResetting = false;
                              });
                            } catch (e) {
                              setDialogState(() {
                                dialogError = e.toString();
                                isResetting = false;
                              });
                            }
                          },
                    child: isResetting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Şifreyi Sıfırla'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSignUpInfoDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Kayıt Ol / Yeni Kullanıcı'),
          content: const Text(
            'Serenut POS, lokal çalışan kapalı devre bir işletme otomasyonudur.\n\nYeni bir kasiyer, yönetici veya personel hesabı açmak için lütfen yönetici (admin) hesabı ile giriş yapıp:\n\n**Yönetim > Ayarlar > Kullanıcı Yönetimi**\n\nekranından yeni kullanıcı kaydı oluşturun.',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Anladım'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SERENUT POS'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),

              // Logo / Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green[100],
                ),
                child: Icon(Icons.store, size: 60, color: Colors.green[700]),
              ),

              const SizedBox(height: 40),

              // Title
              const Text(
                'SERENUT POS',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),

              Text(
                'Giriş Yapın',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Error message
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[300]!),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red[700]),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // Username field
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Kullanıcı Adı veya E-posta',
                  hintText: 'E-posta adresinizi girin',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                enabled: !_isLoading,
              ),

              const SizedBox(height: 16),

              // Password field
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Şifre / PIN',
                  hintText: 'Şifrenizi girin',
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                enabled: !_isLoading,
              ),

              const SizedBox(height: 24),

              // Login button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green[700],
                    disabledBackgroundColor: Colors.grey[400],
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Giriş Yap',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // Options
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _showSignUpInfoDialog,
                    child: const Text(
                      'Yeni Kullanıcı / Kayıt Ol',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: _showForgotPasswordDialog,
                    child: const Text(
                      'Şifremi Unuttum',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // Footer
              Text(
                'Demo Amaçlı Sistem',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
