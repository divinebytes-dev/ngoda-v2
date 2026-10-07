import 'package:ngoda/services/number_conversion_service.dart';

class LoyaltyBadgeSummary {
  const LoyaltyBadgeSummary({
    required this.total,
    required this.earned,
    required this.remaining,
  });

  final int total;
  final int earned;
  final int remaining;

  factory LoyaltyBadgeSummary.fromJson(Map<String, dynamic> json) {
    return LoyaltyBadgeSummary(
      total: NumberConversionService.toInt(json['total']),
      earned: NumberConversionService.toInt(json['earned']),
      remaining: NumberConversionService.toInt(json['remaining']),
    );
  }

  bool get hasBadges => total > 0;

  bool get hasEarnedBadges => earned > 0;

  bool get hasRemainingBadges => remaining > 0;
}
