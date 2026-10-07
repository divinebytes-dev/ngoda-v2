import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';

class AppDisplayCard extends StatelessWidget {
  final Widget child;
  final Color? accentColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const AppDisplayCard({
    super.key,
    required this.child,
    this.accentColor,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final borderColor = accentColor ?? colorScheme.outline;

    return Container(
      margin: margin,
      padding: padding ?? EdgeInsets.all(spacing.padding),
      decoration: BoxDecoration(
        color: context.theme.cardColor,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(color: borderColor.withValues(alpha: 0.09)),
      ),
      child: child,
    );
  }
}
