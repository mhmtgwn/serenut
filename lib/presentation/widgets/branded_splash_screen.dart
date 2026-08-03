import 'package:flutter/material.dart';
import 'package:serenutos/config/theme.dart';

/// Uygulamanın tüm gerçek başlangıç beklemeleri için ortak marka ekranı.
///
/// Yapay gecikme oluşturmaz; çağıran başlangıç adımı tamamlandığında ekrandan
/// çıkılır. İlerleme bilinmiyorsa [progress] null bırakılabilir.
/// Logo, yükleme sırasında sürekli dönerek uygulamanın çalıştığını gösterir.
class BrandedSplashScreen extends StatefulWidget {
  final String status;
  final String? detail;
  final double? progress;
  final String? error;
  final VoidCallback? onRetry;

  const BrandedSplashScreen({
    super.key,
    required this.status,
    this.detail,
    this.progress,
    this.error,
    this.onRetry,
  });

  @override
  State<BrandedSplashScreen> createState() => _BrandedSplashScreenState();
}

class _BrandedSplashScreenState extends State<BrandedSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    // Hata yoksa sürekli döndür
    if (widget.error == null) {
      _spinController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant BrandedSplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.error != null && _spinController.isAnimating) {
      _spinController.stop();
    } else if (widget.error == null && !_spinController.isAnimating) {
      _spinController.repeat();
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null;
    final normalizedProgress = widget.progress?.clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: POSColors.surface,
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned(
              top: -90,
              right: -70,
              child: _AmbientCircle(
                size: 240,
                color: POSColors.greenLight,
              ),
            ),
            Positioned(
              bottom: -110,
              left: -90,
              child: _AmbientCircle(
                size: 260,
                color: POSColors.amber.withValues(alpha: 0.10),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ── Dönen Logo ──
                      RotationTransition(
                        turns: CurvedAnimation(
                          parent: _spinController,
                          curve: Curves.linear,
                        ),
                        child: Image.asset(
                          'assets/branding/app/mark-color-112.png',
                          width: 96,
                          height: 96,
                          fit: BoxFit.contain,
                          semanticLabel: 'Serenut simgesi',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Serenut OS',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: POSColors.text,
                              letterSpacing: -0.5,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xl + AppSpacing.sm),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Icon(
                          hasError
                              ? Icons.error_outline_rounded
                              : Icons.shield_outlined,
                          key: ValueKey(hasError),
                          color: hasError ? POSColors.red : POSColors.green,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Text(
                          hasError
                              ? 'Başlatma tamamlanamadı'
                              : widget.status,
                          key: ValueKey('$hasError-${widget.status}'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                color:
                                    hasError ? POSColors.red : POSColors.text,
                              ),
                        ),
                      ),
                      if (widget.detail != null || hasError) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          hasError ? widget.error! : widget.detail!,
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    height: 1.5,
                                    color: hasError
                                        ? POSColors.red
                                        : POSColors.textSecondary,
                                  ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      if (!hasError)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          child: LinearProgressIndicator(
                            value: normalizedProgress,
                            minHeight: 6,
                            backgroundColor: POSColors.greenLight,
                          ),
                        ),
                      if (normalizedProgress != null && !hasError) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '%${(normalizedProgress * 100).round()}',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: POSColors.green,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                      if (hasError && widget.onRetry != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: widget.onRetry,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Tekrar Dene'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: AppSpacing.md,
              child: Text(
                'Güvenli perakende yönetimi',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: POSColors.textDisabled,
                      letterSpacing: 0.3,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbientCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _AmbientCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
