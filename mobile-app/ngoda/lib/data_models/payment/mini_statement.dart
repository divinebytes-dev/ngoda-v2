import 'package:ngoda/data_models/wallet/currency_statement.dart';

class MiniStatement {
  MiniStatement({required Map<String, CurrencyStatement> currencies})
    : currencies = Map.unmodifiable(
        currencies.map(
          (currency, statement) =>
              MapEntry(currency.trim().toLowerCase(), statement),
        ),
      );

  final Map<String, CurrencyStatement> currencies;

  factory MiniStatement.fromJson(Map<String, dynamic> json) {
    final currencies = <String, CurrencyStatement>{};

    for (final entry in json.entries) {
      final currency = entry.key.trim().toLowerCase();

      if (currency.isEmpty || entry.value is! Map) {
        continue;
      }

      currencies[currency] = CurrencyStatement.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return MiniStatement(currencies: currencies);
  }

  factory MiniStatement.empty() {
    return MiniStatement(currencies: const {});
  }

  CurrencyStatement? operator [](String currency) {
    return getByCurrency(currency);
  }

  CurrencyStatement? getByCurrency(String currency) {
    return currencies[currency.trim().toLowerCase()];
  }

  bool hasCurrency(String currency) {
    return currencies.containsKey(currency.trim().toLowerCase());
  }

  MiniStatement replaceCurrency({
    required String currency,
    required CurrencyStatement statement,
  }) {
    final normalized = currency.trim().toLowerCase();

    if (normalized.isEmpty) {
      return this;
    }

    return MiniStatement(currencies: {...currencies, normalized: statement});
  }

  bool get isEmpty => currencies.isEmpty;

  bool get isNotEmpty => currencies.isNotEmpty;
}

extension MiniStatementX on MiniStatement {
  List<String> get currencyList {
    return List.unmodifiable(currencies.keys);
  }

  List<String> get sortedCurrencyList {
    final result = [...currencies.keys]..sort();

    return List.unmodifiable(result);
  }

  List<MapEntry<String, CurrencyStatement>> get currencyEntries {
    final result = currencies.entries.toList()
      ..sort((first, second) => first.key.compareTo(second.key));

    return List.unmodifiable(result);
  }
}
