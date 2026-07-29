// lib/presentation/widgets/pos_page_layout.dart
// Serenut OS — Standart Ekran Tasarımı ve Üst Bar Bileşeni

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/presentation/widgets/realtime_status_indicator.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/widgets/serenut_ui.dart';

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpacing.md : AppSpacing.lg,
              vertical: compact ? AppSpacing.sm : AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (compact)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      if (actions != null) ...actions!,
                      if (hasSearch)
                        IconButton(
                          tooltip:
                              isSearching ? 'Aramayı kapat' : 'Ara ve filtrele',
                          onPressed: () => onSearchToggled?.call(!isSearching),
                          icon: Icon(
                            isSearching
                                ? Icons.close_rounded
                                : Icons.search_rounded,
                          ),
                        ),
                      if (showRefresh && onRefresh != null)
                        IconButton(
                          onPressed: onRefresh,
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: 'Yenile',
                        ),
                      if (showStatusIndicator) ...[
                        const RealtimeStatusIndicator(compact: true),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      if (showSettings)
                        IconButton(
                          icon: const Icon(Icons.settings_outlined),
                          tooltip: 'Ayarlar',
                          onPressed: () => requirePermissionAccess(
                            context,
                            permission: Permission.settingsView,
                            title: 'Ayarlar Yetkisi',
                            onGranted: (_, __) =>
                                context.push(AppRoutes.settings),
                          ),
                        ),
                    ],
                  )
                else
                  SerenutSectionHeader(
                    eyebrow: 'SERENUT OS',
                    title: title,
                    trailing: _HeaderActions(
                      actions: actions,
                      hasSearch: hasSearch,
                      isSearching: isSearching,
                      onSearchToggled: onSearchToggled,
                      showRefresh: showRefresh,
                      onRefresh: onRefresh,
                      showStatusIndicator: showStatusIndicator,
                      showSettings: showSettings,
                    ),
                  ),

                // Mobilde arama ve filtre içerik alanını kaplamaz; kullanıcı
                // arama ikonuna dokunduğunda birlikte açılır.
                if (isSearching) ...[
                  const SizedBox(height: AppSpacing.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable:
                          searchController ?? TextEditingController(),
                      builder: (context, value, _) {
                        final isNotEmpty = value.text.isNotEmpty;

                        return TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            hintText: searchHint ?? 'Ara...',
                            prefixIcon:
                                const Icon(Icons.search_rounded, size: 18),
                            suffixIcon: isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.cancel_rounded,
                                        size: 18),
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
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: POSColors.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                          onChanged: onSearchChanged,
                        );
                      },
                    ),
                  ),
                  if (filterWidget != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    filterWidget!,
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeaderActions extends StatelessWidget {
  const _HeaderActions({
    required this.actions,
    required this.hasSearch,
    required this.isSearching,
    required this.onSearchToggled,
    required this.showRefresh,
    required this.onRefresh,
    required this.showStatusIndicator,
    required this.showSettings,
  });

  final List<Widget>? actions;
  final bool hasSearch;
  final bool isSearching;
  final ValueChanged<bool>? onSearchToggled;
  final bool showRefresh;
  final VoidCallback? onRefresh;
  final bool showStatusIndicator;
  final bool showSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (actions != null) ...actions!,
        if (hasSearch)
          IconButton(
            tooltip: isSearching ? 'Aramayı kapat' : 'Ara ve filtrele',
            onPressed: () => onSearchToggled?.call(!isSearching),
            icon: Icon(
              isSearching ? Icons.close_rounded : Icons.search_rounded,
            ),
          ),
        if (showRefresh && onRefresh != null)
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Yenile',
          ),
        if (showStatusIndicator) ...[
          const RealtimeStatusIndicator(compact: true),
          const SizedBox(width: AppSpacing.sm),
        ],
        if (showSettings)
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ayarlar',
            onPressed: () => requirePermissionAccess(
              context,
              permission: Permission.settingsView,
              title: 'Ayarlar Yetkisi',
              onGranted: (_, __) => context.push(AppRoutes.settings),
            ),
          ),
      ],
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
            Expanded(
              child: ColoredBox(
                color: POSColors.surface,
                child: body,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}
