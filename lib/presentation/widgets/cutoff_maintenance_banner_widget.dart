// lib/presentation/widgets/cutoff_maintenance_banner_widget.dart
// SERENUT OS — STAGE 10.12.60
// REAKTİF MERKEZİ KESİM & BAKIM MODU AFİŞİ (FAIL-CLOSED UI INTEGRATION)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/infrastructure/migration/cutoff_maintenance_lock.dart';
import 'package:serenutos/providers/database_provider.dart';

/// Reaktif Merkezi Bakım ve Kesim Kilidi Afişi
///
/// Normal kullanımda (idle) tamamen görünmezdir (SizedBox.shrink).
/// Kilit hazırlığı (draining), kilitli (locked) veya hata (error) durumlarında
/// kullanıcıya anlaşılır Türkçe durum ve yönlendirme sunar.
class CutoffMaintenanceBannerWidget extends ConsumerWidget {
  const CutoffMaintenanceBannerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maintenanceAsync = ref.watch(cutoffMaintenanceStateProvider);
    final fallbackState = currentCutoffMaintenanceState();

    return maintenanceAsync.when(
      data: (state) => _buildBannerContent(context, state),
      loading: () => _buildBannerContent(context, fallbackState),
      error: (err, _) => _buildErrorBanner(
        context,
        'Bakım durumu okunamadı (Fail-Closed Koruma): $err',
      ),
    );
  }

  Widget _buildBannerContent(BuildContext context, CutoffMaintenanceState state) {
    // Normal kullanım: Bildirim yok, sıfır alan kaplar.
    if (state.phase == CutoffMaintenancePhase.idle) {
      return const SizedBox.shrink();
    }

    switch (state.phase) {
      case CutoffMaintenancePhase.lockingRequested:
      case CutoffMaintenancePhase.draining:
        return _buildWarningBanner(
          context: context,
          icon: Icons.hourglass_top_rounded,
          title: 'Veritabanı Bakım Moduna Alınıyor',
          subtitle: state.activeWriteCount > 0
              ? 'Devam eden ${state.activeWriteCount} işlem tamamlanıyor, lütfen bekleyin...'
              : 'Yazma işlemleri durduruluyor, lütfen bekleyin...',
          backgroundColor: const Color(0xFFD97706), // Amber-600
          showSpinner: true,
        );

      case CutoffMaintenancePhase.locked:
        return _buildWarningBanner(
          context: context,
          icon: Icons.lock_rounded,
          title: 'Sistem Bakım Modunda (Yazma Koruması Aktif)',
          subtitle: state.reason != null && state.reason!.isNotEmpty
              ? '${state.reason!} — Yeni satış, sipariş ve veri değişiklikleri durduruldu.'
              : 'Veritabanı kesim güvenliği için yeni satış, sipariş ve tahsilat işlemleri geçici olarak durduruldu.',
          backgroundColor: const Color(0xFF1E293B), // Slate-800
          accentColor: const Color(0xFF38BDF8), // Sky-400
          showSpinner: false,
        );

      case CutoffMaintenancePhase.releasing:
        return _buildWarningBanner(
          context: context,
          icon: Icons.lock_open_rounded,
          title: 'Bakım Kilidi Kaldırılıyor',
          subtitle: 'Normal operasyona dönülüyor, lütfen bekleyin...',
          backgroundColor: const Color(0xFF0D9488), // Teal-600
          showSpinner: true,
        );

      case CutoffMaintenancePhase.error:
        return _buildErrorBanner(
          context,
          state.errorMessage ??
              'Kritik bakım ve kilit hatası oluştu. Veri bütünlüğünü korumak için yazma işlemleri durduruldu (Fail-Closed).',
        );

      case CutoffMaintenancePhase.idle:
        return const SizedBox.shrink();
    }
  }

  Widget _buildWarningBanner({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color backgroundColor,
    Color accentColor = Colors.white,
    bool showSpinner = false,
  }) {
    return Container(
      key: const Key('cutoff_maintenance_banner'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: accentColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: accentColor, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          if (showSpinner) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    return Container(
      key: const Key('cutoff_maintenance_banner_error'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF991B1B), // Red-800
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFFCA5A5),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Kritik Veritabanı Bakım Koruması (Fail-Closed)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFFFEE2E2),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
