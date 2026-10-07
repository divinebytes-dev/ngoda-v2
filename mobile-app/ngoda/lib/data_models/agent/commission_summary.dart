import 'package:ngoda/data_models/agent/commission_period.dart';

class CommissionSummary {
  CommissionSummary({required Map<String, CommissionPeriod> currencies})
    : currencies = Map.unmodifiable(currencies);

  final Map<String, CommissionPeriod> currencies;

  factory CommissionSummary.fromJson(Map<String, dynamic> json) {
    final result = <String, CommissionPeriod>{};

    for (final entry in json.entries) {
      if (entry.value is! Map) {
        continue;
      }

      final currency = entry.key.trim().toLowerCase();

      if (currency.isEmpty) {
        continue;
      }

      result[currency] = CommissionPeriod.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return CommissionSummary(currencies: result);
  }

  CommissionPeriod? operator [](String currency) {
    return getByCurrency(currency);
  }

  CommissionPeriod? getByCurrency(String currency) {
    return currencies[currency.trim().toLowerCase()];
  }

  bool containsCurrency(String currency) {
    return currencies.containsKey(currency.trim().toLowerCase());
  }
}

extension CommissionSummaryX on CommissionSummary {
  List<String> get currencyList {
    return List.unmodifiable(currencies.keys);
  }

  List<String> get sortedCurrencyList {
    final result = [...currencies.keys]..sort();

    return List.unmodifiable(result);
  }

  List<MapEntry<String, CommissionPeriod>> get currencyEntries {
    return List.unmodifiable(currencies.entries);
  }

  bool get isEmpty => currencies.isEmpty;

  bool get isNotEmpty => currencies.isNotEmpty;
}
