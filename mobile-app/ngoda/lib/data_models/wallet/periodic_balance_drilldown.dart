import 'package:ngoda/data_models/common/report_pagination.dart';
import 'package:ngoda/data_models/wallet/periodic_balance_entry.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class PeriodicBalanceDrilldown {
  PeriodicBalanceDrilldown({
    required this.fiscalYear,
    required this.period,
    required this.currencyCode,
    required this.glAccountCode,
    required this.glDescription,
    required this.balanced,
    required this.openingBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.calculatedClosingBalance,
    required this.pageOpeningBalance,
    required this.pageClosingBalance,
    required this.closingBalance,
    required this.difference,
    required this.pagination,
    required List<PeriodicBalanceEntry> entries,
  }) : entries = List.unmodifiable(entries);

  /*
   * Financial comparison tolerance.
   *
   * Small floating-point differences below
   * this value are not treated as actual
   * balance differences.
   */
  static const double differenceTolerance = 0.0001;

  final int fiscalYear;
  final int period;

  final String currencyCode;

  final String glAccountCode;
  final String glDescription;

  /// Backend-calculated balance state.
  final bool balanced;

  final double openingBalance;

  final double totalDebit;
  final double totalCredit;

  /// Backend-calculated closing balance.
  final double calculatedClosingBalance;

  final double pageOpeningBalance;
  final double pageClosingBalance;

  /// Backend snapshot closing balance.
  final double closingBalance;

  /// Backend-calculated difference.
  final double difference;

  final ReportPagination pagination;

  final List<PeriodicBalanceEntry> entries;

  factory PeriodicBalanceDrilldown.fromJson(Map<String, dynamic> json) {
    return PeriodicBalanceDrilldown(
      fiscalYear: NumberConversionService.toInt(json['fiscal_year']),
      period: NumberConversionService.toInt(json['period']),
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      glAccountCode: json['gl_account_code']?.toString().trim() ?? '',
      glDescription: json['description']?.toString().trim() ?? '',
      balanced: json['balanced'] == true,
      openingBalance: NumberConversionService.toDouble(json['opening_balance']),
      totalDebit: NumberConversionService.toDouble(json['total_debit']),
      totalCredit: NumberConversionService.toDouble(json['total_credit']),
      calculatedClosingBalance: NumberConversionService.toDouble(
        json['calculated_closing_balance'],
      ),
      pageOpeningBalance: NumberConversionService.toDouble(
        json['page_opening_balance'],
      ),
      pageClosingBalance: NumberConversionService.toDouble(
        json['page_closing_balance'],
      ),
      closingBalance: NumberConversionService.toDouble(json['closing_balance']),
      difference: NumberConversionService.toDouble(json['difference']),
      pagination: ReportPagination.fromJson(_asMap(json['pagination'])),
      entries: _parseEntries(json['entries']),
    );
  }

  bool get hasEntries => entries.isNotEmpty;

  /*
   * Do not compare financial floating-point
   * values directly with zero.
   *
   * This restores the behaviour that existed
   * before the model cleanup.
   */
  bool get hasDifference => difference.abs() > differenceTolerance;

  int get transactionCount => entries.length;

  double get movement => totalCredit - totalDebit;

  /*
   * Expected closing balance derived from
   * opening balance and the period movement.
   */
  double get expectedClosingBalance => openingBalance + movement;

  /*
   * Confirms that our derived closing value
   * agrees with the backend-calculated
   * closing balance within the same
   * financial tolerance.
   */
  bool get calculationMatches {
    return (expectedClosingBalance - calculatedClosingBalance).abs() <
        differenceTolerance;
  }

  PeriodicBalanceEntry? get firstEntry =>
      entries.isEmpty ? null : entries.first;

  PeriodicBalanceEntry? get lastEntry => entries.isEmpty ? null : entries.last;

  double get lastRunningBalance => lastEntry?.runningBalance ?? openingBalance;

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
