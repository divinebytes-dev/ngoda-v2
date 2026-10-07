import 'dart:collection';

import 'package:ngoda/data_models/tax/tax_summary_row.dart';

class TaxSummary {
  TaxSummary({required List<TaxSummaryRow> rows})
    : rows = List.unmodifiable(rows);

  final List<TaxSummaryRow> rows;

  factory TaxSummary.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];

    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : json;

    final rawRows = data['rows'];

    if (rawRows is! List) {
      return TaxSummary(rows: const []);
    }

    return TaxSummary(
      rows: rawRows
          .whereType<Map>()
          .map((row) => TaxSummaryRow.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
    );
  }

  bool get isEmpty => rows.isEmpty;

  bool get isNotEmpty => rows.isNotEmpty;

  List<String> get currencyList {
    return List.unmodifiable(rows.map((row) => row.currencyCode).toSet());
  }

  List<String> get sortedCurrencyList {
    final currencies = currencyList.toList()..sort();

    return List.unmodifiable(currencies);
  }

  Map<String, List<TaxSummaryRow>> get byCurrency {
    final grouped = <String, List<TaxSummaryRow>>{};

    for (final row in rows) {
      grouped.putIfAbsent(row.currencyCode, () => []).add(row);
    }

    return UnmodifiableMapView({
      for (final entry in grouped.entries)
        entry.key: List.unmodifiable(entry.value),
    });
  }

  List<TaxSummaryRow> forCurrency(String currency) {
    final normalized = currency.trim().toLowerCase();

    return List.unmodifiable(
      rows.where((row) => row.currencyCode == normalized),
    );
  }
}
