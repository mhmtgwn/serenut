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
import 'package:serenutos/presentation/widgets/trial_banner_widget.dart';

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
    // Automatically manage real-time WebSocket connection and auto-sync topics
    ref.watch(realtimeAutoSyncProvider);
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                _PosSideBar(
                  items: navItems,
                  activeIndex: activeIndex,
                  onTap: (index) => _onTap(navItems[index]),
                ),
                const VerticalDivider(width: 1, thickness: 1, color: POSColors.border),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: navigationShell),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 6,
                        child: SafeArea(
                          top: false,
                          child: TrialBannerWidget(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: navigationShell),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 6,
                child: SafeArea(
                  top: false,
                  child: TrialBannerWidget(),
                ),
              ),
            ],
          ),
          bottomNavigationBar: _PosNavBar(
            items: navItems,
            activeIndex: activeIndex,
            onTap: (index) => _onTap(navItems[index]),
          ),
        );
      },
    );
  }

  bool _hasPermission(dynamic user, Permission permission) {
    if (user == null) return false;
    if (user.role == UserRole.owner || user.role == UserRole.sysadmin) {
      return true;
    }
    return user.hasPermission(permission.value);
  }

  void _onTap(_NavItem item) {
    navigationShell.goBranch(
      item.branchIndex,
      initialLocation: item.branchIndex == navigationShell.currentIndex,
    );
  }
}

// ── Sidebar (Desktop / Wide Screen) ──────────────────────────────────────────

class _PosSideBar extends StatelessWidget {
  final List<_NavItem> items;
  final int activeIndex;
  final void Function(int) onTap;

  const _PosSideBar({
    required this.items,
    required this.activeIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      color: POSColors.card,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _kGreenLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.point_of_sale_rounded,
                      color: _kGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'SERENUT OS',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: POSColors.text,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'POS & İşletim',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: POSColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: POSColors.border),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isActive = index == activeIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onTap(index),
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isActive ? _kGreenLight : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isActive ? item.activeIcon : item.icon,
                                size: 20,
                                color: isActive ? _kGreen : _kInactive,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isActive ? _kGreen : POSColors.text,
                                  ),
                                ),
                              ),
                              if (isActive)
                                Container(
                                  width: 4,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: _kGreen,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
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
      decoration: const BoxDecoration(
        color: POSColors.navBackground,
        border: Border(top: BorderSide(color: POSColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 360;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: items.asMap().entries.map((entry) {
                  return Expanded(
                    child: _NavBarItem(
                      item: entry.value,
                      isActive: entry.key == activeIndex,
                      compact: compact,
                      onTap: () => onTap(entry.key),
                    ),
                  );
                }).toList(),
              ),
            );
          },
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
  final bool compact;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.item,
    required this.isActive,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isActive,
      label: item.label,
      child: Tooltip(
        message: item.label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: AnimatedContainer(
                width: double.infinity,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 2 : 4,
                  vertical: 7,
                ),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 9 : 10,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? _kGreen : _kInactive,
                        letterSpacing: isActive ? 0.1 : 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
