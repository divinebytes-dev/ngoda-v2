import 'package:ngoda/data_models/common/report_pagination.dart';
import 'package:ngoda/data_models/wallet/periodic_balance_entry.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class FinancialStatementDrilldown {
  FinancialStatementDrilldown({
    required this.glAccountCode,
    required this.glDescription,
    required this.currencyCode,
    required this.startDate,
    required this.endDate,
    required this.balanced,
    required this.openingBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.calculatedClosingBalance,
    required this.closingBalance,
    required this.difference,
    required this.pagination,
    required List<PeriodicBalanceEntry> entries,
  }) : entries = List.unmodifiable(entries);

  final String glAccountCode;
  final String glDescription;
  final String currencyCode;

  final String startDate;
  final String endDate;

  final bool balanced;

  final double openingBalance;
  final double totalDebit;
  final double totalCredit;
  final double calculatedClosingBalance;
  final double closingBalance;
  final double difference;

  final ReportPagination pagination;

  final List<PeriodicBalanceEntry> entries;

  factory FinancialStatementDrilldown.fromJson(Map<String, dynamic> json) {
    return FinancialStatementDrilldown(
      glAccountCode: json['gl_account_code']?.toString().trim() ?? '',
      glDescription: json['description']?.toString().trim() ?? '',
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      startDate: json['start_date']?.toString().trim() ?? '',
      endDate: json['end_date']?.toString().trim() ?? '',
      balanced: json['balanced'] == true,
      openingBalance: NumberConversionService.toDouble(json['opening_balance']),
      totalDebit: NumberConversionService.toDouble(json['total_debit']),
      totalCredit: NumberConversionService.toDouble(json['total_credit']),
      calculatedClosingBalance: NumberConversionService.toDouble(
        json['calculated_closing_balance'],
      ),
      closingBalance: NumberConversionService.toDouble(json['closing_balance']),
      difference: NumberConversionService.toDouble(json['difference']),
      pagination: ReportPagination.fromJson(_asMap(json['pagination'])),
      entries: _parseEntries(json['entries']),
    );
  }

  bool get hasEntries => entries.isNotEmpty;

  bool get hasDifference => difference.abs() > 0.000001;

  static List<PeriodicBalanceEntry> _parseEntries(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (entry) =>
              PeriodicBalanceEntry.fromJson(Map<String, dynamic>.from(entry)),
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
