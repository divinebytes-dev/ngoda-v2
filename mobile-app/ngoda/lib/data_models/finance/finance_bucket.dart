import 'package:ngoda/data_models/currency/currency_balance.dart';

class FinanceBucket {
  FinanceBucket({required Map<String, CurrencyBalance> balances})
    : balances = Map.unmodifiable(
        balances.map(
          (currency, balance) =>
              MapEntry(currency.trim().toLowerCase(), balance),
        ),
      );

  final Map<String, CurrencyBalance> balances;

  factory FinanceBucket.fromJson(Map<String, dynamic> json) {
    final balances = <String, CurrencyBalance>{};

    for (final entry in json.entries) {
      final currency = entry.key.trim().toLowerCase();

      if (currency.isEmpty || entry.value is! Map) {
        continue;
      }

      balances[currency] = CurrencyBalance.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return FinanceBucket(balances: balances);
  }

  CurrencyBalance? operator [](String currency) {
    return balances[currency.trim().toLowerCase()];
  }

  CurrencyBalance? getByCurrency(String currency) {
    return balances[currency.trim().toLowerCase()];
  }
}

extension FinanceBucketX on FinanceBucket {
  List<String> get currencyList {
    return List.unmodifiable(balances.keys);
  }

  List<String> get sortedCurrencyList {
    final result = [...balances.keys]..sort();

    return List.unmodifiable(result);
  }

  List<MapEntry<String, CurrencyBalance>> get currencyEntries {
    return List.unmodifiable(balances.entries);
  }

  /// Valid because every value is expressed
  /// in the same USD reporting currency.
  double get totalUsd {
    return balances.values.fold<double>(
      0.0,
      (sum, balance) => sum + balance.usdValue,
    );
  }
}
