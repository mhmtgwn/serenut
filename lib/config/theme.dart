import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ════════════════════════════════════════════════════════════
/// POSColors — Serenut OS Merkezi Renk Paleti
/// Tüm sayfalar bu sınıftan beslenmeli
/// Yeşil / Sarı / Beyaz / Siyah / Slate sistemi
/// ════════════════════════════════════════════════════════════
class POSColors {
  POSColors._();

  // ── Ana Renk: Yeşil ──────────────────────────────────────
  static const green = Color(0xFF16A34A);
  static const greenDark = Color(0xFF15803D);
  static const greenLight = Color(0xFFDCFCE7);
  static const greenMid = Color(0xFF22C55E);

  // ── Vurgu: Sarı / Amber ──────────────────────────────────
  static const amber = Color(0xFFE8BD3F);
  static const amberDark = Color(0xFFB8870E);
  static const amberLight = Color(0xFFFFF8DC);

  // ── Yüzey ────────────────────────────────────────────────
  static const surface = Color(0xFFF8FAFC); // Arka plan
  static const card = Color(0xFFFFFFFF); // Kart zemini
  static const border = Color(0xFFE2E8F0); // Çerçeve
  static const surfaceMuted = Color(0xFFF1F5F9);
  static const darkSurface = Color(0xFF0F172A);

  // ── Metin ────────────────────────────────────────────────
  static const text = Color(0xFF0F172A); // Ana metin
  static const textSecondary = Color(0xFF64748B); // İkincil metin
  static const textDisabled = Color(0xFF94A3B8); // Devre dışı

  // ── Durum ────────────────────────────────────────────────
  static const red = Color(0xFFDC2626);
  static const redLight = Color(0xFFFEE2E2);
  static const orange = Color(0xFFF97316);
  static const orangeLight = Color(0xFFFFEDD5);
  static const blue = Color(0xFF2563EB); // Sadece grafik rengi
  static const blueLight = Color(0xFFDBEAFE);

  // ── Navigasyon ───────────────────────────────────────────
  static const navInactive = Color(0xFF64748B);
  static const navBackground = Color(0xFFFFFFFF);

  // ── Gölge ────────────────────────────────────────────────
  static const shadowColor = Color(0x0F000000);
}

/// ════════════════════════════════════════════════════════════
/// AppSpacing — Spacing tokens
/// ════════════════════════════════════════════════════════════
class AppSpacing {
  AppSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class AppRadii {
  AppRadii._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 18.0;
  static const pill = 999.0;
}

/// ════════════════════════════════════════════════════════════
/// AppTheme — ThemeData
/// ════════════════════════════════════════════════════════════
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final baseTextTheme = GoogleFonts.interTextTheme();
    TextStyle? heading(TextStyle? style) => GoogleFonts.outfit(
          textStyle: style,
          letterSpacing: -0.25,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: POSColors.green,
        onPrimary: Colors.white,
        primaryContainer: POSColors.greenLight,
        onPrimaryContainer: POSColors.greenDark,
        secondary: POSColors.amber,
        onSecondary: Colors.white,
        secondaryContainer: POSColors.amberLight,
        onSecondaryContainer: POSColors.amberDark,
        surface: POSColors.card,
        onSurface: POSColors.text,
        error: POSColors.red,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: POSColors.surface,

      // ── Text Theme ──────────────────────────────────────
      textTheme: baseTextTheme.copyWith(
        displayLarge: heading(baseTextTheme.displayLarge)?.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: POSColors.text,
        ),
        headlineLarge: heading(baseTextTheme.headlineLarge)?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: POSColors.text,
        ),
        headlineMedium: heading(baseTextTheme.headlineMedium)?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: POSColors.text,
        ),
        headlineSmall: heading(baseTextTheme.headlineSmall)?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: POSColors.text,
        ),
        titleLarge: heading(baseTextTheme.titleLarge)?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: POSColors.text,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          fontSize: 16,
          color: POSColors.text,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          fontSize: 14,
          color: POSColors.textSecondary,
        ),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: POSColors.text,
        ),
      ),

      // ── AppBar ──────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: POSColors.card,
        foregroundColor: POSColors.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: heading(baseTextTheme.titleLarge)?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: POSColors.text,
        ),
        iconTheme: const IconThemeData(color: POSColors.green),
      ),

      // ── Card ────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: const BorderSide(color: POSColors.border, width: 1),
        ),
        color: POSColors.card,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
      ),

      // ── FAB ─────────────────────────────────────────────
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: POSColors.green,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.md)),
        ),
      ),

      // ── ElevatedButton ───────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: POSColors.green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: POSColors.border,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm + 4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
          ),
          textStyle: baseTextTheme.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      // ── OutlinedButton ───────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: POSColors.green,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm + 4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
          ),
          side: const BorderSide(color: POSColors.border),
        ),
      ),

      // ── TextButton ───────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: POSColors.green,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      // ── InputDecoration ──────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: POSColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 4,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: const BorderSide(color: POSColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: const BorderSide(color: POSColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: const BorderSide(color: POSColors.green, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: const BorderSide(color: POSColors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: const BorderSide(color: POSColors.red, width: 2),
        ),
        labelStyle:
            const TextStyle(color: POSColors.textSecondary, fontSize: 14),
        hintStyle: const TextStyle(color: POSColors.textDisabled, fontSize: 14),
        prefixIconColor: POSColors.textSecondary,
        suffixIconColor: POSColors.textSecondary,
      ),

      // ── Divider ──────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: POSColors.border,
        thickness: 1,
        space: 0,
      ),

      // ── Chip ─────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: POSColors.surface,
        selectedColor: POSColors.greenLight,
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: POSColors.text,
        ),
        side: const BorderSide(color: POSColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
      ),

      // ── ProgressIndicator ────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: POSColors.green,
      ),

      // ── Switch ───────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return POSColors.green;
          return POSColors.textDisabled;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return POSColors.greenLight;
          }
          return POSColors.border;
        }),
      ),

      // ── Website ile ortak yüzey ve kontrol dili ─────────
      dialogTheme: DialogThemeData(
        backgroundColor: POSColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: POSColors.text.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: const BorderSide(color: POSColors.border),
        ),
        titleTextStyle: heading(baseTextTheme.titleLarge)?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: POSColors.text,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: POSColors.card,
        modalBackgroundColor: POSColors.card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.lg),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: POSColors.darkSurface,
        contentTextStyle: baseTextTheme.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: const Color(0xFF6EE7AD),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: POSColors.textSecondary,
        textColor: POSColors.text,
        selectedColor: POSColors.green,
        selectedTileColor: POSColors.greenLight,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.sm)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor:
              const WidgetStatePropertyAll(POSColors.textSecondary),
          overlayColor: WidgetStatePropertyAll(
            POSColors.green.withValues(alpha: 0.08),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return POSColors.green;
          return Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: POSColors.textDisabled, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return POSColors.green;
          return POSColors.textDisabled;
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: POSColors.green,
        unselectedLabelColor: POSColors.textSecondary,
        indicatorColor: POSColors.green,
        dividerColor: POSColors.border,
        labelStyle: baseTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: POSColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: const BorderSide(color: POSColors.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: POSColors.navBackground,
        surfaceTintColor: Colors.transparent,
        indicatorColor: POSColors.greenLight,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? POSColors.green
                : POSColors.navInactive,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return baseTextTheme.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? POSColors.green
                : POSColors.navInactive,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          );
        }),
      ),

      // ── Bottom Navigation ────────────────────────────────
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: POSColors.navBackground,
        selectedItemColor: POSColors.green,
        unselectedItemColor: POSColors.navInactive,
        elevation: 8,
      ),
    );
  }
}

/// ════════════════════════════════════════════════════════════
/// AppColors — Geriye dönük uyumluluk (eski kod için)
/// Yeni kod POSColors kullanmalı
/// ════════════════════════════════════════════════════════════
@Deprecated('POSColors kullanın')
class AppColors {
  static const primary = POSColors.green;
  static const primaryLight = POSColors.greenMid;
  static const primaryDark = POSColors.greenDark;
  static const secondary = POSColors.amber;
  static const secondaryLight = POSColors.amberLight;
  static const secondaryDark = POSColors.amberDark;
  static const background = POSColors.surface;
  static const surface = POSColors.card;
  static const border = POSColors.border;
  static const textPrimary = POSColors.text;
  static const textSecondary = POSColors.textSecondary;
  static const textDisabled = POSColors.textDisabled;
  static const success = POSColors.green;
  static const warning = POSColors.amber;
  static const danger = POSColors.red;
  static const cardBackground = POSColors.surface;
  static const cardBorder = POSColors.border;
}
