import 'package:ngoda/services/number_conversion_service.dart';

class Loyalty {
  const Loyalty({
    required this.availablePoints,
    required this.tierPoints,
    required this.lifetimeEarnedPoints,
    required this.levelCode,
    required this.isActive,
  });

  final int availablePoints;
  final int tierPoints;
  final int lifetimeEarnedPoints;

  final String? levelCode;

  final bool isActive;

  factory Loyalty.fromJson(Map<String, dynamic> json) {
    return Loyalty(
      availablePoints: NumberConversionService.toInt(json['available_points']),
      tierPoints: NumberConversionService.toInt(json['tier_points']),
      lifetimeEarnedPoints: NumberConversionService.toInt(
        json['lifetime_earned_points'],
      ),
      levelCode: _nullableString(json['level_code']),
      isActive: json['is_active'] == true,
    );
  }

  bool canPay(int pointsRequired) {
    return isActive && pointsRequired > 0 && availablePoints >= pointsRequired;
  }

  static String? _nullableString(dynamic value) {
    final result = value?.toString().trim();

    return result == null || result.isEmpty ? null : result.toLowerCase();
  }
}
