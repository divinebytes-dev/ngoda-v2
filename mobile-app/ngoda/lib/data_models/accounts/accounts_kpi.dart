import 'package:ngoda/data_models/currency/currency_balance.dart';

class AccountsKPI {
  const AccountsKPI({
    required this.totalRevenue,
    required this.totalExpenses,
    required this.netProfit,
  });

  final CurrencyBalance totalRevenue;
  final CurrencyBalance totalExpenses;
  final CurrencyBalance netProfit;

  factory AccountsKPI.fromJson(Map<String, dynamic> json) {
    return AccountsKPI(
      totalRevenue: CurrencyBalance.fromJson(json['total_revenue']),
      totalExpenses: CurrencyBalance.fromJson(json['total_expenses']),
      netProfit: CurrencyBalance.fromJson(json['net_profit']),
    );
  }
}
