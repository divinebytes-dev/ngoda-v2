import 'package:ngoda/services/number_conversion_service.dart';

class BalanceSheetTotals {
  const BalanceSheetTotals({
    required this.assets,
    required this.liabilities,
    required this.equity,
  });

  final double assets;
  final double liabilities;
  final double equity;

  factory BalanceSheetTotals.fromJson(Map<String, dynamic> json) {
    return BalanceSheetTotals(
      assets: NumberConversionService.toDouble(json['assets']),
      liabilities: NumberConversionService.toDouble(json['liabilities']),
      equity: NumberConversionService.toDouble(json['equity']),
    );
  }

  double get difference => assets - liabilities - equity;

  bool get isBalanced => difference.abs() <= 0.000001;
}
