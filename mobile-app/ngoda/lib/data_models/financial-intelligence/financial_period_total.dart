import 'package:ngoda/services/number_conversion_service.dart';

class FinancialPeriodTotal {
  const FinancialPeriodTotal({
    required this.depositUsd,
    required this.withdrawalUsd,
    required this.spendingUsd,
    required this.savingsInflowUsd,
    required this.savingsOutflowUsd,
    required this.savingUsd,
    required this.closingSavingsUsd,
    required this.investmentUsd,
    required this.investmentSaleUsd,
    required this.borrowingUsd,
    required this.repaymentUsd,
    required this.interestAccruedUsd,
    required this.closingLoanBalanceUsd,
  });

  final double depositUsd;
  final double withdrawalUsd;
  final double spendingUsd;

  final double savingsInflowUsd;
  final double savingsOutflowUsd;
  final double savingUsd;
  final double closingSavingsUsd;

  final double investmentUsd;
  final double investmentSaleUsd;

  final double borrowingUsd;
  final double repaymentUsd;

  final double interestAccruedUsd;
  final double closingLoanBalanceUsd;

  factory FinancialPeriodTotal.fromJson(Map<String, dynamic> json) {
    return FinancialPeriodTotal(
      depositUsd: NumberConversionService.toDouble(json['deposit_usd']),
      withdrawalUsd: NumberConversionService.toDouble(json['withdrawal_usd']),
      spendingUsd: NumberConversionService.toDouble(json['spending_usd']),
      savingsInflowUsd: NumberConversionService.toDouble(
        json['savings_inflow_usd'],
      ),
      savingsOutflowUsd: NumberConversionService.toDouble(
        json['savings_outflow_usd'],
      ),
      savingUsd: NumberConversionService.toDouble(json['saving_usd']),
      closingSavingsUsd: NumberConversionService.toDouble(
        json['closing_savings_usd'],
      ),
      investmentUsd: NumberConversionService.toDouble(json['investment_usd']),
      investmentSaleUsd: NumberConversionService.toDouble(
        json['investment_sale_usd'],
      ),
      borrowingUsd: NumberConversionService.toDouble(json['borrowing_usd']),
      repaymentUsd: NumberConversionService.toDouble(json['repayment_usd']),
      interestAccruedUsd: NumberConversionService.toDouble(
        json['interest_accrued_usd'],
      ),
      closingLoanBalanceUsd: NumberConversionService.toDouble(
        json['closing_loan_balance_usd'],
      ),
    );
  }

  bool get hasLoan => closingLoanBalanceUsd > 0;

  bool get hasInvestment => investmentUsd > 0 || investmentSaleUsd > 0;

  bool get hasSavings => closingSavingsUsd > 0;

  Map<String, double> get activityChart {
    return Map.unmodifiable({
      'deposit': depositUsd,
      'withdrawal': withdrawalUsd,
      'spending': spendingUsd,
      'investment': investmentUsd,
      'borrowing': borrowingUsd,
      'repayment': repaymentUsd,
      'savings': closingSavingsUsd,
    });
  }

  Map<String, double> get periodicTrendChart {
    return Map.unmodifiable({
      'savings': closingSavingsUsd,
      'spending': spendingUsd,
      'investment': investmentUsd,
      'borrowing': borrowingUsd,
      'repayment': repaymentUsd,
    });
  }

  Map<String, double> get financialActivityMix {
    return Map.unmodifiable({
      'savings': closingSavingsUsd,
      'withdrawal': withdrawalUsd,
      'spending': spendingUsd,
      'investment': investmentUsd,
      'repayment': repaymentUsd,
    });
  }
}
