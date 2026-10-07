import 'package:ngoda/data_models/financial-statements/profit-and-loss/pnl_account.dart';
import 'package:ngoda/data_models/financial-statements/profit-and-loss/pnl_totals.dart';

class PnLCurrency {
  PnLCurrency({
    required List<PnLAccount> revenue,
    required List<PnLAccount> expense,
    required this.totals,
  }) : revenue = List.unmodifiable(revenue),
       expense = List.unmodifiable(expense);

  final List<PnLAccount> revenue;
  final List<PnLAccount> expense;

  final PnLTotals totals;

  factory PnLCurrency.fromJson(Map<String, dynamic> json) {
    return PnLCurrency(
      revenue: _parseAccounts(json['revenue']),
      expense: _parseAccounts(json['expense']),
      totals: PnLTotals.fromJson(_asMap(json['totals'])),
    );
  }

  double get profitMargin => totals.profitMargin;

  bool get isProfit => totals.isProfit;

  bool get isLoss => totals.isLoss;

  bool get hasRevenue => revenue.isNotEmpty;

  bool get hasExpenses => expense.isNotEmpty;

  static List<PnLAccount> _parseAccounts(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (account) => PnLAccount.fromJson(Map<String, dynamic>.from(account)),
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
