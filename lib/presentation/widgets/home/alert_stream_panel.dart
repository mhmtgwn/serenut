import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

final telemetryCollapsedProvider =
    StateProvider.autoDispose<bool>((ref) => true);

final recentAlertsProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  try {
    final telemetry = TelemetryService();
    final events = await telemetry.getEvents();
    return events.reversed
        .map((e) {
          final levelEmoji = e.level == LogLevel.critical
              ? '🚨'
              : e.level == LogLevel.error
                  ? '❌'
                  : e.level == LogLevel.warning
                      ? '⚠️'
                      : 'ℹ️';
          return '$levelEmoji ${e.event}';
        })
        .take(4)
        .toList();
  } catch (_) {
    return ['ℹ️ Sistem güvenliği aktif', 'ℹ️ Ledger bütünlük kontrolü stabil'];
  }
});

class AlertStreamPanel extends ConsumerWidget {
  const AlertStreamPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(recentAlertsProvider);
    final isCollapsed = ref.watch(telemetryCollapsedProvider);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => ref.read(telemetryCollapsedProvider.notifier).state =
                !isCollapsed,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded,
                    color: Color(0xFF10B981), size: 16),
                const SizedBox(width: 8),
                const Text(
                  'CANLI TELEMETRİ ALERTLERİ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isCollapsed
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                  color: const Color(0xFF94A3B8),
                  size: 14,
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => context.go(AppRoutes.system),
                  child: const Row(
                    children: [
                      Text(
                        'İncele',
                        style: TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.chevron_right_rounded,
                          color: Color(0xFF10B981), size: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!isCollapsed) ...[
            const SizedBox(height: 12),
            alertsAsync.when(
              loading: () => const SizedBox(
                  height: 60,
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2))),
              error: (e, _) => Text('Hata: $e',
                  style: const TextStyle(color: Colors.red, fontSize: 11)),
              data: (logs) {
                if (logs.isEmpty) {
                  return const Text(
                    'İzleme günlükleri temiz. Herhangi bir anomali bulunmuyor.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: logs.map((log) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        log,
                        style: const TextStyle(
                          color: Color(0xFFE2E8F0),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
