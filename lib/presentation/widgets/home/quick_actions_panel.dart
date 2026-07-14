import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/presentation/widgets/home/fast_collection_bottom_sheet.dart';

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
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
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
              color: Color(0xFF1E293B),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
              color: Color(0xFF64748B),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              // Responsive grid calculation
              int crossAxisCount = 3;
              if (width > 600) {
                crossAxisCount = 6;
              } else if (width > 400) crossAxisCount = 4;

              final itemWidth = (width - ((crossAxisCount - 1) * 12)) / crossAxisCount;
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
                children: [
                  QuickActionBtn(
                    label: 'POS Satış',
                    icon: Icons.add_shopping_cart_rounded,
                    color: const Color(0xFF10B981),
                    onTap: () => context.go(AppRoutes.sales),
                  ),
                  QuickActionBtn(
                    label: 'Hızlı Tahsilat',
                    icon: Icons.payments_rounded,
                    color: const Color(0xFF3B82F6),
                    onTap: () => FastCollectionBottomSheet.show(context),
                  ),
                  QuickActionBtn(
                    label: 'Siparişler',
                    icon: Icons.restaurant_menu_rounded,
                    color: const Color(0xFFF59E0B),
                    onTap: () => context.push(AppRoutes.orders),
                  ),
                  QuickActionBtn(
                    label: 'Yeni Cari',
                    icon: Icons.person_add_rounded,
                    color: const Color(0xFF8B5CF6),
                    onTap: () => context.push('/customers/add'),
                  ),
                  QuickActionBtn(
                    label: 'Yeni Ürün',
                    icon: Icons.add_box_rounded,
                    color: const Color(0xFF0D9488),
                    onTap: () => context.push('/products/add'),
                  ),
                  QuickActionBtn(
                    label: 'Finans Özet',
                    icon: Icons.bar_chart_rounded,
                    color: const Color(0xFF6366F1),
                    onTap: () => context.go(AppRoutes.finance),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
