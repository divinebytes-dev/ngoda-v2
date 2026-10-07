import 'package:ngoda/data_models/financial-intelligence/financial_distribution.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_money_in.dart';

class FinancialMoneyByCurrency {
  const FinancialMoneyByCurrency({
    required this.currencyCode,
    required this.moneyIn,
    required this.distribution,
  });

  final String currencyCode;
  final FinancialMoneyIn moneyIn;
  final FinancialDistribution distribution;

  factory FinancialMoneyByCurrency.fromJson(Map<String, dynamic> json) {
    return FinancialMoneyByCurrency(
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      moneyIn: FinancialMoneyIn.fromJson(_asMap(json['money_in'])),
      distribution: FinancialDistribution.fromJson(
        _asMap(json['distribution']),
      ),
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
