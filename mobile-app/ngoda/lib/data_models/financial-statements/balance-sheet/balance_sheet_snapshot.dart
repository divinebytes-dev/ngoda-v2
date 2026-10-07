import 'package:ngoda/data_models/currency/currency_balance.dart';

class BalanceSheetSnapshot {
  const BalanceSheetSnapshot({
    required this.assets,
    required this.liabilities,
    required this.equity,
  });

  final CurrencyBalance assets;
  final CurrencyBalance liabilities;
  final CurrencyBalance equity;

  factory BalanceSheetSnapshot.fromJson(Map<String, dynamic> json) {
    return BalanceSheetSnapshot(
      assets: CurrencyBalance.fromJson(_asMap(json['assets'])),
      liabilities: CurrencyBalance.fromJson(_asMap(json['liabilities'])),
      equity: CurrencyBalance.fromJson(_asMap(json['equity'])),
    );
  }

  double get difference =>
      assets.balance - liabilities.balance - equity.balance;

  bool get isBalanced => difference.abs() <= 0.000001;

  double get differenceUsd =>
      assets.usdValue - liabilities.usdValue - equity.usdValue;

  bool get isBalancedUsd => differenceUsd.abs() <= 0.000001;

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
