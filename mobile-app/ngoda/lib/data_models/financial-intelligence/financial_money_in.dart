import 'package:ngoda/services/number_conversion_service.dart';

class FinancialMoneyIn {
  const FinancialMoneyIn({
    this.savingsBroughtForward = 0,
    this.cashIn = 0,
    this.transferIn = 0,
    this.loanDisbursement = 0,
    this.investmentProceeds = 0,
    this.total = 0,
    this.savingsBroughtForwardUsd = 0,
    this.cashInUsd = 0,
    this.transferInUsd = 0,
    this.loanDisbursementUsd = 0,
    this.investmentProceedsUsd = 0,
    this.totalUsd = 0,
  });

  final double savingsBroughtForward;
  final double cashIn;
  final double transferIn;
  final double loanDisbursement;
  final double investmentProceeds;
  final double total;

  final double savingsBroughtForwardUsd;
  final double cashInUsd;
  final double transferInUsd;
  final double loanDisbursementUsd;
  final double investmentProceedsUsd;
  final double totalUsd;

  factory FinancialMoneyIn.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};

    return FinancialMoneyIn(
      savingsBroughtForward: NumberConversionService.toDouble(
        data['savings_brought_forward'],
      ),
      cashIn: NumberConversionService.toDouble(data['cash_in']),
      transferIn: NumberConversionService.toDouble(data['transfer_in']),
      loanDisbursement: NumberConversionService.toDouble(
        data['loan_disbursement'],
      ),
      investmentProceeds: NumberConversionService.toDouble(
        data['investment_proceeds'],
      ),
      total: NumberConversionService.toDouble(data['total']),
      savingsBroughtForwardUsd: NumberConversionService.toDouble(
        data['savings_brought_forward_usd'],
      ),
      cashInUsd: NumberConversionService.toDouble(data['cash_in_usd']),
      transferInUsd: NumberConversionService.toDouble(data['transfer_in_usd']),
      loanDisbursementUsd: NumberConversionService.toDouble(
        data['loan_disbursement_usd'],
      ),
      investmentProceedsUsd: NumberConversionService.toDouble(
        data['investment_proceeds_usd'],
      ),
      totalUsd: NumberConversionService.toDouble(data['total_usd']),
    );
  }

  Map<String, double> get nativeChart {
    return Map.unmodifiable({
      'savings_brought_forward': savingsBroughtForward,
      'cash_in': cashIn,
      'transfer_in': transferIn,
      'loan_disbursement': loanDisbursement,
      'investment_proceeds': investmentProceeds,
    });
  }

  Map<String, double> get usdChart {
    return Map.unmodifiable({
      'savings_brought_forward': savingsBroughtForwardUsd,
      'cash_in': cashInUsd,
      'transfer_in': transferInUsd,
      'loan_disbursement': loanDisbursementUsd,
      'investment_proceeds': investmentProceedsUsd,
    });
  }
}
