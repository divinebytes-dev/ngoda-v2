import 'package:ngoda/data_models/gl/gl_period_balance.dart';

class WalletBalanceSnapshotDrill {
  WalletBalanceSnapshotDrill({
    required this.currencyCode,
    required this.fiscalYear,
    required List<GLPeriodBalance> periods,
  }) : periods = List.unmodifiable(periods);

  final String currencyCode;

  final int fiscalYear;

  final List<GLPeriodBalance> periods;

  factory WalletBalanceSnapshotDrill.fromJson(Map<String, dynamic> json) {
    return WalletBalanceSnapshotDrill(
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      fiscalYear: json['fiscalYear'] is num
          ? (json['fiscalYear'] as num).toInt()
          : int.tryParse(json['fiscalYear']?.toString() ?? '') ?? 0,
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
