import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class AppToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;

  const AppToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final hasLabel = label != null && label!.trim().isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasLabel) ...[
          Flexible(child: Text(label!, style: AppTextStyles.small(context))),

          SizedBox(width: spacing.sm),
        ],

        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
