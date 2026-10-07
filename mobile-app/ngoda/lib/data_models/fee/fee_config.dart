import 'package:ngoda/services/number_conversion_service.dart';

class FeeConfig {
  const FeeConfig({required this.percentage, this.flat, this.min, this.max});

  final double percentage;
  final double? flat;
  final double? min;
  final double? max;

  factory FeeConfig.fromJson(Map<String, dynamic> json) {
    return FeeConfig(
      percentage: NumberConversionService.toDouble(json['percentage']),
      flat: NumberConversionService.toNullableDouble(json['fixed_amount']),
      min: NumberConversionService.toNullableDouble(json['min_amount']),
      max: NumberConversionService.toNullableDouble(json['max_amount']),
    );
  }

  double calculateFee(double amount) {
    var fee = amount * percentage / 100;

    if (flat != null && flat! > 0) {
      fee += flat!;
    }

    if (min != null && min! > 0 && fee < min!) {
      fee = min!;
    }

    if (max != null && max! > 0 && fee > max!) {
      fee = max!;
    }

    return fee;
  }

  bool get hasPercentage => percentage > 0;

  bool get hasFlatFee => flat != null && flat! > 0;

  bool get hasMinimum => min != null && min! > 0;

  bool get hasMaximum => max != null && max! > 0;
}
