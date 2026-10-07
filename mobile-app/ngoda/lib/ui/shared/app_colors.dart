import 'package:flutter/material.dart';

abstract final class AppColors {
  AppColors._();

  // ---------------------------------------------------------------------------
  // Brand
  // ---------------------------------------------------------------------------

  static const Color gold = Color(0xFFD4AF37);
  static const Color goldSoft = Color(0xFFC6A84B);

  static const Color purple = Color(0xFF4B3FAE);
  static const Color purpleSoft = Color(0xFF6658C7);

  // ---------------------------------------------------------------------------
  // Light theme
  // ---------------------------------------------------------------------------

  static const Color lightBackground = Color(0xFFF5F3EF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);

  static const Color lightForeground = Color(0xFF1E293B);
  static const Color lightForegroundSecondary = Color(0xFF64748B);
  static const Color lightForegroundDisabled = Color(0xFF94A3B8);

  static const Color lightPrimary = goldSoft;
  static const Color lightOnPrimary = Color(0xFF1A1608);

  static const Color lightSecondary = Color(0xFF3D2C8D);
  static const Color lightOnSecondary = Colors.white;

  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightDivider = Color(0xFFE5E7EB);

  // ---------------------------------------------------------------------------
  // Dark theme
  // ---------------------------------------------------------------------------

  static const Color darkBackground = Color(0xFF0B0F1A);
  static const Color darkSurface = Color(0xFF111827);
  static const Color darkCard = Color(0xFF141A2A);

  static const Color darkForeground = Color(0xFFE5E7EB);
  static const Color darkForegroundSecondary = Color(0xFF9CA3AF);
  static const Color darkForegroundDisabled = Color(0xFF6B7280);

  static const Color darkPrimary = gold;
  static const Color darkOnPrimary = Color(0xFF1A1608);

  static const Color darkSecondary = purpleSoft;
  static const Color darkOnSecondary = Colors.white;

  static const Color darkBorder = Color(0xFF293244);
  static const Color darkDivider = Color(0xFF252D3D);

  // ---------------------------------------------------------------------------
  // Semantic
  // ---------------------------------------------------------------------------

  static const Color success = Color(0xFF16A34A);
  static const Color successDark = Color(0xFF4ADE80);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningDark = Color(0xFFFBBF24);

  static const Color error = Color(0xFFDC2626);
  static const Color errorDark = Color(0xFFDC2626); // Color(0xFFF87171);

  static const Color info = Color(0xFF2563EB);
  static const Color infoDark = Color(0xFF60A5FA);

  // ---------------------------------------------------------------------------
  // Financial
  // ---------------------------------------------------------------------------

  static const Color positive = Color(0xFF16A34A);
  static const Color positiveDark = Color(0xFF4ADE80);

  static const Color negative = Color(0xFFDC2626);
  static const Color negativeDark = Color(0xFFF87171);
}
