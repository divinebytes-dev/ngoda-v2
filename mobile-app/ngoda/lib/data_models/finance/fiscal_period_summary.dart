import 'package:ngoda/data_models/finance/fiscal_period.dart';

class FiscalPeriodSummary {
  final String countryCode;
  final int currentFiscalYear;
  final int nextFiscalYear;
  final List<FiscalPeriod> currentPeriods;
  final List<FiscalPeriod> nextPeriods;

  const FiscalPeriodSummary({
    required this.countryCode,
    required this.currentFiscalYear,
    required this.nextFiscalYear,
    required this.currentPeriods,
    required this.nextPeriods,
  });

  bool get nextFiscalYearConfigured {
    return nextPeriods.isNotEmpty;
  }

  bool get canOpenNextFiscalYear {
    return nextPeriods.isEmpty;
  }

  factory FiscalPeriodSummary.fromJson(Map<String, dynamic> json) {
    final currentPeriods = json['current_periods'] as List<dynamic>? ?? [];

    final nextPeriods = json['next_periods'] as List<dynamic>? ?? [];

    return FiscalPeriodSummary(
      countryCode: json['country_code'] as String,
      currentFiscalYear: (json['current_fiscal_year'] as num).toInt(),
      nextFiscalYear: (json['next_fiscal_year'] as num).toInt(),
      currentPeriods: currentPeriods
          .map(
            (period) =>
                FiscalPeriod.fromJson(Map<String, dynamic>.from(period as Map)),
          )
          .toList(),
      nextPeriods: nextPeriods
          .map(
            (period) =>
                FiscalPeriod.fromJson(Map<String, dynamic>.from(period as Map)),
          )
          .toList(),
    );
  }
}
