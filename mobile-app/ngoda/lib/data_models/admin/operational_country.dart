import 'package:ngoda/data_models/currency/currency.dart';

class OperationalCountry {
  OperationalCountry({
    required this.countryCode,
    required this.callingCode,
    required this.name,
    required this.isActive,
    required List<Currency> currencies,
  }) : currencies = List.unmodifiable(currencies);

  final String countryCode;
  final String callingCode;
  final String name;
  final bool isActive;

  final List<Currency> currencies;

  factory OperationalCountry.fromJson(Map<String, dynamic> json) {
    final rawCurrencies = json['currencies'];

    return OperationalCountry(
      countryCode: json['country_code']?.toString().trim().toLowerCase() ?? '',
      callingCode: json['calling_code']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      isActive: _toBool(json['is_active']),
      currencies: rawCurrencies is List
          ? rawCurrencies
                .whereType<Map>()
                .map(
                  (currency) =>
                      Currency.fromJson(Map<String, dynamic>.from(currency)),
                )
                .toList()
          : const [],
    );
  }

  bool get isInactive => !isActive;

  bool get hasCurrencies => currencies.isNotEmpty;

  int get totalCurrencies => currencies.length;

  Currency? currency(String currencyCode) {
    return currencies.getByCode(currencyCode);
  }

  bool hasCurrency(String currencyCode) {
    return currency(currencyCode) != null;
  }

  static bool _toBool(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final normalized = value?.toString().trim().toLowerCase();

    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
}

extension OperationalCountryListX on List<OperationalCountry> {
  List<String> get countryCodes {
    return List.unmodifiable(map((country) => country.countryCode));
  }

  List<String> get countryNames {
    return List.unmodifiable(map((country) => country.name));
  }

  List<OperationalCountry> get activeCountries {
    return List.unmodifiable(where((country) => country.isActive));
  }

  List<OperationalCountry> get sortedByName {
    final countries = [...this]
      ..sort((first, second) => first.name.compareTo(second.name));

    return List.unmodifiable(countries);
  }

  OperationalCountry? getByCode(String code) {
    final normalized = code.trim().toLowerCase();

    for (final country in this) {
      if (country.countryCode == normalized) {
        return country;
      }
    }

    return null;
  }

  List<Currency> get allCurrencies {
    return List.unmodifiable(expand((country) => country.currencies));
  }

  List<String> get currencyCodes {
    return List.unmodifiable(
      allCurrencies.map((currency) => currency.code).toSet(),
    );
  }

  Currency? getCurrency(String code) {
    final normalized = code.trim().toLowerCase();

    for (final currency in allCurrencies) {
      if (currency.code == normalized) {
        return currency;
      }
    }

    return null;
  }

  List<Currency> getCurrenciesByCountryCode(String countryCode) {
    return getByCode(countryCode)?.currencies ?? const [];
  }
}
