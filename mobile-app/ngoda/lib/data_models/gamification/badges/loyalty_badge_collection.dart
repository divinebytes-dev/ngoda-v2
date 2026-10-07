import 'package:ngoda/data_models/gamification/badges/loyalty_badge.dart';
import 'package:ngoda/data_models/gamification/badges/loyalty_badge_summary.dart';

class LoyaltyBadgeCollection {
  LoyaltyBadgeCollection({
    required List<LoyaltyBadge> rows,
    required this.summary,
  }) : rows = List.unmodifiable(rows);

  final List<LoyaltyBadge> rows;

  final LoyaltyBadgeSummary summary;

  factory LoyaltyBadgeCollection.fromJson(Map<String, dynamic> json) {
    return LoyaltyBadgeCollection(
      rows: _parseRows(json['rows']),
      summary: LoyaltyBadgeSummary.fromJson(_asMap(json['summary'])),
    );
  }

  bool get isEmpty => rows.isEmpty;

  bool get isNotEmpty => rows.isNotEmpty;

  List<LoyaltyBadge> get earned {
    return List.unmodifiable(rows.where((badge) => badge.isEarned));
  }

  List<LoyaltyBadge> get unearned {
    return List.unmodifiable(rows.where((badge) => !badge.isEarned));
  }

  List<LoyaltyBadge> forCategory(String category) {
    final normalized = category.trim().toLowerCase();

    return List.unmodifiable(
      rows.where((badge) => badge.category == normalized),
    );
  }

  LoyaltyBadge? findByCode(String code) {
    final normalized = code.trim().toLowerCase();

    for (final badge in rows) {
      if (badge.code.toLowerCase() == normalized) {
        return badge;
      }
    }

    return null;
  }

  static List<LoyaltyBadge> _parseRows(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((row) => LoyaltyBadge.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
