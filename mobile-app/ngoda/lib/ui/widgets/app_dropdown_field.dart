import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class AppDropdownField<T> extends StatelessWidget {
  final T? selected;
  final String hint;
  final List<T> values;

  final String Function(T value) labelBuilder;
  final ValueChanged<T>? onSelect;

  const AppDropdownField({
    super.key,
    required this.selected,
    required this.values,
    required this.labelBuilder,
    required this.onSelect,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return DropdownButtonFormField<T>(
      initialValue: selected,
      isExpanded: true,
      style: AppTextStyles.small(context),
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        color: colorScheme.primary,
        size: iconSize.medium,
      ),
      decoration: InputDecoration(labelText: hint),
      items: values.map((value) {
        return DropdownMenuItem<T>(
          value: value,
          child: Text(
            labelBuilder(value),
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.small(context),
          ),
        );
      }).toList(),
      onChanged: onSelect == null
          ? null
          : (value) {
              if (value != null) {
                onSelect!(value);
              }
            },
    );
  }
}
