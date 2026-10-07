import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class DateInputField extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;

  final ValueChanged<DateTime>? onDateSelected;

  final DateTime? initialDate;
  final DateTime? firstDate;
  final DateTime? lastDate;

  const DateInputField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.onDateSelected,
    this.initialDate,
    this.firstDate,
    this.lastDate,
  });

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();

    final minDate = firstDate ?? DateTime(now.year, 1, 1);

    final maxDate = lastDate ?? now;

    var selectedInitialDate = initialDate ?? now;

    if (selectedInitialDate.isBefore(minDate)) {
      selectedInitialDate = minDate;
    }

    if (selectedInitialDate.isAfter(maxDate)) {
      selectedInitialDate = maxDate;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: selectedInitialDate,
      firstDate: minDate,
      lastDate: maxDate,
    );

    if (picked == null) {
      return;
    }

    controller.text =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';

    onDateSelected?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return TextField(
      controller: controller,
      readOnly: true,
      style: AppTextStyles.small(context),
      decoration: InputDecoration(
        labelText: placeholder,
        suffixIcon: Icon(
          Icons.calendar_today_outlined,
          size: iconSize.medium,
          color: colorScheme.primary,
        ),
      ),
      onTap: () {
        _pickDate(context);
      },
    );
  }
}
