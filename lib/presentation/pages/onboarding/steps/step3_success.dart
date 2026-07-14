// lib/presentation/pages/onboarding/steps/step3_success.dart
// Adım 3 — Kurulum Özeti + Başarı Animasyonu
// Sistem durumu özeti kartı, deneme bitiş tarihi, "Serenut OS'yi Başlat" butonu

import 'package:flutter/material.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/pages/onboarding/onboarding_state.dart';
import 'package:intl/intl.dart';

class Step3Success extends StatefulWidget {
  final OnboardingState state;
  final DateTime? trialExpiryDate;
  final String appVersion;
  final VoidCallback onLaunch;

  const Step3Success({
    super.key,
    required this.state,
    this.trialExpiryDate,
    this.appVersion = '1.0.0',
    required this.onLaunch,
  });

  @override
  State<Step3Success> createState() => _Step3SuccessState();
}

class _Step3SuccessState extends State<Step3Success>
    with TickerProviderStateMixin {
  late AnimationController _checkCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _checkScale;
  late Animation<double> _checkDraw;
  late Animation<double> _fadeCards;

  @override
  void initState() {
    super.initState();

    _checkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _checkScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.15), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(parent: _checkCtrl, curve: Curves.easeOut));

    _checkDraw = CurvedAnimation(parent: _checkCtrl, curve: Curves.easeInOut);

    _fadeCards = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    // Sıralı animasyon
    _checkCtrl.forward().then((_) {
      if (mounted) _fadeCtrl.forward();
    });
  }

  @override
  void dispose() {
    _checkCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size   = MediaQuery.sizeOf(context);
    final isWide = size.width > 600;
    final expiryFormatted = widget.trialExpiryDate != null
        ? DateFormat('dd.MM.yyyy').format(widget.trialExpiryDate!)
        : '—';

    return Scaffold(
      backgroundColor: POSColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? size.width * 0.15 : 24,
            vertical: 32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Onay animasyonu ─────────────────────────────────────────
              Center(
                child: ScaleTransition(
                  scale: _checkScale,
                  child: SizedBox(
                    width: 120,
                    height: 120,
                    child: CustomPaint(
                      painter: _CheckPainter(progress: _checkDraw),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Başlık ──────────────────────────────────────────────────
              Text(
                'Kurulum Tamamlandı',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: POSColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Kurulum başarıyla tamamlandı.\nİlk girişinizle birlikte 30 günlük ücretsiz denemeniz başlayacaktır.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: POSColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              // ── İçerik kartları (fade-in) ────────────────────────────────
              FadeTransition(
                opacity: _fadeCards,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Deneme süresi bilgi kartı
                    _TrialBanner(expiryDate: expiryFormatted),
                    const SizedBox(height: 16),

                    // Sistem özeti kartı
                    _SystemSummaryCard(
                      state:      widget.state,
                      appVersion: widget.appVersion,
                    ),
                    const SizedBox(height: 16),

                    // Özellikler kartı
                    _FeaturesCard(),
                    const SizedBox(height: 32),

                    // Başlat butonu
                    FilledButton.icon(
                      onPressed: widget.onLaunch,
                      style: FilledButton.styleFrom(
                        backgroundColor: POSColors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.rocket_launch_rounded, size: 20),
                      label: const Text(
                        'Serenut OS\'yi Başlat',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Onay işareti CustomPainter
// ─────────────────────────────────────────────────────────────────────────────
class _CheckPainter extends CustomPainter {
  final Animation<double> progress;
  _CheckPainter({required this.progress}) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center  = Offset(size.width / 2, size.height / 2);
    final radius  = size.width / 2;

    // Daire
    final circlePaint = Paint()
      ..color = POSColors.green
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * progress.value, circlePaint);

    if (progress.value < 0.4) return;

    // Check çizgisi
    final checkPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final t = ((progress.value - 0.4) / 0.6).clamp(0.0, 1.0);

    // İki segment: p1→p2 ve p2→p3
    final p1 = Offset(size.width * 0.22, size.height * 0.52);
    final p2 = Offset(size.width * 0.42, size.height * 0.68);
    final p3 = Offset(size.width * 0.76, size.height * 0.32);

    final path = Path();
    if (t < 0.5) {
      final t2 = t / 0.5;
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(
        p1.dx + (p2.dx - p1.dx) * t2,
        p1.dy + (p2.dy - p1.dy) * t2,
      );
    } else {
      final t2 = (t - 0.5) / 0.5;
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(p2.dx, p2.dy);
      path.lineTo(
        p2.dx + (p3.dx - p2.dx) * t2,
        p2.dy + (p3.dy - p2.dy) * t2,
      );
    }
    canvas.drawPath(path, checkPaint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Trial banner
// ─────────────────────────────────────────────────────────────────────────────
class _TrialBanner extends StatelessWidget {
  final String expiryDate;
  const _TrialBanner({required this.expiryDate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [POSColors.green, POSColors.greenDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text('30',
                  style: TextStyle(
                      color: Colors.white, fontSize: 22,
                      fontWeight: FontWeight.w900)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ücretsiz Deneme Başladı',
                    style: TextStyle(
                        color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'Deneme Bitiş Tarihi: $expiryDate',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sistem özeti kartı (kullanıcıya güven verir)
// ─────────────────────────────────────────────────────────────────────────────
class _SystemSummaryCard extends StatelessWidget {
  final OnboardingState state;
  final String appVersion;

  const _SystemSummaryCard({required this.state, required this.appVersion});

  @override
  Widget build(BuildContext context) {
    final items = [
      _SummaryItem(icon: Icons.store_rounded,    label: 'İşletme', value: state.business.businessName.isNotEmpty ? state.business.businessName : '—'),
      _SummaryItem(icon: Icons.category_rounded, label: 'Tür', value: state.business.businessType.isNotEmpty ? state.business.businessType : '—'),
      const _SummaryItem(icon: Icons.storage_rounded,  label: 'Veritabanı', value: 'Hazır', isGood: true),
      const _SummaryItem(icon: Icons.backup_rounded,   label: 'Yedekleme', value: 'Hazır', isGood: true),
      _SummaryItem(icon: Icons.manage_accounts_rounded, label: 'Admin', value: state.admin.adminFullName.isNotEmpty ? state.admin.adminFullName : '—', isGood: true),
      const _SummaryItem(icon: Icons.devices_rounded,  label: 'Cihaz', value: 'Aktif', isGood: true),
      _SummaryItem(icon: Icons.info_outline_rounded, label: 'Sürüm', value: appVersion),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: POSColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Sistem Durumu',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: POSColors.text)),
          const SizedBox(height: 16),
          ...items.map((item) => _SummaryRow(item: item)),
        ],
      ),
    );
  }
}

class _SummaryItem {
  final IconData icon;
  final String label;
  final String value;
  final bool isGood;
  const _SummaryItem({
    required this.icon, required this.label, required this.value,
    this.isGood = false,
  });
}

class _SummaryRow extends StatelessWidget {
  final _SummaryItem item;
  const _SummaryRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: item.isGood ? POSColors.greenLight : POSColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, size: 18,
                color: item.isGood ? POSColors.green : POSColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(item.label,
                style: const TextStyle(
                    fontSize: 14, color: POSColors.textSecondary)),
          ),
          if (item.isGood)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: POSColors.greenLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(item.value,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: POSColors.green)),
            )
          else
            Text(item.value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: POSColors.text)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Özellikler kartı
// ─────────────────────────────────────────────────────────────────────────────
class _FeaturesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const features = [
      '✓  Tüm modüller açık',
      '✓  Güncelleme desteği',
      '✓  Offline kullanım',
      '✓  Sınırsız işlem',
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: POSColors.greenLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: POSColors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: features
            .map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Text(f,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: POSColors.greenDark)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}
