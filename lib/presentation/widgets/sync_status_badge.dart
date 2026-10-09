// lib/presentation/widgets/sync_status_badge.dart
// Serenut OS — Kasiyer İçin Senkronizasyon ve Çevrimdışı Kuyruk Durum Göstergesi

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
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
    final conflictCount = syncState.unresolvedConflictCount;
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
    } else if (status == SyncStatus.error) {
      badgeColor = const Color(0xFFEF4444);
      textColor = const Color(0xFFB91C1C);
      icon = Icons.cloud_off_rounded;
      label = conflictCount > 0 ? '$conflictCount çakışma' : 'Eşitleme sorunu';
    } else if (pendingCount > 0) {
      badgeColor = const Color(0xFFF59E0B);
      textColor = const Color(0xFFB45309);
      icon = Icons.cloud_queue_rounded;
      label = '$pendingCount bekliyor';
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
            final conflictCount = syncState.unresolvedConflictCount;
            final lastSyncAt = syncState.lastSyncAt;
            final friendlyError = syncState.userFriendlyError;
            final hasError = status == SyncStatus.error;

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
                        color: hasError
                            ? const Color(0xFFFEF2F2)
                            : pendingCount > 0
                                ? const Color(0xFFFEF3C7)
                                : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasError
                              ? const Color(0xFFFECACA)
                              : pendingCount > 0
                                  ? const Color(0xFFFDE68A)
                                  : const Color(0xFFDCFCE7),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            hasError
                                ? Icons.cloud_off_rounded
                                : pendingCount > 0
                                    ? Icons.inventory_2_outlined
                                    : Icons.check_circle_outline_rounded,
                            color: hasError
                                ? const Color(0xFFDC2626)
                                : pendingCount > 0
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
                                  hasError
                                      ? (conflictCount > 0
                                          ? '$conflictCount kayıt için eşitleme çakışması'
                                          : 'Senkronizasyon tamamlanamadı')
                                      : pendingCount > 0
                                          ? '$pendingCount bekleyen işlem kuyrukta'
                                          : 'Tüm satış ve kayıtlar eşitlendi',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: hasError
                                        ? const Color(0xFF991B1B)
                                        : pendingCount > 0
                                            ? const Color(0xFF92400E)
                                            : const Color(0xFF166534),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  hasError
                                      ? (conflictCount > 0
                                          ? 'Bu kayıtlar başka bir terminalde değiştirildi. Yeni satışlarınız güvende; yetkili kullanıcı senkronizasyon kayıtlarını incelemeli.'
                                          : 'Bekleyen işlemler bu cihazda saklanıyor. Bağlantı veya oturum düzeldiğinde yeniden eşitlenecek.')
                                      : pendingCount > 0
                                          ? 'İşlemleriniz bu cihazın güvenli yerel veritabanında saklanır. İnternet bağlantısı sağlandığında otomatik olarak sunucuya aktarılır.'
                                          : 'Son başarılı eşitleme saati: $timeStr',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: hasError
                                        ? const Color(0xFF991B1B)
                                        : pendingCount > 0
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
                    if (conflictCount > 0) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.rule_folder_outlined),
                          label: Text('$conflictCount çakışma kaydını incele'),
                          onPressed: () => _showConflictDetailsSheet(context),
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

  Future<void> _showConflictDetailsSheet(BuildContext context) async {
    final conflictsFuture = () async {
      final db = await DatabaseManager().getDatabase();
      return db.rawQuery('''
        SELECT entity_type, entity_id, server_revision, detected_at
        FROM sync_conflicts_v4
        WHERE resolved_at IS NULL
        ORDER BY detected_at DESC
        LIMIT 100
      ''');
    }();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Senkronizasyon çakışmaları',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Bu kayıtlar başka bir terminalde daha yeni bir değişiklik olduğu için otomatik uygulanmadı. Yerel işlem korunuyor; çakışmayı yetkili kullanıcı incelemeli.',
                  style: TextStyle(fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<Map<String, Object?>>>(
                    future: conflictsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Çakışma kayıtları şu anda yüklenemedi.'),
                        );
                      }
                      final conflicts = snapshot.data ?? const [];
                      if (conflicts.isEmpty) {
                        return const Center(
                          child: Text('Açık çakışma kaydı bulunmuyor.'),
                        );
                      }
                      return ListView.separated(
                        itemCount: conflicts.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final conflict = conflicts[index];
                          final type =
                              conflict['entity_type']?.toString() ?? 'kayıt';
                          final id = conflict['entity_id']?.toString() ?? '';
                          final revision =
                              conflict['server_revision']?.toString() ?? '—';
                          final detectedAt =
                              conflict['detected_at']?.toString() ?? '';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.sync_problem_outlined,
                                color: Color(0xFFDC2626)),
                            title: Text('$type · $id'),
                            subtitle: Text(
                              'Sunucu sürümü $revision${detectedAt.isEmpty ? '' : ' · $detectedAt'}',
                            ),
                          );
                        },
                      );
                    },
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
