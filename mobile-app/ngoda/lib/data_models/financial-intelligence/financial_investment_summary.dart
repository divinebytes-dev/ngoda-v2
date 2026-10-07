import 'package:ngoda/services/number_conversion_service.dart';

class FinancialInvestmentSummary {
  const FinancialInvestmentSummary({
    required this.purchased,
    required this.purchasedUsd,
    required this.sold,
    required this.soldUsd,
  });

  final double purchased;
  final double purchasedUsd;

  final double sold;
  final double soldUsd;

  factory FinancialInvestmentSummary.fromJson(Map<String, dynamic> json) {
    return FinancialInvestmentSummary(
      purchased: NumberConversionService.toDouble(json['purchased']),
      purchasedUsd: NumberConversionService.toDouble(json['purchased_usd']),
      sold: NumberConversionService.toDouble(json['sold']),
      soldUsd: NumberConversionService.toDouble(json['sold_usd']),
    );
  }

  double get net => purchased - sold;

  double get netUsd => purchasedUsd - soldUsd;

  bool get hasActivity => purchased != 0 || sold != 0;
}
