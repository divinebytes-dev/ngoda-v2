import 'package:ngoda/services/number_conversion_service.dart';

class FinancialLoanSummary {
  const FinancialLoanSummary({
    required this.openingBalance,
    required this.openingBalanceUsd,
    required this.disbursed,
    required this.disbursedUsd,
    required this.repaid,
    required this.repaidUsd,
    required this.principalRepaid,
    required this.principalRepaidUsd,
    required this.interestRepaid,
    required this.interestRepaidUsd,
    required this.interestAccrued,
    required this.interestAccruedUsd,
    required this.closingBalance,
    required this.closingBalanceUsd,
  });

  final double openingBalance;
  final double openingBalanceUsd;

  final double disbursed;
  final double disbursedUsd;

  final double repaid;
  final double repaidUsd;

  final double principalRepaid;
  final double principalRepaidUsd;

  final double interestRepaid;
  final double interestRepaidUsd;

  final double interestAccrued;
  final double interestAccruedUsd;

  final double closingBalance;
  final double closingBalanceUsd;

  factory FinancialLoanSummary.fromJson(Map<String, dynamic> json) {
    return FinancialLoanSummary(
      openingBalance: NumberConversionService.toDouble(json['opening_balance']),
      openingBalanceUsd: NumberConversionService.toDouble(
        json['opening_balance_usd'],
      ),
      disbursed: NumberConversionService.toDouble(json['disbursed']),
      disbursedUsd: NumberConversionService.toDouble(json['disbursed_usd']),
      repaid: NumberConversionService.toDouble(json['repaid']),
      repaidUsd: NumberConversionService.toDouble(json['repaid_usd']),
      principalRepaid: NumberConversionService.toDouble(
        json['principal_repaid'],
      ),
      principalRepaidUsd: NumberConversionService.toDouble(
        json['principal_repaid_usd'],
      ),
      interestRepaid: NumberConversionService.toDouble(json['interest_repaid']),
      interestRepaidUsd: NumberConversionService.toDouble(
        json['interest_repaid_usd'],
      ),
      interestAccrued: NumberConversionService.toDouble(
        json['interest_accrued'],
      ),
      interestAccruedUsd: NumberConversionService.toDouble(
        json['interest_accrued_usd'],
      ),
      closingBalance: NumberConversionService.toDouble(json['closing_balance']),
      closingBalanceUsd: NumberConversionService.toDouble(
        json['closing_balance_usd'],
      ),
    );
  }

  bool get hasActivity => disbursed != 0 || repaid != 0 || interestAccrued != 0;

  bool get hasOutstandingBalance => closingBalance > 0;
}
