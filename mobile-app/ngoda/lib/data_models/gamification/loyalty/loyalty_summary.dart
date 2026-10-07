import 'package:ngoda/data_models/gamification/loyalty/loyalty_level.dart';
import 'package:ngoda/data_models/gamification/loyalty/loyalty_progress.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class LoyaltySummary {
  const LoyaltySummary({
    required this.userId,
    required this.accountId,
    required this.availablePoints,
    required this.tierPoints,
    required this.lifetimeEarnedPoints,
    required this.level,
    required this.nextLevel,
    required this.progress,
    required this.lastEventAt,
    required this.updatedAt,
  });

  final String userId;
  final String? accountId;

  final int availablePoints;
  final int tierPoints;
  final int lifetimeEarnedPoints;

  final LoyaltyLevel level;
  final LoyaltyLevel? nextLevel;

  final LoyaltyProgress progress;

  final DateTime? lastEventAt;
  final DateTime? updatedAt;

  factory LoyaltySummary.fromJson(Map<String, dynamic> json) {
    final nextLevel = _nullableMap(json['next_level']);

    return LoyaltySummary(
      userId: _requiredString(json['user_id'], 'LoyaltySummary.userId'),
      accountId: _nullableString(json['account_id']),
      availablePoints: NumberConversionService.toInt(json['available_points']),
      tierPoints: NumberConversionService.toInt(json['tier_points']),
      lifetimeEarnedPoints: NumberConversionService.toInt(
        json['lifetime_earned_points'],
      ),
      level: LoyaltyLevel.fromJson(_asMap(json['level'])),
      nextLevel: nextLevel == null ? null : LoyaltyLevel.fromJson(nextLevel),
      progress: LoyaltyProgress.fromJson(_asMap(json['progress'])),
      lastEventAt: _nullableDate(json['last_event_at']),
      updatedAt: _nullableDate(json['updated_at']),
    );
  }

  bool get hasAvailablePoints => availablePoints > 0;

  bool get hasNextLevel => nextLevel != null;

  static String _requiredString(dynamic value, String field) {
    final result = value?.toString().trim();

    if (result == null || result.isEmpty) {
      throw FormatException('$field is required.');
    }

    return result;
  }

  static String? _nullableString(dynamic value) {
    final result = value?.toString().trim();

    return result == null || result.isEmpty ? null : result;
  }

  static DateTime? _nullableDate(dynamic value) {
    final raw = _nullableString(value);

    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }

  static Map<String, dynamic>? _nullableMap(dynamic value) {
    if (value == null) {
      return null;
    }

    return _asMap(value);
  }
}
