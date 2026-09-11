// lib/presentation/pages/login_page.dart
// Serenut OS — Karşılama Ekranı (Web Sitesiyle Uyumlu Açık Tema)
// "Giriş Yap" + "Hesap Oluştur" iki büyük buton
// Hesap oluşturulunca 30 günlük deneme otomatik başlar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/presentation/state/app_state.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:serenutos/config/theme.dart';

// ═══════════════════════════════════════════════════════
// Ana Karşılama Sayfası (Giriş Yap / Hesap Oluştur)
// ═══════════════════════════════════════════════════════

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 600;
    final authService = ref.watch(authServiceProvider);
    final lastLogoutReason = authService.getLastLogoutReason();
    final lastLogoutCode = authService.getLastLogoutCode();

    return Scaffold(
      backgroundColor: POSColors.surface, // Açık gri-mavi zemin (0xFFF8FAFC)
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? size.width * 0.25 : 28,
              vertical: 32,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                // ── Uygulama kimliği ──
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/branding/app/icon-color-192.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      color: POSColors.greenLight,
                      child: const Icon(Icons.storefront_rounded,
                          size: 48, color: POSColors.green),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Başlık ──
                Text(
                  'Serenut OS',
                  style: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: POSColors.text,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Hoş Geldiniz',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: POSColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                if (lastLogoutReason != null &&
                    lastLogoutReason.isNotEmpty &&
                    lastLogoutCode != 'MANUAL_LOGOUT') ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDBA74)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            color: Color(0xFFEA580C), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Önceki Oturum Kapanma Nedeni',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF9A3412),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                lastLogoutReason,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFFC2410C),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 36),

                // ── Hesap Oluştur (Birincil) ──
                _PrimaryButton(
                  label: 'Hesap Oluştur',
                  icon: Icons.person_add_rounded,
                  onTap: () => context.go('/register'),
                ),
                const SizedBox(height: 14),

                // ── Giriş Yap (İkincil) ──
                _SecondaryButton(
                  label: 'Giriş Yap',
                  icon: Icons.login_rounded,
                  onTap: () => context.go('/login/form'),
                ),

                const SizedBox(height: 40),

                // ── Bilgi Mesajı ──
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: POSColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: POSColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: POSColors.green, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Hesabınızı oluşturduğunuzda 30 günlük ücretsiz deneme otomatik olarak başlar. Kredi kartı gerekmez.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: POSColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),

                // ── Alt bağlantı ──
                TextButton(
                  onPressed: () async {
                    final uri =
                        Uri.parse('https://serenut.com/forgot-password');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                  child: Text(
                    'Şifremi unuttum',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: POSColors.textSecondary,
                      decoration: TextDecoration.underline,
                      decorationColor: POSColors.textSecondary,
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// Giriş Formu (Açık Tema)
// ═══════════════════════════════════════════════════════

class LoginFormPage extends ConsumerStatefulWidget {
  const LoginFormPage({super.key});

  @override
  ConsumerState<LoginFormPage> createState() => _LoginFormPageState();
}

class _LoginFormPageState extends ConsumerState<LoginFormPage> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _isLoading = false;
  bool _obscure = true;
  String? _errorMessage;

  bool _rememberMe = true;
  String? _lastLogoutReason;
  DateTime? _lastLogoutTime;
  String? _lastLogoutCode;
  String? _lastLogoutDetails;
  bool _showLogoutNotice = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadSavedCredentialsAndLogoutInfo();
    });
  }

  void _loadSavedCredentialsAndLogoutInfo() {
    final authService = ref.read(authServiceProvider);
    _rememberMe = authService.isRememberMeEnabled();
    final savedUser = authService.getRememberedUsername();
    final savedPass = authService.getRememberedPassword();
    if (savedUser != null && savedUser.isNotEmpty) {
      _usernameCtrl.text = savedUser;
    }
    if (savedPass != null && savedPass.isNotEmpty) {
      _passwordCtrl.text = savedPass;
    }

    _lastLogoutReason = authService.getLastLogoutReason();
    _lastLogoutTime = authService.getLastLogoutTime();
    _lastLogoutCode = authService.getLastLogoutCode();
    _lastLogoutDetails = authService.getLastLogoutDetails();
    if (_lastLogoutReason != null &&
        _lastLogoutReason!.isNotEmpty &&
        _lastLogoutCode != 'MANUAL_LOGOUT') {
      _showLogoutNotice = true;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _handleLogin() {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Kullanıcı adı ve şifre zorunludur.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    ref.read(authNotifierProvider.notifier).login(
          username,
          password,
          rememberMe: _rememberMe,
        );
  }

  void _showLogoutDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.history_rounded, color: POSColors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Oturum Kapanma Detayları',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Neden', _lastLogoutReason ?? '-'),
              const SizedBox(height: 10),
              _detailRow('Hata / Durum Kodu', _lastLogoutCode ?? 'UNKNOWN'),
              if (_lastLogoutTime != null) ...[
                const SizedBox(height: 10),
                _detailRow(
                  'Zaman',
                  _lastLogoutTime!.toLocal().toString().split('.').first,
                ),
              ],
              if (_lastLogoutDetails != null &&
                  _lastLogoutDetails!.isNotEmpty) ...[
                const SizedBox(height: 10),
                _detailRow('Açıklama / Parametreler', _lastLogoutDetails!),
              ],
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Geçmiş Çıkış Kayıtları (Son Oturumlar):',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: POSColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              ...ref.read(authServiceProvider).getLogoutHistory().take(5).map(
                    (h) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: POSColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: POSColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                h['code']?.toString() ?? 'LOGOUT',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: POSColors.text,
                                ),
                              ),
                              Text(
                                h['time'] != null
                                    ? DateTime.tryParse(h['time'])
                                            ?.toLocal()
                                            .toString()
                                            .split('.')
                                            .first ??
                                        ''
                                    : '',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: POSColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            h['reason']?.toString() ?? '',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: POSColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Kapat',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: POSColors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: POSColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: POSColors.text,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _formatLogoutTime(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$hour:$min ($day.$month.${local.year})';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 600;

    ref.listen<AppState<AuthUser>>(authNotifierProvider, (_, next) {
      if (!mounted) return;
      next.when(
        success: (_) {
          if (_isLoading) setState(() => _isLoading = false);
          context.go(AppRoutes.home);
        },
        loading: () {},
        error: (err) {
          if (_isLoading) {
            setState(() {
              _isLoading = false;
              _errorMessage = err.userMessage;
            });
          }
        },
      );
    });

    return Scaffold(
      backgroundColor: POSColors.surface,
      appBar: AppBar(
        backgroundColor: POSColors.card,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: POSColors.text, size: 18),
          onPressed: () => context.go('/login'),
        ),
        title: Text(
          'Giriş Yap',
          style: GoogleFonts.inter(
              color: POSColors.text, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: POSColors.border, height: 1),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? size.width * 0.25 : 24,
              vertical: 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),

                // ── Son Çıkış Nedeni Bilgilendirme Kartı ──
                if (_showLogoutNotice && _lastLogoutReason != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDBA74)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                color: Color(0xFFEA580C), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Önceki Oturum Kapanma Nedeni',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF9A3412),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _lastLogoutReason!,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: const Color(0xFFC2410C),
                                      height: 1.4,
                                    ),
                                  ),
                                  if (_lastLogoutTime != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Zaman: ${_formatLogoutTime(_lastLogoutTime!)}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: const Color(0xFF9A3412)
                                            .withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  size: 18, color: Color(0xFF9A3412)),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Kapat',
                              onPressed: () {
                                ref
                                    .read(authServiceProvider)
                                    .clearLastLogoutReason();
                                setState(() => _showLogoutNotice = false);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _showLogoutDetailsDialog(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.analytics_outlined,
                                size: 14, color: Color(0xFFEA580C)),
                            label: Text(
                              'Ayrıntılar & Geçmiş',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFEA580C),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── Hata mesajı ──
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: POSColors.redLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: POSColors.red.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: POSColors.red, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: GoogleFonts.inter(
                                color: POSColors.red,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Kullanıcı Adı / E-posta ──
                _LightField(
                  controller: _usernameCtrl,
                  label: 'Kullanıcı Adı veya E-posta',
                  hint: 'kullanici@ornek.com',
                  icon: Icons.person_outline_rounded,
                  enabled: !_isLoading,
                  keyboardType: TextInputType.emailAddress,
                  focusNode: _usernameFocus,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                ),
                const SizedBox(height: 14),

                // ── Şifre ──
                _LightField(
                  controller: _passwordCtrl,
                  label: 'Şifre',
                  hint: '••••••••',
                  icon: Icons.lock_outline_rounded,
                  enabled: !_isLoading,
                  obscureText: _obscure,
                  focusNode: _passwordFocus,
                  textInputAction: TextInputAction.done,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: POSColors.textSecondary,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  onSubmitted: (_) => _handleLogin(),
                ),

                const SizedBox(height: 12),

                // ── Beni Hatırla & Şifremi Unuttum ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () => setState(() => _rememberMe = !_rememberMe),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: Checkbox(
                                value: _rememberMe,
                                activeColor: POSColors.green,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                onChanged: (v) =>
                                    setState(() => _rememberMe = v ?? true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Beni Hatırla',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: POSColors.text,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push('/forgot-password'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Şifremi unuttum?',
                        style: GoogleFonts.inter(
                          color: POSColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Giriş Butonu ──
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: POSColors.green,
                      disabledBackgroundColor: POSColors.border,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Giriş Yap',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Hesap Oluştur linki ──
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Hesabınız yok mu? ',
                        style: GoogleFonts.inter(
                            color: POSColors.textSecondary, fontSize: 13),
                      ),
                      GestureDetector(
                        onTap: () => context.go('/register'),
                        child: Text(
                          'Hesap Oluştur',
                          style: GoogleFonts.inter(
                            color: POSColors.green,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// Yardımcı Widget'lar
// ═══════════════════════════════════════════════════════

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PrimaryButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [POSColors.green, POSColors.greenDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: POSColors.green.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SecondaryButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            color: POSColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: POSColors.border, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.01),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: POSColors.textSecondary, size: 22),
              const SizedBox(width: 12),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: POSColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LightField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool enabled;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final void Function(String)? onSubmitted;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;

  const _LightField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.enabled = true,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.onSubmitted,
    this.focusNode,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      focusNode: focusNode,
      textInputAction: textInputAction,
      style: GoogleFonts.inter(color: POSColors.text, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle:
            GoogleFonts.inter(color: POSColors.textDisabled, fontSize: 14),
        labelStyle:
            GoogleFonts.inter(color: POSColors.textSecondary, fontSize: 14),
        prefixIcon: Icon(icon, color: POSColors.textSecondary, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: enabled ? POSColors.card : const Color(0xFFF1F5F9),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: POSColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: POSColors.green, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: POSColors.border),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
