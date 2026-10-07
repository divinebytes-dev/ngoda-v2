import 'package:ngoda/data_models/commission/commission_settlement_date.dart';

class LastCommissionSettlementDates {
  LastCommissionSettlementDates({required List<CommissionSettlementDate> rows})
    : rows = List.unmodifiable(rows);

  final List<CommissionSettlementDate> rows;

  factory LastCommissionSettlementDates.fromJson(dynamic json) {
    final rawRows = json is List ? json : const [];

    return LastCommissionSettlementDates(
      rows: rawRows
          .whereType<Map>()
          .map(
            (row) => CommissionSettlementDate.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList(),
    );
  }

  CommissionSettlementDate? getByCurrency(String currency) {
    final normalized = currency.trim().toLowerCase();

    for (final row in rows) {
      if (row.currencyCode == normalized) {
        return row;
      }
    }

    return null;
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
