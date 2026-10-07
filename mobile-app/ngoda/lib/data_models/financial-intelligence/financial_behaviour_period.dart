import 'package:ngoda/data_models/financial-intelligence/financial_behaviour_identity.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_currency_summary.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_distribution.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_money_by_currency.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_money_in.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_period_total.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class FinancialBehaviourPeriod {
  FinancialBehaviourPeriod({
    required this.period,
    required this.isCurrentPeriod,
    required this.hasActivity,
    required this.identity,
    required this.all,
    required List<FinancialCurrencySummary> currencies,
    required this.moneyIn,
    required this.distribution,
    required List<FinancialMoneyByCurrency> moneyByCurrency,
  }) : currencies = List.unmodifiable(currencies),
       moneyByCurrency = List.unmodifiable(moneyByCurrency);

  final int period;
  final bool isCurrentPeriod;
  final bool hasActivity;

  /// Consolidated behaviour identity for this period.
  final FinancialBehaviourIdentity identity;

  /// Consolidated USD financial-position totals.
  final FinancialPeriodTotal all;

  /// Financial-position summaries by currency.
  final List<FinancialCurrencySummary> currencies;

  /// Consolidated USD-equivalent sources of money.
  final FinancialMoneyIn moneyIn;

  /// Consolidated USD-equivalent distribution of money.
  final FinancialDistribution distribution;

  /// Native-currency money-in and distribution.
  final List<FinancialMoneyByCurrency> moneyByCurrency;

  factory FinancialBehaviourPeriod.fromJson(Map<String, dynamic> json) {
    return FinancialBehaviourPeriod(
      period: NumberConversionService.toInt(json['period']),
      isCurrentPeriod: json['is_current_period'] == true,
      hasActivity: json['has_activity'] == true,
      identity: FinancialBehaviourIdentity.fromSummaryJson(
        behavior: json['behavior']?.toString(),
        scores: _asMap(json['behavior_scores']),
      ),
      all: FinancialPeriodTotal.fromJson(_asMap(json['all'])),
      currencies: _parseCurrencies(json['currencies']),
      moneyIn: FinancialMoneyIn.fromJson(_asMap(json['money_in'])),
      distribution: FinancialDistribution.fromJson(
        _asMap(json['distribution']),
      ),
      moneyByCurrency: _parseMoneyByCurrency(json['money_by_currency']),
    );
  }

  FinancialCurrencySummary? operator [](String currency) {
    return getCurrency(currency);
  }

  FinancialCurrencySummary? getCurrency(String currency) {
    final key = currency.trim().toLowerCase();

    if (key.isEmpty) {
      return null;
    }

    for (final item in currencies) {
      if (item.currencyCode == key) {
        return item;
      }
    }

    return null;
  }

  FinancialMoneyByCurrency? getMoneyByCurrency(String currency) {
    final key = currency.trim().toLowerCase();

    if (key.isEmpty) {
      return null;
    }

    for (final item in moneyByCurrency) {
      if (item.currencyCode == key) {
        return item;
      }
    }

    return null;
  }

  /// Native fiat currencies available for the money-in /
  /// distribution report.
  ///
  /// Gold is intentionally excluded because this report represents
  /// money values. Gold quantity movement is handled separately.
  List<String> get currencyList {
    final result =
        moneyByCurrency
            .map((item) => item.currencyCode)
            .where((code) => code.isNotEmpty && code.toLowerCase() != 'gold')
            .toSet()
            .toList()
          ..sort();

    return List.unmodifiable(result);
  }

  bool get isEmpty => !hasActivity;

  Map<String, double> moneyInFor(String selection) {
    if (_isAll(selection)) {
      return moneyIn.usdChart;
    }

    return getMoneyByCurrency(selection)?.moneyIn.nativeChart ??
        const <String, double>{};
  }

  Map<String, double> distributionFor(String selection) {
    if (_isAll(selection)) {
      return distribution.usdChart;
    }

    return getMoneyByCurrency(selection)?.distribution.nativeChart ??
        const <String, double>{};
  }

  double availableMoneyFor(String selection) {
    if (_isAll(selection)) {
      return moneyIn.totalUsd;
    }

    return getMoneyByCurrency(selection)?.moneyIn.total ?? 0;
  }

  static bool _isAll(String selection) {
    return selection.trim().toUpperCase() == 'ALL';
  }

  static List<FinancialCurrencySummary> _parseCurrencies(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (item) => FinancialCurrencySummary.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  static List<FinancialMoneyByCurrency> _parseMoneyByCurrency(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (item) => FinancialMoneyByCurrency.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
