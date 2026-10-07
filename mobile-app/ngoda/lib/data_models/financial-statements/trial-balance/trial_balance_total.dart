import 'package:ngoda/services/number_conversion_service.dart';

class TrialBalanceTotal {
  const TrialBalanceTotal({
    required this.totalDebit,
    required this.totalCredit,
    required this.balanced,
  });

  final double totalDebit;
  final double totalCredit;

  /// Authoritative balance result returned by the backend.
  final bool balanced;

  factory TrialBalanceTotal.fromJson(Map<String, dynamic> json) {
    return TrialBalanceTotal(
      totalDebit: NumberConversionService.toDouble(json['total_debit']),
      totalCredit: NumberConversionService.toDouble(json['total_credit']),
      balanced: json['balanced'] == true,
    );
  }

  double get difference => totalDebit - totalCredit;

  bool get calculatedBalanced => difference.abs() <= 0.000001;

  bool get isConsistent => balanced == calculatedBalanced;
}
