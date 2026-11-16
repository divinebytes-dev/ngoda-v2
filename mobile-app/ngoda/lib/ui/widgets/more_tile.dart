import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class MoreTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;
  final bool showChevron;

  const MoreTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final color = isDestructive ? colorScheme.error : colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius.borderRadius),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: spacing.sm),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(spacing.sm),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(radius.borderRadius),
              ),
              child: Icon(icon, color: color, size: iconSize.medium),
            ),
            SizedBox(width: spacing.md),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.small(context).copyWith(
                  color: isDestructive
                      ? colorScheme.error
                      : colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (showChevron)
              Icon(
                Icons.chevron_right,
                size: iconSize.medium,
                color: colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
