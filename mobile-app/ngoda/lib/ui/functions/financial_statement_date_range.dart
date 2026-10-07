import 'package:flutter/material.dart';
import 'package:ngoda/data_models/params/financial_statement_params.dart';

import 'package:ngoda/ui/functions/select_date_range.dart';

Future<FinancialStatementParams?> selectFinancialStatementDateRange({
  required BuildContext context,
  required FinancialStatementParams currentParams,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  final maximumDate = DateUtils.dateOnly(lastDate ?? DateTime.now());

  final minimumDate = DateUtils.dateOnly(firstDate ?? DateTime(2020, 1, 1));

  final parsedStart = DateTime.tryParse(currentParams.startDate);

  final parsedEnd = DateTime.tryParse(currentParams.endDate);

  final currentRange = DateTimeRange(
    start: parsedStart ?? DateTime(maximumDate.year, 1, 1),
    end: parsedEnd ?? maximumDate,
  );

  final selectedRange = await selectDateRange(
    context: context,
    currentRange: currentRange,
    firstDate: minimumDate,
    lastDate: maximumDate,
    helpText: 'Select reporting period',
    saveText: 'Apply',
  );

  if (selectedRange == null) {
    return null;
  }

  return currentParams.copyWith(
    startDate: formatDate(selectedRange.start),
    endDate: formatDate(selectedRange.end),
    page: 1,
  );
}

String formatDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
