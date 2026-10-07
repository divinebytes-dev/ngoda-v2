import 'package:flutter/material.dart';

import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class AppIconButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  final EdgeInsetsGeometry? padding;
  final double? iconSize;

  final double? width;
  final double? height;

  final bool expanded;
  final AppIconButtonLayout layout;

  const AppIconButton({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    this.onTap,
    this.padding,
    this.iconSize,
    this.width,
    this.height,
    this.expanded = false,
    this.layout = AppIconButtonLayout.vertical,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final appIconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final isEnabled = onTap != null;

    final actionColor = isEnabled
        ? color
        : colorScheme.onSurface.withValues(alpha: 0.38);

    final resolvedIconSize = iconSize ?? appIconSize.medium;

    /*
     * Vertical quick actions use one consistent
     * tile size so their dimensions are not
     * determined by the title.
     *
     * Width and height can still be overridden
     * by a caller when required.
     *
     * Horizontal actions remain content-sized
     * unless explicit dimensions are supplied.
     */
    final resolvedWidth =
        width ??
        (layout == AppIconButtonLayout.vertical
            ? spacing.quickActionWidth
            : null);

    final resolvedHeight =
        height ??
        (layout == AppIconButtonLayout.vertical
            ? spacing.quickActionHeight
            : null);

    final iconWidget = Icon(icon, color: actionColor, size: resolvedIconSize);

    final textWidget = Text(
      title,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.tiny(
        context,
      ).copyWith(fontWeight: FontWeight.w600, color: actionColor),
    );

    final content = layout == AppIconButtonLayout.vertical
        ? Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              SizedBox(height: spacing.xs),
              Flexible(child: textWidget),
            ],
          )
        : Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              SizedBox(width: spacing.xs),
              Flexible(child: textWidget),
            ],
          );

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        child: Ink(
          padding:
              padding ??
              EdgeInsets.symmetric(
                horizontal: spacing.sm,
                vertical: spacing.sm,
              ),
          decoration: BoxDecoration(
            color: context.theme.cardColor,
            borderRadius: BorderRadius.circular(radius.borderRadius),
            border: Border.all(color: actionColor.withValues(alpha: 0.40)),
          ),
          child: content,
        ),
      ),
    );

    if (resolvedWidth == null && resolvedHeight == null) {
      return button;
    }

    return SizedBox(
      width: resolvedWidth,
      height: resolvedHeight,
      child: button,
    );
  }
}
