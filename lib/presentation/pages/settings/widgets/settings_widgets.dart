// lib/presentation/pages/settings/widgets/settings_widgets.dart
import 'package:flutter/material.dart';

// ── Design Theme Sabitleri ───────────────────────────────────────────────────
const kBgColor =
    Color(0xFFFAFAFC); // Sophisticated off-white / light slate grey
const kCardBg = Colors.white;
const kBorderColor = Color(0xFFF0F0F3); // Faint, subtle border
const kTextPrimary =
    Color(0xFF1E293B); // Slate-900: softer and cleaner than raw black
const kTextSecondary = Color(0xFF64748B); // Slate-500: elegant subtitle color
const kGreen = Color(0xFF10B981); // Emerald Green
const kBlue = Color(0xFF3B82F6); // Modern Blue
const kOrange = Color(0xFFF59E0B); // Modern Amber
const kPurple = Color(0xFF8B5CF6); // Modern Violet
const kPink = Color(0xFFEF4444); // Modern Rose/Red
const kGray = Color(0xFF94A3B8); // Cool Slate Grey
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
      backgroundColor: const Color(
          0xFFF2F2F7), // _kBgColor matching the main settings screen
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF000000), // _kTextPrimary
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded,
              color: kGreen), // _kGreen close button
          onPressed: () => Navigator.pop(context),
        ),
        actions: actions,
      ),
      body: SafeArea(
        child: useScrollView
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: child,
              )
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: child,
              ),
      ),
    );
  }
}
