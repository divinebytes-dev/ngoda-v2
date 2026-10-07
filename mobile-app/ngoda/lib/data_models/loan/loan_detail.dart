import 'package:ngoda/data_models/loan/loan_balances.dart';
import 'package:ngoda/data_models/loan/loan_entry.dart';
import 'package:ngoda/data_models/loan/loan_totals.dart';

class LoanDetails {
  LoanDetails({
    required List<LoanEntry> entries,
    required this.totals,
    required this.balances,
  }) : entries = List.unmodifiable(entries);

  final List<LoanEntry> entries;

  final LoanTotals totals;
  final LoanBalances balances;

  factory LoanDetails.fromJson(Map<String, dynamic> json) {
    return LoanDetails(
      entries: _parseEntries(json['entries']),
      totals: LoanTotals.fromJson(_asMap(json['totals'])),
      balances: LoanBalances.fromJson(_asMap(json['balances'])),
    );
  }

  bool get hasEntries => entries.isNotEmpty;

  static List<LoanEntry> _parseEntries(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((entry) => LoanEntry.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
