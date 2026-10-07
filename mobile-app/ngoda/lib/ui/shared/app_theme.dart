import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_fonts.dart';
import 'app_icon_size.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

abstract final class AppTheme {
  AppTheme._();

  // ---------------------------------------------------------------------------
  // Light theme
  // ---------------------------------------------------------------------------

  static ThemeData light(BuildContext context) {
    const colorScheme = ColorScheme.light(
      primary: AppColors.lightPrimary,
      onPrimary: AppColors.lightOnPrimary,
      secondary: AppColors.lightSecondary,
      onSecondary: AppColors.lightOnSecondary,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightForeground,
      error: AppColors.error,
      onError: Colors.white,
      outline: AppColors.lightBorder,
    );

    return _buildTheme(
      context: context,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      background: AppColors.lightBackground,
      card: AppColors.lightCard,
      divider: AppColors.lightDivider,
      secondaryText: AppColors.lightForegroundSecondary,
    );
  }

  // ---------------------------------------------------------------------------
  // Dark theme
  // ---------------------------------------------------------------------------

  static ThemeData dark(BuildContext context) {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.darkOnPrimary,
      secondary: AppColors.darkSecondary,
      onSecondary: AppColors.darkOnSecondary,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkForeground,
      error: AppColors.errorDark,
      onError: Color(0xFF450A0A),
      outline: AppColors.darkBorder,
    );

    return _buildTheme(
      context: context,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      background: AppColors.darkBackground,
      card: AppColors.darkCard,
      divider: AppColors.darkDivider,
      secondaryText: AppColors.darkForegroundSecondary,
    );
  }

  // ---------------------------------------------------------------------------
  // Theme builder
  // ---------------------------------------------------------------------------

  static ThemeData _buildTheme({
    required BuildContext context,
    required Brightness brightness,
    required ColorScheme colorScheme,
    required Color background,
    required Color card,
    required Color divider,
    required Color secondaryText,
  }) {
    final spacing = AppSpacing(context);
    final radius = AppRadius(context);
    final iconSize = AppIconSize(context);

    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      fontFamily: AppFonts.text,
    );

    final defaultBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius.borderRadius),
      borderSide: BorderSide(color: colorScheme.outline),
    );

    return baseTheme.copyWith(
      canvasColor: background,
      cardColor: card,
      dividerColor: divider,

      // -----------------------------------------------------------------------
      // Typography
      // -----------------------------------------------------------------------
      textTheme: baseTheme.textTheme.apply(
        fontFamily: AppFonts.text,
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),

      // -----------------------------------------------------------------------
      // Icons
      // -----------------------------------------------------------------------
      iconTheme: IconThemeData(
        color: colorScheme.onSurface,
        size: iconSize.medium,
      ),

      primaryIconTheme: IconThemeData(
        color: colorScheme.onPrimary,
        size: iconSize.medium,
      ),

      // -----------------------------------------------------------------------
      // App bar
      // -----------------------------------------------------------------------
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: background,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(
          color: colorScheme.onSurface,
          size: iconSize.medium,
        ),
        actionsIconTheme: IconThemeData(
          color: colorScheme.onSurface,
          size: iconSize.medium,
        ),
        titleTextStyle: AppTextStyles.medium(context),
      ),

      // -----------------------------------------------------------------------
      // Cards
      // -----------------------------------------------------------------------
      cardTheme: CardThemeData(
        elevation: 0,
        color: card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius.borderRadius),
          side: BorderSide(color: colorScheme.outline),
        ),
      ),

      // -----------------------------------------------------------------------
      // Inputs
      // -----------------------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        contentPadding: EdgeInsets.symmetric(
          horizontal: spacing.padding,
          vertical: spacing.sm,
        ),
        hintStyle: AppTextStyles.small(
          context,
        ).copyWith(color: secondaryText, fontWeight: FontWeight.w400),
        labelStyle: AppTextStyles.small(
          context,
        ).copyWith(color: secondaryText, fontWeight: FontWeight.w500),
        errorStyle: AppTextStyles.tiny(
          context,
        ).copyWith(color: colorScheme.error),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        disabledBorder: defaultBorder.copyWith(
          borderSide: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: defaultBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: defaultBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: defaultBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
      ),

      // -----------------------------------------------------------------------
      // Elevated buttons
      // -----------------------------------------------------------------------
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: Size(0, spacing.buttonHeight),
          padding: EdgeInsets.symmetric(
            horizontal: spacing.padding,
            vertical: spacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius.borderRadius),
          ),
          textStyle: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ),

      // -----------------------------------------------------------------------
      // Filled buttons
      // -----------------------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: Size(0, spacing.buttonHeight),
          padding: EdgeInsets.symmetric(
            horizontal: spacing.padding,
            vertical: spacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius.borderRadius),
          ),
          textStyle: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ),

      // -----------------------------------------------------------------------
      // Outlined buttons
      // -----------------------------------------------------------------------
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          minimumSize: Size(0, spacing.buttonHeight),
          padding: EdgeInsets.symmetric(
            horizontal: spacing.padding,
            vertical: spacing.sm,
          ),
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius.borderRadius),
          ),
          textStyle: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ),

      // -----------------------------------------------------------------------
      // Text buttons
      // -----------------------------------------------------------------------
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          padding: EdgeInsets.symmetric(
            horizontal: spacing.sm,
            vertical: spacing.sm,
          ),
          textStyle: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ),

      // -----------------------------------------------------------------------
      // Icon buttons
      // -----------------------------------------------------------------------
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          iconSize: iconSize.medium,
        ),
      ),

      // -----------------------------------------------------------------------
      // Dividers
      // -----------------------------------------------------------------------
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 1,
        space: spacing.xs,
      ),

      // -----------------------------------------------------------------------
      // Dialogs
      // -----------------------------------------------------------------------
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        insetPadding: EdgeInsets.all(spacing.margin),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius.borderRadius),
        ),
        titleTextStyle: AppTextStyles.medium(context),
        contentTextStyle: AppTextStyles.small(context),
      ),

      // -----------------------------------------------------------------------
      // Bottom sheets
      // -----------------------------------------------------------------------
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radius.edgeInsert),
          ),
        ),
      ),

      // -----------------------------------------------------------------------
      // Snackbars
      // -----------------------------------------------------------------------
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.onSurface,
        insetPadding: EdgeInsets.all(spacing.margin),
        contentTextStyle: AppTextStyles.small(
          context,
        ).copyWith(color: colorScheme.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius.borderRadius),
        ),
      ),

      // -----------------------------------------------------------------------
      // Progress indicators
      // -----------------------------------------------------------------------
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),

      // -----------------------------------------------------------------------
      // Checkboxes
      // -----------------------------------------------------------------------
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius.sm),
        ),
      ),

      // -----------------------------------------------------------------------
      // Switches
      // -----------------------------------------------------------------------
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }

          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }

          return null;
        }),
      ),

      // -----------------------------------------------------------------------
      // List tiles
      // -----------------------------------------------------------------------
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurface,
        textColor: colorScheme.onSurface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: spacing.padding,
          vertical: spacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius.borderRadius),
        ),
      ),
    );
  }
}
