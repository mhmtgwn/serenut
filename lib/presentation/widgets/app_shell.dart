// lib/presentation/widgets/app_shell.dart
// Bottom Navigation Shell — 5 tabs: Ana Sayfa, Satış, Siparişler, Müşteriler, Ürünler
// Ayarlar → AppBar icon (sağ üst)
// Raporlar → navbar'dan kaldırıldı

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/realtime/realtime_provider.dart';

// ── POS Tema Renkleri ─────────────────────────────────────────────────────────
const _kGreen = Color(0xFF16A34A);
const _kGreenLight = Color(0xFFDCFCE7);
const _kAmber = Color(0xFFEAB308);
const _kInactive = Color(0xFF9CA3AF);

final activeShellIndexProvider = StateProvider<int>((ref) => 0);

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({
    super.key,
    required this.navigationShell,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Automatically manage real-time WebSocket connection based on authentication
    ref.listen(isAuthenticatedProvider, (previous, next) {
      if (next) {
        ref.read(connectionManagerProvider).connect();
      } else {
        ref.read(connectionManagerProvider).disconnect();
      }
    });

    final activeIndex = navigationShell.currentIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(activeShellIndexProvider) != activeIndex) {
        ref.read(activeShellIndexProvider.notifier).state = activeIndex;
      }
      // Trigger connection if already authenticated on initial build
      if (ref.read(isAuthenticatedProvider)) {
        ref.read(connectionManagerProvider).connect();
      }
    });

    const navItems = [
      _NavItem(
        label: 'Ana Sayfa',
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        route: AppRoutes.home,
      ),
      _NavItem(
        label: 'Satış',
        icon: Icons.shopping_cart_outlined,
        activeIcon: Icons.shopping_cart_rounded,
        route: AppRoutes.sales,
      ),
      _NavItem(
        label: 'Siparişler',
        icon: Icons.restaurant_menu_outlined,
        activeIcon: Icons.restaurant_menu_rounded,
        route: AppRoutes.orders,
      ),
      _NavItem(
        label: 'Müşteriler',
        icon: Icons.people_alt_outlined,
        activeIcon: Icons.people_alt_rounded,
        route: AppRoutes.customers,
      ),
      _NavItem(
        label: 'Ürünler',
        icon: Icons.inventory_2_outlined,
        activeIcon: Icons.inventory_2_rounded,
        route: AppRoutes.products,
      ),
    ];

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: _PosNavBar(
        items: navItems,
        activeIndex: activeIndex,
        onTap: (index) => _onTap(index, navItems[index].route),
      ),
    );
  }

  void _onTap(int index, String route) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

// ── Bottom Nav Bar ────────────────────────────────────────────────────────────

class _PosNavBar extends StatelessWidget {
  final List<_NavItem> items;
  final int activeIndex;
  final void Function(int) onTap;

  const _PosNavBar({
    required this.items,
    required this.activeIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: items.asMap().entries.map((entry) {
              return _NavBarItem(
                item: entry.value,
                isActive: entry.key == activeIndex,
                onTap: () => onTap(entry.key),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ── Nav Item Model ────────────────────────────────────────────────────────────

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String route;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.route,
  });
}

// ── Nav Bar Item Widget ───────────────────────────────────────────────────────

class _NavBarItem extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? _kGreenLight : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                isActive ? item.activeIcon : item.icon,
                key: ValueKey(isActive),
                color: isActive ? _kGreen : _kInactive,
                size: 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? _kGreen : _kInactive,
                letterSpacing: isActive ? 0.2 : 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
