import 'package:ngoda/services/number_conversion_service.dart';

class LoanRisk {
  const LoanRisk({
    required this.currentLtv,
    required this.liquidationPrice,
    required this.healthFactor,
    required this.riskLevel,
  });

  final double currentLtv;
  final double liquidationPrice;
  final double healthFactor;

  /// Backend-calculated risk classification.
  final String riskLevel;

  factory LoanRisk.fromJson(Map<String, dynamic> json) {
    return LoanRisk(
      currentLtv: NumberConversionService.toDouble(json['currentLtv']),
      liquidationPrice: NumberConversionService.toDouble(
        json['liquidationPrice'],
      ),
      healthFactor: NumberConversionService.toDouble(json['healthFactor']),
      riskLevel: json['riskLevel']?.toString().trim().toLowerCase() ?? '',
    );
  }
}
