// lib/presentation/widgets/pos_page_layout.dart
// Serenut OS — Standart Ekran Tasarımı ve Üst Bar Bileşeni

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/presentation/widgets/realtime_status_indicator.dart';
import 'package:serenutos/config/theme.dart';

/// POS Standart Üst Bar (Header) Bileşeni
class PosHeader extends StatelessWidget {
  final String title;
  final bool isSearching;
  final ValueChanged<bool>? onSearchToggled;
  final TextEditingController? searchController;
  final String? searchHint;
  final ValueChanged<String>? onSearchChanged;
  final List<Widget>? actions;
  final Widget? filterWidget;
  final bool showSettings;
  final bool showRefresh;
  final VoidCallback? onRefresh;
  final bool showStatusIndicator;

  const PosHeader({
    super.key,
    required this.title,
    this.isSearching = false,
    this.onSearchToggled,
    this.searchController,
    this.searchHint,
    this.onSearchChanged,
    this.actions,
    this.filterWidget,
    this.showSettings = true,
    this.showRefresh = false,
    this.onRefresh,
    this.showStatusIndicator = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasSearch = onSearchChanged != null || searchController != null;

    return Material(
      color: POSColors.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm + 4,
          AppSpacing.md,
          AppSpacing.sm + 4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Title & Actions Row — Always Stable & Clean
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                if (actions != null) ...actions!,
                if (showRefresh && onRefresh != null)
                  IconButton(
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 22),
                    tooltip: 'Yenile',
                  ),
                if (showStatusIndicator) ...[
                  const RealtimeStatusIndicator(compact: true),
                  const SizedBox(width: 4),
                ],
                if (showSettings)
                  IconButton(
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.settings_outlined, size: 22),
                    tooltip: 'Ayarlar',
                    onPressed: () => requirePermissionAccess(
                      context,
                      permission: Permission.settingsView,
                      title: 'Ayarlar Yetkisi',
                      onGranted: (_, __) => context.push(AppRoutes.settings),
                    ),
                  ),
              ],
            ),

            // Inline Search Bar (Zero-Click Mode & 1-Tap Clear)
            if (hasSearch || isSearching) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: searchController ?? TextEditingController(),
                  builder: (context, value, _) {
                    final isNotEmpty = value.text.isNotEmpty;

                    return TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: searchHint ?? 'Ara...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: isNotEmpty
                            ? IconButton(
                                icon:
                                    const Icon(Icons.cancel_rounded, size: 18),
                                onPressed: () {
                                  if (searchController != null) {
                                    searchController!.clear();
                                  }
                                  if (onSearchChanged != null) {
                                    onSearchChanged!('');
                                  }
                                },
                              )
                            : null,
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: POSColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                      onChanged: onSearchChanged,
                    );
                  },
                ),
              ),
            ],

            // Filter Widget Row
            if (filterWidget != null) ...[
              const SizedBox(height: 8),
              filterWidget!,
            ],
          ],
        ),
      ),
    );
  }
}

/// POS Standart Sayfa Düzeni (Scaffold Dahil)
class PosPageLayout extends StatelessWidget {
  final String title;
  final Widget body;
  final bool isSearching;
  final ValueChanged<bool>? onSearchToggled;
  final TextEditingController? searchController;
  final String? searchHint;
  final ValueChanged<String>? onSearchChanged;
  final List<Widget>? actions;
  final Widget? filterWidget;
  final Widget? floatingActionButton;
  final bool showSettings;
  final bool showRefresh;
  final VoidCallback? onRefresh;

  const PosPageLayout({
    super.key,
    required this.title,
    required this.body,
    this.isSearching = false,
    this.onSearchToggled,
    this.searchController,
    this.searchHint,
    this.onSearchChanged,
    this.actions,
    this.filterWidget,
    this.floatingActionButton,
    this.showSettings = true,
    this.showRefresh = false,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            PosHeader(
              title: title,
              isSearching: isSearching,
              onSearchToggled: onSearchToggled,
              searchController: searchController,
              searchHint: searchHint,
              onSearchChanged: onSearchChanged,
              actions: actions,
              filterWidget: filterWidget,
              showSettings: showSettings,
              showRefresh: showRefresh,
              onRefresh: onRefresh,
            ),
            const Divider(height: 1),
            const RealtimeStatusIndicator(compact: false),
            Expanded(child: body),
          ],
        ),
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}
