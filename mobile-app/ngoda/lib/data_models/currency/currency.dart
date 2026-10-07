import 'package:ngoda/services/number_conversion_service.dart';

class Currency {
  const Currency({
    required this.code,
    required this.name,
    required this.symbol,
    required this.decimals,
    required this.rateApi,
    required this.isReporting,
    required this.isActive,
  });

  final String code;
  final String name;
  final String symbol;
  final int decimals;
  final String? rateApi;
  final bool? isReporting;
  final bool isActive;

  factory Currency.fromJson(Map<String, dynamic> json) {
    return Currency(
      code: _asString(json['currency_code']).trim().toLowerCase(),
      name: _asString(json['name']).trim(),
      symbol: _asString(json['symbol']).trim(),
      decimals: NumberConversionService.toInt(json['decimals'], fallback: 2),
      rateApi: _asNullableString(json['rate_api']),
      isReporting: _asNullableBool(json['is_reporting']),
      isActive: _asBool(json['is_active']),
    );
  }

  bool get isFiat => code != 'gold';

  bool get isGold => code == 'gold';

  @override
  String toString() {
    return 'Currency('
        'code: $code, '
        'name: $name, '
        'symbol: $symbol, '
        'decimals: $decimals, '
        'rateApi: $rateApi, '
        'isReporting: $isReporting, '
        'isActive: $isActive'
        ')';
  }
}

extension CurrencyListX on List<Currency> {
  List<String> get codes {
    return List.unmodifiable(map((currency) => currency.code));
  }

  List<String> get sortedCodes {
    final values = codes.toList()..sort();

    return List.unmodifiable(values);
  }

  List<Currency> get activeCurrencies {
    return List.unmodifiable(where((currency) => currency.isActive));
  }

  Currency? getByCode(String code) {
    final normalized = _normalizeCurrencyCode(code);

    if (normalized.isEmpty) {
      return null;
    }

    for (final currency in this) {
      if (currency.code == normalized) {
        return currency;
      }
    }

    return null;
  }

  String getSymbol(String code) {
    final normalized = _normalizeCurrencyCode(code);

    return getByCode(normalized)?.symbol ?? normalized.toUpperCase();
  }

  String getName(String code) {
    final normalized = _normalizeCurrencyCode(code);

    return getByCode(normalized)?.name ?? normalized.toUpperCase();
  }

  Map<String, Currency> get byCode {
    return {for (final currency in this) currency.code: currency};
  }
}

String _normalizeCurrencyCode(String value) {
  return value.trim().toLowerCase();
}

String _asString(dynamic value) {
  return value?.toString() ?? '';
}

String? _asNullableString(dynamic value) {
  if (value == null) {
    return null;
  }

  final normalized = value.toString().trim();

  return normalized.isEmpty ? null : normalized;
}

bool _asBool(dynamic value) {
  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  final normalized = value?.toString().trim().toLowerCase();

  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}

bool? _asNullableBool(dynamic value) {
  if (value == null) {
    return null;
  }

  return _asBool(value);
}
