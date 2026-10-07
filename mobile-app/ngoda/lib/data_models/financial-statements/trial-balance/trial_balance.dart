import 'package:ngoda/data_models/financial-statements/trial-balance/trial_balance_currency.dart';

class TrialBalance {
  TrialBalance({required Map<String, TrialBalanceCurrency> currencies})
    : currencies = Map.unmodifiable(currencies);

  final Map<String, TrialBalanceCurrency> currencies;

  factory TrialBalance.fromJson(Map<String, dynamic> json) {
    return TrialBalance(currencies: _parseCurrencies(json['currencies']));
  }

  TrialBalanceCurrency? operator [](String currency) {
    return getByCurrency(currency);
  }

  TrialBalanceCurrency? getByCurrency(String currency) {
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

  List<MapEntry<String, TrialBalanceCurrency>> get currencyEntries {
    return List.unmodifiable(currencies.entries);
  }

  /// True when every individual currency
  /// is balanced according to the backend.
  bool get allBalanced {
    return currencies.values.every((currency) => currency.isBalanced);
  }

  /// True when the frontend calculation of
  /// every currency also balances.
  bool get allCalculatedBalanced {
    return currencies.values.every((currency) => currency.computedBalanced);
  }

  /// Checks whether all returned account rows
  /// agree with their backend totals.
  bool get allTotalsMatchAccounts {
    return currencies.values.every((currency) => currency.totalsMatchAccounts);
  }

  bool get isEmpty => currencies.isEmpty;

  bool get isNotEmpty => currencies.isNotEmpty;

  static Map<String, TrialBalanceCurrency> _parseCurrencies(dynamic value) {
    if (value is! Map) {
      return const {};
    }

    final result = <String, TrialBalanceCurrency>{};

    for (final entry in value.entries) {
      if (entry.value is! Map) {
        continue;
      }

      final currency = entry.key.toString().trim().toLowerCase();

      if (currency.isEmpty) {
        continue;
      }

      result[currency] = TrialBalanceCurrency.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return result;
  }
}
