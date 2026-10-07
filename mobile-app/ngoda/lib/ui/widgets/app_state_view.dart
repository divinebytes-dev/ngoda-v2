import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class AppStateView extends StatelessWidget {
  final String title;
  final String? message;
  final IconData icon;
  final Color iconColor;
  final Widget? action;

  const AppStateView({
    super.key,
    required this.title,
    required this.icon,
    required this.iconColor,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final hasMessage = message != null && message!.trim().isNotEmpty;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // -----------------------------------------------------------------
            // Icon
            // -----------------------------------------------------------------
            Container(
              padding: EdgeInsets.all(spacing.md),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: iconSize.xl, color: iconColor),
            ),

            SizedBox(height: spacing.md),

            // -----------------------------------------------------------------
            // Title
            // -----------------------------------------------------------------
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.medium(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),

            // -----------------------------------------------------------------
            // Message
            // -----------------------------------------------------------------
            if (hasMessage) ...[
              SizedBox(height: spacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppTextStyles.small(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],

            // -----------------------------------------------------------------
            // Action
            // -----------------------------------------------------------------
            if (action != null) ...[SizedBox(height: spacing.lg), action!],
          ],
        ),
      ),
    );
  }
}
