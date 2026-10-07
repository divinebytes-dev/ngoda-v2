import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  final bool isPrimary;
  final bool isProcessing;
  final bool isDisabled;

  const AppButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isPrimary = true,
    this.isProcessing = false,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final isEnabled = !isDisabled && !isProcessing && onPressed != null;

    final buttonStyle = ButtonStyle(
      elevation: const WidgetStatePropertyAll(0),
      minimumSize: WidgetStatePropertyAll(
        Size(double.infinity, spacing.buttonHeight),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: spacing.padding, vertical: spacing.sm),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius.borderRadius),
        ),
      ),
    );

    final foregroundColor = isEnabled
        ? isPrimary
              ? colorScheme.onPrimary
              : colorScheme.primary
        : colorScheme.onSurface.withValues(alpha: 0.38);

    return SizedBox(
      width: double.infinity,
      child: isPrimary
          ? ElevatedButton(
              onPressed: isEnabled ? onPressed : null,
              style: buttonStyle.copyWith(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return colorScheme.onSurface.withValues(alpha: 0.12);
                  }

                  return colorScheme.primary;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return colorScheme.onSurface.withValues(alpha: 0.38);
                  }

                  return colorScheme.onPrimary;
                }),
              ),
              child: _ButtonContent(
                text: text,
                isProcessing: isProcessing,
                foregroundColor: foregroundColor,
                loaderSize: iconSize.small,
              ),
            )
          : OutlinedButton(
              onPressed: isEnabled ? onPressed : null,
              style: buttonStyle.copyWith(
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return colorScheme.onSurface.withValues(alpha: 0.38);
                  }

                  return colorScheme.primary;
                }),
                side: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return BorderSide(
                      color: colorScheme.onSurface.withValues(alpha: 0.12),
                    );
                  }

                  return BorderSide(color: colorScheme.primary);
                }),
              ),
              child: _ButtonContent(
                text: text,
                isProcessing: isProcessing,
                foregroundColor: foregroundColor,
                loaderSize: iconSize.small,
              ),
            ),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  final String text;
  final bool isProcessing;
  final Color foregroundColor;
  final double loaderSize;

  const _ButtonContent({
    required this.text,
    required this.isProcessing,
    required this.foregroundColor,
    required this.loaderSize,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: isProcessing
          ? SizedBox(
              key: const ValueKey('loader'),
              width: loaderSize,
              height: loaderSize,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foregroundColor,
              ),
            )
          : Text(
              text,
              key: const ValueKey('text'),
              style: AppTextStyles.small(
                context,
              ).copyWith(fontWeight: FontWeight.w700, color: foregroundColor),
            ),
    );
  }
}
