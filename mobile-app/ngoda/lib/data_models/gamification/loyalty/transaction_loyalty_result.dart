import 'package:ngoda/services/number_conversion_service.dart';

class TransactionLoyaltyResult {
  const TransactionLoyaltyResult({
    required this.pointsEarned,
    required this.pointsSpent,
    required this.availablePoints,
    required this.tierPoints,
    required this.previousLevelCode,
    required this.levelCode,
    required this.levelChanged,
  });

  final int pointsEarned;
  final int pointsSpent;

  final int availablePoints;
  final int tierPoints;

  final String? previousLevelCode;
  final String? levelCode;

  final bool levelChanged;

  factory TransactionLoyaltyResult.fromJson(Map<String, dynamic> json) {
    return TransactionLoyaltyResult(
      pointsEarned: NumberConversionService.toInt(json['points_earned']),
      pointsSpent: NumberConversionService.toInt(json['points_spent']),
      availablePoints: NumberConversionService.toInt(json['available_points']),
      tierPoints: NumberConversionService.toInt(json['tier_points']),
      previousLevelCode: _nullableString(json['previous_level_code']),
      levelCode: _nullableString(json['level_code']),
      levelChanged: json['level_changed'] == true,
    );
  }

  bool get hasPointsEarned => pointsEarned > 0;

  bool get hasPointsSpent => pointsSpent > 0;

  bool get shouldCelebrate => hasPointsEarned || levelChanged;

  static String? _nullableString(dynamic value) {
    final result = value?.toString().trim();

    return result == null || result.isEmpty ? null : result.toLowerCase();
  }
}
