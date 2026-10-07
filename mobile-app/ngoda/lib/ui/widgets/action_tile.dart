import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

enum ActionTileIconShape { circle, rounded }

class ActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  final Color? color;

  final VoidCallback? onTap;

  final ActionTileIconShape iconShape;

  const ActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.color,
    this.onTap,
    this.iconShape = ActionTileIconShape.circle,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final isEnabled = onTap != null;

    final baseColor = color ?? colorScheme.primary;

    final actionColor = isEnabled
        ? baseColor
        : colorScheme.onSurface.withValues(alpha: 0.38);

    return Material(
      color: context.theme.cardColor,
      borderRadius: BorderRadius.circular(radius.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        child: Ink(
          padding: EdgeInsets.all(spacing.padding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius.cardRadius),
            border: Border.all(color: actionColor.withValues(alpha: 0.20)),
          ),
          child: Row(
            children: [
              Container(
                width: spacing.xxl,
                height: spacing.xxl,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.08),
                  shape: iconShape == ActionTileIconShape.circle
                      ? BoxShape.circle
                      : BoxShape.rectangle,
                  borderRadius: iconShape == ActionTileIconShape.rounded
                      ? BorderRadius.circular(radius.sm)
                      : null,
                ),
                child: Icon(icon, color: actionColor, size: iconSize.large),
              ),

              SizedBox(width: spacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.small(context).copyWith(
                        fontWeight: FontWeight.w700,
                        color: isEnabled
                            ? null
                            : colorScheme.onSurface.withValues(alpha: 0.38),
                      ),
                    ),

                    SizedBox(height: spacing.xs),

                    Text(
                      subtitle,
                      style: AppTextStyles.tiny(context).copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: isEnabled ? 1 : 0.38,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(width: spacing.sm),

              Icon(
                Icons.chevron_right_rounded,
                size: iconSize.large,
                color: colorScheme.onSurfaceVariant.withValues(
                  alpha: isEnabled ? 0.70 : 0.38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
