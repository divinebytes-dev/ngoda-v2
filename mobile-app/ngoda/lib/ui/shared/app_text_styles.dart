import 'package:flutter/material.dart';
import 'package:ngoda/services/screen_scaling_service.dart';

import 'app_colors.dart';
import 'app_fonts.dart';

abstract final class AppTextStyles {
  AppTextStyles._();

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static Color _primaryTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface;
  }

  static Color _secondaryTextColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return isDark
        ? AppColors.darkForegroundSecondary
        : AppColors.lightForegroundSecondary;
  }

  static TextStyle _text(
    BuildContext context, {
    required double size,
    FontWeight fontWeight = FontWeight.w500,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: AppFonts.text,
      fontSize: ScreenScalingService.scaleFont(context, size),
      fontWeight: fontWeight,
      color: color ?? _primaryTextColor(context),
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle _number(
    BuildContext context, {
    required double size,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: AppFonts.numbers,
      fontSize: ScreenScalingService.scaleFont(context, size),
      fontWeight: fontWeight,
      color: color ?? _primaryTextColor(context),
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  // ---------------------------------------------------------------------------
  // Standard text
  // ---------------------------------------------------------------------------

  static TextStyle tiny(BuildContext context) {
    return _text(
      context,
      size: 12,
      fontWeight: FontWeight.w500,
      color: _secondaryTextColor(context),
    );
  }

  static TextStyle small(BuildContext context) {
    return _text(context, size: 14, fontWeight: FontWeight.w500);
  }

  static TextStyle medium(BuildContext context) {
    return _text(context, size: 18, fontWeight: FontWeight.w600);
  }

  static TextStyle large(BuildContext context) {
    return _text(context, size: 22, fontWeight: FontWeight.w700);
  }

  static TextStyle veryLarge(BuildContext context) {
    return _text(context, size: 26, fontWeight: FontWeight.w700);
  }

  // ---------------------------------------------------------------------------
  // Supporting text
  // ---------------------------------------------------------------------------

  static TextStyle caption(BuildContext context) {
    return _text(
      context,
      size: 12,
      fontWeight: FontWeight.w400,
      color: _secondaryTextColor(context),
    );
  }

  static TextStyle label(BuildContext context) {
    return _text(
      context,
      size: 13,
      fontWeight: FontWeight.w600,
      color: _secondaryTextColor(context),
    );
  }

  // ---------------------------------------------------------------------------
  // Brand
  // ---------------------------------------------------------------------------

  static TextStyle brandTitle(BuildContext context) {
    return _text(
      context,
      size: 28,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.primary,
      letterSpacing: 2,
    );
  }

  static TextStyle brandTagline(BuildContext context) {
    return _text(
      context,
      size: 26,
      fontWeight: FontWeight.w500,
      letterSpacing: 1.2,
    );
  }

  // ---------------------------------------------------------------------------
  // Numbers / financial values
  // ---------------------------------------------------------------------------

  static TextStyle tinyNumber(BuildContext context) {
    return _number(context, size: 12);
  }

  static TextStyle smallNumber(BuildContext context) {
    return _number(context, size: 14);
  }

  static TextStyle mediumNumber(BuildContext context) {
    return _number(context, size: 18, fontWeight: FontWeight.w700);
  }

  static TextStyle largeNumber(BuildContext context) {
    return _number(context, size: 22, fontWeight: FontWeight.w700);
  }

  static TextStyle veryLargeNumber(BuildContext context) {
    return _number(context, size: 30, fontWeight: FontWeight.w700);
  }
}
