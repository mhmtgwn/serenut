// lib/presentation/pages/login_page.dart
// Auth: Backend-first login (online) → local SQLite fallback (offline)
// Race condition fix: ref.listen pattern — navigasyon state'i dinleyerek yapılır

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/presentation/state/app_state.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';

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

  /// Login tetikler — navigasyon ref.listen ile build() içinde handle edilir
  void _handleLogin() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'E-posta ve şifre zorunludur.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Fire and forget — sonucu ref.listen karşılar (race condition yok)
    ref.read(authNotifierProvider.notifier).login(username, password);
  }

  /// Şifre sıfırlama: e-posta ile backend'e istek at
  /// Backend POST /auth/forgot-password çağrılır
  void _showForgotPasswordDialog() {
    final emailController = TextEditingController(
      text: _usernameController.text.trim(),
    );
    bool isSending = false;
    bool sent = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Şifre Sıfırla'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!sent) ...[
                    const Text(
                      'E-posta adresinizi girin. Şifre sıfırlama bağlantısı gönderilecektir.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    if (dialogError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(dialogError!,
                            style: const TextStyle(color: Colors.red, fontSize: 13)),
                      ),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-posta Adresi',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !isSending,
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Sıfırlama bağlantısı ${emailController.text} adresine gönderildi.',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kapat'),
                ),
                if (!sent)
                  ElevatedButton(
                    onPressed: isSending
                        ? null
                        : () async {
                            final email = emailController.text.trim();
                            if (email.isEmpty || !email.contains('@')) {
                              setDialogState(() =>
                                  dialogError = 'Geçerli bir e-posta adresi girin.');
                              return;
                            }
                            setDialogState(() {
                              isSending = true;
                              dialogError = null;
                            });
                            try {
                              final authService =
                                  ref.read(authServiceProvider);
                              await authService.requestPasswordReset(email);
                            } catch (_) {
                              // Enumeration: her zaman başarı göster
                            } finally {
                              setDialogState(() {
                                isSending = false;
                                sent = true;
                              });
                            }
                          },
                    child: isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Gönder'),
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
            'Serenut OS, lokal çalışan kapalı devre bir işletme otomasyonudur.\n\nYeni bir kasiyer, yönetici veya personel hesabı açmak için lütfen yönetici (admin) hesabı ile giriş yapıp:\n\n**Yönetim > Ayarlar > Kullanıcı Yönetimi**\n\nekranından yeni kullanıcı kaydı oluşturun.',
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
    // ── Auth state listener: login/logout sonucu burada handle edilir ──
    // ref.listen, build frame'ine bağlı — race condition yok
    ref.listen<AppState<AuthUser>>(authNotifierProvider, (previous, next) {
      if (!mounted) return;
      next.when(
        success: (_) {
          // Giriş başarılı → home'a git
          if (_isLoading) {
            setState(() => _isLoading = false);
          }
          context.go(AppRoutes.home);
        },
        loading: () {
          // Notifier bizzat loading set etti — buton zaten disabled
        },
        error: (error) {
          // Hata mesajını göster, butonu etkinleştir
          if (_isLoading) {
            setState(() {
              _isLoading = false;
              _errorMessage = error.userMessage;
            });
          }
        },
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('SERENUT OS'),
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
                'SERENUT OS',
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

              // Login button — onPressed artık void (async değil)
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
            ],
          ),
        ),
      ),
    );
  }
}
