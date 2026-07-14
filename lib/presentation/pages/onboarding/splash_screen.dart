// lib/presentation/pages/onboarding/splash_screen.dart
// Serenut OS — Açılış / Karşılama Ekranı
// İki seçenek: 30 Gün Ücretsiz Dene | Lisans Anahtarı Gir

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/theme.dart';

class OnboardingSplashScreen extends StatefulWidget {
  const OnboardingSplashScreen({super.key});

  @override
  State<OnboardingSplashScreen> createState() => _OnboardingSplashScreenState();
}

class _OnboardingSplashScreenState extends State<OnboardingSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 600;

    return Scaffold(
      backgroundColor: POSColors.surface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? size.width * 0.25 : 28,
                  vertical: 40,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Logo ──────────────────────────────────────────────
                    _Logo(),
                    const SizedBox(height: 40),

                    // ── Başlık ────────────────────────────────────────────
                    Text(
                      'İşletmenizi dakikalar içinde\nsatışa hazır hale getirin.',
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                                color: POSColors.text,
                              ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '30 gün boyunca tüm özellikleri ücretsiz deneyebilirsiniz.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 15,
                            height: 1.5,
                            color: POSColors.textSecondary,
                          ),
                    ),

                    const SizedBox(height: 52),

                    // ── 30 Gün Ücretsiz Dene ──────────────────────────────
                    FilledButton.icon(
                      onPressed: () => context.go('/onboarding/business'),
                      style: FilledButton.styleFrom(
                        backgroundColor: POSColors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.rocket_launch_rounded, size: 20),
                      label: const Text(
                        '30 Gün Ücretsiz Dene',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Lisans Anahtarı Gir ───────────────────────────────
                    OutlinedButton.icon(
                      onPressed: () => context.go('/onboarding/license'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: POSColors.text,
                        side: const BorderSide(
                            color: POSColors.border, width: 1.5),
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.vpn_key_outlined,
                          size: 20, color: POSColors.textSecondary),
                      label: const Text(
                        'Lisans Anahtarı Gir',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Alt not ───────────────────────────────────────────
                    Text(
                      'Daha sonra lisansınızı istediğiniz zaman ekleyebilirsiniz.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: POSColors.textDisabled,
                            fontSize: 12,
                            height: 1.5,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Logo widget — asset varsa gösterir, yoksa fallback text
// ─────────────────────────────────────────────────────────────
class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: POSColors.greenLight,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: POSColors.green.withValues(alpha: 0.18),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Image.asset(
              'assets/logo.png',
              width: 60,
              height: 60,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.store_rounded,
                size: 48,
                color: POSColors.green,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'Serenut ',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: POSColors.text,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: 'OS',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: POSColors.green,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Perakende Yönetim Sistemi',
          style: TextStyle(
            fontSize: 13,
            color: POSColors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
