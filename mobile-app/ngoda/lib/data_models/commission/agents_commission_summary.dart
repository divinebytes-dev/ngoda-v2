import 'dart:collection';

import 'package:ngoda/data_models/commission/commission_summary_row.dart';

class AgentsCommissionSummary {
  AgentsCommissionSummary({required List<CommissionSummaryRow> rows})
    : rows = List.unmodifiable(rows);

  final List<CommissionSummaryRow> rows;

  factory AgentsCommissionSummary.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'];

    if (rawRows is! List) {
      return AgentsCommissionSummary(rows: const []);
    }

    return AgentsCommissionSummary(
      rows: rawRows
          .whereType<Map>()
          .map(
            (row) =>
                CommissionSummaryRow.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
    );
  }

  Map<String, List<CommissionSummaryRow>> get byCurrency {
    final grouped = <String, List<CommissionSummaryRow>>{};

    for (final row in rows) {
      grouped.putIfAbsent(row.currencyCode, () => []).add(row);
    }

    return UnmodifiableMapView({
      for (final entry in grouped.entries)
        entry.key: List.unmodifiable(entry.value),
    });
  }

  Map<String, List<CommissionSummaryRow>> get byTransactionType {
    final grouped = <String, List<CommissionSummaryRow>>{};

    for (final row in rows) {
      grouped.putIfAbsent(row.transactionType, () => []).add(row);
    }

    return UnmodifiableMapView({
      for (final entry in grouped.entries)
        entry.key: List.unmodifiable(entry.value),
    });
  }

  List<CommissionSummaryRow> forCurrency(String currency) {
    final normalized = currency.trim().toLowerCase();

    return List.unmodifiable(
      rows.where((row) => row.currencyCode == normalized),
    );
  }

  List<String> get currencyList {
    return List.unmodifiable(rows.map((row) => row.currencyCode).toSet());
  }

  List<String> get sortedCurrencyList {
    final currencies = currencyList.toList()..sort();

    return List.unmodifiable(currencies);
  }

  bool get isEmpty => rows.isEmpty;

  bool get isNotEmpty => rows.isNotEmpty;
}
