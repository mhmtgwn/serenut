// lib/presentation/pages/forgot_password_page.dart
// Serenut OS — Şifre Sıfırlama Sayfası (Bilgi Doğrulama & E-posta Fallback)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/providers/service_providers.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() =>
      _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();

  // ── Adım 1: Bilgi Doğrulama ──
  final _identifierCtrl = TextEditingController(); // E-posta veya Kullanıcı Adı
  final _companyNameCtrl = TextEditingController();
  final _taxNoCtrl = TextEditingController();

  // ── Adım 2: Yeni Şifre ──
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  int _step = 0; // 0: Bilgi Doğrulama, 1: Yeni Şifre Belirleme, 2: Başarılı
  bool _isLoading = false;
  bool _obscurePass = true;
  bool _obscurePass2 = true;
  String? _errorMessage;
  String? _resetToken;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _companyNameCtrl.dispose();
    _taxNoCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // ── 1. Adım: Bilgileri Doğrula ──
  Future<void> _verifyIdentity() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post('/auth/verify-identity', {
        'email': _identifierCtrl.text.trim(),
        'company_name': _companyNameCtrl.text.trim(),
        'tax_number': _taxNoCtrl.text.trim(),
      });

      final body = response.json as Map<String, dynamic>;
      final token = body['token'] as String?;

      if (token != null && token.isNotEmpty) {
        setState(() {
          _resetToken = token;
          _step = 1;
        });
      } else {
        setState(() {
          _errorMessage =
              body['message']?.toString() ?? 'Bilgiler eşleşmedi.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage =
            'Bilgi doğrulama başarısız. Lütfen bilgilerinizi kontrol ediniz.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── 2. Adım: Şifreyi Sıfırla ──
  Future<void> _resetPassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post('/auth/reset-password', {
        'token': _resetToken,
        'newPassword': _newPasswordCtrl.text,
      });

      final body = response.json as Map<String, dynamic>;
      if (body['success'] == true) {
        setState(() => _step = 2);
      } else {
        setState(() {
          _errorMessage = body['message']?.toString() ??
              'Şifre güncellenemedi. Token geçersiz.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Şifre güncellenirken hata oluştu: $e';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Fallback: E-posta ile Talep Gönder ──
  Future<void> _requestEmailReset() async {
    if (_identifierCtrl.text.trim().isEmpty) {
      setState(() {
        _errorMessage =
            'E-posta ile sıfırlama linki almak için lütfen e-posta / kullanıcı adı alanını doldurun.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post('/auth/forgot-password', {
        'email': _identifierCtrl.text.trim(),
      });

      final body = response.json as Map<String, dynamic>;
      final msg = body['message']?.toString() ??
          'Şifre sıfırlama talebiniz alındı.';

      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('E-posta Bildirimi'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage =
            'E-posta servisine şu an ulaşılamıyor. Lütfen bilgi doğrulama adımıyla sıfırlamayı deneyin veya teknik destekle iletişime geçin.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: POSColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: POSColors.text),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Şifremi Unuttum',
          style: GoogleFonts.inter(
            color: POSColors.text,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_step == 0) _buildStep0(),
                    if (_step == 1) _buildStep1(),
                    if (_step == 2) _buildStep2(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Adım 0: Bilgi Doğrulama Ekranı ──
  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: POSColors.greenLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_user_rounded,
                  color: POSColors.green, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bilgi Doğrulama',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: POSColors.greenDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Hesabınızı doğrulamak için kayıtlı bilgilerinizi giriniz.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: POSColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildField(
          controller: _identifierCtrl,
          label: 'E-posta veya Kullanıcı Adı *',
          hint: 'ahmet@market.com',
          icon: Icons.person_outline_rounded,
          validator: (v) =>
              (v?.trim().isEmpty ?? true) ? 'Bu alan zorunludur' : null,
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _companyNameCtrl,
          label: 'İşletme Adı *',
          hint: 'ABC Market',
          icon: Icons.storefront_rounded,
          validator: (v) =>
              (v?.trim().isEmpty ?? true) ? 'İşletme adı zorunludur' : null,
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _taxNoCtrl,
          label: 'Vergi No / TC *',
          hint: '1234567890',
          icon: Icons.badge_rounded,
          keyboardType: TextInputType.number,
          validator: (v) =>
              (v?.trim().isEmpty ?? true) ? 'Vergi no / TC zorunludur' : null,
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          _ErrorBox(message: _errorMessage!),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _isLoading ? null : _verifyIdentity,
          style: FilledButton.styleFrom(
            backgroundColor: POSColors.green,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isLoading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  'Bilgileri Doğrula & Devam Et',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _requestEmailReset,
          icon: const Icon(Icons.mail_outline_rounded, size: 18),
          label: const Text('E-posta ile Sıfırlama Linki İste'),
          style: OutlinedButton.styleFrom(
            foregroundColor: POSColors.textSecondary,
            side: const BorderSide(color: POSColors.border),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  // ── Adım 1: Yeni Şifre Ekranı ──
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: POSColors.greenLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_reset_rounded,
                  color: POSColors.green, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Yeni Şifre Belirleyin',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: POSColors.greenDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Doğrulama başarılı! Lütfen yeni şifrenizi giriniz.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: POSColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildField(
          controller: _newPasswordCtrl,
          label: 'Yeni Şifre *',
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          obscureText: _obscurePass,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePass
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: POSColors.textSecondary,
              size: 20,
            ),
            onPressed: () => setState(() => _obscurePass = !_obscurePass),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Şifre zorunludur';
            if (v.length < 8) return 'En az 8 karakter olmalı';
            return null;
          },
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _confirmPasswordCtrl,
          label: 'Yeni Şifre Tekrar *',
          hint: '••••••••',
          icon: Icons.lock_rounded,
          obscureText: _obscurePass2,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePass2
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: POSColors.textSecondary,
              size: 20,
            ),
            onPressed: () => setState(() => _obscurePass2 = !_obscurePass2),
          ),
          validator: (v) {
            if (v != _newPasswordCtrl.text) return 'Şifreler eşleşmiyor';
            return null;
          },
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          _ErrorBox(message: _errorMessage!),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _isLoading ? null : _resetPassword,
          style: FilledButton.styleFrom(
            backgroundColor: POSColors.green,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isLoading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  'Şifreyi Güncelle',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
        ),
      ],
    );
  }

  // ── Adım 2: Başarılı Ekranı ──
  Widget _buildStep2() {
    return Column(
      children: [
        const Icon(Icons.check_circle_rounded, color: POSColors.green, size: 64),
        const SizedBox(height: 16),
        Text(
          'Şifreniz Değiştirildi!',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: POSColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Yeni şifrenizle giriş yapabilirsiniz.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: POSColors.textSecondary,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => context.go('/login/form'),
            style: FilledButton.styleFrom(
              backgroundColor: POSColors.green,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'Giriş Yap Ekranına Dön',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: GoogleFonts.inter(color: POSColors.text, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle:
            GoogleFonts.inter(color: POSColors.textDisabled, fontSize: 13),
        labelStyle:
            GoogleFonts.inter(color: POSColors.textSecondary, fontSize: 13),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: POSColors.redLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: POSColors.red.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: POSColors.red, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                  color: POSColors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
