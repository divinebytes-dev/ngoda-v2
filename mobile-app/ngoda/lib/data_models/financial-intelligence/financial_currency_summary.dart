import 'package:ngoda/data_models/financial-intelligence/financial_investment_summary.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_loan_summary.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_savings_summary.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class FinancialAmountSummary {
  const FinancialAmountSummary({required this.amount, required this.amountUsd});

  final double amount;
  final double amountUsd;

  factory FinancialAmountSummary.fromJson(Map<String, dynamic> json) {
    return FinancialAmountSummary(
      amount: NumberConversionService.toDouble(json['amount']),
      amountUsd: NumberConversionService.toDouble(json['amount_usd']),
    );
  }
}

class FinancialCurrencySummary {
  const FinancialCurrencySummary({
    required this.currencyCode,
    required this.deposit,
    required this.withdrawal,
    required this.spending,
    required this.savings,
    required this.investment,
    required this.loan,
  });

  final String currencyCode;

  final FinancialAmountSummary deposit;
  final FinancialAmountSummary withdrawal;
  final FinancialAmountSummary spending;

  final FinancialSavingsSummary savings;
  final FinancialInvestmentSummary investment;
  final FinancialLoanSummary loan;

  factory FinancialCurrencySummary.fromJson(Map<String, dynamic> json) {
    return FinancialCurrencySummary(
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      deposit: FinancialAmountSummary.fromJson(_asMap(json['deposit'])),
      withdrawal: FinancialAmountSummary.fromJson(_asMap(json['withdrawal'])),
      spending: FinancialAmountSummary.fromJson(_asMap(json['spending'])),
      savings: FinancialSavingsSummary.fromJson(_asMap(json['savings'])),
      investment: FinancialInvestmentSummary.fromJson(
        _asMap(json['investment']),
      ),
      loan: FinancialLoanSummary.fromJson(_asMap(json['loan'])),
    );
  }

  Map<String, double> get activityChart {
    return Map.unmodifiable({
      'deposit': deposit.amount,
      'withdrawal': withdrawal.amount,
      'spending': spending.amount,
      'investment': investment.purchased,
      'repayment': loan.repaid,
    });
  }

  Map<String, double> get activityChartUsd {
    return Map.unmodifiable({
      'deposit': deposit.amountUsd,
      'withdrawal': withdrawal.amountUsd,
      'spending': spending.amountUsd,
      'investment': investment.purchasedUsd,
      'repayment': loan.repaidUsd,
    });
  }

  Map<String, double> get allocationChart {
    return Map.unmodifiable({
      'withdrawal': withdrawal.amount,
      'spending': spending.amount,
      'investment': investment.purchased,
      'repayment': loan.repaid,
      'savings': savings.closing,
    });
  }

  Map<String, double> get allocationChartUsd {
    return Map.unmodifiable({
      'withdrawal': withdrawal.amountUsd,
      'spending': spending.amountUsd,
      'investment': investment.purchasedUsd,
      'repayment': loan.repaidUsd,
      'savings': savings.closingUsd,
    });
  }

  Map<String, double> get nonZeroAllocationChart {
    return Map.unmodifiable(
      Map.fromEntries(
        allocationChart.entries.where((entry) => entry.value > 0),
      ),
    );
  }

  Map<String, double> get nonZeroAllocationChartUsd {
    return Map.unmodifiable(
      Map.fromEntries(
        allocationChartUsd.entries.where((entry) => entry.value > 0),
      ),
    );
  }

  double get totalFunding => deposit.amount + loan.disbursed;

  double get totalFundingUsd => deposit.amountUsd + loan.disbursedUsd;

  double get totalOutflow =>
      withdrawal.amount + spending.amount + investment.purchased + loan.repaid;

  double get totalOutflowUsd =>
      withdrawal.amountUsd +
      spending.amountUsd +
      investment.purchasedUsd +
      loan.repaidUsd;

  double get netInvestment => investment.net;

  double get netInvestmentUsd => investment.netUsd;

  double get netBorrowing => loan.disbursed - loan.repaid;

  double get netBorrowingUsd => loan.disbursedUsd - loan.repaidUsd;

  bool get hasDeposit => deposit.amount > 0;

  bool get hasWithdrawal => withdrawal.amount > 0;

  bool get hasSpending => spending.amount > 0;

  bool get hasInvestment => investment.hasActivity;

  bool get hasLoan => loan.hasActivity || loan.hasOutstandingBalance;

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
