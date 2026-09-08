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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
              await ref.read(authNotifierProvider.notifier).logout();
              if (context.mounted) context.go(AppRoutes.login);
            },
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: POSColors.red,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () async {
              await ref.read(authNotifierProvider.notifier).logout();
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
