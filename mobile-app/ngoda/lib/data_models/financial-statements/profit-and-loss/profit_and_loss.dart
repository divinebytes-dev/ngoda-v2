import 'package:ngoda/data_models/financial-statements/profit-and-loss/pnl_currency.dart';
import 'package:ngoda/data_models/financial-statements/profit-and-loss/pnl_period.dart';

class ProfitAndLoss {
  ProfitAndLoss({
    required this.period,
    required Map<String, PnLCurrency> currencies,
  }) : currencies = Map.unmodifiable(currencies);

  final PnLPeriod period;

  final Map<String, PnLCurrency> currencies;

  factory ProfitAndLoss.fromJson(Map<String, dynamic> json) {
    return ProfitAndLoss(
      period: PnLPeriod.fromJson(_asMap(json['period'])),
      currencies: _parseCurrencies(json['currencies']),
    );
  }

  PnLCurrency? operator [](String currency) {
    return getByCurrency(currency);
  }

  PnLCurrency? getByCurrency(String currency) {
    return currencies[currency.trim().toLowerCase()];
  }

  bool containsCurrency(String currency) {
    return currencies.containsKey(currency.trim().toLowerCase());
  }

  List<String> get currencyList {
    return List.unmodifiable(currencies.keys);
  }

  List<String> get sortedCurrencyList {
    final result = [...currencies.keys]..sort();

    return List.unmodifiable(result);
  }

  List<MapEntry<String, PnLCurrency>> get currencyEntries {
    return List.unmodifiable(currencies.entries);
  }

  bool get isEmpty => currencies.isEmpty;

  bool get isNotEmpty => currencies.isNotEmpty;

  static Map<String, PnLCurrency> _parseCurrencies(dynamic value) {
    if (value is! Map) {
      return const {};
    }

    final result = <String, PnLCurrency>{};

    for (final entry in value.entries) {
      if (entry.value is! Map) {
        continue;
      }

      final currency = entry.key.toString().trim().toLowerCase();

      if (currency.isEmpty) {
        continue;
      }

      result[currency] = PnLCurrency.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return result;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
