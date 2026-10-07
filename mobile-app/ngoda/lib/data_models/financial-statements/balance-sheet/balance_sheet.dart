import 'package:ngoda/data_models/financial-statements/balance-sheet/balance_sheet_currency.dart';

class BalanceSheet {
  BalanceSheet({
    required this.asOfDate,
    required Map<String, BalanceSheetCurrency> currencies,
  }) : currencies = Map.unmodifiable(currencies);

  final DateTime asOfDate;

  final Map<String, BalanceSheetCurrency> currencies;

  factory BalanceSheet.fromJson(Map<String, dynamic> json) {
    return BalanceSheet(
      asOfDate: _parseRequiredDate(json['asOfDate']),
      currencies: _parseCurrencies(json['currencies']),
    );
  }

  BalanceSheetCurrency? operator [](String currency) {
    return getByCurrency(currency);
  }

  BalanceSheetCurrency? getByCurrency(String currency) {
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

  List<MapEntry<String, BalanceSheetCurrency>> get currencyEntries {
    return List.unmodifiable(currencies.entries);
  }

  static Map<String, BalanceSheetCurrency> _parseCurrencies(dynamic value) {
    if (value is! Map) {
      return const {};
    }

    final result = <String, BalanceSheetCurrency>{};

    for (final entry in value.entries) {
      if (entry.value is! Map) {
        continue;
      }

      final currency = entry.key.toString().trim().toLowerCase();

      if (currency.isEmpty) {
        continue;
      }

      result[currency] = BalanceSheetCurrency.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return result;
  }

  static DateTime _parseRequiredDate(dynamic value) {
    final raw = value?.toString().trim();

    if (raw == null || raw.isEmpty) {
      throw const FormatException('BalanceSheet.asOfDate is required.');
    }

    return DateTime.parse(raw);
  }
}
