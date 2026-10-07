import 'package:ngoda/services/number_conversion_service.dart';

class LoyaltyProgress {
  const LoyaltyProgress({
    required this.pointsInCurrentLevel,
    required this.pointsToNextLevel,
    required this.percent,
    required this.isHighestLevel,
  });

  final int pointsInCurrentLevel;
  final int pointsToNextLevel;

  final double percent;

  final bool isHighestLevel;

  factory LoyaltyProgress.fromJson(Map<String, dynamic> json) {
    return LoyaltyProgress(
      pointsInCurrentLevel: NumberConversionService.toInt(
        json['points_in_current_level'],
      ),
      pointsToNextLevel: NumberConversionService.toInt(
        json['points_to_next_level'],
      ),
      percent: NumberConversionService.toDouble(json['percent']),
      isHighestLevel: json['is_highest_level'] == true,
    );
  }
}
