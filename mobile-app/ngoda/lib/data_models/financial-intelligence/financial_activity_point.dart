import 'package:ngoda/data_models/financial-intelligence/financial_currency_summary.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_period_total.dart';

class FinancialActivityPoint {
  const FinancialActivityPoint({
    required this.period,
    required this.savings,
    required this.spending,
    required this.investment,
    required this.borrowing,
    required this.repayment,
  });

  final int period;
  final double savings;
  final double spending;
  final double investment;
  final double borrowing;
  final double repayment;

  factory FinancialActivityPoint.fromUsdTotal({
    required int period,
    required FinancialPeriodTotal total,
  }) {
    return FinancialActivityPoint(
      period: period,
      savings: total.closingSavingsUsd,
      spending: total.spendingUsd,
      investment: total.investmentUsd,
      borrowing: total.borrowingUsd,
      repayment: total.repaymentUsd,
    );
  }

  factory FinancialActivityPoint.fromCurrency({
    required int period,
    required FinancialCurrencySummary currency,
  }) {
    return FinancialActivityPoint(
      period: period,
      savings: currency.savings.closing,
      spending: currency.spending.amount,
      investment: currency.investment.purchased,
      borrowing: currency.loan.disbursed,
      repayment: currency.loan.repaid,
    );
  }

  bool get hasActivity =>
      savings != 0 ||
      spending != 0 ||
      investment != 0 ||
      borrowing != 0 ||
      repayment != 0;
}
