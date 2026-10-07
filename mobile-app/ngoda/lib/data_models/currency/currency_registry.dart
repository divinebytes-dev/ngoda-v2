import 'dart:collection';

import 'package:ngoda/data_models/currency/currency.dart';

class CurrencyRegistry {
  CurrencyRegistry(Map<String, Currency> currencies)
    : _map = UnmodifiableMapView(_normalizeMap(currencies));

  final Map<String, Currency> _map;

  factory CurrencyRegistry.fromList(List<dynamic> list) {
    final currencies = <Currency>[];

    for (final item in list) {
      if (item is Map<String, dynamic>) {
        currencies.add(Currency.fromJson(item));

        continue;
      }

      if (item is Map) {
        currencies.add(Currency.fromJson(Map<String, dynamic>.from(item)));
      }
    }

    return CurrencyRegistry.fromCurrencies(currencies);
  }

  factory CurrencyRegistry.fromCurrencies(Iterable<Currency> currencies) {
    return CurrencyRegistry({
      for (final currency in currencies) currency.code: currency,
    });
  }

  Currency? operator [](String code) {
    return getByCode(code);
  }

  Currency? getByCode(String code) {
    return _map[_normalizeCurrencyCode(code)];
  }

  bool contains(String code) {
    return _map.containsKey(_normalizeCurrencyCode(code));
  }

  String getSymbol(String code) {
    final normalized = _normalizeCurrencyCode(code);

    return getByCode(normalized)?.symbol ?? normalized.toUpperCase();
  }

  String getName(String code) {
    final normalized = _normalizeCurrencyCode(code);

    return getByCode(normalized)?.name ?? normalized.toUpperCase();
  }

  List<String> get codes {
    return List.unmodifiable(_map.keys);
  }

  List<String> get sortedCodes {
    final values = _map.keys.toList()..sort();

    return List.unmodifiable(values);
  }

  List<Currency> get values {
    return List.unmodifiable(_map.values);
  }

  List<Currency> get activeCurrencies {
    return List.unmodifiable(
      _map.values.where((currency) => currency.isActive),
    );
  }

  Currency? get reportingCurrency {
    for (final currency in _map.values) {
      if (currency.isReporting == true) {
        return currency;
      }
    }

    return null;
  }

  bool get isEmpty => _map.isEmpty;

  bool get isNotEmpty => _map.isNotEmpty;

  int get length => _map.length;

  static Map<String, Currency> _normalizeMap(Map<String, Currency> currencies) {
    final normalized = <String, Currency>{};

    for (final entry in currencies.entries) {
      final code = _normalizeCurrencyCode(entry.key);

      if (code.isEmpty) {
        continue;
      }

      normalized[code] = entry.value;
    }

    return normalized;
  }

  static String _normalizeCurrencyCode(String value) {
    return value.trim().toLowerCase();
  }
}
