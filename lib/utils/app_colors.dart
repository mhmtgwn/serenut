import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors
  static const primary = Color(0xFF2E7D32); // Yeşil
  static const primaryDark = Color(0xFF1B5E20);
  static const primaryLight = Color(0xFF4CAF50);

  // Secondary Colors
  static const secondary = Color(0xFF1976D2); // Mavi
  static const secondaryDark = Color(0xFF0D47A1);
  static const secondaryLight = Color(0xFF42A5F5);

  // Accent Colors
  static const accent = Color(0xFFF57C00); // Turuncu
  static const accentLight = Color(0xFFFFB74D);

  // Status Colors
  static const success = Color(0xFF4CAF50);
  static const warning = Color(0xFFFFA726);
  static const error = Color(0xFFEF5350);
  static const info = Color(0xFF29B6F6);

  // Neutral Colors
  static const background = Color(0xFFF5F5F5);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceVariant = Color(0xFFFAFAFA);

  // Text Colors
  static const textPrimary = Color(0xFF212121);
  static const textSecondary = Color(0xFF757575);
  static const textHint = Color(0xFFBDBDBD);

  // Gradients
  static const primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const successGradient = LinearGradient(
    colors: [success, Color(0xFF66BB6A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
