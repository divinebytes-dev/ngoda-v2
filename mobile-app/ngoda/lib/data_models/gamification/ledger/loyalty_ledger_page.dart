import 'package:ngoda/data_models/gamification/ledger/loyalty_ledger_entry.dart';
import 'package:ngoda/data_models/common/report_pagination.dart';

class LoyaltyLedgerPage {
  LoyaltyLedgerPage({
    required List<LoyaltyLedgerEntry> rows,
    required this.pagination,
  }) : rows = List.unmodifiable(rows);

  final List<LoyaltyLedgerEntry> rows;

  final ReportPagination pagination;

  factory LoyaltyLedgerPage.fromJson(Map<String, dynamic> json) {
    return LoyaltyLedgerPage(
      rows: _parseRows(json['rows']),
      pagination: ReportPagination.fromJson(_asMap(json['pagination'])),
    );
  }

  bool get isEmpty => rows.isEmpty;

  bool get isNotEmpty => rows.isNotEmpty;

  static List<LoyaltyLedgerEntry> _parseRows(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (row) => LoyaltyLedgerEntry.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
