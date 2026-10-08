// lib/presentation/widgets/sync_status_badge.dart
// Serenut OS — Kasiyer İçin Senkronizasyon ve Çevrimdışı Kuyruk Durum Göstergesi

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/providers/sync_provider.dart';

class SyncStatusBadge extends ConsumerWidget {
  final bool compact;

  const SyncStatusBadge({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncProvider);
    final status = syncState.status;
    final pendingCount = syncState.pendingOutboxCount;
    final friendlyError = syncState.userFriendlyError;

    // Determine colors and icon
    final Color badgeColor;
    final Color textColor;
    final IconData icon;
    final String label;

    if (status == SyncStatus.syncing) {
      badgeColor = const Color(0xFF3B82F6);
      textColor = const Color(0xFF1D4ED8);
      icon = Icons.sync_rounded;
      label = 'Eşitleniyor';
    } else if (pendingCount > 0) {
      badgeColor = const Color(0xFFF59E0B);
      textColor = const Color(0xFFB45309);
      icon = Icons.cloud_queue_rounded;
      label = '$pendingCount bekliyor';
    } else if (status == SyncStatus.error) {
      badgeColor = const Color(0xFFEF4444);
      textColor = const Color(0xFFB91C1C);
      icon = Icons.cloud_off_rounded;
      label = 'Bağlantı yok';
    } else {
      badgeColor = POSColors.green;
      textColor = POSColors.greenDark;
      icon = Icons.cloud_done_rounded;
      label = 'Eşitlendi';
    }

    final tooltip = friendlyError ??
        (status == SyncStatus.syncing
            ? 'Sunucu ile senkronizasyon yapılıyor...'
            : pendingCount > 0
                ? '$pendingCount işlem çevrimdışı kuyrukta bekliyor. İnternet gelince otomatik gönderilir.'
                : 'Tüm veriler bulut ile eşitlendi.');

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showSyncDetailsSheet(context, ref),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 4 : 6,
            ),
            decoration: BoxDecoration(
              color: badgeColor.withAlpha(25),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: badgeColor.withAlpha(75), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status == SyncStatus.syncing)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
                    ),
                  )
                else
                  Icon(icon, size: 15, color: badgeColor),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ] else if (pendingCount > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$pendingCount',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSyncDetailsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final syncState = ref.watch(syncProvider);
            final status = syncState.status;
            final pendingCount = syncState.pendingOutboxCount;
            final lastSyncAt = syncState.lastSyncAt;
            final friendlyError = syncState.userFriendlyError;

            final timeStr = lastSyncAt != null
                ? '${lastSyncAt.hour.toString().padLeft(2, '0')}:${lastSyncAt.minute.toString().padLeft(2, '0')}:${lastSyncAt.second.toString().padLeft(2, '0')}'
                : 'Bilinmiyor';

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.cloud_sync_rounded,
                            size: 26, color: POSColors.greenDark),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Veri Senkronizasyon Durumu',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: pendingCount > 0
                            ? const Color(0xFFFEF3C7)
                            : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: pendingCount > 0
                              ? const Color(0xFFFDE68A)
                              : const Color(0xFFDCFCE7),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            pendingCount > 0
                                ? Icons.inventory_2_outlined
                                : Icons.check_circle_outline_rounded,
                            color: pendingCount > 0
                                ? const Color(0xFFB45309)
                                : POSColors.green,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pendingCount > 0
                                      ? '$pendingCount bekleyen işlem kuyrukta'
                                      : 'Tüm satış ve kayıtlar eşitlendi',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: pendingCount > 0
                                        ? const Color(0xFF92400E)
                                        : const Color(0xFF166534),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  pendingCount > 0
                                      ? 'İşlemleriniz bu cihazın güvenli yerel veritabanında saklanır. İnternet bağlantısı sağlandığında otomatik olarak sunucuya aktarılır.'
                                      : 'Son başarılı eşitleme saati: $timeStr',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: pendingCount > 0
                                        ? const Color(0xFFB45309)
                                        : const Color(0xFF15803D),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (friendlyError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 18, color: Color(0xFFDC2626)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                friendlyError,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF991B1B),
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        icon: status == SyncStatus.syncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.refresh_rounded, size: 20),
                        label: Text(
                          status == SyncStatus.syncing
                              ? 'Eşitleniyor...'
                              : 'Şimdi Eşitle',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: POSColors.greenDark,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: status == SyncStatus.syncing
                            ? null
                            : () async {
                                await ref
                                    .read(syncProvider.notifier)
                                    .triggerSync();
                              },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
