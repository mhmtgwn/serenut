import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/presentation/widgets/home/fast_collection_bottom_sheet.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';

class QuickActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const QuickActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: POSColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class QuickActionsPanel extends ConsumerWidget {
  const QuickActionsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final actions = <Widget>[
      if (_hasPermission(user, Permission.salesCreate))
        QuickActionBtn(
          label: 'POS Satış',
          icon: Icons.add_shopping_cart_rounded,
          color: const Color(0xFF10B981),
          onTap: () => context.go(AppRoutes.sales),
        ),
      if (_hasPermission(user, Permission.paymentsRecord))
        QuickActionBtn(
          label: 'Hızlı Tahsilat',
          icon: Icons.payments_rounded,
          color: const Color(0xFF3B82F6),
          onTap: () => FastCollectionBottomSheet.show(context),
        ),
      if (_hasPermission(user, Permission.ordersView))
        QuickActionBtn(
          label: 'Siparişler',
          icon: Icons.restaurant_menu_rounded,
          color: const Color(0xFFF59E0B),
          onTap: () => context.go(AppRoutes.orders),
        ),
      if (_hasPermission(user, Permission.customersCreate))
        QuickActionBtn(
          label: 'Yeni Cari',
          icon: Icons.person_add_rounded,
          color: const Color(0xFF8B5CF6),
          onTap: () => context.push('/customers/add'),
        ),
      if (_hasPermission(user, Permission.inventoryAdjust))
        QuickActionBtn(
          label: 'Yeni Ürün',
          icon: Icons.add_box_rounded,
          color: const Color(0xFF0D9488),
          onTap: () => context.push('/products/add'),
        ),
      if (_hasPermission(user, Permission.settingsPrinter))
        QuickActionBtn(
          label: 'Donanım',
          icon: Icons.settings_input_component_rounded,
          color: const Color(0xFF059669),
          onTap: () => context.push(AppRoutes.hardware),
        ),
      if (_hasPermission(user, Permission.settingsFinance))
        QuickActionBtn(
          label: 'Finans Özet',
          icon: Icons.bar_chart_rounded,
          color: const Color(0xFF6366F1),
          onTap: () => context.push(AppRoutes.finance),
        ),
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.border),
        boxShadow: [
          BoxShadow(
            color: POSColors.text.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HIZLI İŞLEMLER',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: POSColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              // Responsive grid calculation
              int crossAxisCount = actions.length < 3 ? actions.length : 3;
              if (width > 600) {
                crossAxisCount = actions.length < 6 ? actions.length : 6;
              } else if (width > 400) {
                crossAxisCount = actions.length < 4 ? actions.length : 4;
              }

              final itemWidth =
                  (width - ((crossAxisCount - 1) * 12)) / crossAxisCount;
              const spacing = 12.0;
              const childHeight = 90.0;
              final aspectRatio = itemWidth / childHeight;

              return GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: spacing,
                childAspectRatio: aspectRatio,
                children: actions,
              );
            },
          ),
        ],
      ),
    );
  }

  bool _hasPermission(dynamic user, Permission permission) {
    if (user == null) return false;
    if (user.role == UserRole.owner || user.role == UserRole.admin) return true;
    return user.hasPermission(permission.value);
  }
}
