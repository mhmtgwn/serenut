// lib/presentation/widgets/app_shell.dart
// Bottom Navigation Shell — 5 tabs: Ana Sayfa, Satış, Siparişler, Müşteriler, Ürünler
// Ayarlar → AppBar icon (sağ üst)
// Raporlar → navbar'dan kaldırıldı

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/printing/printing_engine.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/printing_providers.dart';
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

    ref.listen<AsyncValue<PrintCoordinatorEvent>>(
      printCoordinatorEventsProvider,
      (previous, next) {
        final event = next.valueOrNull;
        if (event == null) return;
        if (event.type == PrintCoordinatorEventType.failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Yazıcı Hatası: ${event.message}'),
              backgroundColor: Colors.red.shade700,
              action: SnackBarAction(
                label: 'Kuyruk',
                textColor: Colors.white,
                onPressed: () => context.push('/settings/print-queue'),
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        } else if (event.type == PrintCoordinatorEventType.awaitingUserCheck) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Yazıcı çıktısı kontrol edilmeli.'),
              backgroundColor: Colors.orange.shade800,
              action: SnackBarAction(
                label: 'Doğrula',
                textColor: Colors.white,
                onPressed: () => context.push('/settings/print-queue'),
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      },
    );

    final shellIndex = navigationShell.currentIndex;
    final currentUser = ref.watch(currentUserProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(activeShellIndexProvider) != shellIndex) {
        ref.read(activeShellIndexProvider.notifier).state = shellIndex;
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
      height: 60,
      decoration: const BoxDecoration(
        color: POSColors.navBackground,
        border: Border(top: BorderSide(color: POSColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 360;
            return Center(
              heightFactor: 1.0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
                ),
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
