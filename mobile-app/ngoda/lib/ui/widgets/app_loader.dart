import 'package:flutter/material.dart';

import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/animated_dots.dart';

class AppLoader extends StatelessWidget {
  final String? message;
  final bool fullScreen;

  const AppLoader({super.key, this.message, this.fullScreen = false});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final hasMessage = message != null && message!.trim().isNotEmpty;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (hasMessage) ...[
          Flexible(
            child: Text(
              message!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.medium(
                context,
              ).copyWith(decoration: TextDecoration.none),
            ),
          ),
          SizedBox(width: spacing.sm),
        ],
        AnimatedDots(color: colorScheme.primary, size: spacing.sm),
      ],
    );

    final loader = Center(
      child: Padding(padding: EdgeInsets.all(spacing.md), child: content),
    );

    if (!fullScreen) {
      return loader;
    }

    return ColoredBox(
      color: context.theme.scaffoldBackgroundColor,
      child: SizedBox.expand(child: loader),
    );
  }
}
