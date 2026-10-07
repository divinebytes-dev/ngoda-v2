import 'package:ngoda/data_models/financial-intelligence/financial_currency_summary.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_distribution.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_gold_summary.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_money_by_currency.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_money_in.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class FinancialBehaviour {
  FinancialBehaviour({
    required this.fiscalYear,
    required this.currentPeriod,
    required List<FinancialCurrencySummary> currencies,
    required this.gold,
    required this.moneyIn,
    required this.distribution,
    required List<FinancialMoneyByCurrency> moneyByCurrency,
  }) : currencies = List.unmodifiable(currencies),
       moneyByCurrency = List.unmodifiable(moneyByCurrency);

  final int fiscalYear;
  final int currentPeriod;

  /// Financial position/activity by currency.
  final List<FinancialCurrencySummary> currencies;

  /// Gold quantity movement for the fiscal year.
  final FinancialGoldSummary gold;

  /// Consolidated USD-equivalent sources of money.
  final FinancialMoneyIn moneyIn;

  /// Consolidated USD-equivalent use/distribution of money.
  final FinancialDistribution distribution;

  /// Native-currency sources and distribution.
  final List<FinancialMoneyByCurrency> moneyByCurrency;

  factory FinancialBehaviour.fromJson(Map<String, dynamic> json) {
    return FinancialBehaviour(
      fiscalYear: NumberConversionService.toInt(json['fiscal_year']),
      currentPeriod: NumberConversionService.toInt(json['current_period']),
      currencies: _parseCurrencySummaries(json['currencies']),
      gold: FinancialGoldSummary.fromJson(_asMap(json['gold'])),
      moneyIn: FinancialMoneyIn.fromJson(_asMap(json['money_in'])),
      distribution: FinancialDistribution.fromJson(
        _asMap(json['distribution']),
      ),
      moneyByCurrency: _parseMoneyByCurrency(json['money_by_currency']),
    );
  }

  FinancialCurrencySummary? operator [](String currency) {
    return getByCurrency(currency);
  }

  FinancialCurrencySummary? getByCurrency(String currency) {
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

  bool containsCurrency(String currency) {
    return getByCurrency(currency) != null;
  }

  bool containsMoneyCurrency(String currency) {
    return getMoneyByCurrency(currency) != null;
  }

  List<String> get currencyList {
    return List.unmodifiable(currencies.map((item) => item.currencyCode));
  }

  List<String> get sortedCurrencyList {
    final result = [...currencyList]..sort();

    return List.unmodifiable(result);
  }

  List<String> get moneyCurrencyList {
    return List.unmodifiable(moneyByCurrency.map((item) => item.currencyCode));
  }

  List<String> get sortedMoneyCurrencyList {
    final result = [...moneyCurrencyList]..sort();

    return List.unmodifiable(result);
  }

  Map<String, double> get moneyInChartUsd => moneyIn.usdChart;

  Map<String, double> get distributionChartUsd => distribution.usdChart;

  double get totalDepositUsd {
    return currencies.fold(0.0, (sum, item) => sum + item.deposit.amountUsd);
  }

  double get totalWithdrawalUsd {
    return currencies.fold(0.0, (sum, item) => sum + item.withdrawal.amountUsd);
  }

  double get totalSpendingUsd {
    return currencies.fold(0.0, (sum, item) => sum + item.spending.amountUsd);
  }

  double get totalInvestmentPurchaseUsd {
    return currencies.fold(
      0.0,
      (sum, item) => sum + item.investment.purchasedUsd,
    );
  }

  double get totalInvestmentSaleUsd {
    return currencies.fold(0.0, (sum, item) => sum + item.investment.soldUsd);
  }

  double get totalBorrowingUsd {
    return currencies.fold(0.0, (sum, item) => sum + item.loan.disbursedUsd);
  }

  double get totalRepaymentUsd {
    return currencies.fold(0.0, (sum, item) => sum + item.loan.repaidUsd);
  }

  double get totalClosingSavingsUsd {
    return currencies.fold(0.0, (sum, item) => sum + item.savings.closingUsd);
  }

  double get totalClosingLoanUsd {
    return currencies.fold(
      0.0,
      (sum, item) => sum + item.loan.closingBalanceUsd,
    );
  }

  static List<FinancialCurrencySummary> _parseCurrencySummaries(dynamic value) {
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
