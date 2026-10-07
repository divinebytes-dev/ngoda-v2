import 'package:ngoda/data_models/financial-intelligence/financial_behaviour_period.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class FinancialPeriodTrendPoint {
  FinancialPeriodTrendPoint({
    required this.period,
    required Map<String, double> moneyIn,
    required Map<String, double> distribution,
  }) : moneyIn = Map.unmodifiable(moneyIn),
       distribution = Map.unmodifiable(distribution);

  final int period;

  final Map<String, double> moneyIn;
  final Map<String, double> distribution;

  bool get hasActivity =>
      moneyIn.values.any((value) => value != 0) ||
      distribution.values.any((value) => value != 0);
}

class PeriodicFinancialBehaviour {
  PeriodicFinancialBehaviour({
    required this.fiscalYear,
    required this.currentPeriod,
    required List<FinancialBehaviourPeriod> periods,
  }) : periods = List.unmodifiable(periods);

  final int fiscalYear;
  final int currentPeriod;

  final List<FinancialBehaviourPeriod> periods;

  factory PeriodicFinancialBehaviour.fromJson(Map<String, dynamic> json) {
    return PeriodicFinancialBehaviour(
      fiscalYear: NumberConversionService.toInt(json['fiscal_year']),
      currentPeriod: NumberConversionService.toInt(json['current_period']),
      periods: _parsePeriods(json['periods']),
    );
  }

  FinancialBehaviourPeriod? operator [](int period) {
    return getByPeriod(period);
  }

  FinancialBehaviourPeriod? getByPeriod(int period) {
    for (final item in periods) {
      if (item.period == period) {
        return item;
      }
    }

    return null;
  }

  FinancialBehaviourPeriod? get current {
    return getByPeriod(currentPeriod);
  }

  List<FinancialBehaviourPeriod> get completedPeriods {
    final result =
        periods.where((item) => item.period <= currentPeriod).toList()
          ..sort((a, b) => a.period.compareTo(b.period));

    return List.unmodifiable(result);
  }

  List<FinancialBehaviourPeriod> get activePeriods {
    return List.unmodifiable(
      completedPeriods.where((item) => item.hasActivity),
    );
  }

  /// Currencies available across completed fiscal periods.
  ///
  /// Codes remain normalized lowercase domain values.
  /// Display formatting belongs to the UI.
  List<String> get currencyList {
    final currencies = <String>{};

    for (final period in completedPeriods) {
      for (final item in period.moneyByCurrency) {
        final code = item.currencyCode.trim().toLowerCase();

        if (code.isEmpty || code == 'gold') {
          continue;
        }

        currencies.add(code);
      }
    }

    final result = currencies.toList()..sort();

    return List.unmodifiable(result);
  }

  /// `ALL` represents consolidated USD-equivalent values.
  ///
  /// Individual entries represent native currency values.
  List<String> get selectionList {
    return List.unmodifiable(['ALL', ...currencyList]);
  }

  /// Builds the overview report across completed fiscal periods.
  ///
  /// ALL:
  /// consolidated USD-equivalent values.
  ///
  /// Currency:
  /// native values for the selected currency.
  List<FinancialPeriodTrendPoint> trend(String selection) {
    return List.unmodifiable(
      completedPeriods.map((period) {
        return FinancialPeriodTrendPoint(
          period: period.period,
          moneyIn: period.moneyInFor(selection),
          distribution: period.distributionFor(selection),
        );
      }),
    );
  }

  static List<FinancialBehaviourPeriod> _parsePeriods(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (item) => FinancialBehaviourPeriod.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }
}
