import 'package:ngoda/data_models/currency/currency_balance.dart';

class TreasuryWallet {
  TreasuryWallet({required Map<String, CurrencyBalance> currencies})
    : currencies = Map.unmodifiable(
        currencies.map(
          (currency, balance) =>
              MapEntry(currency.trim().toLowerCase(), balance),
        ),
      );

  final Map<String, CurrencyBalance> currencies;

  factory TreasuryWallet.fromJson(Map<String, dynamic> json) {
    final currencies = <String, CurrencyBalance>{};

    for (final entry in json.entries) {
      final currency = entry.key.trim().toLowerCase();

      if (currency.isEmpty || entry.value is! Map) {
        continue;
      }

      currencies[currency] = CurrencyBalance.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return TreasuryWallet(currencies: currencies);
  }

  factory TreasuryWallet.empty() {
    return TreasuryWallet(currencies: const {});
  }

  CurrencyBalance? operator [](String currency) {
    return getByCurrency(currency);
  }

  CurrencyBalance? getByCurrency(String currency) {
    return currencies[currency.trim().toLowerCase()];
  }

  bool hasCurrency(String currency) {
    return currencies.containsKey(currency.trim().toLowerCase());
  }

  bool get isEmpty => currencies.isEmpty;

  bool get isNotEmpty => currencies.isNotEmpty;
}

extension TreasuryWalletX on TreasuryWallet {
  List<String> get currencyList {
    return List.unmodifiable(currencies.keys);
  }

  List<String> get sortedCurrencyList {
    final result = [...currencies.keys]..sort();

    return List.unmodifiable(result);
  }

  List<MapEntry<String, CurrencyBalance>> get currencyEntries {
    final result = currencies.entries.toList()
      ..sort((first, second) => first.key.compareTo(second.key));

    return List.unmodifiable(result);
  }

  double get totalUsdValue {
    return currencies.values.fold(
      0.0,
      (total, balance) => total + balance.usdValue,
    );
  }

  List<String> get nonZeroCurrencies {
    final result =
        currencies.entries
            .where((entry) => entry.value.balance != 0)
            .map((entry) => entry.key)
            .toList()
          ..sort();

    return List.unmodifiable(result);
  }

  MapEntry<String, CurrencyBalance>? get largestHolding {
    if (currencies.isEmpty) {
      return null;
    }

    MapEntry<String, CurrencyBalance>? largest;

    for (final entry in currencies.entries) {
      if (largest == null || entry.value.usdValue > largest.value.usdValue) {
        largest = entry;
      }
    }

    return largest;
  }
}
