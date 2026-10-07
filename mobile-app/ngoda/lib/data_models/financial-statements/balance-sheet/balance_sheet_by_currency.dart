import 'package:ngoda/data_models/financial-statements/balance-sheet/balance_sheet_snapshot.dart';

class BalanceSheetByCurrency {
  BalanceSheetByCurrency({required Map<String, BalanceSheetSnapshot> data})
    : data = Map.unmodifiable(data);

  final Map<String, BalanceSheetSnapshot> data;

  factory BalanceSheetByCurrency.fromJson(Map<String, dynamic> json) {
    final result = <String, BalanceSheetSnapshot>{};

    for (final entry in json.entries) {
      if (entry.value is! Map) {
        continue;
      }

      final currency = entry.key.trim().toLowerCase();

      if (currency.isEmpty) {
        continue;
      }

      result[currency] = BalanceSheetSnapshot.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return BalanceSheetByCurrency(data: result);
  }

  BalanceSheetSnapshot? operator [](String currency) {
    return getByCurrency(currency);
  }

  BalanceSheetSnapshot? getByCurrency(String currency) {
    return data[currency.trim().toLowerCase()];
  }

  bool containsCurrency(String currency) {
    return data.containsKey(currency.trim().toLowerCase());
  }

  List<String> get currencyList {
    return List.unmodifiable(data.keys);
  }

  List<String> get sortedCurrencyList {
    final result = [...data.keys]..sort();

    return List.unmodifiable(result);
  }

  List<MapEntry<String, BalanceSheetSnapshot>> get currencyEntries {
    return List.unmodifiable(data.entries);
  }

  double get totalAssetsUsd {
    return data.values.fold(
      0.0,
      (total, snapshot) => total + snapshot.assets.usdValue,
    );
  }

  double get totalLiabilitiesUsd {
    return data.values.fold(
      0.0,
      (total, snapshot) => total + snapshot.liabilities.usdValue,
    );
  }

  double get totalEquityUsd {
    return data.values.fold(
      0.0,
      (total, snapshot) => total + snapshot.equity.usdValue,
    );
  }

  double get differenceUsd =>
      totalAssetsUsd - totalLiabilitiesUsd - totalEquityUsd;

  bool get isBalancedUsd => differenceUsd.abs() <= 0.000001;

  bool get allCurrenciesBalanced {
    return data.values.every((snapshot) => snapshot.isBalanced);
  }

  bool get isEmpty => data.isEmpty;

  bool get isNotEmpty => data.isNotEmpty;
}
