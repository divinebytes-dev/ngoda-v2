import 'package:ngoda/services/number_conversion_service.dart';

class ActiveLoan {
  const ActiveLoan({
    required this.id,
    required this.principal,
    required this.initiationFee,
    required this.netAmount,
    required this.interestRate,
    required this.collateralGrams,
    required this.liquidationPrice,
    required this.outstandingPrincipal,
    required this.accruedInterest,
  });

  final String id;

  final double principal;
  final double initiationFee;
  final double netAmount;

  final double interestRate;

  final double collateralGrams;
  final double liquidationPrice;

  final double outstandingPrincipal;
  final double accruedInterest;

  factory ActiveLoan.fromJson(Map<String, dynamic> json) {
    return ActiveLoan(
      id: json['id']?.toString().trim() ?? '',
      principal: NumberConversionService.toDouble(json['principal']),
      initiationFee: NumberConversionService.toDouble(json['initiation_fee']),
      netAmount: NumberConversionService.toDouble(json['net_amount']),
      interestRate: NumberConversionService.toDouble(json['interest_rate']),
      collateralGrams: NumberConversionService.toDouble(
        json['collateral_grams'],
      ),
      liquidationPrice: NumberConversionService.toDouble(
        json['liquidation_price'],
      ),
      outstandingPrincipal: NumberConversionService.toDouble(
        json['outstanding_principal'],
      ),
      accruedInterest: NumberConversionService.toDouble(
        json['accrued_interest'],
      ),
    );
  }

  double get outstandingBalance => outstandingPrincipal + accruedInterest;

  bool get hasOutstandingBalance => outstandingBalance > 0;
}

extension ActiveLoanListX on List<ActiveLoan> {
  int get activeLoanCount => length;

  bool hasReachedMaximumActiveLoans(int maximum) {
    return length >= maximum;
  }
}
