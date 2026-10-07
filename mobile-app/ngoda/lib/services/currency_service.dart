import 'package:ngoda/data_models/currency/currency.dart';

abstract final class CurrencyService {
  static final Map<String, Currency> _currencies = {};

  static bool _isInitialized = false;

  static bool get isInitialized {
    return _isInitialized;
  }

  static void initialize(List<Currency> currencies) {
    _currencies
      ..clear()
      ..addEntries(
        currencies.map((currency) {
          return MapEntry(_normalize(currency.code), currency);
        }),
      );

    _isInitialized = true;
  }

  static Currency? get(String code) {
    final normalized = _normalize(code);

    if (normalized.isEmpty) {
      return null;
    }

    return _currencies[normalized];
  }

  static String symbol(String code) {
    final normalized = _normalize(code);

    if (normalized.isEmpty) {
      return '';
    }

    return get(normalized)?.symbol ?? normalized.toUpperCase();
  }

  static String name(String code) {
    final normalized = _normalize(code);

    if (normalized.isEmpty) {
      return '';
    }

    return get(normalized)?.name ?? normalized.toUpperCase();
  }

  static bool isActive(String code) {
    return get(code)?.isActive ?? false;
  }

  static List<Currency> get all {
    return List.unmodifiable(_currencies.values);
  }

  static List<Currency> get active {
    return List.unmodifiable(
      _currencies.values.where((currency) {
        return currency.isActive;
      }),
    );
  }

  static bool contains(String code) {
    final normalized = _normalize(code);

    if (normalized.isEmpty) {
      return false;
    }

    return _currencies.containsKey(normalized);
  }

  static String _normalize(String code) {
    return code.trim().toLowerCase();
  }
}
