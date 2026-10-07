import 'dart:collection';

import 'package:ngoda/data_models/accounts/accounts_kpi.dart';

class AccountsKPIByCurrency {
  AccountsKPIByCurrency({required Map<String, AccountsKPI> data})
    : data = UnmodifiableMapView(_normalizeData(data));

  final Map<String, AccountsKPI> data;

  factory AccountsKPIByCurrency.fromJson(Map<String, dynamic> json) {
    final data = <String, AccountsKPI>{};

    for (final entry in json.entries) {
      final currency = _normalizeCurrency(entry.key);

      if (currency.isEmpty) {
        continue;
      }

      final value = entry.value;

      if (value is Map<String, dynamic>) {
        data[currency] = AccountsKPI.fromJson(value);

        continue;
      }

      if (value is Map) {
        data[currency] = AccountsKPI.fromJson(Map<String, dynamic>.from(value));
      }
    }

    return AccountsKPIByCurrency(data: data);
  }

  AccountsKPI? operator [](String currency) {
    return getByCurrency(currency);
  }

  AccountsKPI? getByCurrency(String currency) {
    return data[_normalizeCurrency(currency)];
  }

  bool containsCurrency(String currency) {
    return data.containsKey(_normalizeCurrency(currency));
  }

  List<String> get currencyList => List.unmodifiable(data.keys);

  List<String> get sortedCurrencyList {
    final currencies = data.keys.toList()..sort();

    return List.unmodifiable(currencies);
  }

  List<MapEntry<String, AccountsKPI>> get currencyEntries =>
      List.unmodifiable(data.entries);

  double get totalRevenueUsd {
    return data.values.fold(
      0.0,
      (total, kpi) => total + kpi.totalRevenue.usdValue,
    );
  }

  double get totalExpensesUsd {
    return data.values.fold(
      0.0,
      (total, kpi) => total + kpi.totalExpenses.usdValue,
    );
  }

  double get totalNetProfitUsd {
    return data.values.fold(
      0.0,
      (total, kpi) => total + kpi.netProfit.usdValue,
    );
  }

  bool get isProfitable => totalNetProfitUsd > 0;

  bool get isEmpty => data.isEmpty;

  bool get isNotEmpty => data.isNotEmpty;

  static Map<String, AccountsKPI> _normalizeData(
    Map<String, AccountsKPI> data,
  ) {
    final normalized = <String, AccountsKPI>{};

    for (final entry in data.entries) {
      final currency = _normalizeCurrency(entry.key);

      if (currency.isEmpty) {
        continue;
      }

      normalized[currency] = entry.value;
    }

    return normalized;
  }

  static String _normalizeCurrency(String value) {
    return value.trim().toLowerCase();
  }
}
