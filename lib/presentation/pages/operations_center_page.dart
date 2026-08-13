import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/presentation/pages/settings/print_queue_page.dart';
import 'package:serenutos/presentation/pages/settings/sms_history_page.dart';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart';
import 'package:serenutos/presentation/pages/settings/widgets/sms_settings_sheet.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:serenutos/providers/sms_provider.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/config/theme.dart';

final _operationPrintSummaryProvider = FutureProvider.autoDispose((ref) async {
  final jobs = await ref.watch(printingRepositoryProvider).getJobs();
  return (
    pending: jobs
        .where(
          (job) =>
              job.state == PrintJobState.queued ||
              job.state == PrintJobState.rendering ||
              job.state == PrintJobState.sending ||
              job.state == PrintJobState.retryWait ||
              job.state == PrintJobState.awaitingUserCheck,
        )
        .length,
    failed: jobs
        .where(
          (job) =>
              job.state == PrintJobState.failed ||
              job.state == PrintJobState.rejected,
        )
        .length,
  );
});

class OperationsCenterPage extends ConsumerWidget {
  const OperationsCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider).value;
    final smsPending = ref.watch(smsPendingCountProvider).valueOrNull ?? 0;
    final printSummary = ref.watch(_operationPrintSummaryProvider).valueOrNull;
    return FullScreenSettingsPage(
      title: 'Operasyon Merkezi',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _OperationsIntro(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatusTile(
                label: 'Bekleyen SMS',
                value: '$smsPending',
                icon: Icons.sms_outlined,
                attention: smsPending > 0,
              ),
              _StatusTile(
                label: 'Bekleyen Baskı',
                value: '${printSummary?.pending ?? 0}',
                icon: Icons.print_outlined,
                attention: (printSummary?.pending ?? 0) > 0,
              ),
              _StatusTile(
                label: 'Başarısız Baskı',
                value: '${printSummary?.failed ?? 0}',
                icon: Icons.error_outline_rounded,
                attention: (printSummary?.failed ?? 0) > 0,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _OperationCard(
            icon: Icons.print_rounded,
            color: kBlue,
            title: 'Yazıcı Kuyruğu',
            description:
                'Bekleyen ve başarısız çıktı işlerini inceleyin, yeniden deneyin.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PrintQueuePage()),
            ),
          ),
          if (settings != null) ...[
            const SizedBox(height: 12),
            _OperationCard(
              icon: Icons.campaign_rounded,
              color: kPurple,
              title: 'Müşteri İletişimi',
              description:
                  'Bakiye hatırlatması veya tanıtım ve duyuru mesajı gönderin.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SmsSettingsSheet(
                    settings: settings,
                    operationsOnly: true,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _OperationCard(
            icon: Icons.sms_rounded,
            color: kOrange,
            title: 'SMS Gönderim Geçmişi',
            description:
                'Gönderilen, bekleyen ve başarısız mesajları takip edin.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SmsHistoryPage()),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.attention,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool attention;

  @override
  Widget build(BuildContext context) => Container(
        width: 170,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: attention ? POSColors.amberLight : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorderColor),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: attention ? POSColors.amberDark : POSColors.green),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: kTextSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _OperationsIntro extends StatelessWidget {
  const _OperationsIntro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderColor),
      ),
      child: const Row(
        children: [
          Icon(Icons.monitor_heart_outlined, color: kGreen, size: 38),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Günlük işlemleri takip edin',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: kTextPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Ayar değiştirmeden, tamamlanmamış operasyonları tek merkezden yönetin.',
                  style: TextStyle(fontSize: 12, color: kTextSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _OperationCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: kBorderColor),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .1),
          foregroundColor: color,
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: kTextPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            description,
            style: const TextStyle(fontSize: 12, color: kTextSecondary),
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
