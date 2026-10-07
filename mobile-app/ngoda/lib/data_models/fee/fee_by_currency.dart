import 'package:ngoda/data_models/fee/fee_config.dart';

class FeeByCurrency {
  FeeByCurrency({required Map<String, FeeConfig> currencies})
    : currencies = Map.unmodifiable(currencies);

  final Map<String, FeeConfig> currencies;

  factory FeeByCurrency.fromJson(Map<String, dynamic> json) {
    final result = <String, FeeConfig>{};

    for (final entry in json.entries) {
      if (entry.value is! Map) {
        continue;
      }

      final currency = entry.key.trim().toLowerCase();

      if (currency.isEmpty) {
        continue;
      }

      result[currency] = FeeConfig.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return FeeByCurrency(currencies: result);
  }

  FeeConfig? forCurrency(String currency) {
    return currencies[currency.trim().toLowerCase()];
  }

  FeeConfig? operator [](String currency) {
    return forCurrency(currency);
  }

  bool containsCurrency(String currency) {
    return currencies.containsKey(currency.trim().toLowerCase());
  }

  List<String> get currencyCodes {
    return List.unmodifiable(currencies.keys);
  }

  List<String> get sortedCurrencyCodes {
    final result = [...currencies.keys]..sort();

    return List.unmodifiable(result);
  }
}
