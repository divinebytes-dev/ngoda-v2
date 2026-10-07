import 'package:flutter/material.dart';

Future<DateTimeRange?> selectDateRange({
  required BuildContext context,
  DateTimeRange? currentRange,
  DateTime? firstDate,
  DateTime? lastDate,
  String helpText = 'Select date range',
  String saveText = 'Apply',
}) async {
  final maximumDate = DateUtils.dateOnly(lastDate ?? DateTime.now());

  final minimumDate = DateUtils.dateOnly(firstDate ?? DateTime(2020, 1, 1));

  assert(
    !minimumDate.isAfter(maximumDate),
    'firstDate cannot be after lastDate.',
  );

  final initialRange = _normalizeRange(
    currentRange: currentRange,
    minimumDate: minimumDate,
    maximumDate: maximumDate,
  );

  return showDateRangePicker(
    context: context,
    firstDate: minimumDate,
    lastDate: maximumDate,
    initialDateRange: initialRange,
    helpText: helpText,
    saveText: saveText,
  );
}

DateTimeRange? _normalizeRange({
  required DateTimeRange? currentRange,
  required DateTime minimumDate,
  required DateTime maximumDate,
}) {
  if (currentRange == null) {
    return null;
  }

  final start = _clampDate(
    DateUtils.dateOnly(currentRange.start),
    minimumDate,
    maximumDate,
  );

  final end = _clampDate(
    DateUtils.dateOnly(currentRange.end),
    start,
    maximumDate,
  );

  return DateTimeRange(start: start, end: end);
}

DateTime _clampDate(DateTime value, DateTime minimum, DateTime maximum) {
  if (value.isBefore(minimum)) {
    return minimum;
  }

  if (value.isAfter(maximum)) {
    return maximum;
  }

  return value;
}
