import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart';
import 'package:serenutos/presentation/widgets/serenut_ui.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return FullScreenSettingsPage(
        title: 'Hesabım',
        useScrollView: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_circle_outlined,
                  size: 48, color: POSColors.textSecondary),
              const SizedBox(height: 16),
              const Text(
                'Aktif kullanıcı oturumu bulunamadı.',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: POSColors.text),
              ),
              const SizedBox(height: 8),
              const Text(
                'Lütfen tekrar giriş yapın.',
                style: TextStyle(fontSize: 13, color: POSColors.textSecondary),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: POSColors.green,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                  context.go(AppRoutes.login);
                },
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Giriş Yap'),
              ),
            ],
          ),
        ),
      );
    }
    return FullScreenSettingsPage(
      title: 'Hesabım',
      useScrollView: false,
      child: ListView(
        children: [
          _ProfileCard(user: user),
          const SizedBox(height: 16),
          _AccountAction(
            icon: Icons.badge_outlined,
            title: 'Kasiyer / Kullanıcı Adı',
            subtitle: '${user.name} (Fişlerde ve siparişlerde görünen isim)',
            onTap: () => _showEditNameDialog(context, ref, user.name),
          ),
          _AccountAction(
            icon: Icons.switch_account_rounded,
            title: 'Kullanıcı değiştir',
            subtitle: 'Başka bir çalışan hesabıyla giriş yapın',
            onTap: () async {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
              await ref.read(authNotifierProvider.notifier).logout('Kullanıcı değiştirildi.');
              if (context.mounted) context.go(AppRoutes.login);
            },
          ),
          _AccountAction(
            icon: Icons.history_rounded,
            title: 'Oturum & Çıkış Geçmişi',
            subtitle: 'Son oturum sonlandırma ve otomatik çıkış nedenlerini inceleyin',
            onTap: () => _showLogoutHistoryDialog(context, ref),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: POSColors.red,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () async {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
              await ref.read(authNotifierProvider.notifier).logout('Kullanıcı oturumu kapattı.');
              if (context.mounted) context.go(AppRoutes.login);
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Oturumu kapat'),
          ),
        ],
      ),
    );
  }

  void _showEditNameDialog(
      BuildContext context, WidgetRef ref, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Kasiyer / Kullanıcı İsmi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fişlerde ve siparişlerde görünen kasiyer adı bu bilgiden alınır.',
              style: TextStyle(fontSize: 13, color: POSColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Ad Soyad / Kasiyer İsmi',
                hintText: 'örn: Kasa 1 veya Adınız',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(dialogCtx);
              await ref
                  .read(authNotifierProvider.notifier)
                  .updateProfileName(newName);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Kasiyer ismi "$newName" olarak güncellendi.'),
                    backgroundColor: POSColors.green,
                  ),
                );
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _showLogoutHistoryDialog(BuildContext context, WidgetRef ref) {
    final authService = ref.read(authServiceProvider);
    final history = authService.getLogoutHistory();
    final lastReason = authService.getLastLogoutReason();
    final lastCode = authService.getLastLogoutCode();
    final lastTime = authService.getLastLogoutTime();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.history_rounded, color: POSColors.green),
            SizedBox(width: 8),
            Text(
              'Oturum & Çıkış Geçmişi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lastReason != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: POSColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: POSColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Son Kaydedilen Çıkış Bilgisi:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: POSColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lastReason,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: POSColors.text,
                          ),
                        ),
                        if (lastTime != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Zaman: ${lastTime.toLocal().toString().split('.').first} (${lastCode ?? ''})',
                            style: const TextStyle(
                              fontSize: 11,
                              color: POSColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text(
                  'Geçmiş Oturum Kapanma Olayları:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: POSColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                if (history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'Henüz kayıtlı çıkış geçmişi bulunmuyor.',
                        style: TextStyle(
                          fontSize: 12,
                          color: POSColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                else
                  ...history.map(
                    (item) => Container(
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
                                item['code']?.toString() ?? 'LOGOUT',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: POSColors.green,
                                ),
                              ),
                              Text(
                                item['time'] != null
                                    ? DateTime.tryParse(item['time'])
                                            ?.toLocal()
                                            .toString()
                                            .split('.')
                                            .first ??
                                        ''
                                    : '',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: POSColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item['reason']?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: POSColors.text,
                            ),
                          ),
                          if (item['details'] != null &&
                              item['details'].toString().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              item['details'].toString(),
                              style: const TextStyle(
                                fontSize: 11,
                                color: POSColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  final AuthUser user;

  const _ProfileCard({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SerenutSurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: POSColors.green,
              child: Text(
                user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    user.name,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 18, color: POSColors.green),
                  tooltip: 'Kasiyer / Kullanıcı İsmini Değiştir',
                  onPressed: () => (context.findAncestorWidgetOfExactType<AccountPage>() ?? const AccountPage())
                      ._showEditNameDialog(context, ref, user.name),
                ),
              ],
            ),
            Text(user.email,
                style: const TextStyle(color: POSColors.textSecondary)),
            const SizedBox(height: 12),
            Chip(label: Text(_roleLabel(user.role))),
            const Divider(height: 28),
            Material(
              color: Colors.transparent,
              child: ExpansionTile(
                title: const Text('Yetkilerim'),
                subtitle: Text('${user.permissions.length} özel yetki'),
                children: [
                  if (user.permissions.isEmpty)
                    const ListTile(
                      title: Text(
                          'Bu hesap rolün varsayılan yetkilerini kullanıyor.'),
                    )
                  else
                    for (final permission in user.permissions)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.check_circle_outline_rounded,
                            color: POSColors.green),
                        title: Text(permission),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AccountAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: POSColors.card,
      child: ListTile(
        leading: Icon(icon, color: POSColors.green),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

String _roleLabel(UserRole role) => switch (role) {
      UserRole.owner => 'İşletme Sahibi',
      UserRole.admin => 'Yönetici',
      UserRole.sysadmin => 'Sistem Yöneticisi',
      UserRole.manager => 'Müdür',
      UserRole.cashier => 'Kasiyer',
      UserRole.staff => 'Personel',
    };
