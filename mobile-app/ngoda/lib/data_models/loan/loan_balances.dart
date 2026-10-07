import 'package:ngoda/services/number_conversion_service.dart';

class LoanBalances {
  const LoanBalances({
    required this.principalBalance,
    required this.interestBalance,
    required this.outstandingBalance,
  });

  final double principalBalance;
  final double interestBalance;

  /// Backend-calculated outstanding balance.
  final double outstandingBalance;

  factory LoanBalances.fromJson(Map<String, dynamic> json) {
    return LoanBalances(
      principalBalance: NumberConversionService.toDouble(
        json['principal_balance'],
      ),
      interestBalance: NumberConversionService.toDouble(
        json['interest_balance'],
      ),
      outstandingBalance: NumberConversionService.toDouble(
        json['outstanding_balance'],
      ),
    );
  }

  double get calculatedOutstandingBalance => principalBalance + interestBalance;

  double get difference => outstandingBalance - calculatedOutstandingBalance;

  bool get isConsistent => difference.abs() <= 0.000001;

  bool get hasOutstandingBalance => outstandingBalance > 0;
}
