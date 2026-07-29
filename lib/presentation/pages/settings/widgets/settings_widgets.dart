// lib/presentation/pages/settings/widgets/settings_widgets.dart
import 'package:flutter/material.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/widgets/serenut_ui.dart';

// ── Design Theme Sabitleri ───────────────────────────────────────────────────
const kBgColor = POSColors.surface;
const kCardBg = POSColors.card;
const kBorderColor = POSColors.border;
const kTextPrimary = POSColors.text;
const kTextSecondary = POSColors.textSecondary;
const kGreen = POSColors.green;
const kBlue = POSColors.blue;
const kOrange = POSColors.amber;
const kPurple = Color(0xFF8B5CF6); // Modern Violet
const kPink = POSColors.red;
const kGray = POSColors.textDisabled;
const kTeal = Color(0xFF0D9488); // Deep Teal

// ── iOS Bölücü Çizgisi ────────────────────────────────────────────────────────
class IOSDivider extends StatelessWidget {
  const IOSDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 56),
      height: 0.5,
      color: kBorderColor,
    );
  }
}

// ── Full-Screen Settings Page Route Container ─────────────────────────────────
class FullScreenSettingsPage extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final bool useScrollView;

  const FullScreenSettingsPage({
    required this.title,
    required this.child,
    this.actions,
    this.useScrollView = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: POSColors.surface,
      appBar: AppBar(
        backgroundColor: POSColors.card,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: kGreen),
          onPressed: () => Navigator.pop(context),
        ),
        actions: actions,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: useScrollView
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: child,
                  )
                : Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: child,
                  ),
          ),
        ),
      ),
    );
  }
}

class SettingsSurface extends StatelessWidget {
  const SettingsSurface({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return SerenutSurface(
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      child: child,
    );
  }
}
