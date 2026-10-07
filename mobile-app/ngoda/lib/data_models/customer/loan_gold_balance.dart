import 'package:ngoda/services/number_conversion_service.dart';

class LoanGoldBalance {
  const LoanGoldBalance({required this.grams, required this.usdValue});

  final double grams;
  final double usdValue;

  factory LoanGoldBalance.fromJson(Map<String, dynamic> json) {
    return LoanGoldBalance(
      grams: NumberConversionService.toDouble(json['grams']),
      usdValue: NumberConversionService.toDouble(json['usdValue']),
    );
  }

  bool get hasBalance => grams > 0;
}
