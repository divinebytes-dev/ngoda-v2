import 'package:ngoda/services/number_conversion_service.dart';

class GoldMetrics {
  const GoldMetrics({
    required this.total,
    required this.totalUsd,
    required this.locked,
    required this.lockedUsd,
    required this.available,
    required this.availableUsd,
  });

  final double total;
  final double totalUsd;

  final double locked;
  final double lockedUsd;

  final double available;
  final double availableUsd;

  factory GoldMetrics.fromJson(Map<String, dynamic> json) {
    return GoldMetrics(
      total: NumberConversionService.toDouble(json['total']),
      totalUsd: NumberConversionService.toDouble(json['total_usd']),
      locked: NumberConversionService.toDouble(json['locked']),
      lockedUsd: NumberConversionService.toDouble(json['locked_usd']),
      available: NumberConversionService.toDouble(json['available']),
      availableUsd: NumberConversionService.toDouble(json['available_usd']),
    );
  }

  bool get hasGold => total > 0;

  bool get hasLockedGold => locked > 0;

  bool get hasAvailableGold => available > 0;
}
