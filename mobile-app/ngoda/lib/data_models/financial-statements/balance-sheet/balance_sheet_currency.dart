import 'package:ngoda/data_models/financial-statements/balance-sheet/balance_sheet_account.dart';
import 'package:ngoda/data_models/financial-statements/balance-sheet/balance_sheet_totals.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class BalanceSheetCurrency {
  BalanceSheetCurrency({
    required List<BalanceSheetAccount> assets,
    required List<BalanceSheetAccount> liabilities,
    required List<BalanceSheetAccount> equity,
    required this.totals,
    required this.revenue,
    required this.expenses,
  }) : assets = List.unmodifiable(assets),
       liabilities = List.unmodifiable(liabilities),
       equity = List.unmodifiable(equity);

  final List<BalanceSheetAccount> assets;
  final List<BalanceSheetAccount> liabilities;
  final List<BalanceSheetAccount> equity;

  final BalanceSheetTotals totals;

  /// Revenue carried over from the P&L.
  final double revenue;

  /// Expenses carried over from the P&L.
  final double expenses;

  factory BalanceSheetCurrency.fromJson(Map<String, dynamic> json) {
    return BalanceSheetCurrency(
      assets: _parseAccounts(json['assets']),
      liabilities: _parseAccounts(json['liabilities']),
      equity: _parseAccounts(json['equity']),
      totals: BalanceSheetTotals.fromJson(_asMap(json['totals'])),
      revenue: NumberConversionService.toDouble(json['revenue']),
      expenses: NumberConversionService.toDouble(json['expenses']),
    );
  }

  double get profitOrLoss => revenue - expenses;

  bool get isBalanced => totals.isBalanced;

  static List<BalanceSheetAccount> _parseAccounts(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (account) =>
              BalanceSheetAccount.fromJson(Map<String, dynamic>.from(account)),
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
