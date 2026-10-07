import 'package:ngoda/services/number_conversion_service.dart';

class FinancialDistribution {
  const FinancialDistribution({
    this.withdrawal = 0,
    this.spending = 0,
    this.investment = 0,
    this.repayment = 0,
    this.savings = 0,
    this.total = 0,
    this.withdrawalUsd = 0,
    this.spendingUsd = 0,
    this.investmentUsd = 0,
    this.repaymentUsd = 0,
    this.savingsUsd = 0,
    this.totalUsd = 0,
  });

  final double withdrawal;
  final double spending;
  final double investment;
  final double repayment;
  final double savings;
  final double total;

  final double withdrawalUsd;
  final double spendingUsd;
  final double investmentUsd;
  final double repaymentUsd;
  final double savingsUsd;
  final double totalUsd;

  factory FinancialDistribution.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};

    return FinancialDistribution(
      withdrawal: NumberConversionService.toDouble(data['withdrawal']),
      spending: NumberConversionService.toDouble(data['spending']),
      investment: NumberConversionService.toDouble(data['investment']),
      repayment: NumberConversionService.toDouble(data['repayment']),
      savings: NumberConversionService.toDouble(data['savings']),
      total: NumberConversionService.toDouble(data['total']),
      withdrawalUsd: NumberConversionService.toDouble(data['withdrawal_usd']),
      spendingUsd: NumberConversionService.toDouble(data['spending_usd']),
      investmentUsd: NumberConversionService.toDouble(data['investment_usd']),
      repaymentUsd: NumberConversionService.toDouble(data['repayment_usd']),
      savingsUsd: NumberConversionService.toDouble(data['savings_usd']),
      totalUsd: NumberConversionService.toDouble(data['total_usd']),
    );
  }

  Map<String, double> get nativeChart {
    return Map.unmodifiable({
      'withdrawal': withdrawal,
      'spending': spending,
      'investment': investment,
      'repayment': repayment,
      'savings': savings,
    });
  }

  Map<String, double> get usdChart {
    return Map.unmodifiable({
      'withdrawal': withdrawalUsd,
      'spending': spendingUsd,
      'investment': investmentUsd,
      'repayment': repaymentUsd,
      'savings': savingsUsd,
    });
  }
}
