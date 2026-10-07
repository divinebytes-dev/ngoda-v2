import 'package:ngoda/services/number_conversion_service.dart';

class PnLTotals {
  const PnLTotals({
    required this.totalRevenue,
    required this.totalExpense,
    required this.netIncome,
  });

  final double totalRevenue;
  final double totalExpense;
  final double netIncome;

  factory PnLTotals.fromJson(Map<String, dynamic> json) {
    return PnLTotals(
      totalRevenue: NumberConversionService.toDouble(json['totalRevenue']),
      totalExpense: NumberConversionService.toDouble(json['totalExpense']),
      netIncome: NumberConversionService.toDouble(json['netIncome']),
    );
  }

  double get calculatedNetIncome => totalRevenue - totalExpense;

  double get difference => netIncome - calculatedNetIncome;

  bool get isConsistent => difference.abs() <= 0.000001;

  double get profitMargin {
    if (totalRevenue == 0) {
      return 0;
    }

    return (netIncome / totalRevenue) * 100;
  }

  bool get isProfit => netIncome > 0;

  bool get isLoss => netIncome < 0;

  bool get isBreakEven => netIncome == 0;
}
