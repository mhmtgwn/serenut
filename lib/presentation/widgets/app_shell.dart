// lib/presentation/widgets/app_shell.dart
// Bottom Navigation Shell — 5 tabs: Ana Sayfa, Satış, Siparişler, Müşteriler, Ürünler
// Ayarlar → AppBar icon (sağ üst)
// Raporlar → navbar'dan kaldırıldı

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/realtime/realtime_provider.dart';

// ── POS Tema Renkleri ─────────────────────────────────────────────────────────
const _kGreen = POSColors.green;
const _kGreenLight = POSColors.greenLight;
const _kInactive = POSColors.navInactive;

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

    final shellIndex = navigationShell.currentIndex;
    final currentUser = ref.watch(currentUserProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(activeShellIndexProvider) != shellIndex) {
        ref.read(activeShellIndexProvider.notifier).state = shellIndex;
      }
      // Trigger connection if already authenticated on initial build
      if (ref.read(isAuthenticatedProvider)) {
        ref.read(connectionManagerProvider).connect();
      }
    });

    final navItems = <_NavItem>[
      const _NavItem(
        label: 'Ana Sayfa',
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        branchIndex: 0,
      ),
      if (_hasPermission(currentUser, Permission.salesView))
        const _NavItem(
          label: 'Satış',
          icon: Icons.shopping_cart_outlined,
          activeIcon: Icons.shopping_cart_rounded,
          branchIndex: 1,
        ),
      if (_hasPermission(currentUser, Permission.ordersView))
        const _NavItem(
          label: 'Siparişler',
          icon: Icons.restaurant_menu_outlined,
          activeIcon: Icons.restaurant_menu_rounded,
          branchIndex: 2,
        ),
      if (_hasPermission(currentUser, Permission.customersView))
        const _NavItem(
          label: 'Müşteriler',
          icon: Icons.people_alt_outlined,
          activeIcon: Icons.people_alt_rounded,
          branchIndex: 3,
        ),
      if (_hasPermission(currentUser, Permission.inventoryView))
        const _NavItem(
          label: 'Ürünler',
          icon: Icons.inventory_2_outlined,
          activeIcon: Icons.inventory_2_rounded,
          branchIndex: 4,
        ),
    ];
    final activeIndex = navItems.indexWhere(
      (item) => item.branchIndex == shellIndex,
    );

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: _PosNavBar(
        items: navItems,
        activeIndex: activeIndex,
        onTap: (index) => _onTap(navItems[index]),
      ),
    );
  }

  bool _hasPermission(dynamic user, Permission permission) {
    if (user == null) return false;
    if (user.role == UserRole.owner || user.role == UserRole.admin) return true;
    return user.hasPermission(permission.value);
  }

  void _onTap(_NavItem item) {
    navigationShell.goBranch(
      item.branchIndex,
      initialLocation: item.branchIndex == navigationShell.currentIndex,
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
        color: POSColors.navBackground,
        border:
            const Border(top: BorderSide(color: POSColors.border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: POSColors.text.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, -4),
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
  final int branchIndex;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.branchIndex,
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
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? _kGreenLight : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.sm),
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
