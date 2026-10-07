import 'package:ngoda/data_models/gl/gl_period_balance.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class WalletBalancePeriod {
  WalletBalancePeriod({
    required this.currencyCode,
    required this.fiscalYear,
    required List<GLPeriodBalance> periods,
  }) : periods = List.unmodifiable(periods);

  final String currencyCode;

  final int fiscalYear;

  final List<GLPeriodBalance> periods;

  factory WalletBalancePeriod.fromJson(Map<String, dynamic> json) {
    return WalletBalancePeriod(
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      fiscalYear: NumberConversionService.toInt(
        json['fiscalYear'] ?? json['fiscal_year'],
      ),
      periods: _parsePeriods(json['periods']),
    );
  }

  bool get isEmpty => periods.isEmpty;

  bool get isNotEmpty => periods.isNotEmpty;

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

  double get movement => totalCredit - totalDebit;

  List<GLPeriodBalance> get activePeriods {
    return List.unmodifiable(
      periods.where((period) => period.debit != 0 || period.credit != 0),
    );
  }

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
