import 'package:ngoda/services/number_conversion_service.dart';

class FinancialSavingsSummary {
  const FinancialSavingsSummary({
    required this.opening,
    required this.openingUsd,
    required this.inflow,
    required this.inflowUsd,
    required this.outflow,
    required this.outflowUsd,
    required this.saved,
    required this.savedUsd,
    required this.closing,
    required this.closingUsd,
  });

  final double opening;
  final double openingUsd;

  final double inflow;
  final double inflowUsd;

  final double outflow;
  final double outflowUsd;

  final double saved;
  final double savedUsd;

  final double closing;
  final double closingUsd;

  factory FinancialSavingsSummary.fromJson(Map<String, dynamic> json) {
    return FinancialSavingsSummary(
      opening: NumberConversionService.toDouble(json['opening']),
      openingUsd: NumberConversionService.toDouble(json['opening_usd']),
      inflow: NumberConversionService.toDouble(json['inflow']),
      inflowUsd: NumberConversionService.toDouble(json['inflow_usd']),
      outflow: NumberConversionService.toDouble(json['outflow']),
      outflowUsd: NumberConversionService.toDouble(json['outflow_usd']),
      saved: NumberConversionService.toDouble(json['saved']),
      savedUsd: NumberConversionService.toDouble(json['saved_usd']),
      closing: NumberConversionService.toDouble(json['closing']),
      closingUsd: NumberConversionService.toDouble(json['closing_usd']),
    );
  }

  bool get hasActivity => inflow != 0 || outflow != 0 || saved != 0;
}
