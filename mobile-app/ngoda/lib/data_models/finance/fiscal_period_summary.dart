import 'package:ngoda/data_models/finance/fiscal_period.dart';

class FiscalPeriodSummary {
  final String countryCode;
  final int previousFiscalYear;
  final int currentFiscalYear;
  final List<FiscalPeriod> previousPeriods;
  final List<FiscalPeriod> currentPeriods;

  const FiscalPeriodSummary({
    required this.countryCode,
    required this.previousFiscalYear,
    required this.currentFiscalYear,
    required this.previousPeriods,
    required this.currentPeriods,
  });

  factory FiscalPeriodSummary.fromJson(Map<String, dynamic> json) {
    final previousPeriods = json['previous_periods'] as List<dynamic>? ?? [];
    final currentPeriods = json['current_periods'] as List<dynamic>? ?? [];

    return FiscalPeriodSummary(
      countryCode: json['country_code'] as String,
      previousFiscalYear: (json['previous_fiscal_year'] as num).toInt(),
      currentFiscalYear: (json['current_fiscal_year'] as num).toInt(),
      previousPeriods: previousPeriods
          .map(
            (period) =>
                FiscalPeriod.fromJson(Map<String, dynamic>.from(period as Map)),
          )
          .toList(),
      currentPeriods: currentPeriods
          .map(
            (period) =>
                FiscalPeriod.fromJson(Map<String, dynamic>.from(period as Map)),
          )
          .toList(),
    );
  }
}
