import 'package:ngoda/services/number_conversion_service.dart';

class LoyaltyBadge {
  const LoyaltyBadge({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.category,
    required this.iconKey,
    required this.sortOrder,
    required this.isSecret,
    required this.userBadgeId,
    required this.awardedAt,
    required this.isEarned,
    required this.currentValue,
    required this.targetValue,
    required this.progressPercent,
  });

  final String id;
  final String code;

  final String name;
  final String description;

  /// Dynamic category supplied by the backend.
  final String category;

  /// Dynamic icon identifier supplied by the backend.
  final String iconKey;

  final int sortOrder;

  final bool isSecret;

  final String? userBadgeId;
  final DateTime? awardedAt;

  final bool isEarned;

  final int currentValue;
  final int targetValue;

  /// Backend-calculated progress.
  final double progressPercent;

  factory LoyaltyBadge.fromJson(Map<String, dynamic> json) {
    return LoyaltyBadge(
      id: _requiredString(json['id'], 'id'),
      code: _requiredString(json['badge_code'], 'badge_code'),
      name: _requiredString(json['name'], 'name'),
      description: _requiredString(json['description'], 'description'),
      category: _requiredString(json['category'], 'category').toLowerCase(),
      iconKey: _requiredString(json['icon_key'], 'icon_key'),
      sortOrder: NumberConversionService.toInt(json['sort_order']),
      isSecret: json['is_secret'] == true,
      userBadgeId: _nullableString(json['user_badge_id']),
      awardedAt: _nullableDateTime(json['awarded_at']),
      isEarned: json['is_earned'] == true,
      currentValue: NumberConversionService.toInt(json['current_value']),
      targetValue: NumberConversionService.toInt(json['target_value']),
      progressPercent: NumberConversionService.toDouble(
        json['progress_percent'],
      ),
    );
  }

  bool get hasProgress => currentValue > 0;

  bool get hasTarget => targetValue > 0;

  bool get isLocked => !isEarned;

  static String _requiredString(dynamic value, String field) {
    final result = value?.toString().trim();

    if (result == null || result.isEmpty) {
      throw FormatException('LoyaltyBadge.$field is required.');
    }

    return result;
  }

  static String? _nullableString(dynamic value) {
    final result = value?.toString().trim();

    if (result == null || result.isEmpty) {
      return null;
    }

    return result;
  }

  static DateTime? _nullableDateTime(dynamic value) {
    final raw = _nullableString(value);

    if (raw == null) {
      return null;
    }

    return DateTime.tryParse(raw)?.toLocal();
  }
}
