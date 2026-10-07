import 'package:flutter/material.dart';
import 'package:ngoda/ui/shared/app_colors.dart';

abstract final class SnackbarService {
  static const Duration _defaultDuration = Duration(seconds: 3);

  static void show(
    BuildContext context, {
    required String message,
    Color? backgroundColor,
    Color? foregroundColor,
    Duration duration = _defaultDuration,
    SnackBarAction? action,
  }) {
    final value = message.trim();

    if (value.isEmpty) {
      return;
    }

    final colorScheme = Theme.of(context).colorScheme;

    final resolvedBackgroundColor =
        backgroundColor ?? colorScheme.inverseSurface;

    final resolvedForegroundColor =
        foregroundColor ?? colorScheme.onInverseSurface;

    final messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            value,
            style: TextStyle(color: resolvedForegroundColor),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: resolvedBackgroundColor,
          duration: duration,
          action: action,
        ),
      );
  }

  static void success(
    BuildContext context,
    String message, {
    Duration duration = _defaultDuration,
  }) {
    show(
      context,
      message: message,
      backgroundColor: AppColors.success,
      foregroundColor: Colors.white,
      duration: duration,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    Duration duration = _defaultDuration,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    show(
      context,
      message: message,
      backgroundColor: colorScheme.error,
      foregroundColor: colorScheme.onError,
      duration: duration,
    );
  }

  static void info(
    BuildContext context,
    String message, {
    Duration duration = _defaultDuration,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    show(
      context,
      message: message,
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      duration: duration,
    );
  }

  static void warning(
    BuildContext context,
    String message, {
    Duration duration = _defaultDuration,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    show(
      context,
      message: message,
      backgroundColor: colorScheme.tertiary,
      foregroundColor: colorScheme.onTertiary,
      duration: duration,
    );
  }

  static void hide(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  static void clear(BuildContext context) {
    ScaffoldMessenger.of(context).clearSnackBars();
  }
}
