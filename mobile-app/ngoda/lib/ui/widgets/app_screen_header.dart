import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class AppScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onClose;

  const AppScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.padding,
        spacing.lg,
        spacing.padding,
        spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.large(
                    context,
                  ).copyWith(fontWeight: FontWeight.w800),
                ),
              ),

              if (onClose != null) ...[
                SizedBox(width: spacing.sm),

                Material(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(radius.borderRadius),
                  child: InkWell(
                    onTap: onClose,
                    borderRadius: BorderRadius.circular(radius.borderRadius),
                    child: Padding(
                      padding: EdgeInsets.all(spacing.sm),
                      child: Icon(
                        Icons.close_rounded,
                        size: iconSize.large,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),

          if (hasSubtitle) ...[
            SizedBox(height: spacing.sm),

            Text(
              subtitle!,
              style: AppTextStyles.small(context).copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
