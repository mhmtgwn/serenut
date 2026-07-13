// lib/presentation/widgets/pos_page_layout.dart
// Serenut POS — Standart Ekran Tasarımı ve Üst Bar Bileşeni

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/presentation/widgets/realtime_status_indicator.dart';

// ── POS Tema Renkleri ──────────────────────────────────────────────────────────
const _kGreen = Color(0xFF16A34A);
const _kGreenDark = Color(0xFF15803D);
const _kRed = Color(0xFFDC2626);
const _kText = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);
const _kSurface = Color(0xFFF8FAFC);

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
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isSearching) ...[
                Expanded(
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: searchHint ?? 'Ara...',
                        hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, color: _kTextSecondary, size: 18),
                        suffixIcon: searchController != null && searchController!.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  searchController!.clear();
                                  if (onSearchChanged != null) {
                                    onSearchChanged!('');
                                  }
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                      ),
                      style: const TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w600),
                      onChanged: onSearchChanged,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: _kRed),
                  onPressed: () {
                    if (onSearchToggled != null) {
                      onSearchToggled!(false);
                    }
                    if (searchController != null) {
                      searchController!.clear();
                    }
                    if (onSearchChanged != null) {
                      onSearchChanged!('');
                    }
                  },
                ),
              ] else ...[
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _kText,
                    ),
                  ),
                ),
                if (onSearchToggled != null)
                  IconButton(
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.search_rounded, color: _kGreen, size: 22),
                    tooltip: 'Ara',
                    onPressed: () => onSearchToggled!(true),
                  ),
                if (actions != null) ...actions!,
                if (showRefresh && onRefresh != null)
                  IconButton(
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, color: _kTextSecondary, size: 22),
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
                    icon: const Icon(Icons.settings_outlined, color: _kTextSecondary, size: 22),
                    tooltip: 'Ayarlar',
                    onPressed: () => requireAdminAccess(
                      context,
                      title: 'Ayarlar Yetkisi',
                      onGranted: (_, __) => context.push(AppRoutes.settings),
                    ),
                  ),
              ],
            ],
          ),
          if (!isSearching && filterWidget != null) ...[
            const SizedBox(height: 12),
            filterWidget!,
          ],
        ],
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
      backgroundColor: _kSurface,
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
            const Divider(height: 1, color: _kBorder),
            const RealtimeStatusIndicator(compact: false),
            Expanded(child: body),
          ],
        ),
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}
