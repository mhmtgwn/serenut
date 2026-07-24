import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/presentation/pages/settings/print_queue_page.dart';
import 'package:serenutos/presentation/pages/settings/sms_history_page.dart';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart';
import 'package:serenutos/presentation/pages/settings/widgets/sms_settings_sheet.dart';
import 'package:serenutos/providers/settings_provider.dart';

class OperationsCenterPage extends ConsumerWidget {
  const OperationsCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider).value;
    return FullScreenSettingsPage(
      title: 'Operasyon Merkezi',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _OperationsIntro(),
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
              title: 'Toplu SMS İşlemleri',
              description:
                  'Borç hatırlatması veya toplu duyuru gönderimi başlatın.',
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
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: kTextPrimary)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(description,
              style: const TextStyle(fontSize: 12, color: kTextSecondary)),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
