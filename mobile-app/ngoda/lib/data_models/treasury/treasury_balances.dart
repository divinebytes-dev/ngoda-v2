import 'package:ngoda/data_models/treasury/treasury_balance_entry.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class TreasuryBalances {
  TreasuryBalances({
    required this.fiscalYear,
    required this.period,
    required List<TreasuryBalanceEntry> balances,
  }) : balances = List.unmodifiable(balances);

  final int fiscalYear;
  final int period;

  final List<TreasuryBalanceEntry> balances;

  factory TreasuryBalances.fromJson(Map<String, dynamic> json) {
    return TreasuryBalances(
      fiscalYear: NumberConversionService.toInt(json['fiscalYear']),
      period: NumberConversionService.toInt(json['period']),
      balances: _parseBalances(json['balances']),
    );
  }

  factory TreasuryBalances.empty({int fiscalYear = 0, int period = 0}) {
    return TreasuryBalances(
      fiscalYear: fiscalYear,
      period: period,
      balances: const [],
    );
  }

  bool get isEmpty => balances.isEmpty;

  bool get isNotEmpty => balances.isNotEmpty;

  static List<TreasuryBalanceEntry> _parseBalances(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (entry) =>
              TreasuryBalanceEntry.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList();
  }
}

extension TreasuryBalancesX on TreasuryBalances {
  List<String> get currencyList {
    return List.unmodifiable(
      balances
          .map((entry) => entry.currencyCode)
          .where((currency) => currency.isNotEmpty)
          .toSet(),
    );
  }

  List<String> get sortedCurrencyList {
    final result = [...currencyList]..sort();

    return List.unmodifiable(result);
  }

  Map<String, List<TreasuryBalanceEntry>> get byCurrency {
    final grouped = <String, List<TreasuryBalanceEntry>>{};

    for (final entry in balances) {
      final currency = entry.currencyCode;

      if (currency.isEmpty) {
        continue;
      }

      grouped.putIfAbsent(currency, () => []).add(entry);
    }

    return Map.unmodifiable(
      grouped.map(
        (currency, entries) => MapEntry(currency, List.unmodifiable(entries)),
      ),
    );
  }

  Map<String, TreasuryBalanceEntry> get summarizedByCurrency {
    final result = <String, TreasuryBalanceEntry>{};

    for (final groupedEntry in byCurrency.entries) {
      final entries = groupedEntry.value;

      result[groupedEntry.key] = TreasuryBalanceEntry(
        currencyCode: groupedEntry.key,
        debit: entries.fold(0.0, (sum, entry) => sum + entry.debit),
        credit: entries.fold(0.0, (sum, entry) => sum + entry.credit),
        opening: entries.fold(0.0, (sum, entry) => sum + entry.opening),
        closing: entries.fold(0.0, (sum, entry) => sum + entry.closing),
      );
    }

    return Map.unmodifiable(result);
  }

  TreasuryBalanceEntry? getByCurrency(String currency) {
    return summarizedByCurrency[currency.trim().toLowerCase()];
  }
}
