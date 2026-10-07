import 'package:ngoda/services/number_conversion_service.dart';

class LoanTotals {
  const LoanTotals({
    required this.debitPrincipal,
    required this.creditPrincipal,
    required this.debitInterest,
    required this.creditInterest,
  });

  final double debitPrincipal;
  final double creditPrincipal;

  final double debitInterest;
  final double creditInterest;

  factory LoanTotals.fromJson(Map<String, dynamic> json) {
    return LoanTotals(
      debitPrincipal: NumberConversionService.toDouble(json['debit_principal']),
      creditPrincipal: NumberConversionService.toDouble(
        json['credit_principal'],
      ),
      debitInterest: NumberConversionService.toDouble(json['debit_interest']),
      creditInterest: NumberConversionService.toDouble(json['credit_interest']),
    );
  }

  double get netPrincipal => debitPrincipal - creditPrincipal;

  double get netInterest => debitInterest - creditInterest;
}
