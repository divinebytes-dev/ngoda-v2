import 'package:ngoda/services/number_conversion_service.dart';

class LoyaltyLevel {
  LoyaltyLevel({
    required this.code,
    required this.name,
    required this.minTierPoints,
    required this.maxTierPoints,
    required this.sortOrder,
    required Map<String, dynamic> benefits,
  }) : benefits = Map.unmodifiable(benefits);

  final String code;
  final String name;

  final int minTierPoints;
  final int? maxTierPoints;

  final int sortOrder;

  final Map<String, dynamic> benefits;

  factory LoyaltyLevel.fromJson(Map<String, dynamic> json) {
    return LoyaltyLevel(
      code: _requiredString(json['code'], 'LoyaltyLevel.code'),
      name: _requiredString(json['name'], 'LoyaltyLevel.name'),
      minTierPoints: NumberConversionService.toInt(json['min_tier_points']),
      maxTierPoints: NumberConversionService.toNullableInt(
        json['max_tier_points'],
      ),
      sortOrder: NumberConversionService.toInt(json['sort_order']),
      benefits: _asMap(json['benefits']),
    );
  }

  bool get isHighestLevel => maxTierPoints == null;

  static String _requiredString(dynamic value, String field) {
    final result = value?.toString().trim();

    if (result == null || result.isEmpty) {
      throw FormatException('$field is required.');
    }

    return result;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
