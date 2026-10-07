import 'package:ngoda/data_models/gl/gl_period_balance.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class GLDrilldown {
  GLDrilldown({
    required this.accountCode,
    required this.description,
    required this.fiscalYear,
    required List<GLPeriodBalance> periods,
  }) : periods = List.unmodifiable(periods);

  final String accountCode;
  final String description;

  final int fiscalYear;

  final List<GLPeriodBalance> periods;

  factory GLDrilldown.fromJson(Map<String, dynamic> json) {
    return GLDrilldown(
      accountCode: json['gl_account_code']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      fiscalYear: NumberConversionService.toInt(json['fiscalYear']),
      periods: _parsePeriods(json['periods']),
    );
  }

  double get totalDebit {
    return periods.fold(0.0, (total, period) => total + period.debit);
  }

  double get totalCredit {
    return periods.fold(0.0, (total, period) => total + period.credit);
  }

  double get opening {
    if (periods.isEmpty) {
      return 0;
    }

    return periods.first.opening;
  }

  double get closing {
    if (periods.isEmpty) {
      return 0;
    }

    return periods.last.closing;
  }

  bool get hasPeriods => periods.isNotEmpty;

  static List<GLPeriodBalance> _parsePeriods(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (period) =>
              GLPeriodBalance.fromJson(Map<String, dynamic>.from(period)),
        )
        .toList();
  }
}
